import 'dart:async';
import 'package:gwid/api/api_service.dart';
import 'package:gwid/models/call_response.dart';

/// Сервис для обработки входящих звонков
class CallsService {
  CallsService._privateConstructor();
  static final CallsService instance = CallsService._privateConstructor();

  final StreamController<IncomingCallData> _incomingCallController =
      StreamController<IncomingCallData>.broadcast();

  /// Stream входящих звонков
  Stream<IncomingCallData> get incomingCalls => _incomingCallController.stream;

  StreamSubscription? _apiSubscription;
  bool _isInitialized = false;

  /// Инициализирует прослушивание входящих звонков
  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;

    // Слушаем сообщения от API
    _apiSubscription = ApiService.instance.messages.listen((message) {
      final opcode = message['opcode'];
      final cmd = message['cmd'];
      final payload = message['payload'];

      // Проверяем если это входящий звонок
      // opcode 78 (старый формат) или opcode 137 (новый формат с vcp)
      if (payload is Map<String, dynamic>) {
        if (opcode == 78 && cmd == 0) {
          _handleIncomingCall(payload);
        } else if (opcode == 137) {
          _handleIncomingCallV2(payload);
        }
      }
    });

    print('📞 CallsService инициализирован');
  }

  void _handleIncomingCall(Map<String, dynamic> payload) {
    try {
      // Парсим данные входящего звонка (старый формат)
      final conversationId = payload['conversationId'] as String?;
      final callerId = payload['callerId'] as int?;
      final callerName = payload['callerName'] as String?;
      final isVideo = payload['isVideo'] as bool? ?? false;

      if (conversationId == null || callerId == null) {
        print('⚠️ Некорректные данные входящего звонка');
        return;
      }

      print('📞 Входящий звонок от $callerName (ID: $callerId)');

      // Создаем объект входящего звонка
      final incomingCall = IncomingCallData(
        conversationId: conversationId,
        callerId: callerId,
        callerName: callerName ?? 'Неизвестный',
        isVideo: isVideo,
        timestamp: DateTime.now(),
      );

      // Отправляем в stream
      _incomingCallController.add(incomingCall);
    } catch (e) {
      print('❌ Ошибка обработки входящего звонка: $e');
    }
  }

  Future<void> _handleIncomingCallV2(Map<String, dynamic> payload) async {
    try {
      // Парсим данные входящего звонка (новый формат с opcode 137)
      final conversationId = payload['conversationId'] as String?;
      final callerId = payload['callerId'] as int?;
      final callType = payload['type'] as String?; // "AUDIO" или "VIDEO"
      final vcp = payload['vcp'] as String?; // base64 encoded video call params

      if (conversationId == null || callerId == null) {
        print('⚠️ Некорректные данные входящего звонка (opcode 137)');
        return;
      }

      final isVideo = callType == 'VIDEO';
      
      print('📞 Входящий звонок (v2) от ID: $callerId, тип: $callType');
      print('📦 VCP: ${vcp?.substring(0, 50)}...');

      // Получаем имя и аватарку из кэша контактов
      String callerName = 'Неизвестный';
      String? callerAvatarUrl;
      try {
        final contacts = await ApiService.instance.fetchContactsByIds([callerId]);
        if (contacts.isNotEmpty) {
          callerName = contacts.first.name;
          callerAvatarUrl = contacts.first.photoBaseUrl;
        }
      } catch (e) {
        print('⚠️ Не удалось получить данные контакта: $e');
      }

      // Создаем объект входящего звонка
      final incomingCall = IncomingCallData(
        conversationId: conversationId,
        callerId: callerId,
        callerName: callerName,
        callerAvatarUrl: callerAvatarUrl,
        isVideo: isVideo,
        timestamp: DateTime.now(),
      );

      // Отправляем в stream
      _incomingCallController.add(incomingCall);
    } catch (e) {
      print('❌ Ошибка обработки входящего звонка v2: $e');
    }
  }

  Future<CallResponse> acceptCall(String conversationId, int callerId) async {
    try {
      print('Accepting call: $conversationId');
      
      await ApiService.instance.sendCallEvent(
        eventType: 'INCOMING_CALL_INIT',
        conversationId: conversationId,
      );
      
      final response = await ApiService.instance.initiateCall(
        callerId,
        isVideo: false,
      );
      
      return response;
    } catch (e) {
      print('Error accepting call: $e');
      rethrow;
    }
  }

  Future<void> rejectCall(String conversationId) async {
    try {
      print('Rejecting call: $conversationId');
      
      await ApiService.instance.hangupCall(
        conversationId: conversationId,
        hangupType: 'REJECTED',
        duration: 0,
      );
    } catch (e) {
      print('Error rejecting call: $e');
      rethrow;
    }
  }

  void dispose() {
    _apiSubscription?.cancel();
    _incomingCallController.close();
    _isInitialized = false;
  }
}

/// Данные входящего звонка
class IncomingCallData {
  final String conversationId;
  final int callerId;
  final String callerName;
  final String? callerAvatarUrl;
  final bool isVideo;
  final DateTime timestamp;

  IncomingCallData({
    required this.conversationId,
    required this.callerId,
    required this.callerName,
    this.callerAvatarUrl,
    required this.isVideo,
    required this.timestamp,
  });
}
