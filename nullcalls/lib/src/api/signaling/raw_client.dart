import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../logger/logger.dart';

class SignalingRawClient {
  final String url;
  final String token;
  
  WebSocketChannel? _channel;
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController.broadcast();
  
  int _sequenceNumber = 1;
  bool _isConnected = false;

  SignalingRawClient({
    required this.url,
    required this.token,
  });

  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  bool get isConnected => _isConnected;

  Future<void> connect() async {
    if (_isConnected) {
      MaxCallsLogger.warning('SignalingRawClient already connected');
      return;
    }

    try {
      final wsUrl = '$url?token=$token';
      MaxCallsLogger.debug('Connecting to Signaling WebSocket: $wsUrl');
      
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      await _channel!.ready;
      _isConnected = true;
      MaxCallsLogger.info('Connected to Signaling WebSocket');

      _channel!.stream.listen(
        (data) {
          try {
            final message = json.decode(data as String) as Map<String, dynamic>;
            MaxCallsLogger.debug('Received Signaling message: $message');
            _messageController.add(message);
          } catch (e) {
            MaxCallsLogger.error('Failed to parse Signaling message', e);
          }
        },
        onError: (error) {
          MaxCallsLogger.error('Signaling WebSocket error', error);
          _isConnected = false;
        },
        onDone: () {
          MaxCallsLogger.info('Signaling WebSocket connection closed');
          _isConnected = false;
        },
      );
    } catch (e) {
      MaxCallsLogger.error('Failed to connect to Signaling WebSocket', e);
      _isConnected = false;
      rethrow;
    }
  }

  void send(Map<String, dynamic> message) {
    if (!_isConnected || _channel == null) {
      throw StateError('Not connected to Signaling WebSocket');
    }

    final jsonString = json.encode(message);
    MaxCallsLogger.debug('Sending Signaling message: $jsonString');
    _channel!.sink.add(jsonString);
  }

  void sendWithSequence(Map<String, dynamic> message) {
    final messageWithSeq = {
      ...message,
      'sequence': _sequenceNumber++,
    };
    send(messageWithSeq);
  }

  Future<Map<String, dynamic>> waitForCommand(
    String command, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    final completer = Completer<Map<String, dynamic>>();
    late StreamSubscription subscription;

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        subscription.cancel();
        completer.completeError(
          TimeoutException('Timeout waiting for command $command'),
        );
      }
    });

    subscription = messages.listen((message) {
      if (message['command'] == command) {
        timer.cancel();
        subscription.cancel();
        completer.complete(message);
      }
    });

    return completer.future;
  }

  Future<void> close() async {
    MaxCallsLogger.debug('Closing Signaling WebSocket connection');
    await _channel?.sink.close();
    _isConnected = false;
    await _messageController.close();
  }
}
