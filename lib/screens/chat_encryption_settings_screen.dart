// chat_encryption_settings_screen.dart — настройки шифрования ОДНОГО чата.
//
// В новой архитектуре (PR 1+) пароль чата НЕ хранится — у каждого чата
// случайный chat_key, обёрнутый мастер-паролем. Пользователь больше не
// вводит пароль для чата; вместо этого он либо «включает шифрование»
// (генерируется ключ), либо «выключает».
//
// Для обмена ключами с собеседником используется отдельный экран
// «Поделиться ключом» (PR 3 — экспорт/импорт, QR).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:gwid/services/chat_encryption_service.dart';
import 'package:gwid/services/encrypted_file_service.dart';
import 'package:gwid/services/crypt/master_key_manager.dart';
import 'package:gwid/screens/key_share_export_screen.dart';
import 'package:gwid/screens/key_share_import_screen.dart';

class ChatEncryptionSettingsScreen extends StatefulWidget {
  final int chatId;

  /// Сохранён для совместимости с местами, которые передавали этот
  /// параметр в старом API. Используется только для дисплея текущего
  /// статуса при первом открытии.
  final bool isPasswordSet;

  const ChatEncryptionSettingsScreen({
    super.key,
    required this.chatId,
    this.isPasswordSet = false,
  });

  @override
  State<ChatEncryptionSettingsScreen> createState() =>
      _ChatEncryptionSettingsScreenState();
}

