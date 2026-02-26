import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gwid/api/api_service.dart';
import 'package:gwid/models/chat.dart';
import 'package:gwid/models/contact.dart';
import 'package:gwid/models/message.dart';
import 'package:gwid/models/profile.dart';
import 'package:gwid/models/chat_folder.dart';
import 'package:gwid/services/notification_service.dart';
import 'package:gwid/services/message_queue_service.dart';
import 'package:gwid/services/chat_cache_service.dart';
import 'package:gwid/services/message_read_status_service.dart';

class MessageHandler {
  final void Function(VoidCallback) setState;
  final BuildContext Function() getContext;
  final bool Function() getMounted;
  final List<Chat> allChats;
  final Map<int, Contact> contacts;
  final List<ChatFolder> folders;
  final Set<int> onlineChats;
  final Set<int> typingChats;
  final Map<int, Timer> typingDecayTimers;
  final Function(int) setTypingForChat;
  final Function() filterChats;
  final Function() refreshChats;
  final Function(List<dynamic>?) sortFoldersByOrder;
  final Function() updateFolderTabController;
  final TabController folderTabController;
  final Function(Profile) setMyProfile;
  final Function(String) showTokenExpiredDialog;
  final bool Function(Chat) isSavedMessages;

  // Дедупликация сообщений - храним ID последних обработанных сообщений
  static final Set<String> _processedMessageIds = {};
  static const int _maxProcessedMessages = 100;
  
  // Дедупликация обновлений чатов
  static final Map<int, int> _lastChatUpdateTime = {};
  static const int _chatUpdateThrottleMs = 500;

  // Debouncer для filterChats - объединяет множественные вызовы в один
  Timer? _filterChatsDebouncer;
  bool _filterChatsScheduled = false;

  MessageHandler({
    required this.setState,
    required this.getContext,
    required this.getMounted,
    required this.allChats,
    required this.contacts,
    required this.folders,
    required this.onlineChats,
    required this.typingChats,
    required this.typingDecayTimers,
    required this.setTypingForChat,
    required this.filterChats,
    required this.refreshChats,
    required this.sortFoldersByOrder,
    required this.updateFolderTabController,
    required this.folderTabController,
    required this.setMyProfile,
    required this.showTokenExpiredDialog,
    required this.isSavedMessages,
  });

  /// Вызывает filterChats с debouncing для оптимизации при множественных обновлениях
  void _debouncedFilterChats() {
    _filterChatsDebouncer?.cancel();
    _filterChatsScheduled = true;
    _filterChatsDebouncer = Timer(const Duration(milliseconds: 50), () {
      if (_filterChatsScheduled) {
        _filterChatsScheduled = false;
        filterChats();
      }
    });
  }

  /// Освобождает ресурсы
  void dispose() {
    _filterChatsDebouncer?.cancel();
  }
  /// Получить текстовое представление вложения для уведомления
  String _getAttachmentPreviewText(Message message) {
    if (message.attaches.isEmpty) {
      return message.text;
    }

    // Если есть текст - возвращаем его
    if (message.text.isNotEmpty) {
      return message.text;
    }

    // Анализируем вложения
    for (final attach in message.attaches) {
      final type = attach['_type'] ?? attach['type'];

      switch (type) {
        case 'STICKER':
          return '🎭 Стикер';
        case 'PHOTO':
        case 'IMAGE':
          final count = message.attaches
              .where(
                (a) =>
                    (a['_type'] ?? a['type']) == 'PHOTO' ||
                    (a['_type'] ?? a['type']) == 'IMAGE',
              )
              .length;
          return count > 1 ? '🖼 Фото ($count)' : '🖼 Фото';
        case 'VIDEO':
          final videoType = attach['videoType'] as int?;
          if (videoType == 1) {
            // Кружочек (видеосообщение)
            return '📹 Видеосообщение';
          }
          final count = message.attaches
              .where((a) => (a['_type'] ?? a['type']) == 'VIDEO')
              .length;
          return count > 1 ? '🎬 Видео ($count)' : '🎬 Видео';
        case 'VOICE':
          return '🎤 Голосовое сообщение';
        case 'AUDIO':
          final title = attach['title'] as String? ?? attach['name'] as String?;
          if (title != null && title.isNotEmpty) {
            return '🎵 $title';
          }
          return '🎵 Аудио';
        case 'FILE':
          final fileName = attach['name'] as String?;
          if (fileName != null && fileName.isNotEmpty) {
            return '📎 $fileName';
          }
          return '📎 Файл';
        case 'DOCUMENT':
          final docName = attach['name'] as String?;
          if (docName != null && docName.isNotEmpty) {
            return '📄 $docName';
          }
          return '📄 Документ';
        case 'GIF':
          return '🎞 GIF';
        case 'LOCATION':
        case 'GEO':
          return '📍 Местоположение';
        case 'CONTACT':
          final contactName =
              attach['name'] as String? ?? attach['firstName'] as String?;
          if (contactName != null && contactName.isNotEmpty) {
            return '👤 Контакт: $contactName';
          }
          return '👤 Контакт';
        case 'POLL':
          final question = attach['question'] as String?;
          if (question != null && question.isNotEmpty) {
            return '📊 $question';
          }
          return '📊 Опрос';
        case 'CALL':
        case 'call':
          final callType = attach['callType'] as String? ?? 'AUDIO';
          final hangupType = attach['hangupType'] as String? ?? '';
          if (hangupType == 'MISSED') {
            return callType == 'VIDEO'
                ? '📵 Пропущенный видеозвонок'
                : '📵 Пропущенный звонок';
          } else if (hangupType == 'CANCELED') {
            return callType == 'VIDEO'
                ? '📵 Видеозвонок отменён'
                : '📵 Звонок отменён';
          } else if (hangupType == 'REJECTED') {
            return callType == 'VIDEO'
                ? '📵 Видеозвонок отклонён'
                : '📵 Звонок отклонён';
          }
          return callType == 'VIDEO' ? '📹 Видеозвонок' : '📞 Звонок';
        case 'FORWARD':
          return 'Пересланное сообщение';
        case 'REPLY':
          return message.text.isNotEmpty ? message.text : 'Ответ';
      }
    }

    // Если тип не распознан - возвращаем generic
    return '📎 Вложение';
  }

