import 'dart:async';
import 'dart:convert';

import 'dart:typed_data';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../core/connection/connection_state.dart';
import '../core/connection/connection_event.dart';
import '../app_urls.dart';

/// Callback для обработки входящих бинарных данных
typedef BinaryDataHandler = void Function(Uint8List data);

/// Callback для обработки JSON данных
typedef JsonDataHandler = void Function(Map<String, dynamic> data);

/// Сервис для управления WebSocket соединением
/// 
/// Отвечает только за установку и поддержание соединения,
/// не содержит бизнес-логики приложения.
class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  IOWebSocketChannel? _channel;
  StreamSubscription? _subscription;
  
  final _eventController = StreamController<ConnectionEvent>.broadcast();
  final _stateController = StreamController<ConnectionInfo>.broadcast();
  
  ConnectionInfo _currentState = const ConnectionInfo(
    status: ConnectionStatus.initial,
  );
  
  Timer? _pingTimer;
  Timer? _pongTimeoutTimer;
  
  bool _isDisposed = false;
  bool _isConnecting = false;
  
  int _currentServerIndex = 0;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _baseReconnectDelay = Duration(seconds: 2);
  
  /// Поток событий соединения
  Stream<ConnectionEvent> get events => _eventController.stream;
  
  /// Поток состояний соединения
  Stream<ConnectionInfo> get state => _stateController.stream;
  
  /// Текущее состояние
  ConnectionInfo get currentState => _currentState;
  
  /// Соединение активно
  bool get isConnected => _currentState.isConnected;
  
  /// Инициализация сервиса
  Future<void> initialize() async {
    if (_isDisposed) return;
    _updateState(const ConnectionInfo(status: ConnectionStatus.initial));
  }
  
  /// Подключиться к серверу
  Future<void> connect() async {
    if (_isDisposed || _isConnecting) return;
    
    _isConnecting = true;
    _updateState(const ConnectionInfo(
      status: ConnectionStatus.connecting,
      message: 'Подключение к серверу...',
    ));
    
    try {
      await _tryConnect();
    } catch (e) {
      _updateState(ConnectionInfo(
        status: ConnectionStatus.error,
        message: 'Ошибка подключения: $e',
      ));
      _eventController.add(ConnectionErrorEvent(e.toString()));
      _scheduleReconnect();
    } finally {
      _isConnecting = false;
    }
  }
  
  /// Отключиться от сервера
  Future<void> disconnect() async {
    _pingTimer?.cancel();
    _pongTimeoutTimer?.cancel();
    _subscription?.cancel();
    
    await _channel?.sink.close(status.normalClosure);
    _channel = null;
    
    _updateState(const ConnectionInfo(
      status: ConnectionStatus.disconnected,
      message: 'Отключено',
    ));
  }

  /// Отправить JSON сообщение
  Future<bool> sendJson(Map<String, dynamic> data) async {
    if (_channel == null || !isConnected) {
      return false;
    }
    
    try {
      _channel!.sink.add(jsonEncode(data));
      return true;
    } catch (e) {
      print('❌ Ошибка отправки JSON: $e');
      return false;
    }
  }
  
  /// Отправить бинарные данные
  Future<bool> sendBinary(Uint8List data) async {
    if (_channel == null || !isConnected) {
      return false;
    }
    
    try {
      _channel!.sink.add(data);
      return true;
    } catch (e) {
      print('❌ Ошибка отправки бинарных данных: $e');
      return false;
    }
  }
  
  /// Принудительное переподключение
  Future<void> reconnect() async {
    await disconnect();
    _reconnectAttempts = 0;
    _currentServerIndex = 0;
    await connect();
  }
  
  /// Освобождение ресурсов
  void dispose() {
    if (_isDisposed) return;
    
    _isDisposed = true;
    disconnect();
    
    _eventController.close();
    _stateController.close();
  }
  
  // Private methods
  
  Future<void> _tryConnect() async {
    final servers = AppUrls.websocketUrls;
    
    while (_currentServerIndex < servers.length) {
      final serverUrl = servers[_currentServerIndex];
      
      try {
        await _connectToServer(serverUrl);
        _reconnectAttempts = 0;
        return;
      } catch (e) {
        print('⚠️ Ошибка подключения к $serverUrl: $e');
        _currentServerIndex++;
        
        if (_currentServerIndex < servers.length) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    
    throw Exception('Все серверы недоступны');
  }
  
  Future<void> _connectToServer(String url) async {
    final uri = Uri.parse(url);
    
    final headers = {
      'Origin': AppUrls.webOrigin,
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.0.36',
    };
    
    _channel = IOWebSocketChannel.connect(uri, headers: headers);
    await _channel!.ready;
    
    _subscription = _channel!.stream.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
    
    _updateState(ConnectionInfo(
      status: ConnectionStatus.connected,
      serverUrl: url,
      connectedAt: DateTime.now(),
    ));
    
    _eventController.add(ConnectedEvent(url));
    _startPingTimer();
  }
  
  void _onData(dynamic data) {
    if (data is Uint8List) {
      _eventController.add(DataReceivedEvent({'binary': data}));
    } else if (data is String) {
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        _eventController.add(DataReceivedEvent(json));
      } catch (e) {
        print('⚠️ Ошибка парсинга JSON: $e');
      }
    }
  }
  
  void _onError(Object error) {
    print('❌ Ошибка WebSocket: $error');
    _eventController.add(ConnectionErrorEvent(error.toString()));
    _scheduleReconnect();
  }
  
  void _onDone() {
    print('🔌 WebSocket соединение закрыто');
    _eventController.add(const DisconnectedEvent());
    _scheduleReconnect();
  }
  
  void _scheduleReconnect() {
    if (_isDisposed || _reconnectAttempts >= _maxReconnectAttempts) {
      _updateState(const ConnectionInfo(
        status: ConnectionStatus.error,
        message: 'Превышено максимальное количество попыток переподключения',
      ));
      return;
    }
    
    _reconnectAttempts++;
    final delay = _baseReconnectDelay * _reconnectAttempts;
    
    _updateState(ConnectionInfo(
      status: ConnectionStatus.reconnecting,
      message: 'Переподключение через ${delay.inSeconds}с...',
      reconnectAttempt: _reconnectAttempts,
    ));
    
    _eventController.add(ReconnectingEvent(
      attempt: _reconnectAttempts,
      delay: delay,
    ));
    
    Future.delayed(delay, () {
      if (!_isDisposed) {
        _currentServerIndex = 0;
        connect();
      }
    });
  }
  
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      sendJson({'opcode': 1, 'payload': {}});
      
      _pongTimeoutTimer?.cancel();
      _pongTimeoutTimer = Timer(const Duration(seconds: 10), () {
        print('⚠️ Таймаут pong ответа');
        reconnect();
      });
    });
  }
  
  void _updateState(ConnectionInfo newState) {
    _currentState = newState;
    _stateController.add(newState);
  }
}
