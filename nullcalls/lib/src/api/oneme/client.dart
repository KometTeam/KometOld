import 'dart:async';
import '../../logger/logger.dart';
import 'raw_client.dart';
import 'messages/client_hello.dart';
import 'messages/verification_request.dart';
import 'messages/verification_token.dart';
import 'messages/code_enter.dart';
import 'messages/successful_login.dart';
import 'messages/chat_sync_request.dart';
import 'messages/chat_sync_response.dart';
import 'messages/call_token_request.dart';
import 'messages/call_token.dart';
import 'messages/incoming_call.dart';

class OneMeClient {
  final OneMeRawClient _rawClient = OneMeRawClient();
  final StreamController<IncomingCall> _incomingCallController =
      StreamController.broadcast();

  Stream<IncomingCall> get onIncomingCall => _incomingCallController.stream;

  Future<void> connect() async {
    await _rawClient.connect();
    
    // Listen for incoming calls
    _rawClient.messages.listen((message) {
      final opcode = message['opcode'] as int;
      
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

  Future<void> sendClientHello() async {
    final clientHello = ClientHello.create();
    _rawClient.send(
      ClientHello.opcode,
      clientHello,
      (payload) => payload.toJson(),
    );
    MaxCallsLogger.debug('Sent ClientHello');
  }

  Future<String> requestVerification(String phone) async {
    final verificationRequest = VerificationRequest.create(phone);
    _rawClient.send(
      VerificationRequest.opcode,
      verificationRequest,
      (payload) => payload.toJson(),
    );

    MaxCallsLogger.debug('Sent VerificationRequest for $phone');

    // Wait for verification token response
    final response = await _rawClient.waitForOpcode(VerificationRequest.opcode);
    final payload = response['payload'] as Map<String, dynamic>;
    final verificationToken = VerificationToken.fromJson(payload);

    MaxCallsLogger.info('Received verification token');
    return verificationToken.token;
  }

  Future<String> enterCode(String token, String code) async {
    final codeEnter = CodeEnter.create(token, code);
    _rawClient.send(
      CodeEnter.opcode,
      codeEnter,
      (payload) => payload.toJson(),
    );

    MaxCallsLogger.debug('Sent CodeEnter');

    // Wait for successful login response
    final response = await _rawClient.waitForOpcode(CodeEnter.opcode);
    final payload = response['payload'] as Map<String, dynamic>;
    final successfulLogin = SuccessfulLogin.fromJson(payload);

    MaxCallsLogger.info('Successfully logged in');
    return successfulLogin.token;
  }

  Future<String?> syncChats(String token) async {
    final chatSyncRequest = ChatSyncRequest.create(token);
    _rawClient.send(
      ChatSyncRequest.opcode,
      chatSyncRequest,
      (payload) => payload.toJson(),
    );

    MaxCallsLogger.debug('Sent ChatSyncRequest');

    // Wait for chat sync response
    final response = await _rawClient.waitForOpcode(ChatSyncRequest.opcode);
    final payload = response['payload'] as Map<String, dynamic>;
    final chatSyncResponse = ChatSyncResponse.fromJson(payload);

    MaxCallsLogger.debug('Received ChatSyncResponse');
    return chatSyncResponse.token;
  }

  Future<String> getCallToken() async {
    final callTokenRequest = const CallTokenRequest();
    _rawClient.send(
      CallTokenRequest.opcode,
      callTokenRequest,
      (payload) => payload.toJson(),
    );

    MaxCallsLogger.debug('Sent CallTokenRequest');

    // Wait for call token response
    final response = await _rawClient.waitForOpcode(CallTokenRequest.opcode);
    final payload = response['payload'] as Map<String, dynamic>;
    final callToken = CallToken.fromJson(payload);

    MaxCallsLogger.info('Received call token');
    return callToken.token;
  }

  Future<void> close() async {
    await _rawClient.close();
    await _incomingCallController.close();
  }
}
