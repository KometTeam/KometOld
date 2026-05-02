// password_recovery_screen.dart — восстановление после прерванной смены
// мастер-пароля.
//
// Открывается автоматически из EncryptionStartupGate если
// MasterKeyManager.hasPendingPasswordChange() == true.
//
// Сценарий:
//   1. Показываем список чатов, чьи обёртки нечитаемы текущим master.
//   2. Пользователь вводит СТАРЫЙ пароль.
//   3. Запускаем recoverWithOldPassword() — пере-оборачиваем все
//      corrupted chat_keys текущим master.
//   4. После успеха pending salt+check удаляются.
//
// Альтернатива: «Пропустить» — теряем доступ к этим чатам, но приложение
// продолжает работать.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:gwid/services/crypt/master_key_manager.dart';

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  State<PasswordRecoveryScreen> createState() =>
      _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _oldPwCtl = TextEditingController();
  bool _busy = false;
  List<int>? _corruptedIds;
  String? _error;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _oldPwCtl.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final mgr = MasterKeyManager.instance;
    if (!mgr.isUnlocked) {
      // Master locked — диагностика невозможна без ключа в RAM.
      // Возвращаем пустой список и показываем сообщение, чтобы экран не
      // висел в спиннере вечно.
      if (!mounted) return;
      setState(() {
        _corruptedIds = const <int>[];
        _error =
            'Сначала разблокируйте приложение мастер-паролем. После этого '
            'откройте «Шифрование» → «Восстановление чатов».';
      });
      return;
    }
    try {
      final ids = await mgr.scanForCorruptedChatKeys();
      if (!mounted) return;
      setState(() => _corruptedIds = ids);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _corruptedIds = const <int>[];
        _error = 'Ошибка сканирования: $e';
      });
    }
  }

  Future<void> _onRecover() async {
    final ids = _corruptedIds;
    if (ids == null || ids.isEmpty) return;
    if (_oldPwCtl.text.isEmpty) {
      setState(() => _error = 'Введите старый пароль');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final mgr = MasterKeyManager.instance;
      final recovered = await mgr.recoverWithOldPassword(
        oldPassword: _oldPwCtl.text,
        corruptedChatIds: ids,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            recovered == ids.length
                ? 'Восстановлено $recovered чатов'
                : 'Восстановлено $recovered из ${ids.length}',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } on WrongMasterPasswordException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Неверный старый пароль';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Ошибка: $e';
      });
    }
  }

  Future<void> _onSkip() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Пропустить восстановление?'),
        content: Text(
          'Доступ к ${_corruptedIds?.length ?? 0} зашифрованным чатам '
          'будет потерян безвозвратно. Старые сообщения останутся в чатах, '
          'но прочитать их будет нельзя. Это действие необратимо.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Пропустить'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final ids = _corruptedIds ?? const <int>[];
    final mgr = MasterKeyManager.instance;
    await mgr.dropCorruptedChatKeys(ids);
    await mgr.dismissPendingPasswordChange();
    if (!mounted) return;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Восстановление чатов', style: GoogleFonts.inter()),
        automaticallyImplyLeading: false,
      ),
      body: _corruptedIds == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.warning_amber,
                      size: 56,
                      color: Colors.orange.shade700,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Прерванная смена пароля',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Прошлый раз вы меняли мастер-пароль, но операция '
                      'не завершилась полностью. Доступ к '
                      '${_corruptedIds!.length} зашифрованным чатам сейчас '
                      'нарушен. Введите старый пароль, чтобы восстановить '
                      'их.',
                      style: GoogleFonts.inter(fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    if (_corruptedIds!.isNotEmpty) _buildCorruptedList(),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _oldPwCtl,
                      obscureText: _obscure,
                      enabled: !_busy,
                      decoration: InputDecoration(
                        labelText: 'Старый мастер-пароль',
                        errorText: _error,
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_busy)
                      const LinearProgressIndicator()
                    else ...[
                      FilledButton(
                        onPressed: _onRecover,
                        style: FilledButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Восстановить'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _onSkip,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        child: const Text(
                          'Пропустить (потерять доступ к этим чатам)',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCorruptedList() {
    final ids = _corruptedIds!;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Затронутые чаты:',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: ids
                  .take(20)
                  .map((id) => Chip(label: Text('#$id')))
                  .toList(),
            ),
            if (ids.length > 20)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'и ещё ${ids.length - 20}…',
                  style: GoogleFonts.inter(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
