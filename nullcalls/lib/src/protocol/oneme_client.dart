import 'dart:async';
import '../logger/logger.dart';
import '../socket/socket_client.dart';
import '../models/client_hello.dart';
import '../models/verification_request.dart';
import '../models/code_enter.dart';
import '../models/chat_sync.dart';
import '../models/call_token.dart';
import '../models/incoming_call.dart';

/// Клиент для работы с OneMe API через socket
class OneMeClient {
  late SocketClient _socket;
  final StreamController<IncomingCall> _incomingCallController =
      StreamController.broadcast();

  Stream<IncomingCall> get onIncomingCall => _incomingCallController.stream;

  /// Подключается к серверу OneMe
  Future<void> connect() async {
    _socket = SocketClient(
      host: 'api.oneme.ru',
      port: 443,
    );

    await _socket.connect();

    // Слушаем входящие звонки
    _socket.messages.listen((message) {
      final opcode = message['opcode'] as int;
      final cmd = message['cmd'] as int;

      // Проверяем что это успешный ответ (cmd = 0x100 или 256)
      if (cmd != 0x100 && cmd != 256) {
        return;
      }

      if (opcode == IncomingCall.opcode) {
        try {
          final payload = message['payload'] as Map<String, dynamic>;
          final incomingCallJson = IncomingCallJson.fromJson(payload);
          final incomingCall = IncomingCall.fromJson(incomingCallJson);

          MaxCallsLogger.info('Incoming call from: ${incomingCall.callerId}');
          _incomingCallController.add(incomingCall);
        } catch (e) {
          MaxCallsLogger.error('Failed to parse incoming call', e);
        }
      }
    });
  }

  /// Отправляет handshake
  Future<void> sendClientHello({
    String? mtInstanceId,
    int? clientSessionId,
    String? deviceId,
  }) async {
    final clientHello = ClientHello.create(
      mtInstanceId: mtInstanceId,
      clientSessionId: clientSessionId,
      deviceId: deviceId,
    );

    _socket.sendMessage(ClientHello.opcode, clientHello.toJson());
    MaxCallsLogger.debug('Sent ClientHello');

    // Ждем успешный ответ
    await _waitForSuccess(ClientHello.opcode);
    MaxCallsLogger.info('Handshake successful');
  }

  /// Запрашивает код верификации
  Future<String> requestVerification(String phone) async {
    final request = VerificationRequest.create(phone);
    _socket.sendMessage(VerificationRequest.opcode, request.toJson());

    MaxCallsLogger.debug('Sent VerificationRequest for $phone');

    // Ждем ответ
    final response = await _socket.waitForOpcode(VerificationRequest.opcode);
    final payload = response['payload'] as Map<String, dynamic>;
    final token = VerificationToken.fromJson(payload);

    MaxCallsLogger.info('Received verification token');
    return token.token;
  }

  /// Вводит код верификации
  Future<String> enterCode(String token, String code) async {
    final codeEnter = CodeEnter.create(token, code);
    _socket.sendMessage(CodeEnter.opcode, codeEnter.toJson());

    MaxCallsLogger.debug('Sent CodeEnter');

    // Ждем успешный ответ
    final response = await _socket.waitForOpcode(CodeEnter.opcode);
    final payload = response['payload'] as Map<String, dynamic>;
    final login = SuccessfulLogin.fromJson(payload);

    MaxCallsLogger.info('Successfully logged in');
    return login.token;
  }

  /// Синхронизирует чаты
  Future<void> syncChats(String token) async {
    final request = ChatSyncRequest.create(token);
    _socket.sendMessage(ChatSyncRequest.opcode, request.toJson());

    MaxCallsLogger.debug('Sent ChatSyncRequest');

    // Ждем успешный ответ
    await _waitForSuccess(ChatSyncRequest.opcode);
    MaxCallsLogger.debug('Chats synced');
  }

  /// Получает токен для звонков
  Future<String> getCallToken() async {
    const request = CallTokenRequest();
    _socket.sendMessage(CallTokenRequest.opcode, request.toJson());

    MaxCallsLogger.debug('Sent CallTokenRequest');

    // Ждем ответ
    final response = await _socket.waitForOpcode(CallTokenRequest.opcode);
    final payload = response['payload'] as Map<String, dynamic>;
    final callToken = CallToken.fromJson(payload);

    MaxCallsLogger.info('Received call token');
    return callToken.token;
  }

  /// Ждет успешный ответ от сервера
  Future<void> _waitForSuccess(int opcode) async {
    final response = await _socket.waitForOpcode(opcode);
    final cmd = response['cmd'] as int;

    if (cmd == 0x300 || cmd == 768) {
      // Ошибка
      final payload = response['payload'];
      throw Exception('Server error: $payload');
    }
  }

  /// Закрывает соединение
  Future<void> close() async {
    await _socket.close();
    await _incomingCallController.close();
  }
}
