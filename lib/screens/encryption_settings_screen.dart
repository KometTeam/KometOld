// encryption_settings_screen.dart — глобальные настройки шифрования.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:gwid/services/crypt/biometric_lock.dart';
import 'package:gwid/services/crypt/master_key_manager.dart';
import 'package:gwid/services/crypt/recovery.dart';
import 'package:gwid/screens/master_password_setup_screen.dart';
import 'package:gwid/screens/master_password_change_screen.dart';
import 'package:gwid/screens/password_recovery_screen.dart';
import 'package:gwid/screens/backup_screen.dart';

class EncryptionSettingsScreen extends StatefulWidget {
  const EncryptionSettingsScreen({super.key});

  @override
  State<EncryptionSettingsScreen> createState() =>
      _EncryptionSettingsScreenState();
}

class _EncryptionSettingsScreenState extends State<EncryptionSettingsScreen> {
  bool _initialized = false;
  bool _isInitialized = false;
  bool _isUnlocked = false;
  int? _relockSeconds;
  String _argon2Profile = 'balanced';
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  RecoveryReport? _recoveryReport;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final mgr = MasterKeyManager.instance;
    final init = await mgr.isInitialized();
    final relock = await mgr.getRelockSeconds();
    final argon = init ? await mgr.getArgon2Profile() : 'balanced';
    final bioAvail = await BiometricLock.instance.isAvailable();
    final bioEnabled = await BiometricLock.instance.isEnabled();

