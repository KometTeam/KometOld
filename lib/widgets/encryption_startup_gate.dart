// encryption_startup_gate.dart — wrap-виджет, который при старте
// приложения определяет, нужна ли миграция или unlock мастер-пароля,
// и блокирует UI до их завершения.
//
// Использование в main.dart:
//
//   MaterialApp(
//     home: EncryptionStartupGate(
//       child: HomeScreen(),
//     ),
//   );
//
// Состояния:
//   1. Загрузка флагов (~10ms) — показываем splash.
//   2. Первый запуск без legacy — пропускаем, показываем child.
//   3. Есть legacy и не было миграции — навигируем на
//      MasterPasswordSetupScreen(mode: migration).
//   4. Master initialized но locked — показываем
//      MasterPasswordUnlockScreen.
//   5. Master initialized и unlocked — пропускаем.
//
// Также подписывается на MasterKeyManager.lockEvents и при auto-relock
// показывает UnlockScreen.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gwid/services/crypt/biometric_lock.dart';
import 'package:gwid/services/crypt/master_key_manager.dart';
import 'package:gwid/services/migration_v2.dart';
import 'package:gwid/screens/master_password_setup_screen.dart';
import 'package:gwid/screens/master_password_unlock_screen.dart';
import 'package:gwid/screens/password_recovery_screen.dart';

class EncryptionStartupGate extends StatefulWidget {
  final Widget child;

  const EncryptionStartupGate({super.key, required this.child});

  @override
  State<EncryptionStartupGate> createState() => _EncryptionStartupGateState();
}

enum _GateState {
  loading,
  pass, // ничего делать не надо, показываем child
  migrationNeeded,
  unlockNeeded,
  recoveryNeeded,
}

