// master_password_change_screen.dart — экран смены мастер-пароля.
//
// Показывается из настроек шифрования. Требует:
//   - Знания старого пароля.
//   - Подтверждение нового.
//
// Запускает MasterKeyManager.changeMasterPassword():
//   - Argon2id для нового master_key (~2-3 сек).
//   - Перешифровывает все обёртки chat_keys.
//
// При сбое посередине (приложение упало) — старый пароль перестанет
// работать, но новый сработает; обёртки чатов будут потеряны (TODO PR 3
// recovery flow).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:gwid/services/crypt/master_key_manager.dart';

class MasterPasswordChangeScreen extends StatefulWidget {
  const MasterPasswordChangeScreen({super.key});

  @override
  State<MasterPasswordChangeScreen> createState() =>
      _MasterPasswordChangeScreenState();
}

class _MasterPasswordChangeScreenState
    extends State<MasterPasswordChangeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _oldCtl = TextEditingController();
  final _newCtl = TextEditingController();
  final _newCtl2 = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _oldCtl.dispose();
    _newCtl.dispose();
    _newCtl2.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Сменить мастер-пароль?'),
        content: const Text(
          'Это перешифрует все ключи чатов на новый пароль. Операция '
          'может занять несколько секунд. Не выходите из приложения.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Сменить'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busy = true);

    try {
      await MasterKeyManager.instance.changeMasterPassword(
        _oldCtl.text,
        _newCtl.text,
      );
      if (!mounted) return;
      // F-NEW fix: очищаем поля паролей после успеха.
      _oldCtl.clear();
      _newCtl.clear();
      _newCtl2.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пароль успешно изменён')),
      );
      Navigator.of(context).pop(true);
    } on WrongMasterPasswordException {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Текущий пароль неверен'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String? _validateNonEmpty(String? v) {
    if (v == null || v.isEmpty) return 'Обязательное поле';
    return null;
  }

  String? _validateNew(String? v) {
    if (v == null || v.isEmpty) return 'Обязательное поле';
    if (v.length < 8) return 'Минимум 8 символов';
    if (v == _oldCtl.text) {
      return 'Новый пароль не может совпадать со старым';
    }
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v != _newCtl.text) return 'Пароли не совпадают';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Во время операции пользователь не должен иметь возможность выйти —
      // это может оставить storage в pending-состоянии (старые обёртки уже
      // не разворачиваются новым master, новые ещё не записаны). Recovery
      // существует, но лучше предотвратить состояние.
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Сменить пароль', style: GoogleFonts.inter()),
          // Во время _busy скрываем кнопку back в AppBar тоже.
          automaticallyImplyLeading: !_busy,
        ),
        body: AbsorbPointer(
          absorbing: _busy,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _oldCtl,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Текущий пароль',
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      validator: _validateNonEmpty,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _newCtl,
                      obscureText: _obscure,
                      decoration: const InputDecoration(
                        labelText: 'Новый пароль',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validateNew,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _newCtl2,
                      obscureText: _obscure,
                      decoration: const InputDecoration(
                        labelText: 'Подтвердите новый пароль',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validateConfirm,
                    ),
                    const SizedBox(height: 24),
                    if (_busy) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        'Перешифровываем ключи… не закрывайте приложение',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 13),
                      ),
                    ] else
                      FilledButton(
                        onPressed: _onSave,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Сменить пароль',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