  StreamSubscription? listen() {
    return ApiService.instance.messages.listen((message) {
      if (!getMounted()) return;

      if (message['type'] == 'invalid_token') {
        print(
          'Получено событие недействительного токена, перенаправляем на вход',
        );
        showTokenExpiredDialog(
          message['message'] ?? 'Токен авторизации недействителен',
        );
        return;
      }

      final opcode = message['opcode'];
      final cmd = message['cmd'];
      final payload = message['payload'];

      if (opcode == 19 && (cmd == 0x100 || cmd == 256) && payload != null) {
        _handleProfileUpdate(payload);
        return;
      }

      // Обработка push-уведомлений об обновлении профиля (opcode 159)
      if (opcode == 159 && payload != null) {
        _handleProfileUpdate(payload);
        return;
      }

      if (payload == null) return;
      final chatIdValue = payload['chatId'];
      final int? chatId = chatIdValue != null ? chatIdValue as int? : null;

      if (opcode == 272 ||
          opcode == 274 ||
          opcode == 48 ||
          opcode == 55 ||
          opcode == 135) {
      } else if (chatId == null) {
        return;
      }

      if (opcode == 129 && chatId != null) {
        setTypingForChat(chatId);
      } else if (opcode == 64 && (cmd == 0x100 || cmd == 256)) {
        // Успешная отправка сообщения с сервера - обновляем чат
        final messageData = payload['message'] as Map<String, dynamic>?;
        if (messageData != null) {
          final cid = messageData['cid'] as int?;

          // Удаляем из очереди по id или cid
          final queueService = MessageQueueService();
          if (cid != null) {
            final queueItem = queueService.findByCid(cid);
            if (queueItem != null) {
              queueService.removeFromQueue(queueItem.id);
            }
          }
        }

        // Обновляем чат с новым сообщением
        _handleNewChat(payload);
      } else if (opcode == 64) {
        // Локальное обновление чата (без cmd, это локальное сообщение)
        _handleNewChat(payload);
      } else if (opcode == 128 && chatId != null) {
        unawaited(_handleNewMessage(chatId, payload));
      } else if (opcode == 67 && chatId != null) {
        _handleEditedMessage(chatId, payload);
      } else if ((opcode == 66 || opcode == 142) && chatId != null) {
        _handleDeletedMessages(chatId, payload);
      } else if (opcode == 130) {
        _handleMessageReadStatus(payload);
      } else if (opcode == 132) {
        _handlePresenceUpdate(payload);
      } else if (opcode == 36) {
        _handleBlockedContacts(payload);
      } else if (opcode == 48) {
        _handleGroupCreatedOrUpdated(payload);
      } else if (opcode == 89) {
        _handleJoinGroup(payload, cmd);
      } else if (opcode == 55) {
        _handleChatUpdate(payload, cmd);
      } else if (opcode == 135) {
        // ОТКЛЮЧЕНО: opcode 135 вызывает критические баги с videoConversation
        // _handleChatChanged(payload);
      } else if (opcode == 272) {
        _handleFoldersUpdate(payload);
      } else if (opcode == 274) {
        _handleFolderCreatedOrUpdated(payload, cmd);
      } else if (opcode == 276) {
        _handleFolderDeleted(payload, cmd);
      }
    });
  }

  void _handleProfileUpdate(Map<String, dynamic> payload) {
    final profileData = payload['profile'];
    if (profileData != null) {
      print('🔄 ChatsScreen: Получен профиль из opcode 19, обновляем UI');
      Future.microtask(() {
        final context = getContext();
        if (context.mounted) {
          setMyProfile(Profile.fromJson(profileData));
        }
      });
    }

    // Обновляем favIndex из config.chats
    final config = payload['config'] as Map<String, dynamic>?;
    final configChats = config?['chats'] as Map<String, dynamic>?;
    if (configChats != null && configChats.isNotEmpty) {
      Future.microtask(() {
        final context = getContext();
        if (!context.mounted) return;
        setState(() {
          for (var i = 0; i < allChats.length; i++) {
            final chatIdStr = allChats[i].id.toString();
            final chatConfig = configChats[chatIdStr] as Map<String, dynamic>?;
            if (chatConfig != null) {
              final newFavIndex = chatConfig['favIndex'] as int? ?? 0;
              if (allChats[i].favIndex != newFavIndex) {
                allChats[i] = allChats[i].copyWith(favIndex: newFavIndex);
              }
            } else {
              if (allChats[i].favIndex != 0) {
                allChats[i] = allChats[i].copyWith(favIndex: 0);
              }
            }
          }
        });
        _debouncedFilterChats();
      });
    }
  }