class _ChatEncryptionSettingsScreenState
    extends State<ChatEncryptionSettingsScreen> {
  bool _initialized = false;
  bool _hasNewKey = false;
  bool _hasLegacyArchive = false;
  bool _sendEncrypted = true;
  bool _encryptFiles = true;
  bool _busy = false;
  String _obfuscationProfile = 'ru_full';
  String _fileExtension = 'bin';
  String _fileNameProfile = 'file_seq';
  final _customExtCtl = TextEditingController();
  final _legacyXorCtl = TextEditingController();
  bool _legacyXorObscure = true;

  static const _profiles = [
    ('ru_full', 'ru_full — кириллица полная'),
    ('ru_max', 'ru_max — максимальная маскировка'),
    ('natural', 'natural — смешанный'),
    ('compact', 'compact — компактный'),
    ('tiny', 'tiny — минимальный'),
  ];

  static const _extPresets = ['bin', 'dat', 'log', 'txt', 'kbak'];

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _customExtCtl.dispose();
    _legacyXorCtl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final cfg = await ChatEncryptionService.getConfigForChat(widget.chatId);
    if (!mounted) return;
    setState(() {
      _initialized = true;
      _hasNewKey = ChatEncryptionService.hasNewKey(cfg);
      _hasLegacyArchive = (cfg?.legacyXorPassword ?? '').isNotEmpty;
      _sendEncrypted = cfg?.sendEncrypted ?? true;
      _encryptFiles = cfg?.encryptFiles ?? true;
      _obfuscationProfile = cfg?.obfuscationProfile ?? 'ru_full';
      _fileExtension = cfg?.encryptedFileExtension ?? 'bin';
      _fileNameProfile = cfg?.encryptedFileNameProfile ?? 'file_seq';
      // Заполняем поле XOR если уже сохранён
      if (_legacyXorCtl.text.isEmpty && (cfg?.legacyXorPassword ?? '').isNotEmpty) {
        _legacyXorCtl.text = cfg!.legacyXorPassword!;
      }
      if (_extPresets.contains(_fileExtension)) {
        _customExtCtl.clear();
      } else {
        _customExtCtl.text = _fileExtension;
      }
    });
  }

  Future<void> _onSaveLegacyXor() async {
    final pw = _legacyXorCtl.text.trim();
    if (pw.isEmpty) return;
    final cfg = await ChatEncryptionService.getConfigForChat(widget.chatId);
    final updated = (cfg ?? ChatEncryptionConfig(
      password: '',
      sendEncrypted: false,
    )).copyWith(legacyXorPassword: pw);
    await ChatEncryptionService.saveRawConfigForChat(widget.chatId, updated);
    await _loadConfig();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Пароль для архива сохранён')),
    );
  }

  Future<void> _onClearLegacyXor() async {
    final cfg = await ChatEncryptionService.getConfigForChat(widget.chatId);
    if (cfg == null) return;
    final updated = cfg.copyWith(legacyXorPassword: '');
    await ChatEncryptionService.saveRawConfigForChat(widget.chatId, updated);
    _legacyXorCtl.clear();
    await _loadConfig();
  }

  Future<bool> _ensureMasterUnlocked() async {
    final mgr = MasterKeyManager.instance;
    if (mgr.isUnlocked) return true;

    if (!await mgr.isInitialized()) {
      // Мастер не настроен. Подсказываем пользователю.
      if (!mounted) return false;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Сначала включите шифрование приложения'),
          content: const Text(
            'Чтобы шифровать чаты, задайте мастер-пароль приложения '
            'в Настройках → Шифрование.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return false;
    }

    // Мастер настроен но locked — UI должен сам направить пользователя
    // в unlock-экран. Здесь просто отказываем.
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Разблокируйте приложение мастер-паролем'),
      ),
    );
    return false;
  }

  Future<void> _onEnable() async {
    if (!await _ensureMasterUnlocked()) return;
    setState(() => _busy = true);
    try {
      // Фактически создаст случайный chat_key через MasterKeyManager.
      // Параметр пароля игнорируется в новой архитектуре.
      await ChatEncryptionService.setPasswordForChat(widget.chatId, '');
      await ChatEncryptionService.setSendEncryptedForChat(
        widget.chatId,
        true,
      );
      await _loadConfig();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Шифрование включено для этого чата'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onDisable() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Отключить шифрование?'),
        content: const Text(
          'Новые сообщения в этом чате будут отправляться в открытом '
          'виде. Старые зашифрованные сообщения останутся читаемыми, '
          'пока ключ хранится в приложении.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Отключить'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      await ChatEncryptionService.setSendEncryptedForChat(
        widget.chatId,
        false,
      );
      await _loadConfig();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Отправка зашифрованных отключена')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onResetKey() async {
    if (!await _ensureMasterUnlocked()) return;

    final firstConfirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            size: 48, color: Colors.red),
        title: const Text(
          'Сбросить ключ чата?',
          textAlign: TextAlign.center,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.10),
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'ВНИМАНИЕ! Все ранее отправленные и полученные '
                  'зашифрованные сообщения В ЭТОМ ЧАТЕ станут '
                  'НЕЧИТАЕМЫМИ — они навсегда останутся с закрытым '
                  'замком 🔒.\n\n'
                  'Это действие НЕОБРАТИМО.',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.red.shade900,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Что произойдёт:',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '• Текущий ключ чата будет безвозвратно удалён.\n'
                '• Сразу после удаления будет создан НОВЫЙ ключ.\n'
                '• Старые сообщения нельзя будет расшифровать ничем —\n'
                '  ни на вашем устройстве, ни у собеседника.\n'
                '• Собеседнику нужно будет передать новый ключ заново\n'
                '  (через QR / экспорт), иначе вы не поймёте друг друга.',
                style: GoogleFonts.inter(fontSize: 12.5, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Понимаю, продолжить'),
          ),
        ],
      ),
    );
    if (firstConfirm != true) return;


    final secondConfirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Последнее подтверждение'),
        content: const Text(
          'Сбросить ключ ОКОНЧАТЕЛЬНО? Восстановить старые сообщения '
          'будет невозможно.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Нет, оставить'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Да, сбросить'),
          ),
        ],
      ),
    );
    if (secondConfirm != true) return;


    // Повторная проверка — мастер мог залочиться пока шли диалоги.
    if (!await _ensureMasterUnlocked()) return;

    setState(() => _busy = true);
    try {
      // 1. Удаляем chat_key из Secure Storage и RAM-кэша.
      await MasterKeyManager.instance.removeChatKey(widget.chatId);
      // 2. Удаляем конфиг чата (включая legacyXorPassword).
      await ChatEncryptionService.deleteConfig(widget.chatId);
      // 3. Сразу создаём новый chat_key (по выбору пользователя — ротация).
      await ChatEncryptionService.setPasswordForChat(widget.chatId, '');
      await ChatEncryptionService.setSendEncryptedForChat(
        widget.chatId,
        true,
      );
      await _loadConfig();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ключ сброшен и сгенерирован заново. Передайте новый '
            'ключ собеседнику через QR.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка сброса ключа: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onToggleSendEncrypted(bool value) async {
    setState(() => _sendEncrypted = value);
    await ChatEncryptionService.setSendEncryptedForChat(
      widget.chatId,
      value,
    );
  }

  Future<void> _onToggleEncryptFiles(bool value) async {
    setState(() => _encryptFiles = value);
    await _saveConfig();
  }

  Future<void> _onProfileChanged(String value) async {
    setState(() => _obfuscationProfile = value);
    await _saveConfig();
  }

  Future<void> _onFileNameProfileChanged(String value) async {
    setState(() => _fileNameProfile = value);
    await _saveConfig();
  }

  /// Подставляет в шаблон-пример (типа 'IMG_20260315_142233.bin') реальное
  /// расширение, выбранное пользователем. Нужно чтобы превью в UI всегда
  /// соответствовало текущим настройкам.
  String _substituteExt(String example, String currentExt) {
    final dot = example.lastIndexOf('.');
    if (dot <= 0) return example;
    return '${example.substring(0, dot)}.$currentExt';
  }

  Future<void> _onExtChanged(String ext) async {
    // F-NEW fix: санитизация — расширение не должно содержать разделителей
    // или служебных символов. Иначе сервер может отклонить, или возникнут
    // проблемы при кросс-платформенной работе.
    final clean = ext
        .replaceAll('.', '')
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toLowerCase()
        .trim();
    if (clean.isEmpty) return;
    if (clean.length > 10) {
      // Длинные расширения — фильтр-провокатор для сервера, обрезаем.
      return;
    }
    if (!mounted) return;
    setState(() => _fileExtension = clean);
    await _saveConfig();
  }

  Future<void> _saveConfig() async {
    final cfg = await ChatEncryptionService.getConfigForChat(widget.chatId);
    if (cfg == null) return;
    await ChatEncryptionService.saveRawConfigForChat(
      widget.chatId,
      cfg.copyWith(
        obfuscationProfile: _obfuscationProfile,
        encryptedFileExtension: _fileExtension,
        encryptedFileNameProfile: _fileNameProfile,
        encryptFiles: _encryptFiles,
      ),
    );
  }

  Future<void> _onShare() async {
    if (!await _ensureMasterUnlocked()) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => KeyShareExportScreen(chatId: widget.chatId),
      ),
    );
  }

  Future<void> _onImport() async {
    if (!await _ensureMasterUnlocked()) return;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => KeyShareImportScreen(chatId: widget.chatId),
      ),
    );
    if (result == true) {
      await _loadConfig();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Шифрование чата', style: GoogleFonts.inter()),
      ),
      body: !_initialized
          ? const Center(child: CircularProgressIndicator())
          : AbsorbPointer(
              absorbing: _busy,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'ID чата: ${widget.chatId}',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _statusCard(),
                  const SizedBox(height: 24),
                  if (_hasNewKey) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Отправлять зашифрованные сообщения',
                      ),
                      subtitle: const Text(
                        'Если выключено — сообщения уйдут в открытом виде, '
                        'но входящие зашифрованные продолжат расшифровываться',
                      ),
                      value: _sendEncrypted,
                      onChanged: _onToggleSendEncrypted,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Шифровать файлы и фото'),
                      subtitle: const Text(
                        'Авто-расшифровка при скачивании',
                      ),
                      value: _encryptFiles,
                      onChanged: _onToggleEncryptFiles,
                    ),
                    const Divider(height: 24),
                    Text(
                      'Профиль обфускации',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Как зашифрованный текст маскируется под обычный. '
                      'У вас и собеседника может быть разный профиль — '
                      'декодер сам определит нужный.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ..._profiles.map(
                      (pr) => RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(pr.$2,
                            style: GoogleFonts.inter(fontSize: 13)),
                        value: pr.$1,
                        groupValue: _obfuscationProfile,
                        onChanged: (v) => _onProfileChanged(v!),
                      ),
                    ),
                    const Divider(height: 24),
                    Text(
                      'Расширение зашифрованных файлов',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Что видит сервер MAX вместо реального формата',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _extPresets.map((ext) {
                        // Чип подсвечен, если текущее расширение совпадает
                        // с пресетом. Не привязываемся к _customExtCtl.text:
                        // пользователь мог стереть кастом, но _fileExtension
                        // всё ещё хранит его — пресет не должен ложно
                        // подсвечиваться, и наоборот, пресет должен
                        // подсвечиваться когда сохранён именно он.
                        return ChoiceChip(
                          label: Text('.$ext'),
                          selected: _fileExtension == ext,
                          onSelected: (_) {
                            _customExtCtl.clear();
                            _onExtChanged(ext);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _customExtCtl,
                            decoration: const InputDecoration(
                              labelText: 'Своё расширение',
                              hintText: 'Без точки, напр. jpg',
                              prefixText: '.',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: _onExtChanged,
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () =>
                              _onExtChanged(_customExtCtl.text),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Text(
                      'Имя зашифрованного файла',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Под какой шаблон маскируется имя файла перед '
                      'отправкой. Сервер MAX увидит только это имя; '
                      'оригинальное название восстанавливается '
                      'при расшифровке у получателя.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...EncryptedFileService.fileNameProfiles.map(
                      (pr) => RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          pr.label,
                          style: GoogleFonts.inter(fontSize: 13),
                        ),
                        subtitle: Text(
                          'Пример: ${_substituteExt(pr.example, _fileExtension)}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                        value: pr.id,
                        groupValue: _fileNameProfile,
                        onChanged: (v) => _onFileNameProfileChanged(v!),
                      ),
                    ),
                    const Divider(height: 24),
                    // Пароль для расшифровки старых XOR-сообщений
                    Text(
                      'Пароль для старых сообщений',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Если до включения шифрования чат использовал '
                      'старый XOR-пароль — введите его здесь для '
                      'расшифровки исторических сообщений.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _legacyXorCtl,
                            obscureText: _legacyXorObscure,
                            decoration: InputDecoration(
                              labelText: 'Старый XOR-пароль',
                              border: const OutlineInputBorder(),
                              isDense: true,
                              suffixIcon: IconButton(
                                icon: Icon(_legacyXorObscure
                                    ? Icons.visibility
                                    : Icons.visibility_off),
                                onPressed: () => setState(
                                    () => _legacyXorObscure = !_legacyXorObscure),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _onSaveLegacyXor,
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                    if (_hasLegacyArchive) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.check_circle,
                              size: 14, color: Colors.green),
                          const SizedBox(width: 4),
                          Text('Пароль сохранён',
                              style: GoogleFonts.inter(
                                  fontSize: 12, color: Colors.green)),
                          const Spacer(),
                          TextButton(
                            onPressed: _onClearLegacyXor,
                            child: const Text('Удалить',
                                style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    ],
                    const Divider(height: 24),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _onShare,
                      icon: const Icon(Icons.qr_code),
                      label: const Text('Поделиться ключом'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _onImport,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Заменить ключ другим (импорт)'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _onResetKey,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Сбросить ключ чата'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Удалит текущий ключ и создаст новый. Старые '
                      'сообщения станут нечитаемыми (🔒).',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _onDisable,
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Отключить шифрование чата'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ] else ...[
                    FilledButton.icon(
                      onPressed: _onEnable,
                      icon: const Icon(Icons.lock),
                      label: const Text('Включить шифрование'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _onImport,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Импортировать ключ от собеседника'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Будет создан случайный ключ для этого чата, '
                      'защищённый вашим мастер-паролем. Для переписки с '
                      'другим человеком — обменяйтесь ключами через QR.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  Text(
                    'Как это работает',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Сообщения шифруются AES-256-GCM, ключ для каждого '
                    'чата случайный, защищён вашим мастер-паролем через '
                    'Argon2id. Серверу не известен ни ключ, ни сам факт '
                    'шифрования (используется обфускация под обычный '
                    'текст).',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: colors.primary.withValues(alpha: 0.20),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.favorite,
                          size: 16,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Спасибо разработчику проекта Crypt — '
                            'за архитектуру и реализацию шифрования.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: colors.onSurface,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _statusCard() {
    Color color;
    IconData icon;
    String title;
    String subtitle;

    if (_hasNewKey) {
      color = Colors.green;
      icon = Icons.lock;
      title = 'Шифрование включено';
      subtitle = _sendEncrypted
          ? 'Исходящие шифруются. Входящие расшифровываются.'
          : 'Только входящие расшифровываются. Исходящие — открытым текстом.';
    } else if (_hasLegacyArchive) {
      color = Colors.orange;
      icon = Icons.history;
      title = 'Только архив (старые сообщения)';
      subtitle = 'Старые XOR-сообщения будут расшифрованы. '
          'Новое шифрование не настроено — нажмите «Включить шифрование».';
    } else {
      color = Colors.grey;
      icon = Icons.lock_open;
      title = 'Шифрование не настроено';
      subtitle = 'Сообщения отправляются в открытом виде';
    }

    return Card(
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
