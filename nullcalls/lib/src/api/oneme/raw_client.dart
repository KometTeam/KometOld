import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../logger/logger.dart';
import 'message.dart';

class OneMeRawClient {
  static const String _wsUrl = 'wss://oneme.mail.ru:9443';
  
  WebSocketChannel? _channel;
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController.broadcast();
  
  int _sequenceNumber = 1;
  bool _isConnected = false;

  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  bool get isConnected => _isConnected;

  Future<void> connect() async {
    if (_isConnected) {
      MaxCallsLogger.warning('OneMeRawClient already connected');
      return;
    }

    try {
      MaxCallsLogger.debug('Connecting to OneMe WebSocket: $_wsUrl');
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      
      await _channel!.ready;
      _isConnected = true;
      MaxCallsLogger.info('Connected to OneMe WebSocket');

      _channel!.stream.listen(
        (data) {
          try {
            final message = json.decode(data as String) as Map<String, dynamic>;
            MaxCallsLogger.debug('Received OneMe message: $message');
            _messageController.add(message);
          } catch (e) {
            MaxCallsLogger.error('Failed to parse OneMe message', e);
          }
        },
        onError: (error) {
          MaxCallsLogger.error('OneMe WebSocket error', error);
          _isConnected = false;
        },
        onDone: () {
          MaxCallsLogger.info('OneMe WebSocket connection closed');
          _isConnected = false;
        },
      );
    } catch (e) {
      MaxCallsLogger.error('Failed to connect to OneMe WebSocket', e);
      _isConnected = false;
      rethrow;
    }
  }

  void sendMessage<T>(OneMeMessage<T> message, dynamic Function(T) payloadSerializer) {
    if (!_isConnected || _channel == null) {
      throw StateError('Not connected to OneMe WebSocket');
    }

    final jsonMessage = message.toJson(payloadSerializer);
    final jsonString = json.encode(jsonMessage);
    
    MaxCallsLogger.debug('Sending OneMe message: $jsonString');
    _channel!.sink.add(jsonString);
  }

  void send<T>(int opcode, T payload, dynamic Function(T) payloadSerializer) {
    final message = OneMeMessage.create(
      sequenceNumber: _sequenceNumber++,
      opcode: opcode,
      payload: payload,
    );
    sendMessage(message, payloadSerializer);
  }

  Future<Map<String, dynamic>> waitForOpcode(int opcode, {Duration timeout = const Duration(seconds: 30)}) {
    final completer = Completer<Map<String, dynamic>>();
    late StreamSubscription subscription;

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        subscription.cancel();
        completer.completeError(TimeoutException('Timeout waiting for opcode $opcode'));
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

  Future<void> close() async {
    MaxCallsLogger.debug('Closing OneMe WebSocket connection');
    await _channel?.sink.close();
    _isConnected = false;
    await _messageController.close();
  }
}
