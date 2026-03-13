import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../logger/logger.dart';
import 'packet_framer.dart';

/// Клиент для работы с TCP socket соединением к MAX API
class SocketClient {
  final String host;
  final int port;
  
  Socket? _socket;
  SecureSocket? _secureSocket;
  StreamSubscription? _subscription;
  
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  
  Uint8List _buffer = Uint8List(0);
  int _seq = 0;
  bool _isConnected = false;

  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  bool get isConnected => _isConnected;

  SocketClient({
    required this.host,
    required this.port,
  });

  /// Подключается к серверу через SSL/TLS
  Future<void> connect() async {
    if (_isConnected) {
      MaxCallsLogger.warning('SocketClient already connected');
      return;
    }

    try {
      MaxCallsLogger.debug('Connecting to $host:$port');
      
      // Создаем обычный сокет
      final rawSocket = await Socket.connect(host, port);
      _socket = rawSocket;
      
      // Оборачиваем в SSL/TLS
      final securityContext = SecurityContext.defaultContext;
      _secureSocket = await SecureSocket.secure(
        rawSocket,
        context: securityContext,
        host: host,
        onBadCertificate: (certificate) => true, // Принимаем любой сертификат
      );

      _isConnected = true;
      _buffer = Uint8List(0);
      _seq = 0;

      MaxCallsLogger.info('Connected to $host:$port');

      // Слушаем входящие данные
      _subscription = _secureSocket!.listen(
        _handleData,
        onError: (error) {
          MaxCallsLogger.error('Socket error', error);
          _isConnected = false;
        },
        onDone: () {
          MaxCallsLogger.info('Socket connection closed');
          _isConnected = false;
        },
      );
    } catch (e) {
      MaxCallsLogger.error('Failed to connect to socket', e);
      _isConnected = false;
      rethrow;
    }
  }

  /// Обрабатывает входящие данные
  void _handleData(Uint8List newData) {
    // Добавляем новые данные в буфер
    _buffer = Uint8List.fromList([..._buffer, ...newData]);

    // Обрабатываем все полные пакеты в буфере
    while (_buffer.length >= 10) {
      // Читаем длину payload из заголовка
      final header = _buffer.sublist(0, 10);
      final payloadLen = ByteData.view(header.buffer, 6, 4)
          .getUint32(0, Endian.big) & 0xFFFFFF;

      // Проверяем что у нас есть весь пакет
      if (_buffer.length < 10 + payloadLen) {
        break;
      }

      // Извлекаем полный пакет
      final fullPacket = _buffer.sublist(0, 10 + payloadLen);
      _buffer = _buffer.sublist(10 + payloadLen);

      // Обрабатываем пакет
      _processPacket(fullPacket);
    }
  }

  /// Обрабатывает один пакет
  void _processPacket(Uint8List packet) {
    try {
      final message = unpackPacket(packet);
      if (message != null) {
        MaxCallsLogger.debug('Received message: opcode=${message['opcode']}');
        _messageController.add(message);
      }
    } catch (e) {
      MaxCallsLogger.error('Failed to process packet', e);
    }
  }

  /// Отправляет сообщение
  int sendMessage(int opcode, Map<String, dynamic> payload) {
    if (!_isConnected || _secureSocket == null) {
      throw StateError('Not connected to socket');
    }

    _seq = (_seq + 1) % 256;
    final seq = _seq;

    final packet = packPacket(
      ver: 10,
      cmd: 0,
      seq: seq,
      opcode: opcode,
      payload: payload,
    );

    MaxCallsLogger.debug(
      'Sending message: opcode=$opcode, seq=$seq, size=${packet.length} bytes',
    );

    _secureSocket!.add(packet);
    return seq;
  }

  /// Ждет сообщение с определенным opcode
  Future<Map<String, dynamic>> waitForOpcode(
    int opcode, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    final completer = Completer<Map<String, dynamic>>();
    late StreamSubscription subscription;

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        subscription.cancel();
        completer.completeError(
          TimeoutException('Timeout waiting for opcode $opcode'),
        );
      }
    });

    subscription = messages.listen((message) {
      if (message['opcode'] == opcode) {
        timer.cancel();
        subscription.cancel();
        completer.complete(message);
      }
    });

    return completer.future;
  }

  /// Закрывает соединение
  Future<void> close() async {
    MaxCallsLogger.debug('Closing socket connection');
    await _subscription?.cancel();
    await _secureSocket?.close();
    await _socket?.close();
    _isConnected = false;
    await _messageController.close();
  }
}
