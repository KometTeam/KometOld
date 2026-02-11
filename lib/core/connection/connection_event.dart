/// Базовый класс событий соединения
sealed class ConnectionEvent {
  const ConnectionEvent();
}

/// Соединение установлено
class ConnectedEvent extends ConnectionEvent {
  final String serverUrl;
  const ConnectedEvent(this.serverUrl);
}

/// Соединение разорвано
class DisconnectedEvent extends ConnectionEvent {
  final String? reason;
  const DisconnectedEvent({this.reason});
}

/// Сессия готова к работе
class SessionReadyEvent extends ConnectionEvent {
  const SessionReadyEvent();
}

/// Получены данные
class DataReceivedEvent extends ConnectionEvent {
  final Map<String, dynamic> data;
  const DataReceivedEvent(this.data);
}

/// Ошибка соединения
class ConnectionErrorEvent extends ConnectionEvent {
  final String error;
  final bool isFatal;
  const ConnectionErrorEvent(this.error, {this.isFatal = false});
}

/// Начато переподключение
class ReconnectingEvent extends ConnectionEvent {
  final int attempt;
  final Duration delay;
  const ReconnectingEvent({required this.attempt, required this.delay});
}
