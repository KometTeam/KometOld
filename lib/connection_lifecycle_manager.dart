import 'package:flutter/material.dart';
import 'package:gwid/api/api_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class ConnectionLifecycleManager extends StatefulWidget {
  final Widget child;

  const ConnectionLifecycleManager({super.key, required this.child});

  @override
  _ConnectionLifecycleManagerState createState() =>
      _ConnectionLifecycleManagerState();
}

class _ConnectionLifecycleManagerState extends State<ConnectionLifecycleManager>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WakelockPlus.enable();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

  }

  @override
  void dispose() {
    _animationController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        print("Возобновлено");
        ApiService.instance.setAppInForeground(true);
        ApiService.instance.sendNavEvent('WARM_START');
        _checkAndReconnectIfNeeded();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        ApiService.instance.setAppInForeground(false);
        if (state == AppLifecycleState.paused) {
          ApiService.instance.sendNavEvent('GO', screenTo: 1, screenFrom: 150);
        }
        break;
    }
  }

  Future<void> _checkAndReconnectIfNeeded() async {
    if (ApiService.instance.isConnecting) {
      print("🔄 Подключение уже в процессе, пропускаем проверку (ранняя)");
      return;
    }

    final hasToken = await ApiService.instance.hasToken();
    if (!hasToken) {
      print("🔒 Токен отсутствует, переподключение не требуется");
      return;
    }

    await Future.delayed(const Duration(milliseconds: 500));

    if (ApiService.instance.isConnecting) {
      print("🔄 Подключение уже в процессе, пропускаем проверку");
      return;
    }

    final bool actuallyConnected = ApiService.instance.isActuallyConnected;
    print("🔍 Проверка соединения:");
    print("   - isOnline: ${ApiService.instance.isOnline}");
    print("   - isActuallyConnected: $actuallyConnected");

    if (!actuallyConnected) {
      print("🔌 Соединение потеряно. Запускаем переподключение...");
      _animationController.forward();

      try {
        await ApiService.instance.performFullReconnection();
        print("✅ Переподключение выполнено успешно");
        await _animationController.reverse();
      } catch (e) {
        print("❌ Ошибка при переподключении: $e");
        Future.delayed(const Duration(seconds: 3), () async {
          if (!ApiService.instance.isActuallyConnected) {
            print("🔁 Повторная попытка переподключения...");
            try {
              await ApiService.instance.performFullReconnection();
              await _animationController.reverse();
            } catch (e) {
              print("❌ Повторная попытка не удалась: $e");
              await _animationController.reverse();
            }
          }
        });
      }
    } else {}
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(children: [widget.child]),
    );
  }
}
