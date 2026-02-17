part of 'api_service.dart';

/// Расширение ApiService для работы со звонками
extension ApiServiceCalls on ApiService {
  
  /// Отправляет событие звонка (аналитика)
  /// 
  /// [eventType] - тип события: "START_CALL", "INCOMING_CALL_INIT", etc.
  /// [conversationId] - ID разговора
  Future<void> sendCallEvent({
    required String eventType,
    required String conversationId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id') ?? 0;
      final sessionId = prefs.getInt('session_id') ?? DateTime.now().millisecondsSinceEpoch;
      
      final event = {
        'type': 'CALL',
        'userId': userId,
        'time': DateTime.now().millisecondsSinceEpoch,
        'sessionId': sessionId,
        'event': eventType,
        'params': {
          'call_id': conversationId,
          'event_label_int': 1,
          'is_group': false,
        },
      };
      
      _log(
        '📊 Отправка события звонка',
        level: LogLevel.info,
        data: {'event': eventType, 'conversationId': conversationId},
      );
      
      // Отправляем через opcode 5 (события)
      await sendRequest(5, {
        'events': [event],
      });
    } catch (e) {
      _log(
        '❌ Ошибка отправки события звонка',
        level: LogLevel.error,
        data: {'error': e.toString()},
      );
      // Не критично, не пробрасываем
    }
  }

  /// Отменяет или завершает звонок
  /// 
  /// [conversationId] - ID разговора
  /// [hangupType] - тип завершения: "CANCELED" (отменен), "HUNGUP" (завершен), "DECLINED" (отклонен)
  /// [duration] - длительность звонка в миллисекундах (0 если отменен)
  Future<void> hangupCall({
    required String conversationId,
    required String hangupType,
    int duration = 0,
  }) async {
    try {
      _log(
        '📴 Завершение звонка',
        level: LogLevel.info,
        data: {
          'conversationId': conversationId,
          'hangupType': hangupType,
          'duration': duration,
        },
      );
      
      // Отправляем запрос (opcode 79 - hangup call)
      // Или возможно это через opcode 64 как обычное сообщение с attach CALL
      final payload = {
        'conversationId': conversationId,
        'hangupType': hangupType,
        'duration': duration,
      };
      
      await sendRequest(79, payload);
      
      _log(
        '✅ Звонок завершен',
        level: LogLevel.info,
      );
    } catch (e) {
      _log(
        '❌ Ошибка завершения звонка',
        level: LogLevel.error,
        data: {'error': e.toString()},
      );
      // Не пробрасываем ошибку, т.к. завершение звонка не критично
    }
  }

