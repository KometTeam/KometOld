import 'dart:convert';
import 'package:http/http.dart' as http;
import '../logger/logger.dart';

/// Данные авторизации в Calls API
class CallsLoginData {
  final String uid;
  final String sessionKey;
  final String sessionSecretKey;
  final String apiServer;
  final String externalUserId;

  const CallsLoginData({
    required this.uid,
    required this.sessionKey,
    required this.sessionSecretKey,
    required this.apiServer,
    required this.externalUserId,
  });

  factory CallsLoginData.fromJson(Map<String, dynamic> json) {
    return CallsLoginData(
      uid: json['uid'] as String,
      sessionKey: json['session_key'] as String,
      sessionSecretKey: json['session_secret_key'] as String,
      apiServer: json['api_server'] as String,
      externalUserId: json['external_user_id'] as String,
    );
  }
}

/// Информация о начатом разговоре
class StartedConversationInfo {
  final List<String> turnUrls;
  final String turnUsername;
  final String turnPassword;
  final List<String> stunUrls;
  final String endpoint;

  const StartedConversationInfo({
    required this.turnUrls,
    required this.turnUsername,
    required this.turnPassword,
    required this.stunUrls,
    required this.endpoint,
  });

  factory StartedConversationInfo.fromJson(Map<String, dynamic> json) {
    final turnServer = json['turn_server'] as Map<String, dynamic>;
    final stunServer = json['stun_server'] as Map<String, dynamic>;

    return StartedConversationInfo(
      turnUrls: (turnServer['urls'] as List).cast<String>(),
      turnUsername: turnServer['username'] as String,
      turnPassword: turnServer['credential'] as String,
      stunUrls: (stunServer['urls'] as List).cast<String>(),
      endpoint: json['endpoint'] as String,
    );
  }
}

/// Клиент для работы с Calls API (HTTP)
class CallsClient {
  CallsLoginData? _loginData;

  /// Авторизуется в Calls API
  Future<void> login(String callToken) async {
    MaxCallsLogger.debug('Logging in to Calls API');

    final sessionData = {
      'auth_token': callToken,
      'client_type': 'SDK_JS',
      'client_version': '1.1',
      'device_id': 'dart-client',
      'version': 3,
    };

    final response = await http.post(
      Uri.parse('https://calls.mail.ru/voip/session'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: sessionData,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to login: ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    _loginData = CallsLoginData.fromJson(data);

    MaxCallsLogger.info('Logged in to Calls API');
  }

  /// Начинает разговор
  Future<StartedConversationInfo> startConversation(
    String conversationId, {
    bool isVideo = false,
  }) async {
    if (_loginData == null) {
      throw StateError('Not logged in to Calls API');
    }

    MaxCallsLogger.debug('Starting conversation: $conversationId');

    final params = {
      'conversation_id': conversationId,
      'session_key': _loginData!.sessionKey,
      'session_secret_key': _loginData!.sessionSecretKey,
      'is_video': isVideo.toString(),
    };

    final response = await http.post(
      Uri.parse('${_loginData!.apiServer}/voip/conversation/start'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: params,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to start conversation: ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final info = StartedConversationInfo.fromJson(data);

    MaxCallsLogger.info('Conversation started');
    return info;
  }

  String? get externalUserId => _loginData?.externalUserId;
}