  void _handleNewChat(Map<String, dynamic> payload) {
    final chatId = payload['chatId'] as int?;
    final chatJson = payload['chat'] as Map<String, dynamic>?;
    final messageJson = payload['message'] as Map<String, dynamic>?;

    // Если есть полный объект чата - используем его
    if (chatJson != null) {
      final newChat = Chat.tryFromJson(chatJson);
      if (newChat == null) return;
      ApiService.instance.updateChatInCacheFromJson(chatJson);

      final context = getContext();
      if (context.mounted) {
        setState(() {
          final existingIndex = allChats.indexWhere(
            (chat) => chat.id == newChat.id,
          );
          if (existingIndex != -1) {
            allChats[existingIndex] = newChat;
          } else {
            final savedIndex = allChats.indexWhere(isSavedMessages);
            final insertIndex = savedIndex >= 0 ? savedIndex + 1 : 0;
            allChats.insert(insertIndex, newChat);
          }
        });
        // ОПТИМИЗАЦИЯ: Используем debounced вызов filterChats
        // При множественных обновлениях это объединит вызовы в один
        _debouncedFilterChats();
      }
    }
    // Если есть только сообщение и chatId - обновляем существующий чат
    else if (chatId != null && messageJson != null) {
      final newMessage = Message.fromJson(messageJson);
      final context = getContext();
      if (context.mounted) {
        setState(() {
          final chatIndex = allChats.indexWhere((chat) => chat.id == chatId);
          if (chatIndex != -1) {
            final oldChat = allChats[chatIndex];
            final updatedChat = oldChat.copyWith(lastMessage: newMessage);
            allChats.removeAt(chatIndex);
            _insertChatAtCorrectPosition(updatedChat);
          }
        });
        // ОПТИМИЗАЦИЯ: Используем debounced вызов filterChats
        // При множественных обновлениях это объединит вызовы в один
        _debouncedFilterChats();
      }
    }
  }

