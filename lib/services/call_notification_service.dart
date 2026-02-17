import 'package:flutter/services.dart';
import 'dart:io' show Platform;

/// Сервис для управления уведомлениями о входящих звонках на Android
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
  
  /// Обработчики событий
  Function(String conversationId)? onCallAnswered;
  Function(String conversationId)? onCallDeclined;
  
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
}
