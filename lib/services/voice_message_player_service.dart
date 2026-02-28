/// Глобальный менеджер воспроизведения голосовых сообщений.
/// Гарантирует что только одно ГС играет в один момент времени.
library;

import 'dart:async';

class VoiceMessagePlayerService {
  VoiceMessagePlayerService._();
  static final VoiceMessagePlayerService instance = VoiceMessagePlayerService._();

  // Колбек для остановки текущего плеера
  VoidCallback? _stopCurrentPlayer;
  String? _currentUrl;

  final _currentUrlController = StreamController<String?>.broadcast();

  /// Стрим текущего воспроизводимого URL (null = ничего не играет)
  Stream<String?> get currentUrlStream => _currentUrlController.stream;

  String? get currentUrl => _currentUrl;

  /// Регистрирует новый плеер как активный, останавливает предыдущий.
  /// [url] — URL текущего ГС
  /// [stop] — колбек для остановки этого плеера
  void registerPlaying(String url, VoidCallback stop) {
    if (_currentUrl == url) return;
    // Останавливаем предыдущий плеер
    _stopCurrentPlayer?.call();
    _stopCurrentPlayer = stop;
    _currentUrl = url;
    _currentUrlController.add(_currentUrl);
  }

  /// Вызывается когда плеер остановился сам (пауза, конец, dispose)
  void notifyStopped(String url) {
    if (_currentUrl == url) {
      _stopCurrentPlayer = null;
      _currentUrl = null;
      _currentUrlController.add(null);
    }
  }

  void dispose() {
    _currentUrlController.close();
  }
}

typedef VoidCallback = void Function();
