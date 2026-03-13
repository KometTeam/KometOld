import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gwid/api/api_service.dart';

/// Сервис для отслеживания статусов прочитанности сообщений
/// Хранит TIMESTAMP последнего прочитанного сообщения для каждого чата
class MessageReadStatusService {
  static final MessageReadStatusService _instance = MessageReadStatusService._internal();
  factory MessageReadStatusService() => _instance;
  MessageReadStatusService._internal();

  static const String _storageKey = 'message_read_status_timestamps';
  
  /// Маппинг chatId -> lastReadTimestamp (время последнего прочитанного сообщения)
  final Map<int, int> _lastReadTimestamps = {};

  /// Stream controller для уведомления об обновлениях статусов
  final _statusUpdateController = StreamController<MessageReadUpdate>.broadcast();
  
  bool _isInitialized = false;
  
  /// Stream обновлений статусов прочитанности
  Stream<MessageReadUpdate> get statusUpdates => _statusUpdateController.stream;
  
  /// Инициализация сервиса - загрузка сохраненных данных
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonData = prefs.getString(_storageKey);
      
      if (jsonData != null) {
        final Map<String, dynamic> decoded = json.decode(jsonData);
        _lastReadTimestamps.clear();
        
        // Конвертируем String keys обратно в int
        decoded.forEach((key, value) {
          final chatId = int.tryParse(key);
          if (chatId != null && value is int) {
            _lastReadTimestamps[chatId] = value;
          }
        });
        
        print('✅ [MessageReadStatusService] Загружено ${_lastReadTimestamps.length} статусов из хранилища');
      }
      
      _isInitialized = true;
    } catch (e) {
      print('❌ [MessageReadStatusService] Ошибка загрузки: $e');
    }
  }
  
  /// Сохранить текущее состояние в SharedPreferences
  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Конвертируем int keys в String для JSON
      final Map<String, dynamic> toSave = {};
      _lastReadTimestamps.forEach((chatId, timestamp) {
        toSave[chatId.toString()] = timestamp;
      });
      
      final String jsonData = json.encode(toSave);
      await prefs.setString(_storageKey, jsonData);
    } catch (e) {
      print('❌ [MessageReadStatusService] Ошибка сохранения: $e');
    }
  }

  /// Обработка входящего пакета opcode 130 (статус прочитанности)
  /// 
  /// Payload: {
  ///   "setAsUnread": false,     // false = прочитали, true = пометить непрочитанным
  ///   "chatId": 6747636,        // ID чата
  ///   "userId": 103666767,      // ID пользователя (кто прочитал)
  ///   "mark": 1771481427964     // TIMESTAMP (время) последнего прочитанного сообщения
  /// }
  void handleReadStatusUpdate(Map<String, dynamic> payload) {
    final chatId = payload['chatId'] as int?;
    final markTimestamp = payload['mark'] as int?;
    final setAsUnread = payload['setAsUnread'] as bool? ?? false;

    if (chatId == null || markTimestamp == null) {
      print('⚠️ [opcode 130] Некорректные данные: chatId=$chatId, mark=$markTimestamp');
      return;
    }

    // setAsUnread:false означает что сообщение прочли
    if (!setAsUnread) {
      _updateReadStatus(chatId, markTimestamp);
    }
  }

  /// Обновить статус прочитанности для чата
  void _updateReadStatus(int chatId, int timestamp) {
    final currentLastRead = _lastReadTimestamps[chatId];
    
    // Обновляем только если новый timestamp больше текущего
    // (так как прочитанность работает каскадно - все сообщения до указанного времени помечаются как прочитанные)
    if (currentLastRead == null || timestamp > currentLastRead) {
      print('✅ [opcode 130] Обновляем статус прочитанности: chatId=$chatId, lastReadTimestamp=$timestamp');
      _lastReadTimestamps[chatId] = timestamp;
      
      // Обновляем глобальный кэш в ApiService
      ApiService.instance.updatePeerReadTimestamp(chatId, timestamp);
      
      // Сохраняем в persistent storage
      _saveToStorage();
      
      // Уведомляем подписчиков об изменении
      _statusUpdateController.add(MessageReadUpdate(
        chatId: chatId,
        lastReadTimestamp: timestamp,
      ));
    } else {
      print('⏭️ [opcode 130] Пропускаем обновление (текущий $currentLastRead >= новый $timestamp)');
    }
  }

  /// Проверить, прочитано ли сообщение по времени отправки
  /// messageTimestamp - время отправки сообщения (message.time)
  bool isMessageRead(int chatId, int messageTimestamp) {
    final lastReadTimestamp = _lastReadTimestamps[chatId];
    if (lastReadTimestamp == null) return false;
    
    // Все сообщения с временем <= lastReadTimestamp считаются прочитанными
    return messageTimestamp <= lastReadTimestamp;
  }

  /// Получить timestamp последнего прочитанного сообщения в чате
  int? getLastReadTimestamp(int chatId) {
    return _lastReadTimestamps[chatId];
  }

  /// Очистить данные (например, при выходе из аккаунта)
  Future<void> clear() async {
    _lastReadTimestamps.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  void dispose() {
    _statusUpdateController.close();
  }
}

/// Модель обновления статуса прочитанности
class MessageReadUpdate {
  final int chatId;
  final int lastReadTimestamp;

  MessageReadUpdate({
    required this.chatId,
    required this.lastReadTimestamp,
  });
}
