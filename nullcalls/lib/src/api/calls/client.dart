import '../../logger/logger.dart';
import 'raw_client.dart';
import 'messages/login_data.dart';
import 'messages/session_data.dart';
import 'messages/start_conversation_payload.dart';
import 'messages/started_conversation_info.dart';

class CallsClient {
  late CallsRawClient _rawClient;
  bool _initialized = false;

  Future<void> login(String callToken) async {
    MaxCallsLogger.debug('Logging in to Calls API');

    final sessionData = SessionData.create(callToken);
    
    // The login endpoint is hardcoded in the original
    final loginUrl = 'https://calls.mail.ru';
    
    // Create a temporary client just for login
    final tempClient = CallsRawClient(
      apiServer: loginUrl,
      sessionKey: '',
      sessionSecretKey: '',
    );

    final response = await tempClient.post(
      '/voip/session',
      sessionData.toJson(),
    );

    final loginData = LoginData.fromJson(response);
    MaxCallsLogger.info('Logged in to Calls API');

    // Now create the real client with session credentials
    _rawClient = CallsRawClient(
      apiServer: loginData.apiServer,
      sessionKey: loginData.sessionKey,
      sessionSecretKey: loginData.sessionSecretKey,
    );

    _initialized = true;
  }

  Future<StartedConversationInfo> startConversation(
    String conversationId, {
    bool isVideo = false,
  }) async {
    if (!_initialized) {
      throw StateError('CallsClient not initialized. Call login() first.');
    }

    MaxCallsLogger.debug('Starting conversation: $conversationId');

    final payload = StartConversationPayload.create(isVideo: isVideo);
    final response = await _rawClient.startConversation(
      conversationId,
      payload.toJson(),
    );

    final conversationInfo = StartedConversationInfo.fromJson(response);
    MaxCallsLogger.info('Conversation started');

    return conversationInfo;
  }
}
