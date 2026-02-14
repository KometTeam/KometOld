import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:gwid/api/api_service.dart';
import 'package:gwid/models/call_response.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Сервис для обработки входящих звонков
class CallsService extends ChangeNotifier {
  CallsService._privateConstructor();
  static final CallsService instance = CallsService._privateConstructor();

  final StreamController<IncomingCallData> _incomingCallController =
      StreamController<IncomingCallData>.broadcast();

  /// Stream входящих звонков
  Stream<IncomingCallData> get incomingCalls => _incomingCallController.stream;

  StreamSubscription? _apiSubscription;
  bool _isInitialized = false;
  
  /// Текущий входящий звонок
  IncomingCallData? _currentIncomingCall;
  
  /// Геттер для текущего входящего звонка
  IncomingCallData? get currentIncomingCall => _currentIncomingCall;
  
  /// Очистить текущий входящий звонок
  void clearIncomingCall() {
    _currentIncomingCall = null;
    notifyListeners();
  }

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

      // Сохраняем как текущий входящий звонок
      _currentIncomingCall = incomingCall;
      notifyListeners();
      
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

      // Сохраняем как текущий входящий звонок
      _currentIncomingCall = incomingCall;
      notifyListeners();
      
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

  Future<void> rejectCall(String conversationId, int callerId) async {
    try {
      print('📴 Rejecting incoming call: $conversationId');
      
      // Для отклонения входящего звонка нужно:
      // 1. Подключиться к WebSocket signaling
      // 2. Отправить команду hangup с reason=REJECTED
      // 3. Закрыть соединение
      
      // Сначала инициируем "звонок" чтобы получить endpoint
      final response = await ApiService.instance.initiateCall(
        callerId,
        isVideo: false,
      );
      
      print('📞 Получен endpoint для отклонения: ${response.internalCallerParams.endpoint}');
      
      // Подключаемся к WebSocket signaling
      final uri = Uri.parse(response.internalCallerParams.endpoint);
      final wsUri = uri.replace(queryParameters: {
        ...uri.queryParameters,
        'platform': 'WEB',
        'appVersion': '1.1',
        'version': '5',
        'device': 'browser',
        'capabilities': '2A03F',
        'clientType': 'ONE_ME',
        'tgt': 'start',
      });
      
      print('🔌 Подключаемся к WebSocket для отклонения...');
      final channel = WebSocketChannel.connect(wsUri);
      
      await channel.ready;
      print('✅ WebSocket подключен');
      
      // Отправляем hangup с reason=REJECTED
      final hangupMessage = {
        'command': 'hangup',
        'sequence': 1,
        'reason': 'REJECTED',
      };
      
      channel.sink.add(json.encode(hangupMessage));
      print('📤 Отправлено: hangup reason=REJECTED');
      
      // Ждём немного чтобы сообщение ушло
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Закрываем соединение
      await channel.sink.close();
      print('✅ Звонок отклонён');
      
    } catch (e) {
      print('❌ Error rejecting call: $e');
      // Fallback на старый метод через REST API
      try {
        await ApiService.instance.hangupCall(
          conversationId: conversationId,
          hangupType: 'REJECTED',
          duration: 0,
        );
      } catch (e2) {
        print('❌ Fallback также не сработал: $e2');
      }
    }
  }

  @override
  void dispose() {
    _apiSubscription?.cancel();
    _incomingCallController.close();
    _isInitialized = false;
    super.dispose();
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
