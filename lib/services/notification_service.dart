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
import 'package:gwid/services/avatar_cache_service.dart';
import 'package:gwid/services/chat_cache_service.dart';
import 'package:gwid/services/notification_settings_service.dart';
import 'package:gwid/api/api_service.dart';
import 'package:gwid/models/contact.dart';
import 'package:gwid/screens/chat_screen.dart';
import 'package:gwid/consts.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // MethodChannel для нативных уведомлений Android
  static const _nativeChannel = MethodChannel('com.gwid.app/notifications');

  // Константы паттернов вибрации
  static const List<int> _vibrationPatternNone = [0];
  static const List<int> _vibrationPatternShort = [0, 200, 100, 200];
  static const List<int> _vibrationPatternLong = [0, 500, 200, 500];

  static Future<void> updateForegroundServiceNotification({
    String title = 'Komet',
    String content = '',
  }) async {
    if (Platform.isAndroid) {
      try {
        await _nativeChannel.invokeMethod(
          'updateForegroundServiceNotification',
          {'title': title, 'content': content},
        );
        print("✅ Уведомление фонового сервиса обновлено с кнопкой действия");
      } catch (e) {
        print("⚠️ Ошибка обновления уведомления фонового сервиса: $e");
      }
    }
  }

  bool _initialized = false;
  GlobalKey<NavigatorState>? _navigatorKey;

  /// Инициализация сервиса уведомлений
  Future<void> initialize() async {
    if (_initialized) return;

    // Устанавливаем обработчик вызовов из нативного кода
    if (Platform.isAndroid) {
      _nativeChannel.setMethodCallHandler(_handleNativeCall);
    }

    // Инициализация локальных уведомлений
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
      windows: windowsSettings,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Запрос разрешений для iOS/macOS
    if (Platform.isIOS || Platform.isMacOS) {
      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    // Запрос разрешений для Android 13+
    if (Platform.isAndroid) {
      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();

      // Проверяем pending notification (если приложение было запущено из уведомления)
      _checkPendingNotification();
    }

    _initialized = true;
    print("✅ NotificationService инициализирован");
  }

  /// Обработка вызовов из нативного кода Android
  Future<dynamic> _handleNativeCall(MethodCall call) async {
    print(
      "🔔 [Native -> Flutter] Получен вызов: ${call.method}, args: ${call.arguments}",
    );

    switch (call.method) {
      case 'onNotificationTap':
        final args = call.arguments as Map<dynamic, dynamic>;
        final payload = args['payload'] as String?;
        final chatId = args['chatId'];

        print(
          "🔔 Получен тап по уведомлению из нативного кода: payload=$payload, chatId=$chatId",
        );

        if (payload != null && payload.startsWith('chat_')) {
          final chatIdFromPayload = int.tryParse(
            payload.replaceFirst('chat_', ''),
          );
          print("🔔 chatIdFromPayload: $chatIdFromPayload");
          if (chatIdFromPayload != null) {
            // Добавляем небольшую задержку чтобы Flutter был готов
            Future.delayed(const Duration(milliseconds: 500), () {
              print(
                "🔔 Вызываем _openChatFromNotification($chatIdFromPayload)",
              );
              _openChatFromNotification(chatIdFromPayload);
            });
          }
        }
        return null;
      case 'sendReplyFromNotification':
        final args = call.arguments as Map<dynamic, dynamic>;
        // Handle both int and Long from Android
        final chatIdDynamic = args['chatId'];
        final chatId = chatIdDynamic is int
            ? chatIdDynamic
            : (chatIdDynamic is num ? chatIdDynamic.toInt() : null);
        final text = args['text'] as String?;

        print("🔔 Получен ответ из уведомления: chatId=$chatId, text=$text");

        if (chatId != null && text != null && text.isNotEmpty) {
          try {
            // Отправляем сообщение через API
            ApiService.instance.sendMessage(chatId, text);
            print("✅ Сообщение из уведомления отправлено успешно");
          } catch (e) {
            print("❌ Ошибка отправки сообщения из уведомления: $e");
          }
        }
        return null;
      default:
        return null;
    }
  }

  /// Проверка pending notification после запуска
  Future<void> _checkPendingNotification() async {
    try {
      // Ждём пока приложение полностью загрузится
      await Future.delayed(const Duration(milliseconds: 1000));

      print("🔔 Проверяем pending notification...");
      final result = await _nativeChannel.invokeMethod(
        'getPendingNotification',
      );
      print("🔔 getPendingNotification результат: $result");

      if (result != null && result is Map) {
        final payload = result['payload'] as String?;
        final chatId = result['chatId'];

        print(
          "🔔 Найден pending notification: payload=$payload, chatId=$chatId",
        );

        if (payload != null && payload.startsWith('chat_')) {
          final chatIdFromPayload = int.tryParse(
            payload.replaceFirst('chat_', ''),
          );
          if (chatIdFromPayload != null) {
            print("🔔 Открываем чат из pending: $chatIdFromPayload");
            _openChatFromNotification(chatIdFromPayload);
          }
        }
      } else {
        print("🔔 Pending notification не найден");
      }
    } catch (e) {
      print("⚠️ Ошибка при проверке pending notification: $e");
    }
  }

  /// Установить navigatorKey для навигации при нажатии на уведомление
  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
    print("🔔 NavigatorKey установлен для NotificationService");
  }

  /// Обработка нажатия на уведомление
  void _onNotificationTap(NotificationResponse response) {
    print("🔔 Нажатие на уведомление: ${response.payload}");

    if (response.payload != null) {
      try {
        // Парсим payload формата 'chat_123'
        if (response.payload!.startsWith('chat_')) {
          final chatIdStr = response.payload!.replaceFirst('chat_', '');
          final chatId = int.tryParse(chatIdStr);

          if (chatId != null) {
            _openChatFromNotification(chatId);
          }
        }
      } catch (e) {
        print("❌ Ошибка при обработке нажатия на уведомление: $e");
      }
    }
  }

  /// Открыть чат при нажатии на уведомление
  Future<void> _openChatFromNotification(int chatId) async {
    print("🔔 Открываем чат $chatId из уведомления");

    if (_navigatorKey == null) {
      print("⚠️ NavigatorKey не установлен!");
      return;
    }

    try {
      // Подписываемся на чат
      await ApiService.instance.subscribeToChat(chatId, true);
      print("✅ Подписались на чат $chatId");

      // Получаем данные из lastChatsPayload
      final lastPayload = ApiService.instance.lastChatsPayload;
      if (lastPayload == null) {
        print("⚠️ lastChatsPayload пуст");
        return;
      }

      // Получаем профиль
      final profileData = lastPayload['profile'] as Map<String, dynamic>?;
      final contactProfile = profileData?['contact'] as Map<String, dynamic>?;
      final myId = contactProfile?['id'] as int? ?? 0;

      // Получаем данные чата из payload
      final chatsData = lastPayload['chats'] as List?;
      if (chatsData == null || chatsData.isEmpty) {
        print("⚠️ Чаты не найдены в payload");
        return;
      }

      // Находим нужный чат
      Map<String, dynamic>? chatData;
      bool isGroupChat = false;
      bool isChannel = false;
      int? participantCount;

      for (final chat in chatsData) {
        if (chat['id'] == chatId) {
          chatData = chat as Map<String, dynamic>;
          // Определяем тип чата
          final chatType = chat['type'] as String?;
          isChannel = chatType == 'CHANNEL';
          isGroupChat =
              !isChannel &&
              (chatType == 'CHAT' || chat['isGroup'] == true || chatId < 0);
          // Проверяем оба варианта названия поля (participantCount и participantsCount)
          participantCount =
              chat['participantsCount'] as int? ??
              chat['participantCount'] as int?;
          break;
        }
      }

      if (chatData == null) {
        print("⚠️ Чат $chatId не найден в payload, пробуем загрузить из кэша");
        // Пробуем загрузить из кэша
        final cachedChat = await ChatCacheService().getChatById(chatId);
        if (cachedChat != null) {
          chatData = cachedChat;
          final chatType = cachedChat['type'] as String?;
          isChannel = chatType == 'CHANNEL';
          isGroupChat =
              !isChannel &&
              (chatType == 'CHAT' ||
                  cachedChat['isGroup'] == true ||
                  chatId < 0);
          // Проверяем оба варианта названия поля (participantCount и participantsCount)
          participantCount =
              cachedChat['participantsCount'] as int? ??
              cachedChat['participantCount'] as int?;
        } else {
          print("⚠️ Чат не найден в кэше");
          return;
        }
      }

      // Логируем определённый тип чата
      final chatType = chatData['type'] as String?;
      print(
        "🔔 Тип чата: $chatType, isChannel: $isChannel, isGroupChat: $isGroupChat, participantCount: $participantCount",
      );

      // Для групп и каналов создаём фейковый Contact с данными чата
      Contact contact;
      if (isChannel) {
        // Канал - создаём Contact из данных чата
        final title =
            chatData['title'] as String? ??
            chatData['displayTitle'] as String? ??
            'Канал';
        final baseIconUrl = chatData['baseIconUrl'] as String?;
        contact = Contact(
          id: chatId,
          name: title,
          firstName: title,
          lastName: '',
          photoBaseUrl: baseIconUrl,
        );
        print(
          "✅ Создан контакт для канала: $title, participantCount: $participantCount",
        );
      } else if (isGroupChat) {
        // Группа - создаём Contact из данных чата
        final title =
            chatData['title'] as String? ??
            chatData['displayTitle'] as String? ??
            'Группа';
        final baseIconUrl = chatData['baseIconUrl'] as String?;
        contact = Contact(
          id: chatId,
          name: title,
          firstName: title,
          lastName: '',
          photoBaseUrl: baseIconUrl,
        );
        print("✅ Создан контакт для группы: $title");
      } else {
        // Личный чат - получаем контакт
        final contactData = chatData['contact'] as Map<String, dynamic>?;
        if (contactData != null) {
          contact = Contact.fromJson(contactData);
          print("✅ Найден контакт в чате: ${contact.name}");
        } else {
          // Контакт не в данных чата - пробуем загрузить через API
          print("! Контакт не найден в данных чата");
          print("🔔 chatData keys: ${chatData.keys.toList()}");

          // Пробуем получить ID контакта из participants
          int? contactId;
          String? participantName;
          String? participantPhotoUrl;

          final participantsRaw = chatData['participants'];
          final owner = chatData['owner'] as int?;
          print("🔔 participants type: ${participantsRaw.runtimeType}");
          print("🔔 owner: $owner, myId: $myId");

          // participants может быть Map<String, dynamic> или List<dynamic>
          if (participantsRaw is Map<String, dynamic>) {
            // Это Map - ключи это ID участников
            print(
              "🔔 participants is Map with keys: ${participantsRaw.keys.toList()}",
            );
            for (final key in participantsRaw.keys) {
              final pId = int.tryParse(key.toString());
              if (pId != null && pId != myId && pId != owner) {
                contactId = pId;
                final pData = participantsRaw[key];
                if (pData is Map<String, dynamic>) {
                  participantName =
                      pData['name'] as String? ?? pData['firstName'] as String?;
                  participantPhotoUrl =
                      pData['baseUrl'] as String? ??
                      pData['photoBaseUrl'] as String?;
                }
                print(
                  "🔔 Найден собеседник из Map: id=$contactId, name=$participantName",
                );
                break;
              }
            }
          } else if (participantsRaw is List) {
            // Это List - массив объектов или ID
            for (final p in participantsRaw) {
              if (p is Map<String, dynamic>) {
                final pId = p['id'] as int?;
                print("🔔 Checking participant: id=$pId");
                if (pId != null && pId != myId && pId != owner) {
                  contactId = pId;
                  participantName =
                      p['name'] as String? ?? p['firstName'] as String?;
                  participantPhotoUrl =
                      p['baseUrl'] as String? ?? p['photoBaseUrl'] as String?;
                  print(
                    "🔔 Найден собеседник из List: id=$contactId, name=$participantName",
                  );
                  break;
                }
              } else if (p is int) {
                if (p != myId && p != owner) {
                  contactId = p;
                  print(
                    "🔔 Найден contactId из participants (int): $contactId",
                  );
                  break;
                }
              }
            }
          }

          // Fallback на participantIds если participants не дал результата
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
              print("🔔 Найден contactId из participantIds: $contactId");
            }
          }

          // Если contactId найден - загружаем контакт
          if (contactId != null) {
            try {
              final contacts = await ApiService.instance.fetchContactsByIds([
                contactId,
              ]);
              if (contacts.isNotEmpty) {
                contact = contacts.first;
                print(
                  "✅ Контакт загружен через API: ${contact.name}, фото: ${contact.photoBaseUrl}",
                );
              } else if (participantName != null) {
                // API не вернул контакт, но у нас есть данные из participants
                contact = Contact(
                  id: contactId,
                  name: participantName,
                  firstName: participantName.split(' ').first,
                  lastName: participantName.split(' ').length > 1
                      ? participantName.split(' ').sublist(1).join(' ')
                      : '',
                  photoBaseUrl: participantPhotoUrl,
                );
                print("✅ Контакт создан из participants: $participantName");
              } else {
                // Создаём контакт из displayTitle
                final displayTitle =
                    chatData['displayTitle'] as String? ?? 'Контакт';
                final baseIconUrl = chatData['baseIconUrl'] as String?;
                contact = Contact(
                  id: contactId,
                  name: displayTitle,
                  firstName: displayTitle.split(' ').first,
                  lastName: displayTitle.split(' ').length > 1
                      ? displayTitle.split(' ').sublist(1).join(' ')
                      : '',
                  photoBaseUrl: baseIconUrl,
                );
                print(
                  "⚠️ Контакт не найден в API, создан из displayTitle: $displayTitle",
                );
              }
            } catch (e) {
              print("❌ Ошибка загрузки контакта: $e");
              final displayTitle =
                  chatData['displayTitle'] as String? ?? 'Контакт';
              final baseIconUrl = chatData['baseIconUrl'] as String?;
              contact = Contact(
                id: contactId,
                name: displayTitle,
                firstName: displayTitle.split(' ').first,
                lastName: displayTitle.split(' ').length > 1
                    ? displayTitle.split(' ').sublist(1).join(' ')
                    : '',
                photoBaseUrl: baseIconUrl,
              );
            }
          } else {
            // participantIds не найден или пуст - используем displayTitle напрямую
            final displayTitle =
                chatData['displayTitle'] as String? ?? 'Контакт';
            final baseIconUrl = chatData['baseIconUrl'] as String?;
            print(
              "⚠️ participantIds не найден, используем displayTitle: $displayTitle",
            );
            contact = Contact(
              id: chatId,
              name: displayTitle,
              firstName: displayTitle.split(' ').first,
              lastName: displayTitle.split(' ').length > 1
                  ? displayTitle.split(' ').sublist(1).join(' ')
                  : '',
              photoBaseUrl: baseIconUrl,
            );
          }
        }
      }

      // Отменяем уведомление перед открытием чата
      await cancelNotificationForChat(chatId);
      await clearNotificationMessagesForChat(chatId);

      // Открываем ChatScreen
      if (_navigatorKey?.currentState != null) {
        print("🔔 Открываем ChatScreen через навигатор");
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
              onChatUpdated: () {
                print("🔔 Chat updated from notification");
              },
            ),
          ),
        );
        print("🔔 ChatScreen открыт успешно");
      } else {
        print("⚠️ NavigatorKey.currentState == null!");
      }
    } catch (e, stack) {
      print("❌ Ошибка при открытии чата из уведомления: $e");
      print("❌ Stack trace: $stack");
    }
  }

  /// Очистить накопленные сообщения для чата (вызывать при открытии чата)
  Future<void> clearNotificationMessagesForChat(int chatId) async {
    print("🔔 clearNotificationMessagesForChat вызван для chatId: $chatId");

    if (Platform.isAndroid) {
      try {
        print("🔔 Вызываем clearNotificationMessages...");
        await _nativeChannel.invokeMethod('clearNotificationMessages', {
          'chatId': chatId,
        });
        print("🔔 Очищены накопленные уведомления для чата $chatId");
      } catch (e) {
        print("⚠️ Ошибка очистки уведомлений: $e");
      }
    }

    // Также отменяем само уведомление
    print("🔔 Вызываем cancelNotificationForChat...");
    await cancelNotificationForChat(chatId);
  }

  /// Отменить уведомление для конкретного чата
  Future<void> cancelNotificationForChat(int chatId) async {
    try {
      if (Platform.isAndroid) {
        // Используем нативный метод для Android
        await _nativeChannel.invokeMethod('cancelNotification', {
          'chatId': chatId,
        });
        print("🔔 Отменено уведомление для чата $chatId (нативно)");
      } else {
        // Для iOS используем flutter_local_notifications
        final notificationId = chatId.hashCode;
        await _flutterLocalNotificationsPlugin.cancel(notificationId);
        print("🔔 Отменено уведомление для чата $chatId (id: $notificationId)");
      }
    } catch (e) {
      print("⚠️ Ошибка отмены уведомления: $e");
    }
  }

  /// Показать уведомление о новом сообщении
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
    print("🔔 [NotificationService] showMessageNotification вызван:");
    print("   chatId: $chatId");
    print("   senderName: $senderName");
    print("   messageText: $messageText");
    print("   avatarUrl: $avatarUrl");
    print("   isGroupChat: $isGroupChat");
    print("   isChannel: $isChannel");
    print("   groupTitle: $groupTitle");
    print("   showPreview: $showPreview");

    // Проверяем новые настройки уведомлений
    final settingsService = NotificationSettingsService();
    final shouldShow = await settingsService.shouldShowNotification(
      chatId: chatId,
      isGroupChat: isGroupChat,
      isChannel: isChannel,
    );

    if (!shouldShow) {
      print("🔔 [NotificationService] Уведомления отключены для этого чата");
      return;
    }

    // Получаем настройки для чата
    final chatSettings = await settingsService.getSettingsForChat(
      chatId: chatId,
      isGroupChat: isGroupChat,
      isChannel: isChannel,
    );

    final prefs = await SharedPreferences.getInstance();
    final chatsPushEnabled = prefs.getString('chatsPushNotification') != 'OFF';
    final pushDetails = prefs.getBool('pushDetails') ?? true;

    print("🔔 [NotificationService] Настройки:");
    print("   chatsPushEnabled: $chatsPushEnabled");
    print("   pushDetails: $pushDetails");
    print("   chatSettings: $chatSettings");
    print("   _initialized: $_initialized");

    if (!chatsPushEnabled) {
      print("🔔 [NotificationService] Уведомления отключены в настройках");
      return;
    }

    if (!_initialized) {
      print(
        "⚠️ [NotificationService] Сервис не инициализирован! Инициализируем...",
      );
      await initialize();
    }

    final displayText = showPreview && pushDetails
        ? messageText
        : 'Новое сообщение';

    print(
      "🔔 [NotificationService] Итоговый текст для уведомления: $displayText",
    );

    // Пытаемся получить аватарку
    final avatarPath = await _ensureAvatarFile(avatarUrl, chatId);

    // Получаем режим вибрации из настроек чата
    final vibrationModeStr = chatSettings['vibration'] as String? ?? 'short';
    final enableVibration = vibrationModeStr != 'none';
    final vibrationPattern = _getVibrationPattern(vibrationModeStr);

    // Определяем, можно ли ответить (нельзя в каналах)
    final canReply = !isChannel;

    // Получаем имя текущего пользователя для корректного отображения в inline reply
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
            if (myName.isEmpty == true) {
              myName = null;
            }
          }
        }
      }
    } catch (e) {
      print("⚠️ Ошибка получения имени пользователя: $e");
    }

    // На Android используем нативный канал для стиля как в Telegram
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
        print(
          "🔔 Показано нативное уведомление Android: ${isGroupChat ? '[$groupTitle] ' : ''}$senderName - $displayText (canReply: $canReply)",
        );
        return;
      } catch (e) {
        print(
          "⚠️ [NotificationService] Ошибка нативного уведомления, fallback: $e",
        );
        // Fallback на flutter_local_notifications
      }
    }

    // Fallback для iOS/macOS или при ошибке нативного канала
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

    // Используем hashCode для notification id (chatId может быть > 32-bit)
    final notificationId = chatId.hashCode.abs() % 2147483647;

    await _flutterLocalNotificationsPlugin.show(
      notificationId,
      isGroupChat ? groupTitle : senderName,
      displayText,
      notificationDetails,
      payload: 'chat_$chatId',
    );

    print(
      "🔔 Показано уведомление: ${isGroupChat ? '[$groupTitle] ' : ''}$senderName - $displayText",
    );
  }

  /// Получить паттерн вибрации в зависимости от режима
  List<int> _getVibrationPattern(String mode) {
    switch (mode) {
      case 'none':
        return _vibrationPatternNone;
      case 'short':
        return _vibrationPatternShort;
      case 'long':
        return _vibrationPatternLong;
      default:
        return _vibrationPatternShort;
    }
  }

  /// Показывает один выбранный тестовый вариант (по номеру).
  /// 1) Person.icon + largeIcon
  /// 2) Только largeIcon
  /// 3) Только Person.icon
  /// 4) Без аватарки
  /// 5) BigText + largeIcon (без MessagingStyle)
  /// 6) BigPicture avatar (bigPicture + largeIcon)
  Future<void> debugShowNotificationVariant({
    required int variantNumber,
    required String senderName,
    required String messageText,
    required String avatarUrl,
    String? groupTitle,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    final prefs = await SharedPreferences.getInstance();
    final chatsPushEnabled = prefs.getString('chatsPushNotification') != 'OFF';
    if (!chatsPushEnabled) {
      print(
        "⚠️ [NotificationService] debugShowAllNotificationVariants: уведомления выключены в настройках",
      );
      return;
    }

    // Готовим аватар один раз
    final avatarPath = await _ensureAvatarFile(avatarUrl, 9000);
    BitmapFilePathAndroidIcon? avatarIcon;
    FilePathAndroidBitmap? avatarBitmap;

    if (avatarPath != null) {
      final file = File(avatarPath);
      final exists = await file.exists();
      final size = exists ? await file.length() : 0;
      print(
        "🔔 [NotificationService] (debug) Bitmap: path=$avatarPath, exists=$exists, size=$size",
      );

      if (exists && size > 0) {
        try {
          avatarIcon = BitmapFilePathAndroidIcon(avatarPath);
          avatarBitmap = FilePathAndroidBitmap(avatarPath);
          print(
            "✅ [NotificationService] (debug) icon=${avatarIcon != null}, largeIcon=${avatarBitmap != null}",
          );
        } catch (e) {
          print("⚠️ [NotificationService] (debug) Ошибка создания Bitmap: $e");
        }
      }
    }

    // Оставляем только одно уведомление по выбранному номеру
    final variant = variantNumber.clamp(1, 6);
    final id = 9000 + variant;
    final title = '#$variant';

    NotificationDetails details;

    switch (variant) {
      case 1:
        details = NotificationDetails(
          android: _buildAndroidDetails(
            channelId: 'chat_debug_1',
            channelName: 'Debug 1',
            channelDesc: 'Person.icon + largeIcon',
            personName: senderName,
            messageText: messageText,
            personIcon: avatarIcon,
            largeIcon: avatarBitmap,
            groupTitle: groupTitle,
            groupKey: 'debug_1',
            tag: 'debug_tag_1',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
          macOS: const DarwinNotificationDetails(),
        );
        break;
      case 2:
        details = NotificationDetails(
          android: _buildAndroidDetails(
            channelId: 'chat_debug_2',
            channelName: 'Debug 2',
            channelDesc: 'Только largeIcon',
            personName: senderName,
            messageText: messageText,
            personIcon: null,
            largeIcon: avatarBitmap,
            groupTitle: groupTitle,
            groupKey: 'debug_2',
            tag: 'debug_tag_2',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
          macOS: const DarwinNotificationDetails(),
        );
        break;
      case 3:
        details = NotificationDetails(
          android: _buildAndroidDetails(
            channelId: 'chat_debug_3',
            channelName: 'Debug 3',
            channelDesc: 'Только Person.icon',
            personName: senderName,
            messageText: messageText,
            personIcon: avatarIcon,
            largeIcon: null,
            groupTitle: groupTitle,
            groupKey: 'debug_3',
            tag: 'debug_tag_3',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
          macOS: const DarwinNotificationDetails(),
        );
        break;
      case 4:
        details = NotificationDetails(
          android: _buildAndroidDetails(
            channelId: 'chat_debug_4',
            channelName: 'Debug 4',
            channelDesc: 'Без аватарки',
            personName: senderName,
            messageText: messageText,
            personIcon: null,
            largeIcon: null,
            groupTitle: groupTitle,
            groupKey: 'debug_4',
            tag: 'debug_tag_4',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
          macOS: const DarwinNotificationDetails(),
        );
        break;
      case 5:
        details = NotificationDetails(
          android: AndroidNotificationDetails(
            'chat_debug_5',
            'Debug 5',
            channelDescription: 'BigText + largeIcon',
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            showWhen: true,
            enableVibration: true,
            playSound: true,
            icon: 'notification_icon',
            largeIcon: avatarBitmap,
            styleInformation: BigTextStyleInformation(messageText),
            tag: 'debug_tag_5',
            groupKey: null,
            setAsGroupSummary: false,
            groupAlertBehavior: GroupAlertBehavior.all,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
          macOS: const DarwinNotificationDetails(),
        );
        break;
      case 6:
      default:
        details = NotificationDetails(
          android: AndroidNotificationDetails(
            'chat_debug_6',
            'Debug 6',
            channelDescription: 'BigPicture with avatar',
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            showWhen: true,
            enableVibration: true,
            playSound: true,
            icon: 'notification_icon',
            largeIcon: avatarBitmap,
            styleInformation: avatarBitmap != null
                ? BigPictureStyleInformation(
                    avatarBitmap,
                    hideExpandedLargeIcon: false,
                    contentTitle: senderName,
                    summaryText: messageText,
                  )
                : null,
            tag: 'debug_tag_6',
            groupKey: null,
            setAsGroupSummary: false,
            groupAlertBehavior: GroupAlertBehavior.all,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
          macOS: const DarwinNotificationDetails(),
        );
        break;
    }

    await _flutterLocalNotificationsPlugin.show(
      id,
      title,
      messageText,
      details,
      payload: 'debug_$variant',
    );

    print('🔔 Отправлено тестовое уведомление variant=$variant');
  }

  /// Показать уведомление о звонке
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

    print("📞 Показано уведомление о звонке: $callerName");
  }

  /// Отменить уведомление
  Future<void> cancelNotification(int id) async {
    await _flutterLocalNotificationsPlugin.cancel(id);
  }

  /// Отменить все уведомления
  Future<void> cancelAllNotifications() async {
    await _flutterLocalNotificationsPlugin.cancelAll();
  }

  // ----- Helpers -----

  /// Обрезает изображение в круг с прозрачным фоном
  img.Image _makeCircular(img.Image src) {
    final size = src.width < src.height ? src.width : src.height;
    final radius = size ~/ 2;
    final centerX = src.width ~/ 2;
    final centerY = src.height ~/ 2;

    // Создаём новое изображение с прозрачным фоном
    final output = img.Image(width: size, height: size, numChannels: 4);

    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final dx = x - radius;
        final dy = y - radius;
        final distance = (dx * dx + dy * dy);

        if (distance <= radius * radius) {
          // Внутри круга - копируем пиксель из исходного изображения
          final srcX = centerX - radius + x;
          final srcY = centerY - radius + y;
          if (srcX >= 0 && srcX < src.width && srcY >= 0 && srcY < src.height) {
            output.setPixel(x, y, src.getPixel(srcX, srcY));
          }
        }
        // Вне круга - пиксель остаётся прозрачным (по умолчанию)
      }
    }

    return output;
  }

  Future<String?> _ensureAvatarFile(String? avatarUrl, int chatId) async {
    String? avatarPath;
    if (avatarUrl == null || avatarUrl.isEmpty) {
      return null;
    }

    try {
      print("🔔 [NotificationService] Загружаем аватарку с: $avatarUrl");

      final appDir = await getApplicationDocumentsDirectory();
      final notifDir = Directory('${appDir.path}/notifications');
      if (!await notifDir.exists()) {
        await notifDir.create(recursive: true);
      }

      final urlHash = md5.convert(utf8.encode(avatarUrl)).toString();
      final pngPath = '${notifDir.path}/avatar_${chatId}_$urlHash.png';
      final pngFile = File(pngPath);

      print("🔔 [NotificationService] Путь для аватарки: $pngPath");
      print(
        "🔔 [NotificationService] Директория уведомлений существует: ${await notifDir.exists()}",
      );
      print(
        "🔔 [NotificationService] Размер файла, если есть: ${await pngFile.exists() ? (await pngFile.length()) : 0} байт",
      );

      if (await pngFile.exists()) {
        print("🔔 [NotificationService] PNG кэш найден: $pngPath");
        avatarPath = pngPath;
      } else {
        try {
          final files = notifDir.listSync();
          print(
            "🔔 [NotificationService] Удаляем старые аватарки для чата $chatId (всего файлов: ${files.length})",
          );
          for (var file in files) {
            if (file is File && file.path.contains('avatar_$chatId')) {
              print("   Удаляем: ${file.path}");
              await file.delete();
            }
          }
        } catch (e) {
          print("⚠️ Ошибка при очистке старых аватарок: $e");
        }

        try {
          print("🔔 [NotificationService] Скачиваем с URL...");
          final response = await http
              .get(
                Uri.parse(avatarUrl),
                headers: {'User-Agent': 'gwid-app/1.0'},
              )
              .timeout(const Duration(seconds: 10));

          print("🔔 [NotificationService] HTTP статус: ${response.statusCode}");
          print(
            "🔔 [NotificationService] Content-Type: ${response.headers['content-type']}",
          );
          print(
            "🔔 [NotificationService] Длина bodyBytes: ${response.bodyBytes.length}",
          );

          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            try {
              final image = img.decodeImage(response.bodyBytes);

              if (image != null) {
                print(
                  "🔔 [NotificationService] decodeImage успех: ${image.width}x${image.height}",
                );
                // Увеличиваем размер до 256x256 для лучшего качества
                final resized = img.copyResize(image, width: 256, height: 256);
                print(
                  "🔔 [NotificationService] resized: ${resized.width}x${resized.height}",
                );

                // Обрезаем в круг для круглой аватарки
                final circular = _makeCircular(resized);
                print(
                  "🔔 [NotificationService] circular: ${circular.width}x${circular.height}",
                );

                final pngBytes = img.encodePng(circular);
                await pngFile.writeAsBytes(pngBytes);
                print(
                  "✅ [NotificationService] Сохранено как круглый PNG: $pngPath (bytes: ${pngBytes.length})",
                );
                avatarPath = pngPath;
              } else {
                await pngFile.writeAsBytes(response.bodyBytes);
                avatarPath = pngPath;
                print(
                  "⚠️ [NotificationService] decodeImage null, сохраняем RAW: $pngPath (bytes: ${response.bodyBytes.length})",
                );
              }
            } catch (decodeError) {
              print(
                "⚠️ [NotificationService] Ошибка декодирования: $decodeError",
              );
              try {
                await pngFile.writeAsBytes(response.bodyBytes);
                avatarPath = pngPath;
                print(
                  "💾 [NotificationService] Сохранено RAW без декодирования: $pngPath (bytes: ${response.bodyBytes.length})",
                );
              } catch (saveError) {
                print(
                  "❌ [NotificationService] Ошибка сохранения RAW: $saveError",
                );
              }
            }
          }
        } catch (downloadError) {
          print("⚠️ [NotificationService] Ошибка скачивания: $downloadError");
        }
      }
    } catch (e) {
      print("⚠️ [NotificationService] Ошибка обработки аватарки: $e");
    }

    return avatarPath;
  }

  AndroidNotificationDetails _buildAndroidDetails({
    required String channelId,
    required String channelName,
    required String channelDesc,
    required String personName,
    required String messageText,
    BitmapFilePathAndroidIcon? personIcon,
    FilePathAndroidBitmap? largeIcon,
    String? groupTitle,
    String? groupKey,
    String? tag,
  }) {
    final person = Person(
      name: personName,
      icon: personIcon,
      key: 'debug_person',
      important: true,
    );

    return AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      icon: 'notification_icon',
      tag: tag,
      largeIcon: largeIcon,
      groupKey: null,
      setAsGroupSummary: false,
      groupAlertBehavior: GroupAlertBehavior.all,
      styleInformation: MessagingStyleInformation(
        person,
        conversationTitle: groupTitle,
        groupConversation: groupTitle != null,
        messages: [Message(messageText, DateTime.now(), person)],
      ),
      fullScreenIntent: false,
    );
  }
}

/// Инициализация фонового сервиса
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  // Создание notification channel для Android
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
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
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

  print("✅ Фоновый сервис настроен");
}

/// Entry point для фонового сервиса
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  print("🚀 Фоновый сервис запущен");

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

  // Периодическое обновление уведомления (менее часто для экономии батареи)
  Timer.periodic(const Duration(minutes: 5), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        // В фоновом изоляте MethodChannel недоступен, поэтому обновляем
        // foreground-уведомление напрямую через service API.
        service.setForegroundNotificationInfo(
          title: "Komet активен",
          content: "",
        );
      }
    }

    print("🔄 Фоновый сервис активен: ${DateTime.now()}");
  });
}

/// Background handler для iOS
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  print("🍎 iOS фоновый режим активирован");
  return true;
}