  Future<void> _handleNewMessage(int chatId, Map<String, dynamic> payload) async {
    print('🔔 [MessageHandler] _handleNewMessage вызван для chatId: $chatId');

    if (allChats.isEmpty) {
      print('🔔 [MessageHandler] allChats пустой, выход');
      return;
    }

    // КРИТИЧНО: Игнорируем сообщения о звонках (CONTROL attach) - они вызывают баги
    final messageJson = payload['message'] as Map<String, dynamic>?;
    if (messageJson != null) {
      final attaches = messageJson['attaches'] as List<dynamic>?;
      if (attaches != null && attaches.isNotEmpty) {
        final hasControl = attaches.any((a) => a is Map && a['_type'] == 'CONTROL');
        if (hasControl) {
          print('⏭️ [MessageHandler] Пропускаем CONTROL-сообщение (звонок)');
          return;
        }
      }
    }

    final newMessage = Message.fromJson(payload['message']);
    print('🔔 [MessageHandler] Сообщение: id=${newMessage.id}, senderId=${newMessage.senderId}, text=${newMessage.text.substring(0, newMessage.text.length > 50 ? 50 : newMessage.text.length)}...');

    if (newMessage.status == 'REMOVED') {
      ApiService.instance.clearCacheForChat(chatId);
      unawaited(
        ChatCacheService().removeMessageFromCache(chatId, newMessage.id),
      );
      return;
    }

    // Обработка контактов в сообщении
    for (final attach in newMessage.attaches) {
      if (attach['_type'] == 'CONTACT') {
        final contactIdValue = attach['contactId'];
        final int? contactId = contactIdValue is int
            ? contactIdValue
            : (contactIdValue is String ? int.tryParse(contactIdValue) : null);
        if (contactId != null) {
          // Проверяем, есть ли контакт в кэше перед запросом
          final cachedContact = ApiService.instance.getCachedContact(contactId);
          if (cachedContact == null) {
            // Запрашиваем данные контакта по ID только если его нет в кэше
            ApiService.instance.fetchContactsByIds([contactId]);
          }
        }
      }
    }

    // Дедупликация
    final messageId = newMessage.id;
    if (_processedMessageIds.contains(messageId)) return;

    _processedMessageIds.add(messageId);
    if (_processedMessageIds.length > _maxProcessedMessages) {
      _processedMessageIds.remove(_processedMessageIds.first);
    }

    ApiService.instance.clearCacheForChat(chatId);

    // Получаем myId из профиля
    int? myId;
    final lastPayload = ApiService.instance.lastChatsPayload;
    if (lastPayload != null) {
      final profileData = lastPayload['profile'] as Map<String, dynamic>?;
      final contactProfile = profileData?['contact'] as Map<String, dynamic>?;
      myId = contactProfile?['id'] as int?;
    }

    // Если myId не найден, пробуем получить из ApiService
    if (myId == null && ApiService.instance.userId != null) {
      myId = int.tryParse(ApiService.instance.userId!);
    }

    // Не показываем уведомление для своих сообщений
    bool shouldShowNotification = (myId == null || newMessage.senderId != myId);
    print('🔔 [MessageHandler] myId=$myId, senderId=${newMessage.senderId}, shouldShowNotification=$shouldShowNotification');

    final bool isInActiveChat = ApiService.instance.currentActiveChatId == chatId;

    // Never show a push notification for the currently opened chat.
    if (shouldShowNotification && isInActiveChat) {
      print('🔔 [MessageHandler] В foreground и в этом чате - не показываем');
      shouldShowNotification = false;
    }
    if (isInActiveChat) {
      unawaited(NotificationService().clearNotificationMessagesForChat(chatId));
    }
    print('🔔 [MessageHandler] isAppInForeground=${ApiService.instance.isAppInForeground}, currentActiveChatId=${ApiService.instance.currentActiveChatId}');

    final int chatIndex = allChats.indexWhere((chat) => chat.id == chatId);
    print('🔔 [MessageHandler] chatIndex=$chatIndex');
    if (shouldShowNotification && chatIndex != -1) {
      final oldChat = allChats[chatIndex];
      print('🔔 [MessageHandler] oldChat.ownerId=${oldChat.ownerId}, oldChat.type=${oldChat.type}');
      // Для каналов НЕ проверяем senderId == ownerId, т.к. оба равны 0
      // Проверяем только для личных чатов и групп
      final isChannel = oldChat.type == 'CHANNEL';
      if (!isChannel) {
        // Проверяем как по myId, так и по ownerId чата (только для НЕ-каналов)
        if (newMessage.senderId == oldChat.ownerId ||
            (myId != null && newMessage.senderId == myId)) {
          print('🔔 [MessageHandler] senderId совпадает с ownerId или myId - не показываем');
          shouldShowNotification = false;
        }
      } else {
        print('🔔 [MessageHandler] Это канал, пропускаем проверку ownerId');
      }
    }

    if (shouldShowNotification) {
      print('🔔 [MessageHandler] Показываем уведомление!');
      final chatFromPayload = payload['chat'] as Map<String, dynamic>?;

      // Для каналов используем специальную логику - показываем название канала
      if (chatIndex != -1 && allChats[chatIndex].type == 'CHANNEL') {
        _showChannelNotification(
          chatId,
          newMessage,
          allChats[chatIndex],
          chatFromPayload,
        );
      } else {
        final contact = contacts[newMessage.senderId];
        if (contact == null) {
          _loadAndShowNotification(
            chatId,
            newMessage,
            newMessage.senderId,
            chatFromPayload,
          );
        } else {
          _showNotificationWithContact(
            chatId,
            newMessage,
            contact,
            chatFromPayload,
          );
        }
      }
    }

    // Определяем, наше ли это сообщение (до проверки автопрочтения)
    bool isMyMessage = false;
    if (chatIndex != -1) {
      final oldChat = allChats[chatIndex];
      isMyMessage = (myId != null && newMessage.senderId == myId) ||
          newMessage.senderId == oldChat.ownerId;
    } else {
      // Для новых чатов считаем сообщение "не нашим" по умолчанию
      isMyMessage = myId != null && newMessage.senderId == myId;
    }

    // Проверяем, нужно ли автоматически отметить сообщение как прочитанное
    // Условия: приложение на переднем плане, пользователь в этом чате, сообщение не наше, режим скрытия онлайна выключен
    bool shouldAutoMarkAsRead = false;
    final isForegroundActiveChat = ApiService.instance.isAppInForeground && isInActiveChat;
    
    print('🔔 [MessageHandler] Проверка автопрочтения: isForegroundActiveChat=$isForegroundActiveChat, isMyMessage=$isMyMessage');
    
    if (isForegroundActiveChat && !isMyMessage) {
      // Проверяем настройку скрытия онлайна
      final prefs = await SharedPreferences.getInstance();
      final isHiddenMode = prefs.getBool('privacy_hidden') ?? false;
      // Автоматически отмечаем как прочитанное только если режим скрытия выключен
      shouldAutoMarkAsRead = !isHiddenMode;
      print('🔔 [MessageHandler] Режим скрытия онлайна: $isHiddenMode, shouldAutoMarkAsRead=$shouldAutoMarkAsRead');
    }

    // Если нужно автоматически отметить как прочитанное - делаем это
    if (shouldAutoMarkAsRead) {
      print('🔔 [MessageHandler] Автоматически отмечаем сообщение как прочитанное');
      ApiService.instance.markMessageAsRead(chatId, newMessage.id);
    }

    if (chatIndex != -1) {
      final oldChat = allChats[chatIndex];

      // Увеличиваем счётчик непрочитанных только если:
      // 1. Это не наше сообщение
      // 2. Не включено автоматическое прочтение (скрытие онлайна выключено и мы в чате)
      final shouldIncrementUnread = !isMyMessage && !shouldAutoMarkAsRead && !isInActiveChat;
      print('🔔 [MessageHandler] shouldIncrementUnread=$shouldIncrementUnread (isMyMessage=$isMyMessage, shouldAutoMarkAsRead=$shouldAutoMarkAsRead)');

      final updatedChat = oldChat.copyWith(
        lastMessage: newMessage,
        newMessages: shouldIncrementUnread
            ? oldChat.newMessages + 1
            : oldChat.newMessages,
      );

      setState(() {
        allChats.removeAt(chatIndex);
        _insertChatAtCorrectPosition(updatedChat);
      });
      _debouncedFilterChats();
    } else if (payload['chat'] is Map<String, dynamic>) {
      final chatJson = payload['chat'] as Map<String, dynamic>;
      final newChat = Chat.tryFromJson(chatJson);
      if (newChat == null) return;
      ApiService.instance.updateChatInCacheFromJson(chatJson);

      setState(() {
        final savedIndex = allChats.indexWhere(isSavedMessages);
        final insertIndex = savedIndex >= 0 ? savedIndex + 1 : 0;
        allChats.insert(insertIndex, newChat);
      });
      _debouncedFilterChats();
    } else {
      final lastPayload = ApiService.instance.lastChatsPayload;
      if (lastPayload != null) {
        final chats = lastPayload['chats'] as List<dynamic>?;
        if (chats != null) {
          Map<String, dynamic>? chatJson;
          for (final c in chats) {
            if (c is Map<String, dynamic> && c['id'] == chatId) {
              chatJson = c;
              break;
            }
          }
          if (chatJson != null) {
            final newChat = Chat.tryFromJson(chatJson);
            if (newChat == null) return;
            // Для новых чатов тоже учитываем автоматическое прочтение
            final shouldIncrementUnread = !isMyMessage && !shouldAutoMarkAsRead && !isInActiveChat;
            final updatedChat = newChat.copyWith(
              lastMessage: Message.fromJson(payload['message']),
              newMessages: shouldIncrementUnread ? newChat.newMessages + 1 : newChat.newMessages,
            );
            setState(() {
              allChats.add(updatedChat);
              _insertChatAtCorrectPosition(updatedChat);
            });
            _debouncedFilterChats();
          }
        }
      }
    }
  }

