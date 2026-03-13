import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' as typed_data;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

import '../services/chat_cache_service.dart';
import '../services/notification_settings_service.dart';
import '../api/api_service.dart';
import '../models/contact.dart';
import '../screens/chat_screen.dart';
import '../consts.dart';

/// Сервис для управления уведомлениями
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const _nativeChannel = MethodChannel('com.gwid.app/notifications');

  static const List<int> _vibrationPatternNone = [0];
  static const List<int> _vibrationPatternShort = [0, 200, 100, 200];
  static const List<int> _vibrationPatternLong = [0, 500, 200, 500];

  bool _initialized = false;
  GlobalKey<NavigatorState>? _navigatorKey;

  Future<void> initialize() async {
    if (_initialized) return;

    if (Platform.isAndroid) {
      _nativeChannel.setMethodCallHandler(_handleNativeCall);
    }

    const androidSettings = AndroidInitializationSettings('notification_icon');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const macosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open notification',
    );
    const windowsSettings = WindowsInitializationSettings(
      appName: appName,
      appUserModelId: windowsAppUserModelId,
      guid: windowsNotificationGuid,
    );

    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: macosSettings,
      linux: linuxSettings,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    if (Platform.isIOS || Platform.isMacOS) {
      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    if (Platform.isAndroid) {
      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _checkPendingNotification();
    }

    _initialized = true;
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onNotificationTap':
        final args = call.arguments as Map<dynamic, dynamic>;
        final payload = args['payload'] as String?;
        if (payload != null && payload.startsWith('chat_')) {
          final chatId = int.tryParse(payload.replaceFirst('chat_', ''));
          if (chatId != null) {
            Future.delayed(const Duration(milliseconds: 500), () {
              _openChatFromNotification(chatId);
            });
          }
        }
        return null;
      case 'sendReplyFromNotification':
        final args = call.arguments as Map<dynamic, dynamic>;
        final chatIdDynamic = args['chatId'];
        final chatId = chatIdDynamic is int
            ? chatIdDynamic
            : (chatIdDynamic is num ? chatIdDynamic.toInt() : null);
        final text = args['text'] as String?;
        if (chatId != null && text != null && text.isNotEmpty) {
          ApiService.instance.sendMessage(chatId, text);
        }
        return null;
      default:
        return null;
    }
  }

  Future<void> _checkPendingNotification() async {
    try {
      await Future.delayed(const Duration(milliseconds: 1000));
      final result = await _nativeChannel.invokeMethod('getPendingNotification');
      if (result != null && result is Map) {
        final payload = result['payload'] as String?;
        if (payload != null && payload.startsWith('chat_')) {
          final chatId = int.tryParse(payload.replaceFirst('chat_', ''));
          if (chatId != null) {
            _openChatFromNotification(chatId);
          }
        }
      }
    } catch (_) {}
  }

  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  void _onNotificationTap(NotificationResponse response) {
    if (response.payload != null) {
      if (response.payload!.startsWith('chat_')) {
        final chatIdStr = response.payload!.replaceFirst('chat_', '');
        final chatId = int.tryParse(chatIdStr);
        if (chatId != null) {
          _openChatFromNotification(chatId);
        }
      }
    }
  }

  Future<void> _openChatFromNotification(int chatId) async {
    if (_navigatorKey == null) return;

    try {
      await ApiService.instance.subscribeToChat(chatId, true);
      final lastPayload = ApiService.instance.lastChatsPayload;
      if (lastPayload == null) return;

      final profileData = lastPayload['profile'] as Map<String, dynamic>?;
      final contactProfile = profileData?['contact'] as Map<String, dynamic>?;
      final myId = contactProfile?['id'] as int? ?? 0;

      final chatsData = lastPayload['chats'] as List?;
      if (chatsData == null || chatsData.isEmpty) return;

      Map<String, dynamic>? chatData;
      bool isGroupChat = false;
      bool isChannel = false;
      int? participantCount;

      for (final chat in chatsData) {
        if (chat['id'] == chatId) {
          chatData = chat as Map<String, dynamic>;
          final chatType = chat['type'] as String?;
          isChannel = chatType == 'CHANNEL';
          isGroupChat = !isChannel && (chatType == 'CHAT' || chatId < 0);
          participantCount = chat['participantsCount'] as int? ?? chat['participantCount'] as int?;
          break;
        }
      }

      if (chatData == null) {
        final cachedChat = await ChatCacheService().getChatById(chatId);
        if (cachedChat != null) {
          chatData = cachedChat;
          final chatType = cachedChat['type'] as String?;
          isChannel = chatType == 'CHANNEL';
          isGroupChat = !isChannel && (chatType == 'CHAT' || chatId < 0);
          participantCount = cachedChat['participantsCount'] as int? ?? cachedChat['participantCount'] as int?;
        } else {
          return;
        }
      }

      Contact contact;
      if (isChannel) {
        final title = chatData['title'] as String? ?? chatData['displayTitle'] as String? ?? 'Канал';
        contact = Contact(
          id: chatId,
          name: title,
          firstName: title,
          lastName: '',
          photoBaseUrl: chatData['baseIconUrl'] as String?,
        );
      } else if (isGroupChat) {
        final title = chatData['title'] as String? ?? chatData['displayTitle'] as String? ?? 'Группа';
        contact = Contact(
          id: chatId,
          name: title,
          firstName: title,
          lastName: '',
          photoBaseUrl: chatData['baseIconUrl'] as String?,
        );
      } else {
        final contactData = chatData['contact'] as Map<String, dynamic>?;
        if (contactData != null) {
          contact = Contact.fromJson(contactData);
        } else {
          int? contactId;
          final participantsRaw = chatData['participants'];
          final owner = chatData['owner'] as int?;

          if (participantsRaw is Map<String, dynamic>) {
            for (final key in participantsRaw.keys) {
              final pId = int.tryParse(key.toString());
              if (pId != null && pId != myId && pId != owner) {
                contactId = pId;
                break;
              }
            }
          } else if (participantsRaw is List) {
            for (final p in participantsRaw) {
              if (p is Map<String, dynamic>) {
                final pId = p['id'] as int?;
                if (pId != null && pId != myId && pId != owner) {
                  contactId = pId;
                  break;
                }
              } else if (p is int && p != myId && p != owner) {
                contactId = p;
                break;
              }
            }
          }

          if (contactId == null) {
            final participantIds = chatData['participantIds'] as List<dynamic>?;
            if (participantIds != null && participantIds.isNotEmpty) {
              for (final pid in participantIds) {
                final id = pid is int ? pid : int.tryParse(pid.toString());
                if (id != null && id != myId) {
                  contactId = id;
                  break;
                }
              }
            }
          }

          if (contactId != null) {
            try {
              final contacts = await ApiService.instance.fetchContactsByIds([contactId]);
              contact = contacts.isNotEmpty ? contacts.first : Contact(
                id: contactId,
                name: 'Пользователь',
                firstName: 'Пользователь',
                lastName: '',
              );
            } catch (_) {
              contact = Contact(
                id: contactId,
                name: 'Пользователь',
                firstName: 'Пользователь',
                lastName: '',
              );
            }
          } else {
            final displayTitle = chatData['displayTitle'] as String? ?? 'Контакт';
            contact = Contact(
              id: chatId,
              name: displayTitle,
              firstName: displayTitle.split(' ').first,
              lastName: displayTitle.split(' ').length > 1
                  ? displayTitle.split(' ').sublist(1).join(' ')
                  : '',
              photoBaseUrl: chatData['baseIconUrl'] as String?,
            );
          }
        }
      }

      await cancelNotificationForChat(chatId);
      await clearNotificationMessagesForChat(chatId);

      if (_navigatorKey?.currentState != null) {
        _navigatorKey!.currentState!.push(
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              chatId: chatId,
              contact: contact,
              myId: myId,
              pinnedMessage: null,
              isGroupChat: isGroupChat,
              isChannel: isChannel,
              participantCount: participantCount,
              onChatUpdated: () {},
            ),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> clearNotificationMessagesForChat(int chatId) async {
    if (Platform.isAndroid) {
      try {
        await _nativeChannel.invokeMethod('clearNotificationMessages', {'chatId': chatId});
      } catch (_) {}
    }
    await cancelNotificationForChat(chatId);
  }

  Future<void> cancelNotificationForChat(int chatId) async {
    try {
      if (Platform.isAndroid) {
        await _nativeChannel.invokeMethod('cancelNotification', {'chatId': chatId});
      } else {
        await _flutterLocalNotificationsPlugin.cancel(chatId.hashCode);
      }
    } catch (_) {}
  }

  Future<void> showMessageNotification({
    required int chatId,
    required String senderName,
    required String messageText,
    String? avatarUrl,
    bool showPreview = true,
    bool isGroupChat = false,
    bool isChannel = false,
    String? groupTitle,
  }) async {
    final settingsService = NotificationSettingsService();
    final shouldShow = await settingsService.shouldShowNotification(
      chatId: chatId,
      isGroupChat: isGroupChat,
      isChannel: isChannel,
    );
    if (!shouldShow) return;

    final chatSettings = await settingsService.getSettingsForChat(
      chatId: chatId,
      isGroupChat: isGroupChat,
      isChannel: isChannel,
    );

    final prefs = await SharedPreferences.getInstance();
    final chatsPushEnabled = prefs.getString('chatsPushNotification') != 'OFF';
    final pushDetails = prefs.getBool('pushDetails') ?? true;

    if (!chatsPushEnabled) return;
    if (!_initialized) await initialize();

    final displayText = showPreview && pushDetails ? messageText : 'Новое сообщение';
    final avatarPath = await _ensureAvatarFile(avatarUrl, chatId);

    final vibrationModeStr = chatSettings['vibration'] as String? ?? 'short';
    final enableVibration = vibrationModeStr != 'none';
    final vibrationPattern = _getVibrationPattern(vibrationModeStr);
    final canReply = !isChannel;

    String? myName;
    try {
      final lastPayload = ApiService.instance.lastChatsPayload;
      if (lastPayload != null) {
        final profileData = lastPayload['profile'] as Map<String, dynamic>?;
        final contactProfile = profileData?['contact'] as Map<String, dynamic>?;
        if (contactProfile != null) {
          final names = contactProfile['names'] as List<dynamic>? ?? [];
          if (names.isNotEmpty) {
            final nameData = names[0] as Map<String, dynamic>;
            final firstName = nameData['firstName'] as String? ?? '';
            final lastName = nameData['lastName'] as String? ?? '';
            myName = '$firstName $lastName'.trim();
            if (myName.isEmpty) myName = null;
          }
        }
      }
    } catch (_) {}

    if (Platform.isAndroid) {
      try {
        await _nativeChannel.invokeMethod('showMessageNotification', {
          'chatId': chatId,
          'senderName': senderName,
          'messageText': displayText,
          'avatarPath': avatarPath,
          'isGroupChat': isGroupChat,
          'groupTitle': groupTitle,
          'enableVibration': enableVibration,
          'vibrationPattern': vibrationPattern,
          'canReply': canReply,
          'myName': myName,
        });
        return;
      } catch (_) {
        // Fallback to flutter_local_notifications
      }
    }

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      threadIdentifier: 'chat_messages',
    );

    final notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'chat_messages_v2',
        'Сообщения чатов',
        channelDescription: 'Уведомления о новых сообщениях в чатах',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
        showWhen: true,
        enableVibration: enableVibration,
        vibrationPattern: enableVibration
            ? typed_data.Int64List.fromList(vibrationPattern)
            : null,
        playSound: true,
        icon: 'notification_icon',
        styleInformation: BigTextStyleInformation(
          displayText,
          contentTitle: isGroupChat ? '$groupTitle: $senderName' : senderName,
          summaryText: isGroupChat ? groupTitle : null,
        ),
        fullScreenIntent: false,
      ),
      iOS: iosDetails,
      macOS: const DarwinNotificationDetails(),
    );

    final notificationId = chatId.hashCode.abs() % 2147483647;

    await _flutterLocalNotificationsPlugin.show(
      notificationId,
      isGroupChat ? groupTitle : senderName,
      displayText,
      notificationDetails,
      payload: 'chat_$chatId',
    );
  }

  List<int> _getVibrationPattern(String mode) => switch (mode) {
    'none' => _vibrationPatternNone,
    'long' => _vibrationPatternLong,
    _ => _vibrationPatternShort,
  };

  Future<void> showCallNotification({
    required String callerName,
    required int callId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final mCallPushEnabled = prefs.getBool('mCallPushNotification') ?? true;
    if (!mCallPushEnabled) return;

    const androidDetails = AndroidNotificationDetails(
      'calls',
      'Звонки',
      channelDescription: 'Уведомления о входящих звонках',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      icon: 'notification_icon',
      ongoing: true,
      autoCancel: false,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
    );

    const macosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: macosDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      callId,
      '📞 Входящий звонок',
      'От: $callerName',
      notificationDetails,
      payload: 'call_$callId',
    );
  }

  Future<void> cancelNotification(int id) async {
    await _flutterLocalNotificationsPlugin.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await _flutterLocalNotificationsPlugin.cancelAll();
  }

  Future<String?> _ensureAvatarFile(String? avatarUrl, int chatId) async {
    if (avatarUrl == null || avatarUrl.isEmpty) return null;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final notifDir = Directory('${appDir.path}/notifications');
      if (!await notifDir.exists()) {
        await notifDir.create(recursive: true);
      }

      final urlHash = md5.convert(utf8.encode(avatarUrl)).toString();
      final pngPath = '${notifDir.path}/avatar_${chatId}_$urlHash.png';
      final pngFile = File(pngPath);

      if (await pngFile.exists()) return pngPath;

      // Clean old avatars for this chat
      try {
        final files = notifDir.listSync();
        for (var file in files) {
          if (file is File && file.path.contains('avatar_$chatId')) {
            await file.delete();
          }
        }
      } catch (_) {}

      // Download and process new avatar
      try {
        final response = await http
            .get(Uri.parse(avatarUrl), headers: {'User-Agent': 'gwid-app/1.0'})
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          final image = img.decodeImage(response.bodyBytes);
          if (image != null) {
            final resized = img.copyResize(image, width: 256, height: 256);
            final circular = _makeCircular(resized);
            final pngBytes = img.encodePng(circular);
            await pngFile.writeAsBytes(pngBytes);
            return pngPath;
          } else {
            await pngFile.writeAsBytes(response.bodyBytes);
            return pngPath;
          }
        }
      } catch (_) {}
    } catch (_) {}

    return null;
  }

  img.Image _makeCircular(img.Image src) {
    final size = src.width < src.height ? src.width : src.height;
    final radius = size ~/ 2;
    final centerX = src.width ~/ 2;
    final centerY = src.height ~/ 2;

    final output = img.Image(width: size, height: size, numChannels: 4);

    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final dx = x - radius;
        final dy = y - radius;
        final distance = (dx * dx + dy * dy);

        if (distance <= radius * radius) {
          final srcX = centerX - radius + x;
          final srcY = centerY - radius + y;
          if (srcX >= 0 && srcX < src.width && srcY >= 0 && srcY < src.height) {
            output.setPixel(x, y, src.getPixel(srcX, srcY));
          }
        }
      }
    }

    return output;
  }

  static Future<void> updateForegroundServiceNotification({
    String title = 'Komet',
    String content = '',
  }) async {
    if (Platform.isAndroid) {
      try {
        await _nativeChannel.invokeMethod('updateForegroundServiceNotification', {
          'title': title,
          'content': content,
        });
      } catch (_) {}
    }
  }
}

/// Инициализация фонового сервиса
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  if (Platform.isAndroid) {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'background_service',
      'Фоновый сервис',
      description: 'Поддерживает приложение активным в фоне',
      importance: Importance.low,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'background_service',
      initialNotificationTitle: 'Komet активен',
      initialNotificationContent: '',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );

  if (Platform.isAndroid) {
    await Future.delayed(const Duration(seconds: 1));
    await NotificationService.updateForegroundServiceNotification();
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  Timer.periodic(const Duration(minutes: 5), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        service.setForegroundNotificationInfo(
          title: "Komet активен",
          content: "",
        );
      }
    }
  });
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}
