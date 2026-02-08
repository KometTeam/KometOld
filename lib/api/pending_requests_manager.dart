/// Менеджер ожидающих запросов с автоматической очисткой.
///
/// Решает проблему: текущая реализация не очищает зависшие Completer-ы
/// при обрыве соединения, что может приводить к утечкам памяти и
/// бесконечному ожиданию ответов, которые никогда не придут.

import 'dart:async';

class PendingRequest {
  final int seq;
  final Completer<dynamic> completer;
  final DateTime createdAt;
  final String? debugLabel;

  PendingRequest({
    required this.seq,
    required this.completer,
    required this.createdAt,
    this.debugLabel,
  });

  Duration get age => DateTime.now().difference(createdAt);
  bool get isTimedOut => age > const Duration(seconds: 30);
}

class PendingRequestsManager {
  final Map<int, PendingRequest> _pending = {};
  Timer? _cleanupTimer;

  /// Таймаут для зависших запросов (по умолчанию 30 секунд)
  final Duration requestTimeout;

  /// Callback для логирования таймаутов
  final void Function(int seq, String? label)? onTimeout;

  PendingRequestsManager({
    this.requestTimeout = const Duration(seconds: 30),
    this.onTimeout,
  }) {
    _startCleanupTimer();
  }

  /// Регистрирует новый ожидающий запрос
  Completer<dynamic> register(int seq, {String? debugLabel}) {
    // Если запрос с таким seq уже есть, просто удаляем старый
    // без вызова ошибки, чтобы избежать unhandled exceptions
    if (_pending.containsKey(seq)) {
      _pending.remove(seq);
    }

    final completer = Completer<dynamic>();
    _pending[seq] = PendingRequest(
      seq: seq,
      completer: completer,
      createdAt: DateTime.now(),
      debugLabel: debugLabel,
    );

    return completer;
  }

  /// Завершает запрос с результатом
  bool complete(int seq, dynamic result) {
    final request = _pending.remove(seq);
    if (request == null) return false;

    if (!request.completer.isCompleted) {
      request.completer.complete(result);
      return true;
    }
    return false;
  }

  /// Завершает запрос с ошибкой
  bool completeError(int seq, Object error, [StackTrace? stackTrace]) {
    final request = _pending.remove(seq);
    if (request == null) return false;

    if (!request.completer.isCompleted) {
      request.completer.completeError(error, stackTrace);
      return true;
    }
    return false;
  }

  /// Получает Completer для запроса (без удаления)
  Completer<dynamic>? get(int seq) {
    return _pending[seq]?.completer;
  }

  /// Проверяет, существует ли запрос
  bool has(int seq) => _pending.containsKey(seq);

  /// Количество ожидающих запросов
  int get count => _pending.length;

  /// Очищает все ожидающие запросы (например, при разрыве соединения)
  void clearAll({String reason = 'Connection lost'}) {
    final requests = List<PendingRequest>.from(_pending.values);
    _pending.clear();

    for (final request in requests) {
      if (!request.completer.isCompleted) {
        request.completer.completeError(
          StateError('Запрос отменен: $reason'),
        );
      }
    }
  }

  /// Очищает зависшие запросы (старше requestTimeout)
  int cleanupTimedOut() {
    final now = DateTime.now();
    final timedOut = <int>[];

    _pending.forEach((seq, request) {
      if (now.difference(request.createdAt) > requestTimeout) {
        timedOut.add(seq);
      }
    });

    for (final seq in timedOut) {
      final request = _pending.remove(seq);
      if (request != null && !request.completer.isCompleted) {
        onTimeout?.call(seq, request.debugLabel);
        request.completer.completeError(
          TimeoutException(
            'Запрос seq=$seq превысил таймаут ${requestTimeout.inSeconds}с',
            requestTimeout,
          ),
        );
      }
    }

    return timedOut.length;
  }

  /// Запускает периодическую очистку зависших запросов
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(
      const Duration(seconds: 10),
          (_) => cleanupTimedOut(),
    );
  }

  /// Останавливает таймер очистки
  void dispose() {
    _cleanupTimer?.cancel();
    clearAll(reason: 'Manager disposed');
  }

  /// Диагностическая информация
  Map<String, dynamic> getStats() {
    final now = DateTime.now();
    final ages = _pending.values.map((r) => now.difference(r.createdAt));

    return {
      'count': _pending.length,
      'oldestAge': ages.isEmpty ? 0 : ages.reduce((a, b) => a > b ? a : b).inSeconds,
      'avgAge': ages.isEmpty
          ? 0
          : ages.fold<int>(0, (sum, age) => sum + age.inSeconds) ~/ ages.length,
      'timedOut': _pending.values.where((r) => r.isTimedOut).length,
    };
  }

  /// Список всех ожидающих запросов (для отладки)
  List<Map<String, dynamic>> getPendingList() {
    return _pending.values.map((r) => {
      'seq': r.seq,
      'age': r.age.inSeconds,
      'label': r.debugLabel,
      'timedOut': r.isTimedOut,
    }).toList()..sort((a, b) => (b['age'] as int).compareTo(a['age'] as int));
  }
}
