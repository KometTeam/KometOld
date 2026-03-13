import 'package:flutter/services.dart';
import 'dart:io' show Platform;

/// Сервис для управления уведомлениями о входящих и активных звонках на Android
class CallNotificationService {
  static const MethodChannel _channel = MethodChannel('com.gwid.app/calls');
  
  static CallNotificationService? _instance;
  
  static CallNotificationService get instance {
    _instance ??= CallNotificationService._();
    return _instance!;
  }
  
  CallNotificationService._() {
    _setupMethodCallHandler();
  }
  
  /// Обработчики событий входящего звонка
  Function(String conversationId)? onCallAnswered;
  Function(String conversationId)? onCallDeclined;

  /// Обработчики событий из ongoing-уведомления активного звонка
  /// isMuted: true = пользователь нажал «Выкл. микро», false = «Вкл. микро»
  Function(bool isMuted)? onCallMuteToggled;
  VoidCallback? onCallEndedFromNotification;
  
  void _setupMethodCallHandler() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onCallAnswered':
          final conversationId = call.arguments['conversationId'] as String?;
          if (conversationId != null) {
            print('📞 Call answered from notification: $conversationId');
            onCallAnswered?.call(conversationId);
          }
          break;
          
        case 'onCallDeclined':
          final conversationId = call.arguments['conversationId'] as String?;
          if (conversationId != null) {
            print('❌ Call declined from notification: $conversationId');
            onCallDeclined?.call(conversationId);
          }
          break;

        case 'onCallMuteToggled':
          final isMuted = call.arguments['isMuted'] as bool? ?? false;
          print('🎙️ Mute toggled from notification: isMuted=$isMuted');
          onCallMuteToggled?.call(isMuted);
          break;

        case 'onCallEndedFromNotification':
          print('📴 Call ended from notification button');
          onCallEndedFromNotification?.call();
          break;
      }
    });
  }
  
  /// Показать уведомление о входящем звонке
  Future<void> showIncomingCallNotification({
    required String conversationId,
    required String callerName,
    required int callerId,
    String? avatarPath,
  }) async {
    if (!Platform.isAndroid) return;
    
    try {
      await _channel.invokeMethod('showIncomingCallNotification', {
        'conversationId': conversationId,
        'callerName': callerName,
        'callerId': callerId,
        'avatarPath': avatarPath,
      });
      print('📱 Показано уведомление о входящем звонке от $callerName');
    } catch (e) {
      print('❌ Ошибка показа уведомления о звонке: $e');
    }
  }
  
  /// Отменить уведомление о входящем звонке
  Future<void> cancelIncomingCallNotification() async {
    if (!Platform.isAndroid) return;
    
    try {
      await _channel.invokeMethod('cancelIncomingCallNotification');
      print('🔕 Уведомление о звонке отменено');
    } catch (e) {
      print('❌ Ошибка отмены уведомления: $e');
    }
  }

  // ── Ongoing-уведомление активного звонка ────────────────────────────────────

  /// Показать/обновить ongoing-уведомление активного звонка.
  /// Вызывать при установлении соединения и при каждом изменении mute/длительности.
  Future<void> showOngoingCallNotification({
    required String contactName,
    required bool isMuted,
    int durationSec = 0,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('showOngoingCallNotification', {
        'contactName': contactName,
        'isMuted': isMuted,
        'durationSec': durationSec,
      });
    } catch (e) {
      print('❌ Ошибка показа ongoing-уведомления: $e');
    }
  }

  /// Обновить ongoing-уведомление (например, при изменении mute или каждую секунду).
  Future<void> updateOngoingCallNotification({
    required String contactName,
    required bool isMuted,
    int durationSec = 0,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('updateOngoingCallNotification', {
        'contactName': contactName,
        'isMuted': isMuted,
        'durationSec': durationSec,
      });
    } catch (e) {
      print('❌ Ошибка обновления ongoing-уведомления: $e');
    }
  }

  /// Убрать ongoing-уведомление (звонок завершён).
  Future<void> cancelOngoingCallNotification() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('cancelOngoingCallNotification');
      print('🔕 Ongoing-уведомление звонка убрано');
    } catch (e) {
      print('❌ Ошибка отмены ongoing-уведомления: $e');
    }
  }
}