  void _handleEditedMessage(int chatId, Map<String, dynamic> payload) {
    final editedMessage = Message.fromJson(payload['message']);
    ApiService.instance.clearCacheForChat(chatId);

    final int chatIndex = allChats.indexWhere((chat) => chat.id == chatId);
    if (chatIndex != -1) {
      final oldChat = allChats[chatIndex];
      if (oldChat.lastMessage.id == editedMessage.id) {
        final updatedChat = oldChat.copyWith(lastMessage: editedMessage);
        setState(() {
          allChats.removeAt(chatIndex);
          _insertChatAtCorrectPosition(updatedChat);
        });
        _debouncedFilterChats();
      }
    }
  }

  void _handleDeletedMessages(int chatId, Map<String, dynamic> payload) {
    final rawMessageIds = payload['messageIds'] as List<dynamic>? ?? [];
    final deletedMessageIds = rawMessageIds.map((id) => id.toString()).toList();
    ApiService.instance.clearCacheForChat(chatId);

    final int chatIndex = allChats.indexWhere((chat) => chat.id == chatId);
    if (chatIndex != -1) {
      final oldChat = allChats[chatIndex];
      if (deletedMessageIds.contains(oldChat.lastMessage.id)) {
        ApiService.instance.getChatsOnly(force: true).then((data) {
          final context = getContext();
          if (context.mounted) {
            final chats = data['chats'] as List<dynamic>;
            final filtered = chats
                .cast<Map<String, dynamic>>()
                .where((chat) => chat['id'] == chatId)
                .toList();
            final Map<String, dynamic>? updatedChatData = filtered.isNotEmpty
                ? filtered.first
                : null;
            if (updatedChatData != null) {
              final updatedChat = Chat.tryFromJson(updatedChatData);
              if (updatedChat == null) return;
              setState(() {
                allChats.removeAt(chatIndex);
                _insertChatAtCorrectPosition(updatedChat);
              });
              _debouncedFilterChats();
            }
          }
        });
      }
    }
  }

  void _handlePresenceUpdate(Map<String, dynamic> payload) {
    final bool isOnline = payload['online'] == true;
    final dynamic contactIdAny = payload['contactId'] ?? payload['userId'];

    if (contactIdAny != null) {
      final int? cid = contactIdAny is int
          ? contactIdAny
          : int.tryParse(contactIdAny.toString());
      if (cid != null) {
        final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final userPresence = {
          'seen': currentTime,
          'on': isOnline ? 'ON' : 'OFF',
        };
        ApiService.instance.updatePresenceData({cid.toString(): userPresence});

        for (final chat in allChats) {
          final otherId = chat.participantIds.firstWhere(
            (id) => id != chat.ownerId,
            orElse: () => chat.ownerId,
          );
          if (otherId == cid) {
            if (isOnline) {
              onlineChats.add(chat.id);
            } else {
              onlineChats.remove(chat.id);
            }
          }
        }
        final context = getContext();
        if (context.mounted) setState(() {});
        return;
      }
    }

    final dynamic cidAny = payload['chatId'];
    final int? chatIdFromPayload = cidAny is int
        ? cidAny
        : int.tryParse(cidAny?.toString() ?? '');
    if (chatIdFromPayload != null) {
      if (isOnline) {
        onlineChats.add(chatIdFromPayload);
      } else {
        onlineChats.remove(chatIdFromPayload);
      }
      final context = getContext();
      if (context.mounted) setState(() {});
    }
  }

  void _handleBlockedContacts(Map<String, dynamic> payload) {
    if (payload['contacts'] == null) return;
    final List<dynamic> blockedContactsJson = payload['contacts'] as List;
    final blockedContacts = blockedContactsJson
        .map((json) => Contact.fromJson(json))
        .toList();

    for (final blockedContact in blockedContacts) {
      contacts[blockedContact.id] = blockedContact;
      ApiService.instance.notifyContactUpdate(blockedContact);
    }

    final context = getContext();
    if (context.mounted) setState(() {});
  }

