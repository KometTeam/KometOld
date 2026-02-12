import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис для работы с REST API звонков (calls.okcdn.ru)
class CallsRestService {
  static const String _baseUrl = 'https://calls.okcdn.ru';
  
  String? _sessionKey;
  String? _sessionSecretKey;
  String? _uid;
  String? _externalUserId;

  /// Инициализация сессии звонков
  Future<void> initializeSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Получаем данные из основной сессии
      final sessionKey = prefs.getString('session_key');
      final sessionSecretKey = prefs.getString('session_secret_key');
      
      if (sessionKey == null || sessionSecretKey == null) {
        throw Exception('Нет данных сессии для звонков');
      }

      // Формируем параметры для fb.do
      final params = {
        'uid': '910342002155', // TODO: Получить из профиля
        'session_key': sessionKey,
        'session_secret_key': sessionSecretKey,
        'api_server': _baseUrl,
        'external_user_id': prefs.getInt('user_id')?.toString() ?? '',
      };

      print('📞 Инициализация сессии звонков...');
      print('📤 Параметры: $params');

      final response = await http.post(
        Uri.parse('$_baseUrl/fb.do'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: params,
      );

      if (response.statusCode != 200) {
        throw Exception('Ошибка инициализации: ${response.statusCode}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      print('✅ Сессия звонков инициализирована: $data');

      _sessionKey = sessionKey;
      _sessionSecretKey = sessionSecretKey;
      _uid = params['uid'];
      _externalUserId = params['external_user_id'];
      
    } catch (e) {
      print('❌ Ошибка инициализации сессии звонков: $e');
      rethrow;
    }
  }

  /// Начать разговор (отправить SDP offer)
  Future<Map<String, dynamic>> startConversation({
    required String conversationId,
    required String sdpOffer,
    bool isVideo = false,
  }) async {
    try {
      print('📞 Попытка начать разговор: $conversationId');
      print('📤 SDP Offer длина: ${sdpOffer.length} символов');
      
      // Пробуем БЕЗ авторизации - может сервер не требует её
      final params = {
        'conversation_id': conversationId,
        'sdp': sdpOffer,
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/voip/conversation/start'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: params,
      );

      print('📥 Ответ сервера: ${response.statusCode}');
      print('📥 Body: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}...');

      if (response.statusCode != 200) {
        print('⚠️ Сервер вернул ошибку: ${response.statusCode}');
        print('⚠️ Возможно нужна авторизация или другой формат запроса');
        // Возвращаем пустой объект, чтобы не падать
        return {};
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      print('✅ Получен ответ от сервера: ${data.keys}');

      return data;
      
    } catch (e) {
      print('❌ Ошибка startConversation: $e');
      // Не падаем, просто возвращаем пустой объект
      return {};
    }
  }

  /// Отправить ICE candidate
  Future<void> sendIceCandidate({
    required String conversationId,
    required String candidate,
  }) async {
    if (_sessionKey == null) return;

    try {
      final params = {
        'conversation_id': conversationId,
        'session_key': _sessionKey!,
        'session_secret_key': _sessionSecretKey!,
        'candidate': candidate,
      };

      await http.post(
        Uri.parse('$_baseUrl/voip/conversation/candidate'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: params,
      );

      print('🧊 ICE candidate отправлен');
      
    } catch (e) {
      print('⚠️ Ошибка отправки ICE candidate: $e');
    }
  }

  /// Завершить разговор
  Future<void> endConversation(String conversationId) async {
    if (_sessionKey == null) return;

    try {
      final params = {
        'conversation_id': conversationId,
        'session_key': _sessionKey!,
        'session_secret_key': _sessionSecretKey!,
      };

      await http.post(
        Uri.parse('$_baseUrl/voip/conversation/end'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: params,
      );

      print('📴 Разговор завершён через REST API');
      
    } catch (e) {
      print('⚠️ Ошибка завершения разговора: $e');
    }
  }
}
