// master_password_unlock_screen.dart — ввод мастер-пароля для разблокировки
// зашифрованных чатов.
//
// Показывается:
//   - При старте приложения, если в Secure Storage есть мастер-пароль
//     и MasterKeyManager.isUnlocked == false.
//   - При попытке прочитать/отправить зашифрованное сообщение, когда
//     мастер ушёл в авто-релок.
//
// Использование:
//   final ok = await Navigator.of(context).push<bool>(
//     MaterialPageRoute(builder: (_) => MasterPasswordUnlockScreen()),
//   );
//   if (ok == true) { ... master_key теперь в RAM ... }
//
// При неверном пароле — показываем ошибку, не закрываем экран. Можно
// нажать «Отмена», тогда returns false (UI должен это обработать —
// например, скрыть содержимое чатов).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gwid/services/crypt/biometric_lock.dart';
import 'package:gwid/services/crypt/master_key_manager.dart';

class MasterPasswordUnlockScreen extends StatefulWidget {
  /// Показывать ли кнопку «Отмена». Если false — пользователь обязан
  /// ввести правильный пароль (например, при первом запуске).
  final bool allowCancel;

  /// Текст подзаголовка. По умолчанию — стандартный.
  final String? subtitle;

  const MasterPasswordUnlockScreen({
    super.key,
    this.allowCancel = true,
    this.subtitle,
  });

  @override
  State<MasterPasswordUnlockScreen> createState() =>
      _MasterPasswordUnlockScreenState();
}