  void _handleGroupCreatedOrUpdated(Map<String, dynamic> payload) {
    final chatJson = payload['chat'] as Map<String, dynamic>?;
    final chatsJson = payload['chats'] as List<dynamic>?;

    Map<String, dynamic>? effectiveChatJson = chatJson;
    if (effectiveChatJson == null &&
        chatsJson != null &&
        chatsJson.isNotEmpty) {
      final first = chatsJson.first;
      if (first is Map<String, dynamic>) {
        effectiveChatJson = first;
      }
    }

    if (effectiveChatJson != null) {
      final newChat = Chat.tryFromJson(effectiveChatJson);
      if (newChat == null) return;
      ApiService.instance.updateChatInCacheFromJson(effectiveChatJson);
      final context = getContext();
      if (context.mounted) {
        setState(() {
          final existingIndex = allChats.indexWhere(
            (chat) => chat.id == newChat.id,
          );
          if (existingIndex != -1) {
            allChats[existingIndex] = newChat;
          } else {
            final savedIndex = allChats.indexWhere(isSavedMessages);
            final insertIndex = savedIndex >= 0 ? savedIndex + 1 : 0;
            allChats.insert(insertIndex, newChat);
          }
        });
        _debouncedFilterChats();
      }
    } else {
      refreshChats();
    }
  }

  void _handleJoinGroup(Map<String, dynamic> payload, int cmd) {
    if (cmd != 0x100 && cmd != 256) return;
    final chatJson = payload['chat'] as Map<String, dynamic>?;
    if (chatJson != null) {
      final chatType = chatJson['type'] as String?;
      if (chatType == 'CHAT') {
        final newChat = Chat.tryFromJson(chatJson);
        if (newChat == null) return;
        ApiService.instance.updateChatInCacheFromJson(chatJson);
        final context = getContext();
        if (context.mounted) {
          setState(() {
            final existingIndex = allChats.indexWhere(
              (chat) => chat.id == newChat.id,
            );
            if (existingIndex != -1) {
              allChats[existingIndex] = newChat;
            } else {
              final savedIndex = allChats.indexWhere(isSavedMessages);
              final insertIndex = savedIndex >= 0 ? savedIndex + 1 : 0;
              allChats.insert(insertIndex, newChat);
            }
          });
          _debouncedFilterChats();
        }
      }
    }
  }

  void _handleChatUpdate(Map<String, dynamic> payload, int cmd) {
    if (cmd != 0x100 && cmd != 256) return;
    final chatJson = payload['chat'] as Map<String, dynamic>?;
    if (chatJson != null) {
      final updatedChat = Chat.tryFromJson(chatJson);
      if (updatedChat == null) return;
      ApiService.instance.updateChatInCacheFromJson(chatJson);
      final context = getContext();
      if (context.mounted) {
        setState(() {
          final existingIndex = allChats.indexWhere(
            (chat) => chat.id == updatedChat.id,
          );
          if (existingIndex != -1) {
            allChats[existingIndex] = updatedChat;
          } else {
            final savedIndex = allChats.indexWhere(isSavedMessages);
            final insertIndex = savedIndex >= 0 ? savedIndex + 1 : 0;
            allChats.insert(insertIndex, updatedChat);
          }
        });
        _debouncedFilterChats();
      }
    }
  }

  void _handleChatChanged(Map<String, dynamic> payload) {
    try {
      if (payload['chat'] is! Map<String, dynamic>) return;
      
      final chatJson = payload['chat'] as Map<String, dynamic>;
      final int? chatId = chatJson['id'] as int?;
      final String? status = chatJson['status'] as String?;
      if (chatId == null) return;

      // Дедупликация: игнорируем повторные обновления в течение 500мс
      final now = DateTime.now().millisecondsSinceEpoch;
      final lastUpdate = _lastChatUpdateTime[chatId] ?? 0;
      if (now - lastUpdate < _chatUpdateThrottleMs) {
        print('⏭️ [opcode 135] Пропускаем дубликат обновления чата $chatId');
        return;
      }
      _lastChatUpdateTime[chatId] = now;

      print('🔄 [opcode 135] chatId=$chatId, status=$status');

      final context = getContext();
      if (!context.mounted) {
        print('⚠️ [opcode 135] Context not mounted');
        return;
      }

      if (status == 'REMOVED') {
        print('🗑️ [opcode 135] Удаляем чат $chatId');
        // Удаляем чат из списка
        setState(() {
          allChats.removeWhere((chat) => chat.id == chatId);
        });
        _debouncedFilterChats();
        // Чистим disk cache чтобы чат не воскрес после перезапуска
        ChatCacheService().removeChatFromCachedList(chatId);
        ChatCacheService().clearChatCache(chatId);
      } else if (status == 'ACTIVE') {
        print('✅ [opcode 135] Обновляем/добавляем чат $chatId');
        
        // КРИТИЧНО: Если есть videoConversation - зануляем его перед парсингом
        final hasVideoConv = chatJson['videoConversation'] != null;
        if (hasVideoConv) {
          print('   ⚠️ [opcode 135] Обнаружен videoConversation, удаляем из JSON');
          chatJson['videoConversation'] = null;
        }
        
        // КРИТИЧНО: парсинг Chat.tryFromJson может зависнуть на videoConversation
        Chat? newChat;
        try {
          print('   📝 [opcode 135] Парсинг Chat.tryFromJson...');
          newChat = Chat.tryFromJson(chatJson);
          print('   ✅ [opcode 135] Chat.tryFromJson успешно');
        } catch (e, stackTrace) {
          print('   ❌ [opcode 135] Ошибка Chat.tryFromJson: $e');
          print('   Stack: $stackTrace');
          return;
        }
        if (newChat == null) {
          return;
        }

        try {
          print('   📝 [opcode 135] updateChatInCacheFromJson...');
          ApiService.instance.updateChatInCacheFromJson(chatJson);
          print('   ✅ [opcode 135] Кэш обновлен');
        } catch (e) {
          print('   ⚠️ [opcode 135] Ошибка обновления кэша: $e');
          // Продолжаем даже если кэш не обновился
        }

        final existingIndex = allChats.indexWhere((chat) => chat.id == chatId);
        if (existingIndex != -1) {
          print('   🔄 [opcode 135] Обновляем существующий чат на позиции $existingIndex');
          allChats[existingIndex] = newChat!;
        } else {
          print('   ➕ [opcode 135] Добавляем новый чат');
          final savedIndex = allChats.indexWhere(isSavedMessages);
          final insertIndex = savedIndex >= 0 ? savedIndex + 1 : 0;
          allChats.insert(insertIndex, newChat!);
        }
        
        // Вызываем setState только если контекст всё ещё mounted
        if (context.mounted) {
          setState(() {});
          print('   ✅ [opcode 135] setState выполнен');
        }
        
        print('✅ [opcode 135] _handleChatChanged завершен успешно');
      }
    } catch (e, stackTrace) {
      print('❌ [opcode 135] КРИТИЧЕСКАЯ ОШИБКА в _handleChatChanged: $e');
      print('Stack trace: $stackTrace');
      print('Payload: $payload');
      // НЕ пробрасываем ошибку дальше - это предотвратит зависание
    }
  }

