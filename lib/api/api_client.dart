import 'dart:async';
import 'dart:typed_data';
import '../core/connection/connection_state.dart';
import '../core/connection/connection_event.dart';
import '../core/packets/packet_protocol.dart';
import '../services/websocket_service.dart';
import '../services/pending_requests_service.dart';

/// Упрощенный API клиент для работы с сервером
/// 
/// Использует WebSocketService для соединения и PendingRequestsService
/// для отслеживания запросов.
class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  final WebSocketService _webSocket = WebSocketService();
  final PendingRequestsService _pending = PendingRequestsService();
  final PacketBuffer _packetBuffer = PacketBuffer();
  
  StreamSubscription? _eventSubscription;
  StreamSubscription? _stateSubscription;
  
  int _sequence = 0;
  bool _isSessionReady = false;
  Completer<void>? _readyCompleter;
  
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<ConnectionInfo>.broadcast();
  
  /// Поток входящих сообщений
  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  
  /// Поток состояний соединения  
  Stream<ConnectionInfo> get connectionState => _connectionController.stream;
  
  /// Текущее состояние
  ConnectionInfo get currentState => _webSocket.currentState;
  
  /// Сессия готова
  bool get isSessionReady => _isSessionReady;
  
  /// Соединение активно
  bool get isConnected => _webSocket.isConnected;
  
  /// Инициализация клиента
  Future<void> initialize() async {
    _pending.initialize();
    await _webSocket.initialize();
    
    _eventSubscription = _webSocket.events.listen(_handleEvent);
    _stateSubscription = _webSocket.state.listen(_connectionController.add);
  }
  
  /// Подключиться к серверу
  Future<void> connect() async {
    await _webSocket.connect();
  }
  
  /// Отключиться от сервера
  Future<void> disconnect() async {
    await _webSocket.disconnect();
    _pending.clearAll(reason: 'disconnected');
  }
  
  /// Ожидать готовности сессии
  Future<void> waitForSession() async {
    if (_isSessionReady) return;
    _readyCompleter ??= Completer<void>();
    return _readyCompleter!.future;
  }
  
  /// Отправить запрос и дождаться ответа
  Future<Map<String, dynamic>> sendRequest(
    int opcode,
    Map<String, dynamic> payload, {
    String? debugLabel,
    bool requireSession = true,
  }) async {
    if (requireSession && !_isSessionReady) {
      await waitForSession();
    }
    
    if (!isConnected) {
      throw Exception('Нет соединения с сервером');
    }
    
    final seq = _sequence++ % 256;
    final completer = _pending.register(seq, debugLabel: debugLabel ?? 'op_$opcode');
    
    final packet = Packet(
      version: 11,
      command: 0,
      sequence: seq,
      opcode: opcode,
      payload: payload,
      receivedAt: DateTime.now(),
    );
    
    final sent = await _webSocket.sendBinary(packet.toBytes());
    if (!sent) {
      _pending.completeError(seq, Exception('Не удалось отправить пакет'));
    }
    
    return await completer.future as Map<String, dynamic>;
  }
  
  /// Отправить сообщение без ожидания ответа
  Future<int> sendMessage(
    int opcode,
    Map<String, dynamic> payload, {
    String? debugLabel,
  }) async {
    final seq = _sequence++ % 256;
    
    final packet = Packet(
      version: 11,
      command: 0,
      sequence: seq,
      opcode: opcode,
      payload: payload,
      receivedAt: DateTime.now(),
    );
    
    await _webSocket.sendBinary(packet.toBytes());
    return seq;
  }
  
  /// Освобождение ресурсов
  void dispose() {
    _eventSubscription?.cancel();
    _stateSubscription?.cancel();
    _webSocket.dispose();
    _pending.dispose();
    _messageController.close();
    _connectionController.close();
  }
  
  void _handleEvent(ConnectionEvent event) {
    switch (event) {
      case ConnectedEvent():
        _isSessionReady = false;
        break;
        
      case DataReceivedEvent(:final data):
        _handleData(data);
        break;
        
      case DisconnectedEvent():
        _isSessionReady = false;
        _readyCompleter = null;
        break;
        
      case ConnectionErrorEvent(:final error):
        print('❌ Ошибка соединения: $error');
        break;
        
      default:
        break;
    }
  }
  
  void _handleData(Map<String, dynamic> data) {
    // Бинарные данные
    if (data['binary'] != null) {
      _handleBinaryData(data['binary'] as Uint8List);
      return;
    }
    
    // JSON данные (для совместимости)
    _messageController.add(data);
  }
  
  void _handleBinaryData(Uint8List data) {
    _packetBuffer.append(data);
    
    while (true) {
      final packet = _packetBuffer.tryReadPacket();
      if (packet == null) break;
      
      _processPacket(packet);
    }
  }
  
  void _processPacket(Packet packet) {
    // Опкоды готовности сессии
    if (!_isSessionReady && 
        (packet.opcode == 32 || packet.opcode == 64 || packet.opcode == 128)) {
      _isSessionReady = true;
      if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
        _readyCompleter!.complete();
      }
    }
    
    // Завершить pending запрос
    _pending.complete(packet.sequence, packet.toMap());
    
    // Отправить в общий поток
    _messageController.add(packet.toMap());
  }
}