class _MasterPasswordUnlockScreenState
    extends State<MasterPasswordUnlockScreen> {
  final _pwCtl = TextEditingController();
  final _focus = FocusNode();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  int _attempts = 0;
  bool _biometricEnabled = false;

  // F-NEW fix: rate limiting. Argon2id ~2 сек/попытку — это уже значительная
  // защита. Но для слабых паролей (4-6 цифр) бот может прогнать тысячи
  // попыток за день. Дополнительная защита: после 5 неудачных попыток
  // вводим cooldown который растёт линейно. После 10 — длинный cooldown
  // и предложение nuclear reset.
  //
  // Storage-ключи общие с другими сессиями приложения — счётчик не
  // сбрасывается при перезапуске.
  static const String _kAttemptsKey = 'komet_unlock_failed_attempts';
  static const String _kCooldownUntilKey = 'komet_unlock_cooldown_until_ms';
  Timer? _cooldownTimer;
  Duration _cooldownLeft = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadAttempts();
    _checkBiometric();
  }

  Future<void> _loadAttempts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(_kAttemptsKey) ?? 0;
      final cooldownMs = prefs.getInt(_kCooldownUntilKey) ?? 0;
      if (!mounted) return;
      setState(() {
        _attempts = stored;
      });
      if (cooldownMs > 0) {
        final left = DateTime.fromMillisecondsSinceEpoch(cooldownMs)
            .difference(DateTime.now());
        if (left.inMilliseconds > 0) {
          _startCooldownTimer(left);
        } else {
          await prefs.remove(_kCooldownUntilKey);
        }
      }
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _persistAttempts(int n) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kAttemptsKey, n);
    } catch (_) {}
  }

  Future<void> _persistCooldown(Duration d) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final until = DateTime.now().add(d).millisecondsSinceEpoch;
      await prefs.setInt(_kCooldownUntilKey, until);
    } catch (_) {}
  }

  Future<void> _clearAttemptsAndCooldown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kAttemptsKey);
      await prefs.remove(_kCooldownUntilKey);
    } catch (_) {}
  }

  Duration _computeCooldown(int attempts) {
    // 1-4 попытки: без cooldown.
    // 5-9: линейно 5/10/20/40/60 секунд.
    // 10+: 5 минут.
    if (attempts < 5) return Duration.zero;
    if (attempts == 5) return const Duration(seconds: 5);
    if (attempts == 6) return const Duration(seconds: 10);
    if (attempts == 7) return const Duration(seconds: 20);
    if (attempts == 8) return const Duration(seconds: 40);
    if (attempts == 9) return const Duration(seconds: 60);
    return const Duration(minutes: 5);
  }

  void _startCooldownTimer(Duration initial) {
    _cooldownTimer?.cancel();
    setState(() => _cooldownLeft = initial);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final left = _cooldownLeft - const Duration(seconds: 1);
      if (left.inSeconds <= 0) {
        setState(() => _cooldownLeft = Duration.zero);
        t.cancel();
      } else {
        setState(() => _cooldownLeft = left);
      }
    });
  }

  Future<void> _checkBiometric() async {
    final bio = await BiometricLock.instance.isEnabled();
    if (!mounted) return;
    setState(() => _biometricEnabled = bio);
    // Если биометрия включена — попробовать сразу.
    // F-NEW fix: но не пытаемся, если cooldown активен (например, после
    // 5 неудачных попыток ввода пароля).
    if (bio && _cooldownLeft.inSeconds == 0) {
      // Микро-задержка чтобы UI успел отрисоваться.
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      if (_cooldownLeft.inSeconds > 0) return;
      _onBiometricUnlock();
    }
  }

  Future<void> _onBiometricUnlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BiometricLock.instance.unlockWithBiometrics();
      // F-NEW fix: успешная биометрия тоже сбрасывает счётчик попыток.
      await _clearAttemptsAndCooldown();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on BiometricCancelledException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // Не показываем ошибку — пользователь сам отменил.
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Биометрия не сработала: $e';
      });
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _pwCtl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _onUnlock() async {
    if (_cooldownLeft.inSeconds > 0) {
      // F-NEW fix: пока идёт cooldown — кнопка должна быть disabled,
      // но на случай race ловим здесь.
      return;
    }
    final password = _pwCtl.text;
    if (password.isEmpty) {
      setState(() => _error = 'Введите пароль');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await MasterKeyManager.instance.unlock(password);
      // F-NEW fix: при успехе сбрасываем счётчик попыток и очищаем поле
      // пароля. _pwCtl.clear() мало что даёт (Dart String иммутабелен,
      // в строке `password` копия осталась), но снижает время жизни
      // пароля в TextEditingController и помогает не показывать его
      // случайно если экран резюмится.
      await _clearAttemptsAndCooldown();
      _pwCtl.clear();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on WrongMasterPasswordException {
      if (!mounted) return;
      _attempts++;
      await _persistAttempts(_attempts);
      _pwCtl.clear();
      final cooldown = _computeCooldown(_attempts);
      if (cooldown.inSeconds > 0) {
        await _persistCooldown(cooldown);
        _startCooldownTimer(cooldown);
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _attempts >= 10
            ? 'Слишком много попыток. Подождите ${cooldown.inMinutes} мин '
                'или сбросьте шифрование (потеряете доступ к чатам).'
            : _attempts >= 5
                ? 'Неверный пароль (попыток: $_attempts). '
                    'Подождите ${cooldown.inSeconds} сек.'
                : _attempts >= 3
                    ? 'Неверный пароль. Попыток: $_attempts. '
                        'Если забыли пароль — единственный вариант '
                        'сбросить шифрование.'
                    : 'Неверный пароль (попыток: $_attempts)';
      });
      _focus.requestFocus();
    } on MasterNotInitializedException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Мастер-пароль не настроен';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Ошибка: $e';
      });
    }
  }

  Future<void> _onForgotPassword() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Забыли пароль?'),
        content: const Text(
          'Восстановить мастер-пароль НЕВОЗМОЖНО. Если вы сбросите '
          'шифрование, все зашифрованные сообщения и ключи чатов будут '
          'удалены. Старые сообщения останутся в чатах, но прочитать их '
          'будет нельзя.\n\n'
          'Это действие НЕОБРАТИМО. Продолжить?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await MasterKeyManager.instance.nuclearReset();
    // F-NEW fix: после nuclearReset сбрасываем счётчик попыток —
    // мастер-пароля больше нет, шифрование заново настраивается с нуля.
    await _clearAttemptsAndCooldown();
    if (!mounted) return;
    // После nuclearReset мастер удалён, шифрование выключено. Закрываем
    // экран независимо от allowCancel — пользователь явно подтвердил
    // сброс. Возвращаем false как сигнал «пароль не введён, но и не нужен
    // больше». Вызывающий код (EncryptionStartupGate) должен проверить
    // isInitialized() == false и не показывать unlock-экран снова.
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Разблокировка', style: GoogleFonts.inter()),
        automaticallyImplyLeading: widget.allowCancel,
      ),
      body: PopScope(
        canPop: widget.allowCancel && !_busy,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 1),
                Icon(
                  Icons.lock,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Введите мастер-пароль',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.subtitle ??
                      'Для доступа к зашифрованным чатам',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _pwCtl,
                  focusNode: _focus,
                  autofocus: true,
                  obscureText: _obscure,
                  enabled: !_busy,
                  onSubmitted: (_) => _onUnlock(),
                  decoration: InputDecoration(
                    labelText: 'Пароль',
                    errorText: _error,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
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
                    onPressed: _cooldownLeft.inSeconds > 0 ? null : _onUnlock,
                    style: FilledButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      _cooldownLeft.inSeconds > 0
                          ? 'Подождите ${_cooldownLeft.inSeconds} сек…'
                          : 'Разблокировать',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_biometricEnabled) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _cooldownLeft.inSeconds > 0
                          ? null
                          : _onBiometricUnlock,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Биометрия'),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ],
                ],
                if (_busy)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Проверяем пароль (1-3 секунды)…',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                const Spacer(flex: 2),
                if (_attempts >= 3)
                  TextButton(
                    onPressed: _busy ? null : _onForgotPassword,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    child: const Text(
                      'Забыли пароль? (сбросить шифрование)',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