  void _handleFoldersUpdate(Map<String, dynamic> payload) {
    if (payload['folders'] == null && payload['foldersOrder'] == null) {
      refreshChats();
      return;
    }

    try {
      final foldersJson = payload['folders'] as List<dynamic>?;
      if (foldersJson != null) {
        // Защищенный маппинг - пропускаем битые папки
        final newFolders = foldersJson.map((json) {
          try {
            final jsonMap = json is Map<String, dynamic>
                ? json
                : Map<String, dynamic>.from(json as Map);
            return ChatFolder.fromJson(jsonMap);
          } catch (err) {
            print('⚠️ Ошибка парсинга папки: $err');
            return null; // Пропускаем битую папку
          }
        }).whereType<ChatFolder>().toList(); // Оставляем только валидные

        final context = getContext();
        if (context.mounted) {
          setState(() {
            folders.clear();
            folders.addAll(newFolders);
            final foldersOrder = payload['foldersOrder'] as List<dynamic>?;
            sortFoldersByOrder(foldersOrder);
          });
          updateFolderTabController();
          _debouncedFilterChats();
        }
      }
    } catch (e) {
      print('❌ Критическая ошибка обработки папок из opcode 272: $e');
    }
  }

  void _handleFolderCreatedOrUpdated(Map<String, dynamic> payload, int cmd) {
    if (cmd != 0x100 && cmd != 256) return;
    try {
      final folderJson = payload['folder'] as Map<String, dynamic>?;
      if (folderJson != null) {
        final updatedFolder = ChatFolder.fromJson(folderJson);
        final folderId = updatedFolder.id;

        final context = getContext();
        if (context.mounted) {
          final existingIndex = folders.indexWhere((f) => f.id == folderId);
          final isNewFolder = existingIndex == -1;

          setState(() {
            if (existingIndex != -1) {
              folders[existingIndex] = updatedFolder;
            } else {
              folders.add(updatedFolder);
            }
            final foldersOrder = payload['foldersOrder'] as List<dynamic>?;
            sortFoldersByOrder(foldersOrder);
          });

          updateFolderTabController();
          _debouncedFilterChats();

          if (isNewFolder) {
            final newFolderIndex = folders.indexWhere((f) => f.id == folderId);
            if (newFolderIndex != -1) {
              final targetIndex = newFolderIndex + 1;
              if (folderTabController.length > targetIndex) {
                folderTabController.animateTo(targetIndex);
              }
            }
          }
        }
      }
    } catch (e) {
      print('Ошибка обработки созданной/обновленной папки из opcode 274: $e');
    }
  }

  void _handleFolderDeleted(Map<String, dynamic> payload, int cmd) {
    if (cmd != 0x100 && cmd != 256) return;
    try {
      final foldersOrder = payload['foldersOrder'] as List<dynamic>?;
      final context = getContext();
      if (foldersOrder != null && context.mounted) {
        final currentIndex = folderTabController.index;

        setState(() {
          final orderedIds = foldersOrder.map((id) => id.toString()).toList();
          folders.removeWhere((folder) => !orderedIds.contains(folder.id));
          sortFoldersByOrder(foldersOrder);
        });

        updateFolderTabController();
        _debouncedFilterChats();

        if (currentIndex >= folderTabController.length) {
          folderTabController.animateTo(0);
        } else if (currentIndex > 0) {
          folderTabController.animateTo(
            currentIndex < folderTabController.length ? currentIndex : 0,
          );
        }

        ApiService.instance.requestFolderSync();
      }
    } catch (e) {
      print('Ошибка обработки удаления папки из opcode 276: $e');
    }
  }

  void _insertChatAtCorrectPosition(Chat chat) {
    // Вставляем чат в правильную позицию по времени последнего сообщения
    final chatTime = chat.lastMessage.time;
    int insertIndex = 0;
    for (int i = 0; i < allChats.length; i++) {
      if (chatTime >= allChats[i].lastMessage.time) {
        insertIndex = i;
        break;
      }
      insertIndex = i + 1;
    }
    allChats.insert(insertIndex, chat);
  }

