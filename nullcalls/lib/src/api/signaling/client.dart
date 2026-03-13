import 'dart:async';
import '../../logger/logger.dart';
import 'raw_client.dart';
import 'messages/server_hello.dart';
import 'messages/accept_call.dart';
import 'messages/transmit_data.dart';
import 'messages/new_candidate.dart';
import 'messages/credentials.dart';

class SignalingClient {
  late SignalingRawClient _rawClient;
  final StreamController<NewCandidate> _candidateController =
      StreamController.broadcast();
  final StreamController<Credentials> _credentialsController =
      StreamController.broadcast();

  Stream<NewCandidate> get onCandidate => _candidateController.stream;
  Stream<Credentials> get onCredentials => _credentialsController.stream;
  Stream<Map<String, dynamic>> get rawMessages => _rawClient.messages;

  Future<void> connect(String url, String token) async {
    _rawClient = SignalingRawClient(url: url, token: token);
    await _rawClient.connect();

    // Listen for incoming messages
    _rawClient.messages.listen((message) {
      final command = message['command'] as String?;
      
      if (command == 'new-candidate') {
        try {
          final data = message['data'] as Map<String, dynamic>;
          final candidate = NewCandidate.fromJson(data);
          _candidateController.add(candidate);
        } catch (e) {
          MaxCallsLogger.error('Failed to parse new-candidate', e);
        }
      } else if (command == 'credentials') {
        try {
          final data = message['data'] as Map<String, dynamic>;
          final credentials = Credentials.fromJson(data);
          _credentialsController.add(credentials);
        } catch (e) {
          MaxCallsLogger.error('Failed to parse credentials', e);
        }
      }
    });
  }

  Future<ServerHello> waitForServerHello() async {
    MaxCallsLogger.debug('Waiting for server-hello');
    final response = await _rawClient.waitForCommand('server-hello');
    return ServerHello.fromJson(response);
  }

  void acceptCall() {
    MaxCallsLogger.debug('Accepting call');
    final acceptCall = AcceptCall.create(1);
    _rawClient.send(acceptCall.toJson());
  }

  void transmitData(int participantId, dynamic data) {
    MaxCallsLogger.debug('Transmitting data to participant $participantId');
    final transmitData = TransmitData.create(
      sequence: 1,
      participantId: participantId,
      data: data,
    );
    _rawClient.send(transmitData.toJson());
  }

  void sendCandidate(int participantId, String candidate) {
    MaxCallsLogger.debug('Sending ICE candidate');
    final candidateData = NewCandidate(candidate: candidate);
    transmitData(participantId, candidateData.toJson());
  }

  void sendCredentials(int participantId, Credentials credentials) {
    MaxCallsLogger.debug('Sending ICE credentials');
    transmitData(participantId, credentials.toJson());
  }

  Future<void> close() async {
    await _rawClient.close();
    await _candidateController.close();
    await _credentialsController.close();
  }
}
