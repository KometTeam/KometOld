/// Состояние WebSocket соединения
enum ConnectionStatus {
  /// Начальное состояние
  initial,
  
  /// Подключение в процессе
  connecting,
  
  /// Соединение установлено
  connected,
  
  /// Сессия активна (после handshake)
  ready,
  
  /// Переподключение
  reconnecting,
  
  /// Соединение разорвано
  disconnected,
  
  /// Ошибка соединения
  error,
}

/// Информация о состоянии соединения
class ConnectionInfo {
  final ConnectionStatus status;
  final String? message;
  final String? serverUrl;
  final DateTime? connectedAt;
  final int? reconnectAttempt;
  
  const ConnectionInfo({
    required this.status,
    this.message,
    this.serverUrl,
    this.connectedAt,
    this.reconnectAttempt,
  });
  
  ConnectionInfo copyWith({
    ConnectionStatus? status,
    String? message,
    String? serverUrl,
    DateTime? connectedAt,
    int? reconnectAttempt,
  }) {
    return ConnectionInfo(
      status: status ?? this.status,
      message: message ?? this.message,
      serverUrl: serverUrl ?? this.serverUrl,
      connectedAt: connectedAt ?? this.connectedAt,
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
    );
  }
  
  bool get isConnected => status == ConnectionStatus.connected || status == ConnectionStatus.ready;
  bool get isReady => status == ConnectionStatus.ready;
  bool get isConnecting => status == ConnectionStatus.connecting || status == ConnectionStatus.reconnecting;
}