  /// Инициирует звонок пользователю
  /// 
  /// [userId] - ID пользователя (calleeId)
  /// [isVideo] - видеозвонок или аудио (по умолчанию аудио)
  /// 
  /// Возвращает CallResponse с данными для установки WebRTC соединения
  Future<CallResponse> initiateCall(int userId, {bool isVideo = false}) async {
    try {
      await waitUntilOnline();
      
      // Получаем deviceId из спуфинга
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('spoof_deviceid');
      
      if (deviceId == null || deviceId.isEmpty) {
        throw Exception('Device ID не найден. Требуется авторизация.');
      }
      
      // Создаем запрос звонка
      final request = CallRequest.create(
        calleeId: userId,
        deviceId: deviceId,
        isVideo: isVideo,
      );
      
      _log(
        '📞 Инициация звонка',
        level: LogLevel.info,
        data: {
          'userId': userId,
          'isVideo': isVideo,
          'conversationId': request.conversationId,
        },
      );
      
      // Отправляем запрос (opcode 78)
      final response = await sendRequest(78, request.toJson());
      
      // Проверяем cmd ответа
      final cmd = response['cmd'] as int?;
      if (cmd != 0x100 && cmd != 256) {
        final error = response['payload']?['error'] ?? 'Неизвестная ошибка';
        throw Exception('Ошибка инициации звонка: $error');
      }
      
      final payload = response['payload'] as Map<String, dynamic>?;
      if (payload == null) {
        throw Exception('Пустой payload в ответе на звонок');
      }
      
      _log(
        '✅ Звонок инициирован успешно',
        level: LogLevel.info,
        data: {
          'conversationId': payload['conversationId'],
        },
      );
      
      // Парсим ответ
      return CallResponse.fromJson(payload);
      
    } catch (e, stackTrace) {
      _log(
        '❌ Ошибка инициации звонка',
        level: LogLevel.error,
        data: {
          'userId': userId,
          'error': e.toString(),
        },
      );
      print('❌ Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Начинает групповой звонок в чате
  /// 
  /// [chatId] - ID чата
  /// [isVideo] - видеозвонок или аудио (по умолчанию аудио)
  /// 
  /// Возвращает ConversationConnection с данными для подключения
  Future<ConversationConnection> startGroupCall(int chatId, {bool isVideo = false}) async {
    try {
      await waitUntilOnline();
      
      _log(
        '📞 Начало группового звонка',
        level: LogLevel.info,
        data: {
          'chatId': chatId,
          'isVideo': isVideo,
        },
      );
      
      final payload = {
        'chatId': chatId,
        'operation': 'START', // Обязательное поле
        'callType': isVideo ? 'VIDEO' : 'AUDIO',
      };
      
      // Отправляем запрос (opcode 77 - start group call)
      final response = await sendRequest(77, payload);
      
      // Проверяем cmd ответа
      final cmd = response['cmd'] as int?;
      if (cmd != 0x100 && cmd != 256) {
        final error = response['payload']?['error'] ?? 'Неизвестная ошибка';
        throw Exception('Ошибка начала группового звонка: $error');
      }
      
      final responsePayload = response['payload'] as Map<String, dynamic>?;
      if (responsePayload == null) {
        throw Exception('Пустой payload в ответе на групповой звонок');
      }
      
      _log(
        '✅ Групповой звонок начат успешно',
        level: LogLevel.info,
        data: {
          'conversationId': responsePayload['conversation']?['id'],
        },
      );
      
      // Парсим ответ
      return ConversationConnection.fromJson(responsePayload);
      
    } catch (e, stackTrace) {
      _log(
        '❌ Ошибка начала группового звонка',
        level: LogLevel.error,
        data: {
          'chatId': chatId,
          'error': e.toString(),
        },
      );
      print('❌ Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Присоединяется к существующему групповому звонку
  /// 
  /// [conferenceId] - ID конференции (из videoConversation.conferenceId)
  /// [chatId] - ID чата
  /// 
  /// Возвращает ConversationConnection с данными для подключения
  Future<ConversationConnection> joinGroupCallByConferenceId({
    required String conferenceId,
    required int chatId,
  }) async {
    try {
      await waitUntilOnline();
      
      _log(
        '📞 Присоединение к групповому звонку',
        level: LogLevel.info,
        data: {
          'conferenceId': conferenceId,
          'chatId': chatId,
        },
      );
      
      final payload = {
        'conferenceId': conferenceId,
        'chatId': chatId,
      };
      
      // Отправляем запрос (opcode 80 - join group call)
      final response = await sendRequest(80, payload);
      
      // Проверяем cmd ответа
      final cmd = response['cmd'] as int?;
      if (cmd != 0x100 && cmd != 256) {
        final error = response['payload']?['error'] ?? 'Неизвестная ошибка';
        throw Exception('Ошибка присоединения к звонку: $error');
      }
      
      final responsePayload = response['payload'] as Map<String, dynamic>?;
      if (responsePayload == null) {
        throw Exception('Пустой payload в ответе на присоединение');
      }
      
      _log(
        '✅ Присоединение к групповому звонку успешно',
        level: LogLevel.info,
        data: {
          'conversationId': responsePayload['conversation']?['id'],
        },
      );
      
      // Парсим ответ
      return ConversationConnection.fromJson(responsePayload);
      
    } catch (e, stackTrace) {
      _log(
        '❌ Ошибка присоединения к групповому звонку',
        level: LogLevel.error,
        data: {
          'conferenceId': conferenceId,
          'error': e.toString(),
        },
      );
      print('❌ Stack trace: $stackTrace');
      rethrow;
    }
  }
}