  /// Показать уведомление с известным контактом
  void _showNotificationWithContact(
    int chatId,
    Message message,
    Contact contact, [
    Map<String, dynamic>? chatFromPayload,
  ]) async {
    // Получаем данные чата
    final effectiveChat = await _getEffectiveChat(chatId, chatFromPayload);

    // Сначала проверяем канал, потом группу
    final isChannel = effectiveChat?.type == 'CHANNEL';
    // Группы: chatId < 0 ИЛИ type='CHAT' ИЛИ isGroup, НО не канал
    final isGroupChat =
        !isChannel &&
        (chatId < 0 ||
            (effectiveChat != null &&
                (effectiveChat.isGroup || effectiveChat.type == 'CHAT')));
    final groupTitle =
        effectiveChat?.title ??
        effectiveChat?.displayTitle ??
        (isGroupChat ? 'Группа' : null);
    final avatarUrl = isGroupChat
        ? (effectiveChat?.baseIconUrl ?? contact.photoBaseUrl)
        : contact.photoBaseUrl;

    NotificationService().showMessageNotification(
      chatId: chatId,
      senderName: contact.name,
      messageText: _getAttachmentPreviewText(message),
      avatarUrl: avatarUrl,
      isGroupChat: isGroupChat,
      isChannel: isChannel,
      groupTitle: groupTitle,
    );
  }

  /// Показать уведомление для канала
  void _showChannelNotification(
    int chatId,
    Message message,
    Chat channel, [
    Map<String, dynamic>? chatFromPayload,
  ]) {
    final channelName = channel.displayTitle;
    final avatarUrl = channel.baseIconUrl;

    print('🔔 [MessageHandler] Показываем уведомление канала: $channelName');

    NotificationService().showMessageNotification(
      chatId: chatId,
      senderName: channelName,
      messageText: _getAttachmentPreviewText(message),
      avatarUrl: avatarUrl,
      isGroupChat: false,
      isChannel: true,
      groupTitle: channelName,
    );
  }

  /// Загрузить контакт и показать уведомление
  void _loadAndShowNotification(
    int chatId,
    Message message,
    int userId, [
    Map<String, dynamic>? chatFromPayload,
  ]) {
    ApiService.instance
        .fetchContactsByIds([userId])
        .then((contactsList) {
          if (contactsList.isNotEmpty) {
            final contact = contactsList.first;
            contacts[userId] = contact;
            _showNotificationWithContact(
              chatId,
              message,
              contact,
              chatFromPayload,
            );
          } else {
            _showNotificationWithoutContact(
              chatId,
              message,
              userId,
              chatFromPayload,
            );
          }
        })
        .catchError((_) {
          _showNotificationWithoutContact(
            chatId,
            message,
            userId,
            chatFromPayload,
          );
        });
  }

  /// Показать уведомление без информации о контакте
  void _showNotificationWithoutContact(
    int chatId,
    Message message,
    int userId, [
    Map<String, dynamic>? chatFromPayload,
  ]) async {
    final effectiveChat = await _getEffectiveChat(chatId, chatFromPayload);

    // Сначала проверяем канал, потом группу
    final isChannel = effectiveChat?.type == 'CHANNEL';
    // Группы: chatId < 0 ИЛИ type='CHAT' ИЛИ isGroup, НО не канал
    final isGroupChat =
        !isChannel &&
        (chatId < 0 ||
            (effectiveChat != null &&
                (effectiveChat.isGroup || effectiveChat.type == 'CHAT')));
    final groupTitle =
        effectiveChat?.title ??
        effectiveChat?.displayTitle ??
        (isGroupChat ? 'Группа' : null);
    final avatarUrl = isGroupChat ? effectiveChat?.baseIconUrl : null;

    NotificationService().showMessageNotification(
      chatId: chatId,
      senderName: 'Пользователь $userId',
      messageText: _getAttachmentPreviewText(message),
      avatarUrl: avatarUrl,
      isGroupChat: isGroupChat,
      isChannel: isChannel,
      groupTitle: groupTitle,
    );
  }

  /// Получить данные чата из разных источников
  Future<Chat?> _getEffectiveChat(
    int chatId, [
    Map<String, dynamic>? chatFromPayload,
  ]) async {
    // Ищем в allChats
    try {
      return allChats.firstWhere((c) => c.id == chatId);
    } catch (e) {
      print('⚠️ Чат $chatId не найден в allChats: $e');
    }

    // Из payload
    if (chatFromPayload != null) {
      return Chat.tryFromJson(chatFromPayload);
    }

    // Из кэша
    try {
      final cachedChatJson = await ChatCacheService().getChatById(chatId);
      if (cachedChatJson != null) {
        return Chat.tryFromJson(cachedChatJson);
      }
    } catch (e) {
      print('⚠️ Ошибка получения чата $chatId из кэша: $e');
    }

    return null;
  }

  /// Обработка opcode 130 - статус прочитанности сообщений
  /// 
  /// Payload: {
  ///   "setAsUnread": false,     // false = прочитали, true = пометить непрочитанным
  ///   "chatId": 6747636,        // ID чата
  ///   "userId": 103666767,      // ID пользователя (кто прочитал)
  ///   "mark": 1771481427964     // ID сообщения которое прочли
  /// }
  void _handleMessageReadStatus(Map<String, dynamic> payload) {
    print('📖 [opcode 130] Получен статус прочитанности: $payload');
    
    // Передаем обработку в сервис
    MessageReadStatusService().handleReadStatusUpdate(payload);
    
    // Триггерим обновление UI для чата
    final chatId = payload['chatId'] as int?;
    if (chatId != null) {
      final context = getContext();
      if (context.mounted) {
        setState(() {});
      }
    }
  }
}
