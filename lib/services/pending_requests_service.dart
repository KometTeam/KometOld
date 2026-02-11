import 'dart:async';
import 'dart:collection';

/// Информация о pending запросе
class PendingRequest {
  final int sequence;
  final Completer<dynamic> completer;
  final DateTime createdAt;
  final String? debugLabel;
  final Duration timeout;
  
  PendingRequest({
    required this.sequence,
    required this.completer,
    required this.createdAt,
    this.debugLabel,
    this.timeout = const Duration(seconds: 30),
  });
  
  bool get isExpired => 
      DateTime.now().difference(createdAt) > timeout;
}

/// Сервис для управления pending запросами
/// 
/// Отслеживает ожидающие ответа запросы и обрабатывает таймауты
class PendingRequestsService {
  static final PendingRequestsService _instance = PendingRequestsService._internal();
  factory PendingRequestsService() => _instance;
  PendingRequestsService._internal();

  final _requests = HashMap<int, PendingRequest>();
  Timer? _cleanupTimer;
  bool _isDisposed = false;
  
  /// Количество активных запросов
  int get pendingCount => _requests.length;
  
  /// Активные запросы
  Iterable<PendingRequest> get pendingRequests => _requests.values;
  
  /// Инициализация сервиса
  void initialize() {
    if (_isDisposed) return;
    
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _cleanupExpiredRequests();
    });
  }
  
  /// Регистрировать новый pending запрос
  Completer<dynamic> register(
    int sequence, {
    String? debugLabel,
    Duration timeout = const Duration(seconds: 30),
  }) {
    final completer = Completer<dynamic>();
    
    final request = PendingRequest(
      sequence: sequence,
      completer: completer,
      createdAt: DateTime.now(),
      debugLabel: debugLabel,
      timeout: timeout,
    );
    
    _requests[sequence] = request;
    
    // Автоматический таймаут
    Future.delayed(timeout, () {
      if (!completer.isCompleted && _requests.containsKey(sequence)) {
        completer.completeError(
          TimeoutException('Запрос $sequence (${debugLabel ?? "unknown"}) превысил таймаут'),
        );
        _requests.remove(sequence);
      }
    });
    
    return completer;
  }
  
  /// Завершить запрос успешно
  bool complete(int sequence, dynamic data) {
    final request = _requests.remove(sequence);
    if (request == null) return false;
    
    if (!request.completer.isCompleted) {
      request.completer.complete(data);
    }
    return true;
  }
  
  /// Завершить запрос с ошибкой
  bool completeError(int sequence, Object error) {
    final request = _requests.remove(sequence);
    if (request == null) return false;
    
    if (!request.completer.isCompleted) {
      request.completer.completeError(error);
    }
    return true;
  }
  
  /// Отменить все pending запросы
  void clearAll({String? reason}) {
    final error = reason != null 
        ? Exception('Запрос отменен: $reason')
        : Exception('Запрос отменен');
    
    for (final request in _requests.values) {
      if (!request.completer.isCompleted) {
        request.completer.completeError(error);
      }
    }
    _requests.clear();
  }
  
  /// Получить pending запрос по sequence
  PendingRequest? get(int sequence) => _requests[sequence];
  
  /// Проверить есть ли pending запрос
  bool has(int sequence) => _requests.containsKey(sequence);
  
  /// Освобождение ресурсов
  void dispose() {
    _isDisposed = true;
    _cleanupTimer?.cancel();
    clearAll(reason: 'service disposed');
  }
  
  void _cleanupExpiredRequests() {
    final expired = _requests.entries
        .where((e) => e.value.isExpired)
        .map((e) => e.key)
        .toList();
    
    for (final sequence in expired) {
      final request = _requests.remove(sequence);
      if (request != null && !request.completer.isCompleted) {
        request.completer.completeError(
          TimeoutException('Запрос $sequence истек при очистке'),
        );
      }
    }
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  
  @override
  String toString() => 'TimeoutException: $message';
}