    RecoveryReport? report;
    if (init && mgr.isUnlocked) {
      try {
        report = await RecoveryService.diagnose();
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _initialized = true;
      _isInitialized = init;
      _isUnlocked = mgr.isUnlocked;
      _biometricAvailable = bioAvail && init;
      _biometricEnabled = bioEnabled;
      _recoveryReport = report;
      _relockSeconds = relock;
      _argon2Profile = argon;
    });
  }

  Future<void> _onSetupFirstTime() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const MasterPasswordSetupScreen(
          mode: MasterPasswordSetupMode.firstTime,
        ),
      ),
    );
    if (ok == true) await _refresh();
  }

  Future<void> _onChangePassword() async {
    if (!_isUnlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала разблокируйте приложение')),
      );
      return;
    }
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const MasterPasswordChangeScreen()),
    );
    if (ok == true) await _refresh();
  }

  Future<void> _onLockNow() async {
    MasterKeyManager.instance.lock();
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Шифрование заблокировано')),
    );
  }

  Future<void> _onToggleBiometric(bool value) async {
    try {
      if (value) {
        await BiometricLock.instance.enable();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Биометрия включена')),
        );
      } else {
        await BiometricLock.instance.disable();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Биометрия выключена')),
        );
      }
      await _refresh();
    } on BiometricCancelledException {
      // молча
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _onRunRecovery() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const PasswordRecoveryScreen(),
      ),
    );
    if (ok == true || ok == false) {
      // Любой ответ = пользователь что-то решил, перечитываем состояние.
      await _refresh();
    }
  }

  Future<void> _onPickRelock() async {
    final result = await showDialog<int>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Авто-блокировка'),
        children: [
          _relockOption(-1, 'Никогда'),
          _relockOption(60, 'Через 1 минуту'),
          _relockOption(5 * 60, 'Через 5 минут'),
          _relockOption(15 * 60, 'Через 15 минут'),
          _relockOption(60 * 60, 'Через 1 час'),
        ],
      ),
    );
    if (result == null) return;
    final newValue = result == -1 ? null : result;
    await MasterKeyManager.instance.setRelockSeconds(newValue);
    await _refresh();
  }

  Widget _relockOption(int value, String label) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(context, value),
      child: Text(label),
    );
  }

  Future<void> _onBackup() async {
    if (!_isUnlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала разблокируйте приложение')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BackupScreen()),
    );
    await _refresh();
  }

  Future<void> _onNuclearReset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Сбросить шифрование?'),
        content: const Text(
          'Это удалит мастер-пароль и ВСЕ ключи зашифрованных чатов. '
          'Старые сообщения останутся в чатах, но прочитать их будет '
          'нельзя. Действие НЕОБРАТИМО.\n\n'
          'Перед сбросом рекомендуется сделать резервную копию.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await MasterKeyManager.instance.nuclearReset();
    await BiometricLock.instance.wipeOnReset();
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Шифрование сброшено')),
    );
  }

  String _formatRelock(int? seconds) {
    if (seconds == null) return 'Никогда';
    if (seconds < 60) return '$seconds сек';
    if (seconds < 3600) return '${seconds ~/ 60} мин';
    return '${seconds ~/ 3600} ч';
  }

  String get _statusText {
    if (!_isInitialized) return 'Не настроено';
    if (_isUnlocked) return 'Разблокировано';
    return 'Заблокировано';
  }

  Color get _statusColor {
    if (!_isInitialized) return Colors.grey;
    if (_isUnlocked) return Colors.green;
    return Colors.orange;
  }

  static String _argon2ProfileLabel(String name) {
    switch (name) {
      case 'lite':
        return 'Lite (64 MiB) — для слабых телефонов';
      case 'balanced':
        return 'Balanced (128 MiB) — рекомендуется';
      case 'strong':
        return 'Strong (256 MiB) — для топовых телефонов';
      default:
        return name;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Шифрование', style: GoogleFonts.inter()),
      ),
      body: !_initialized
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _statusTile(),
                if (_recoveryReport?.hasIssues == true) _recoveryBanner(),
                const Divider(),
                if (!_isInitialized)
                  ListTile(
                    leading: const Icon(Icons.add_moderator),
                    title: const Text('Включить шифрование'),
                    subtitle: const Text(
                      'Задайте мастер-пароль для шифрования чатов',
                    ),
                    onTap: _onSetupFirstTime,
                  )
                else ...[
                  ListTile(
                    leading: const Icon(Icons.password),
                    title: const Text('Сменить мастер-пароль'),
                    subtitle: Text(_isUnlocked
                        ? 'Доступно'
                        : 'Сначала разблокируйте'),
                    enabled: _isUnlocked,
                    onTap: _onChangePassword,
                  ),
                  if (_biometricAvailable)
                    SwitchListTile(
                      secondary: const Icon(Icons.fingerprint),
                      title: const Text('Биометрия'),
                      subtitle: const Text(
                        'Разблокировка отпечатком / лицом',
                      ),
                      value: _biometricEnabled,
                      onChanged: _isUnlocked ? _onToggleBiometric : null,
                    ),
                  ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text('Авто-блокировка'),
                    subtitle: Text(_formatRelock(_relockSeconds)),
                    onTap: _onPickRelock,
                  ),
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('Заблокировать сейчас'),
                    enabled: _isUnlocked,
                    onTap: _onLockNow,
                  ),
                  ListTile(
                    leading: const Icon(Icons.tune),
                    title: const Text('Сложность ключа'),
                    subtitle: Text(_argon2ProfileLabel(_argon2Profile)),
                    enabled: false,
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.cloud_upload_outlined),
                    title: const Text('Резервная копия'),
                    subtitle: const Text(
                      'Экспорт и импорт всех ключей чатов',
                    ),
                    enabled: _isUnlocked,
                    onTap: _onBackup,
                  ),
                  if (_recoveryReport?.hasIssues == true)
                    ListTile(
                      leading: Icon(
                        Icons.healing,
                        color: Colors.orange.shade700,
                      ),
                      title: const Text('Восстановление чатов'),
                      subtitle: Text(
                        'Найдено проблем: ${_recoveryReport!.brokenChats.length}',
                      ),
                      onTap: _onRunRecovery,
                    ),
                  const Divider(),
                  ListTile(
                    leading: Icon(
                      Icons.warning_amber_outlined,
                      color: Colors.red.shade700,
                    ),
                    title: Text(
                      'Сбросить шифрование',
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                    subtitle: const Text(
                      'Удалить пароль и все ключи (необратимо)',
                    ),
                    onTap: _onNuclearReset,
                  ),
                ],
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'AES-256-GCM + Argon2id. Каждое сообщение шифруется '
                    'индивидуальным случайным nonce. Подмена сообщения '
                    'обнаруживается по тегу аутентичности (128 бит).',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _statusTile() {
    return ListTile(
      leading: Icon(Icons.shield_outlined, color: _statusColor),
      title: const Text('Статус'),
      subtitle: Text(
        _statusText,
        style: TextStyle(color: _statusColor, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _recoveryBanner() {
    final r = _recoveryReport!;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.orange.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.hasPendingChange
                      ? 'Незавершённая смена пароля'
                      : 'Найдены проблемные обёртки',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  r.hasPendingChange
                      ? 'Введите старый пароль чтобы восстановить '
                          '${r.brokenChats.length} чатов'
                      : 'Чаты с повреждёнными ключами: '
                          '${r.brokenChats.length}',
                  style: GoogleFonts.inter(fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _onRunRecovery,
            child: const Text('Открыть'),
          ),
        ],
      ),
    );
  }
}
