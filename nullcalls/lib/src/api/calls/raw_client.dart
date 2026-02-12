import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../logger/logger.dart';

class CallsRawClient {
  final String apiServer;
  final String sessionKey;
  final String sessionSecretKey;

  CallsRawClient({
    required this.apiServer,
    required this.sessionKey,
    required this.sessionSecretKey,
  });

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> params,
  ) async {
    final url = Uri.parse('$apiServer$path');
    
    MaxCallsLogger.debug('Calls API POST $url with params: $params');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: params,
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Calls API request failed with status ${response.statusCode}: ${response.body}',
        );
      }

      final responseData = json.decode(response.body) as Map<String, dynamic>;
      MaxCallsLogger.debug('Calls API response: $responseData');

      return responseData;
    } catch (e) {
      MaxCallsLogger.error('Calls API request failed', e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> startConversation(
    String conversationId,
    Map<String, dynamic> payload,
  ) async {
    final params = {
      'conversation_id': conversationId,
      'session_key': sessionKey,
      'session_secret_key': sessionSecretKey,
      ...payload,
    };

    return post('/voip/conversation/start', params);
  }
}