class _EncryptionStartupGateState extends State<EncryptionStartupGate>
    with WidgetsBindingObserver {
  _GateState _state = _GateState.loading;

  // F-NEW fix: время ухода в фон персистится в SharedPreferences. Раньше
  // оно жило только в RAM, и если ОС убивала процесс в фоне (Android
  // делает это часто), таймер relock сбрасывался. Теперь даже после
  // холодного старта мы можем посчитать elapsed.
  //
  // Ключ хранится в обычном SharedPreferences, не в Secure Storage —
  // подделка значения не даёт злоумышленнику ничего: максимум он сможет
  // сделать ВЫНУЖДЕННЫЙ relock (поставить старое время), что только
  // ужесточит защиту.
  static const String _kLastBgKey = 'komet_last_backgrounded_at_ms';
  DateTime? _lastBackgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Регистрируем cleanup-хуки для nuclearReset.
    // BiometricLock хранит мастер-ключ в отдельном storage —
    // его тоже нужно стереть.
    MasterKeyManager.instance.registerResetHook(
      BiometricLock.instance.wipeOnReset,
    );

    _restoreLastBackgrounded();
    _evaluate();

    // Слушаем lock events — например, при ручном lock из настроек.
    MasterKeyManager.instance.lockEvents.listen((_) {
      if (!mounted) return;
      _evaluate();
    });
  }

  Future<void> _restoreLastBackgrounded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_kLastBgKey);
      if (ms != null && ms > 0) {
        _lastBackgroundedAt = DateTime.fromMillisecondsSinceEpoch(ms);
      }
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _persistLastBackgrounded(DateTime t) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLastBgKey, t.millisecondsSinceEpoch);
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _clearLastBackgrounded() async {
    _lastBackgroundedAt = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kLastBgKey);
    } catch (_) {
      // best-effort
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // F-NEW fix: detached тоже фиксируем (на iOS это финальный shutdown
    // app extension). paused — обычное "ушло в фон". inactive — переходное
    // состояние, фиксируем для надёжности.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      final now = DateTime.now();
      _lastBackgroundedAt = now;
      // ignore: discarded_futures
      _persistLastBackgrounded(now);
    } else if (state == AppLifecycleState.resumed) {
      // Проверяем нужен ли auto-relock.
      _checkAutoRelock();
    }
  }

  Future<void> _checkAutoRelock() async {
    final mgr = MasterKeyManager.instance;
    if (!mgr.isUnlocked) return;
    if (_lastBackgroundedAt == null) {
      // Возможно мы только что стартанули и _restoreLastBackgrounded
      // ещё не отработал. Подождём короткий тик и попробуем снова.
      await Future.delayed(const Duration(milliseconds: 50));
      if (_lastBackgroundedAt == null) return;
    }

    final relockSeconds = await mgr.getRelockSeconds();
    if (relockSeconds == null) {
      // Авто-релок выключен — но всё равно очистим persisted timestamp,
      // чтобы он не накапливался.
      await _clearLastBackgrounded();
      return;
    }

    final elapsed = DateTime.now().difference(_lastBackgroundedAt!);
    if (elapsed.inSeconds >= relockSeconds) {
      mgr.lock();
      await _clearLastBackgrounded();
      // lockEvents триггернёт _evaluate автоматически.
    }
  }

  bool _evaluating = false;
  bool _reEvaluatePending = false;

  Future<void> _evaluate() async {
    // Простая re-entrancy защита: если _evaluate уже идёт, помечаем что
    // нужен повторный запуск — и текущий вызов после завершения дёрнет
    // себя ещё раз. Это предотвращает гонку между initState и
    // lockEvents.listen.
    if (_evaluating) {
      _reEvaluatePending = true;
      return;
    }
    _evaluating = true;
    try {
      await _evaluateInternal();
    } finally {
      _evaluating = false;
      if (_reEvaluatePending) {
        _reEvaluatePending = false;
        // Повторный запуск без await — не блокируем вызывающий fr.
        // ignore: discarded_futures
        _evaluate();
      }
    }
  }

  Future<void> _evaluateInternal() async {
    final mgr = MasterKeyManager.instance;

    // 1. Если master разблокирован — проверяем pending change.
    if (mgr.isUnlocked) {
      // Если предыдущая changeMasterPassword не завершилась —
      // показываем recovery flow.
      try {
        if (await mgr.hasPendingPasswordChange()) {
          _setState(_GateState.recoveryNeeded);
          return;
        }
      } catch (_) {}
      _setState(_GateState.pass);
      return;
    }

    // 2. Проверяем нужна ли миграция (есть legacy чаты + master не настроен).
    if (await MigrationV2.needsMigration()) {
      _setState(_GateState.migrationNeeded);
      return;
    }

    // 3. Master настроен, но locked → нужен unlock.
    if (await mgr.isInitialized()) {
      _setState(_GateState.unlockNeeded);
      return;
    }

    // 4. Ничего не настроено и legacy нет → пропускаем.
    _setState(_GateState.pass);
  }

  void _setState(_GateState s) {
    if (!mounted) return;
    setState(() => _state = s);
  }

  Future<void> _onMigrationDone() async {
    await _evaluate();
  }

  Future<void> _onUnlockDone() async {
    await _evaluate();
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _GateState.loading:
        return _buildSplash();
      case _GateState.pass:
        return widget.child;
      case _GateState.migrationNeeded:
        return _MigrationLauncher(onDone: _onMigrationDone);
      case _GateState.unlockNeeded:
        return _UnlockLauncher(onDone: _onUnlockDone);
      case _GateState.recoveryNeeded:
        return _RecoveryLauncher(onDone: _onUnlockDone);
    }
  }

  Widget _buildSplash() {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

/// Хост-виджет для миграционного экрана. Не позволяет уйти назад.
class _MigrationLauncher extends StatefulWidget {
  final VoidCallback onDone;
  const _MigrationLauncher({required this.onDone});

  @override
  State<_MigrationLauncher> createState() => _MigrationLauncherState();
}

class _MigrationLauncherState extends State<_MigrationLauncher> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_shown) return;
      _shown = true;
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const MasterPasswordSetupScreen(
            mode: MasterPasswordSetupMode.migration,
          ),
          fullscreenDialog: true,
        ),
      );
      if (ok == true) widget.onDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_clock, size: 56),
              const SizedBox(height: 16),
              Text(
                'Подготовка обновления шифрования…',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnlockLauncher extends StatefulWidget {
  final VoidCallback onDone;
  const _UnlockLauncher({required this.onDone});

  @override
  State<_UnlockLauncher> createState() => _UnlockLauncherState();
}

class _UnlockLauncherState extends State<_UnlockLauncher> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_shown) return;
      _shown = true;
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) =>
              const MasterPasswordUnlockScreen(allowCancel: false),
          fullscreenDialog: true,
        ),
      );
      // ok=true → unlocked; ok=false → пользователь сделал nuclearReset.
      // В обоих случаях вызываем _evaluate.
      widget.onDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _RecoveryLauncher extends StatefulWidget {
  final VoidCallback onDone;
  const _RecoveryLauncher({required this.onDone});

  @override
  State<_RecoveryLauncher> createState() => _RecoveryLauncherState();
}

class _RecoveryLauncherState extends State<_RecoveryLauncher> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_shown) return;
      _shown = true;
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const PasswordRecoveryScreen(),
          fullscreenDialog: true,
        ),
      );
      widget.onDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
