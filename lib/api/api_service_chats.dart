part of 'api_service.dart';

extension ApiServiceChats on ApiService {
  Future<void> _sendAuthRequestAfterHandshake() async {
    if (authToken == null) {
      print("Токен не найден, пропускаем автоматическую авторизацию");
      return;
    }

    if (_chatsFetchedInThisSession) {
      print("Авторизация уже выполнена в этой сессии, пропускаем");
      return;
    }

    try {
      // Reuse the same flow as manual loading to avoid duplicate opcode=19 logic.
      await getChatsAndContacts(force: true);
    } catch (e) {
      print("Ошибка при автоматической авторизации: $e");
    }
  }

  void createGroup(String name, List<int> participantIds) {
    final payload = {"name": name, "participantIds": participantIds};
    _sendMessage(48, payload);
    print('Создаем группу: $name с участниками: $participantIds');
  }

  void updateGroup(int chatId, {String? name, List<int>? participantIds}) {
    final payload = {
      "chatId": chatId,
      "name": ?name,
      "participantIds": ?participantIds,
    };
    _sendMessage(272, payload);
    print('Обновляем группу $chatId: ${truncatePayloadObjectForLog(payload)}');
  }

  void createGroupWithMessage(String name, List<int> participantIds) {
    final cid = DateTime.now().millisecondsSinceEpoch;
    final payload = {
      "message": {
        "cid": cid,
        "attaches": [
          {
            "_type": "CONTROL",
            "event": "new",
            "chatType": "CHAT",
            "title": name,
            "userIds": participantIds,
          },
        ],
      },
      "notify": true,
    };
    _sendMessage(64, payload);
    print('Создаем группу: $name с участниками: $participantIds');
  }

  Future<void> createChannelWithMessage(
    String title,
    List<int> initialSubscriberContactIds,
  ) async {
    await waitUntilOnline();

    final cid = DateTime.now().millisecondsSinceEpoch;
    final payload = {
      "message": {
        "cid": cid,
        "attaches": [
          {
            "_type": "CONTROL",
            "event": "new",
            "chatType": "CHANNEL",
            "title": title,
            "userIds": [],
          },
        ],
      },
      "notify": true,
    };

    await sendRawRequest(64, payload);

    if (initialSubscriberContactIds.isNotEmpty) {
      await sendRawRequest(32, {"contactIds": initialSubscriberContactIds});
    }
  }

  void renameGroup(int chatId, String newName) {
    final payload = {"chatId": chatId, "theme": newName};
    _sendMessage(55, payload);
    print('Переименовываем группу $chatId в: $newName');
  }

  void updateChatInCacheFromJson(Map<String, dynamic> chatJson) {
    try {
      _lastChatsPayload ??= {
        'chats': <dynamic>[],
        'contacts': <dynamic>[],
        'profile': null,
        'presence': null,
        'config': null,
      };

      final chats = _lastChatsPayload!['chats'] as List<dynamic>;

      final chatId = chatJson['id'];
      if (chatId == null) return;

      final existingIndex = chats.indexWhere(
            (c) => c is Map && c['id'] == chatId,
      );

      if (existingIndex != -1) {
        chats[existingIndex] = chatJson;
      } else {
        chats.insert(0, chatJson);
      }

      _emitLocal({
        'ver': 11,
        'cmd': 1,
        'seq': -1,
        'opcode': 64,
        'payload': {'chatId': chatId, 'chat': chatJson},
      });
    } catch (e) {
      print('Не удалось обновить кэш чатов из chatJson: $e');
    }
  }

  Future<String?> createGroupInviteLink(
      int chatId, {
        bool revokePrivateLink = true,
      }) async {
    final payload = {"chatId": chatId, "revokePrivateLink": revokePrivateLink};

    print(
      'Создаем пригласительную ссылку для группы $chatId: ${truncatePayloadObjectForLog(payload)}',
    );

    try {
      final response = await sendRequest(55, payload).timeout(const Duration(seconds: 15));

      if (response['cmd'] == 3) {
        final error = response['payload'];
        print('Ошибка создания пригласительной ссылки: $error');
        final message =
            error?['localizedMessage'] ??
                error?['message'] ??
                'Неизвестная ошибка';
        throw Exception(message);
      }

      final chat = response['payload']?['chat'];
      final link = chat?['link'] as String?;
      if (link == null || link.isEmpty) {
        print(
          'Пригласительная ссылка не найдена в ответе: ${response['payload']}',
        );
        return null;
      }

      if (chat != null) {
        updateChatInCacheFromJson(chat);
      }

      return link;
    } catch (e) {
      print('Ошибка при создании пригласительной ссылки: $e');
      rethrow;
    }
  }

  void addGroupMember(
      int chatId,
      List<int> userIds, {
        bool showHistory = true,
      }) {
    final payload = {
      "chatId": chatId,
      "userIds": userIds,
      "showHistory": showHistory,
      "operation": "add",
    };
    _sendMessage(77, payload);
    print('Добавляем участников $userIds в группу $chatId');
  }

  void removeGroupMember(
      int chatId,
      List<int> userIds, {
        int cleanMsgPeriod = 0,
      }) {
    final payload = {
      "chatId": chatId,
      "userIds": userIds,
      "operation": "remove",
      "cleanMsgPeriod": cleanMsgPeriod,
    };
    _sendMessage(77, payload);
    print('Удаляем участников $userIds из группы $chatId');
  }

  void leaveGroup(int chatId) {
    final payload = {"chatId": chatId};
    _sendMessage(58, payload);
    print('Выходим из группы $chatId');
  }

  void getGroupMembers(int chatId, {int marker = 0, int count = 50}) {
    final payload = {
      "type": "MEMBER",
      "marker": marker,
      "chatId": chatId,
      "count": count,
    };
    _sendMessage(59, payload);
    print(
      'Запрашиваем участников группы $chatId (marker: $marker, count: $count)',
    );
  }

  Future<Map<String, dynamic>> getChatsOnly({bool force = false}) async {
    if (!force && _lastChatsPayload != null) {
      return _lastChatsPayload!;
    }

    return getChatsAndContacts(force: true);
  }

  Future<Map<String, dynamic>> getChatsAndContacts({bool force = false}) async {
    await waitUntilOnline();

    if (authToken == null) {
      print("Токен авторизации не найден, требуется повторная авторизация");
      throw Exception("Auth token not found - please re-authenticate");
    }

    await _ensureCacheServicesInitialized();

    if (force) {
      if (_chatsFetchedInThisSession && _lastChatsPayload != null) {
        return _lastChatsPayload!;
      }
      _chatsFetchedInThisSession = false;
      _lastChatsPayload = null;
    }

    if (!force && _lastChatsPayload != null && _lastChatsAt != null) {
      if (DateTime.now().difference(_lastChatsAt!) < _chatsCacheTtl) {
        return _lastChatsPayload!;
      }
    }

    if (!force && !_chatsFetchedInThisSession && _lastChatsPayload == null) {
      final cachedChats = await _chatCacheService.getCachedChats();
      final cachedContacts = await _chatCacheService.getCachedContacts();
      if (cachedChats != null &&
          cachedContacts != null &&
          cachedChats.isNotEmpty) {
        final cachedResult = {
          'chats': cachedChats,
          'contacts': cachedContacts.map(_contactToMap).toList(),
          'profile': null,
          'presence': null,
        };
        _lastChatsPayload = cachedResult;
        _lastChatsAt = DateTime.now();
        updateContactCache(cachedContacts);
        _preloadContactAvatars(cachedContacts);
        return cachedResult;
      }
    }

    if (_chatsFetchedInThisSession && _lastChatsPayload != null && !force) {
      return _lastChatsPayload!;
    }

    if (_inflightChatsCompleter != null) {
      return _inflightChatsCompleter!.future;
    }
    _inflightChatsCompleter = Completer<Map<String, dynamic>>();

    if (_isSessionOnline &&
        _isSessionReady &&
        _lastChatsPayload != null &&
        !force) {
      _inflightChatsCompleter!.complete(_lastChatsPayload!);
      _inflightChatsCompleter = null;
      return _lastChatsPayload!;
    }

    try {
      Map<String, dynamic> chatResponse;

      final int opcode;
      final Map<String, dynamic> payload;

      final prefs = await SharedPreferences.getInstance();
      final deviceId =
          prefs.getString('spoof_deviceid') ?? generateRandomDeviceId();

      if (prefs.getString('spoof_deviceid') == null) {
        await prefs.setString('spoof_deviceid', deviceId);
      }

      if (!_chatsFetchedInThisSession) {
        opcode = 19;
        final userAgentPayload = await _buildUserAgentPayload();
        payload = {
          "chatsCount": 100,
          "chatsSync": 0,
          "contactsSync": 0,
          "draftsSync": 0,
          "interactive": true,
          "presenceSync": 0,
          "configHash":
              "00000000-0000000000000000-00000000-0000000000000000-0000000000000000-0-0000000000000000-00000000",
          "token": authToken,
          "userAgent": userAgentPayload,
        };

        if (userId != null) {
          payload["userId"] = userId;
        }
      } else {
        if (_lastChatsPayload != null) {
          _inflightChatsCompleter!.complete(_lastChatsPayload!);
          _inflightChatsCompleter = null;
          return _lastChatsPayload!;
        }
        throw StateError('Чаты уже загружены в этой сессии');
      }

      if (opcode == 19) {
        if (_authBootstrapCompleter != null) {
          chatResponse = await _authBootstrapCompleter!.future;
        } else {
          final authCompleter = Completer<Map<String, dynamic>>();
          _authBootstrapCompleter = authCompleter;
          try {
            chatResponse = await sendRequest(opcode, payload);
            authCompleter.complete(chatResponse);
          } catch (e, stackTrace) {
            authCompleter.future.catchError((_) => <String, dynamic>{});
            authCompleter.completeError(e, stackTrace);
            rethrow;
          } finally {
            if (identical(_authBootstrapCompleter, authCompleter)) {
              _authBootstrapCompleter = null;
            }
          }
        }
      } else {
        chatResponse = await sendRequest(opcode, payload);
      }

      if (opcode == 19 &&
          (chatResponse['cmd'] == 0x100 || chatResponse['cmd'] == 256)) {
        print("✅ Авторизация (opcode 19) успешна. Сессия ГОТОВА.");

        _isSessionReady = true;
        _processMessageQueue();

        _connectionStatusController.add("ready");
        _updateConnectionState(
          conn_state.ConnectionState.ready,
          message: 'Авторизация успешна',
        );

        final profile = chatResponse['payload']?['profile'];
        final contactProfile = profile?['contact'];

        if (contactProfile != null && contactProfile['id'] != null) {
          print(
            "[getChatsAndContacts] ✅ Профиль и ID пользователя найдены. ID: ${contactProfile['id']}. ЗАПУСКАЕМ АНАЛИТИКУ.",
          );
          _userId = contactProfile['id'];
          _sessionId = DateTime.now().millisecondsSinceEpoch;
          _lastActionTime = _sessionId;

          sendNavEvent('COLD_START');

          _sendInitialSetupRequests();
        } else {
          print(
            "[getChatsAndContacts] ❌ ВНИМАНИЕ: Профиль или ID в ответе пустой, аналитика не будет отправлена.",
          );
        }

        if (_onlineCompleter != null && !_onlineCompleter!.isCompleted) {
          _onlineCompleter!.complete();
        }

        _startPinging();
      }

      final profile = chatResponse['payload']?['profile'];
      final presence = chatResponse['payload']?['presence'];
      final config = chatResponse['payload']?['config'];
      final List<dynamic> chatListJson =
          chatResponse['payload']?['chats'] ?? [];

      if (profile != null && authToken != null) {
        try {
          // Определяем наличие 2FA по profileOptions — если есть значения > 0 (например 3, 4)
          final rawProfileOptions = profile['profileOptions'] as List<dynamic>?;
          if (rawProfileOptions != null) {
            final has2fa = rawProfileOptions.any((o) => o is int && o > 0);
            SharedPreferences.getInstance().then((prefs) {
              prefs.setBool('has_2fa_password', has2fa);
            });
          }

          final accountManager = AccountManager();
          await accountManager.initialize();
          final currentAccount = accountManager.currentAccount;
          if (currentAccount != null && currentAccount.token == authToken) {
            final profileMap = profile is Map<String, dynamic>
                ? profile
                : Map<String, dynamic>.from(profile as Map);
            final profileObj = Profile.fromJson(profileMap);
            await accountManager.updateAccountProfile(
              currentAccount.id,
              profileObj,
            );

            try {
              final profileCache = ProfileCacheService();
              await profileCache.initialize();
              await profileCache.syncWithServerProfile(profileObj);
            } catch (e) {
              print('[ProfileCache] Ошибка синхронизации профиля: $e');
            }
          }
        } catch (e) {
          print('Ошибка сохранения профиля в AccountManager: $e');
        }
      }

      if (chatListJson.isEmpty) {
        if (config != null) {
          _processServerPrivacyConfig(config);
        }

        final result = {
          'chats': [],
          'contacts': [],
          'profile': profile,
          'config': config,
        };
        _lastChatsPayload = result;
        _lastChatsAt = DateTime.now();
        _chatsFetchedInThisSession = true;
        _inflightChatsCompleter!.complete(_lastChatsPayload!);
        _inflightChatsCompleter = null;
        return result;
      }

      List<dynamic> contactListJson =
          chatResponse['payload']?['contacts'] ?? [];

      if (contactListJson.isEmpty) {
        final contactIds = <int>{};
        for (var chatJson in chatListJson) {
          final participants =
              chatJson['participants'] as Map<String, dynamic>? ?? {};
          contactIds.addAll(participants.keys.map((id) => int.parse(id)));
        }

        if (contactIds.isNotEmpty) {
          final contactResponse = await sendRequest(32, {
            "contactIds": contactIds.toList(),
          });

          contactListJson = contactResponse['payload']?['contacts'] ?? [];
        }
      }

      if (presence != null) {
        updatePresenceData(presence);
      }

      if (config != null) {
        _processServerPrivacyConfig(config);

        // Мёржим favIndex из config.chats в каждый объект чата
        final configChats = config['chats'] as Map<String, dynamic>?;
        if (configChats != null) {
          for (var i = 0; i < chatListJson.length; i++) {
            final chatJson = Map<String, dynamic>.from(
              chatListJson[i] as Map,
            );
            final chatIdStr = chatJson['id']?.toString();
            if (chatIdStr != null && configChats.containsKey(chatIdStr)) {
              final chatConfig =
                  configChats[chatIdStr] as Map<String, dynamic>?;
              if (chatConfig != null) {
                chatJson['favIndex'] = chatConfig['favIndex'] ?? 0;
              }
            }
            chatListJson[i] = chatJson;
          }
        }
      }

      final result = {
        'chats': chatListJson,
        'contacts': contactListJson,
        'profile': profile,
        'presence': presence,
        'config': config,
      };
      _lastChatsPayload = result;

      final List<Contact> contacts = contactListJson
          .map((json) => Contact.fromJson(json as Map<String, dynamic>))
          .toList();
      updateContactCache(contacts);
      _lastChatsAt = DateTime.now();
      _preloadContactAvatars(contacts);
      unawaited(
        _chatCacheService.cacheChats(chatListJson.cast<Map<String, dynamic>>()),
      );
      unawaited(_chatCacheService.cacheContacts(contacts));
      _chatsFetchedInThisSession = true;
      _inflightChatsCompleter!.complete(result);
      _inflightChatsCompleter = null;
      return result;
    } catch (e) {
      final error = e;
      _inflightChatsCompleter?.completeError(error);
      _inflightChatsCompleter = null;
      rethrow;
    }
  }

  Future<void> _sendInitialSetupRequests() async {
    print("Запускаем отправку единичных запросов при старте...");
    
    // Ждем готовности сессии перед отправкой запросов
    if (!_isSessionReady) {
      print('⏳ _sendInitialSetupRequests: ждем готовности сессии...');
      int attempts = 0;
      while (!_isSessionReady && attempts < 50) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
      if (!_isSessionReady) {
        print('❌ _sendInitialSetupRequests: сессия не готова после ожидания, отменяем');
        return;
      }
    }
    
    print('✅ _sendInitialSetupRequests: сессия готова, отправляем запросы');
    await Future.delayed(const Duration(seconds: 1));

    _sendMessage(272, {"folderSync": 0});
    await Future.delayed(const Duration(milliseconds: 500));
    _sendMessage(27, {"sync": 0, "type": "STICKER"});
    await Future.delayed(const Duration(milliseconds: 500));
    _sendMessage(27, {"sync": 0, "type": "FAVORITE_STICKER"});
    await Future.delayed(const Duration(milliseconds: 500));
    _sendMessage(79, {"forward": false, "count": 100});

    await Future.delayed(const Duration(seconds: 5));
    _sendMessage(26, {
      "sectionId": "NEW_STICKER_SETS",
      "from": 5,
      "count": 100,
    });

    print("Единичные запросы отправлены.");
  }

  /// Загружает историю сообщений с инкрементальной подгрузкой.
  /// Сначала загружает [initialLimit] сообщений для быстрого отображения,
  /// затем в фоне подгружает остальные до [maxMessages].
  Future<List<Message>> getMessageHistory(
      int chatId, {
        bool force = false,
        int initialLimit = AppLimits.historyLoadBatch,
        int maxMessages = AppLimits.historyLoadBatch,
        Function(List<Message> initialMessages)? onInitialLoaded,
        Function(List<Message> allMessages)? onCompleteLoaded,
      }) async {
    await _ensureCacheServicesInitialized();

    // Проверяем кэш в памяти
    if (!force && _messageCache.containsKey(chatId)) {
      final cached = _messageCache[chatId]!;
      print("Загружаем сообщения для чата $chatId из кэша (${cached.length} шт).");
      // Если в кэше уже достаточно сообщений, возвращаем сразу
      if (cached.length >= initialLimit) {
        // Вызываем коллбэки для обновления UI
        onInitialLoaded?.call(cached);
        onCompleteLoaded?.call(cached);
        return cached;
      }
    }

    // Проверяем кэш на диске
    if (!force) {
      final cachedMessages = await _chatCacheService.getCachedChatMessages(
        chatId,
      );
      if (cachedMessages != null && cachedMessages.isNotEmpty) {
        print(
          "История сообщений для чата $chatId загружена из ChatCacheService (${cachedMessages.length} шт).",
        );
        _messageCache[chatId] = cachedMessages;
        if (cachedMessages.length >= initialLimit) {
          // Вызываем коллбэки для обновления UI
          onInitialLoaded?.call(cachedMessages);
          onCompleteLoaded?.call(cachedMessages);
          return cachedMessages;
        }
      }
    }

    await waitUntilOnline();
    
    // Шаг 1: Быстрая загрузка первых [initialLimit] сообщений
    print("📨 Быстрая загрузка для чата $chatId: первые $initialLimit сообщений...");
    final initialPayload = {
      "chatId": chatId,
      "from": DateTime.now()
          .add(const Duration(days: 1))
          .millisecondsSinceEpoch,
      "forward": 0,
      "backward": initialLimit,
      "getMessages": true,
    };

    try {
      final initialResponse = await sendRequest(49, initialPayload)
          .timeout(const Duration(seconds: 10));

      if (initialResponse['cmd'] == 3) {
        final error = initialResponse['payload'];
        print('Ошибка получения истории сообщений: $error');

        if (error['error'] == 'proto.state') {
          print(
            'Ошибка состояния сессии при получении истории, переподключаемся...',
          );
          await reconnect();
          await waitUntilOnline();

          return getMessageHistory(chatId, force: true, initialLimit: initialLimit, maxMessages: maxMessages);
        }
        throw Exception('Ошибка получения истории: ${error['message']}');
      }

      final List<dynamic> initialMessagesJson = initialResponse['payload']?['messages'] ?? [];
      final initialMessages = initialMessagesJson
          .map((json) => Message.fromJson(json))
          .toList()
        ..sort((a, b) => a.time.compareTo(b.time));

      // Сохраняем в кэш и уведомляем
      if (initialMessages.isNotEmpty) {
        _messageCache[chatId] = initialMessages;
        _preloadMessageImages(initialMessages);
        unawaited(_updateMessagesCacheIfNewer(chatId, initialMessages));
      }

      print("✅ Быстрая загрузка для чата $chatId: ${initialMessages.length} сообщений");
      onInitialLoaded?.call(initialMessages);

      // Шаг 2: Фоновая загрузка оставшихся сообщений (если нужно)
      if (initialMessages.length >= initialLimit && maxMessages > initialLimit) {
        unawaited(_loadRemainingMessages(
          chatId,
          initialMessages,
          maxMessages: maxMessages,
          onComplete: onCompleteLoaded,
        ));
      } else {
        // Если фоновая загрузка не требуется, вызываем onCompleteLoaded сразу
        onCompleteLoaded?.call(initialMessages);
      }

      return initialMessages;
    } catch (e) {
      print('Ошибка при получении истории сообщений: $e');
      return _messageCache[chatId] ?? [];
    }
  }

  /// Фоновая загрузка оставшихся сообщений
  Future<void> _loadRemainingMessages(
      int chatId,
      List<Message> existingMessages, {
        required int maxMessages,
        Function(List<Message> allMessages)? onComplete,
      }) async {
    try {
      print("🔄 Фоновая загрузка для чата $chatId: до $maxMessages сообщений...");

      final remainingBackward = maxMessages - existingMessages.length;
      if (remainingBackward <= 0) {
        onComplete?.call(existingMessages);
        return;
      }

      final oldestMessage = existingMessages.first;
      final payload = {
        "chatId": chatId,
        "from": oldestMessage.time,
        "forward": 0,
        "backward": remainingBackward,
        "getMessages": true,
      };

      final response = await sendRequest(49, payload)
          .timeout(const Duration(seconds: 15));

      if (response['cmd'] == 3) {
        print('⚠️ Фоновая загрузка: ошибка получения истории');
        // Всё равно вызываем onComplete с текущими сообщениями
        onComplete?.call(existingMessages);
        return;
      }

      final List<dynamic> messagesJson = response['payload']?['messages'] ?? [];
      if (messagesJson.isEmpty) {
        print("📭 Фоновая загрузка для чата $chatId: нет дополнительных сообщений");
        // Всё равно вызываем onComplete с текущими сообщениями
        onComplete?.call(existingMessages);
        return;
      }

      final newMessages = messagesJson
          .map((json) => Message.fromJson(json))
          .toList();

      // Объединяем с существующими, избегая дубликатов
      final existingIds = existingMessages.map((m) => m.id).toSet();
      final existingCids = existingMessages
          .where((m) => m.cid != null)
          .map((m) => m.cid!)
          .toSet();
      final uniqueNewMessages = newMessages
          .where((m) =>
              !existingIds.contains(m.id) &&
              (m.cid == null || !existingCids.contains(m.cid)))
          .toList();

      final allMessages = [...existingMessages, ...uniqueNewMessages]
        ..sort((a, b) => a.time.compareTo(b.time));

      if (uniqueNewMessages.isNotEmpty) {
        _messageCache[chatId] = allMessages;
        _preloadMessageImages(uniqueNewMessages);
        unawaited(_updateMessagesCacheIfNewer(chatId, allMessages));

        // Уведомляем через стрим о новых сообщениях
        _messageController.add({
          'type': 'messages_loaded',
          'chatId': chatId,
          'messages': allMessages,
          'newCount': uniqueNewMessages.length,
        });

        print("✅ Фоновая загрузка для чата $chatId: +${uniqueNewMessages.length} сообщений (всего: ${allMessages.length})");
      } else {
        print("📭 Фоновая загрузка для чата $chatId: нет новых сообщений");
      }
      
      // Всегда вызываем onComplete с полным списком сообщений
      onComplete?.call(allMessages);
    } catch (e) {
      print('⚠️ Ошибка фоновой загрузки сообщений для чата $chatId: $e');
      // Всё равно вызываем onComplete с текущими сообщениями при ошибке
      onComplete?.call(existingMessages);
    }
  }

  /// Предзагружает сообщения из указанных чатов в фоне.
  /// Полезно для подготовки данных до открытия чата.
  Future<void> preloadChatMessages(
      List<int> chatIds, {
        int messageCount = 7,
      }) async {
    if (chatIds.isEmpty) return;
    
    print("🔄 Предзагрузка сообщений для ${chatIds.length} чатов...");
    
    for (final chatId in chatIds) {
      // Пропускаем если уже в кэше
      if (_messageCache.containsKey(chatId) && _messageCache[chatId]!.length >= messageCount) {
        continue;
      }

      // Проверяем дисковый кэш
      final cachedMessages = await _chatCacheService.getCachedChatMessages(chatId);
      if (cachedMessages != null && cachedMessages.length >= messageCount) {
        _messageCache[chatId] = cachedMessages;
        continue;
      }

      // Загружаем с сервера в фоне
      unawaited(_fetchMessagesForPreload(chatId, messageCount));
      
      // Небольшая задержка чтобы не перегружать сервер
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _fetchMessagesForPreload(int chatId, int count) async {
    try {
      if (!isActuallyConnected) return;

      final payload = {
        "chatId": chatId,
        "from": DateTime.now()
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
        "forward": 0,
        "backward": count,
        "getMessages": true,
      };

      final response = await sendRequest(49, payload)
          .timeout(const Duration(seconds: 10));

      if (response['cmd'] == 3) return;

      final List<dynamic> messagesJson = response['payload']?['messages'] ?? [];
      if (messagesJson.isEmpty) return;

      final messages = messagesJson
          .map((json) => Message.fromJson(json))
          .toList()
        ..sort((a, b) => a.time.compareTo(b.time));

      _messageCache[chatId] = messages;
      _preloadMessageImages(messages);
      unawaited(_updateMessagesCacheIfNewer(chatId, messages));

      print("✅ Предзагружено ${messages.length} сообщений для чата $chatId");
    } catch (e) {
      print('⚠️ Ошибка предзагрузки для чата $chatId: $e');
    }
  }

  Future<Map<String, dynamic>?> loadOldMessages(
      int chatId,
      String fromMessageId,
      int count,
      ) async {
    await waitUntilOnline();
    final payload = {
      "chatId": chatId,
      "from": int.parse(fromMessageId),
      "forward": 0,
      "backward": count,
      "getMessages": true,
    };

    try {
      final response = await sendRequest(49, payload).timeout(const Duration(seconds: 15));

      if (response['cmd'] == 3) {
        final error = response['payload'];
        print('Ошибка получения старых сообщений: $error');
        return null;
      }

      return response['payload'];
    } catch (e) {
      print('Ошибка при получении старых сообщений: $e');
      return null;
    }
  }

  Future<List<Message>> loadOlderMessagesByTimestamp(
      int chatId,
      int fromTimestamp, {
        int backward = AppLimits.historyLoadBatch,
      }) async {
    await waitUntilOnline();

    final payload = {
      "chatId": chatId,
      "from": fromTimestamp,
      "forward": 0,
      "backward": backward,
      "getMessages": true,
    };

    try {
      final response = await sendRequest(49, payload).timeout(const Duration(seconds: 15));

      if (response['cmd'] == 3) {
        final error = response['payload'];
        print('❌ Ошибка получения старых сообщений: $error');
        return [];
      }

      final List<dynamic> messagesJson = response['payload']?['messages'] ?? [];
      final messagesList =
      messagesJson.map((json) => Message.fromJson(json)).toList()
        ..sort((a, b) => a.time.compareTo(b.time));

      print('✅ Получено ${messagesList.length} старых сообщений');
      return messagesList;
    } catch (e) {
      print('❌ Ошибка при получении старых сообщений: $e');
      return [];
    }
  }

  void sendNavEvent(String event, {int? screenTo, int? screenFrom}) {
    if (_userId == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> params = {
      'session_id': _sessionId,
      'action_id': _actionId++,
    };

    switch (event) {
      case 'COLD_START':
        if (_isColdStartSent) return;
        params['screen_to'] = 150;
        params['source_id'] = 1;
        _isColdStartSent = true;
        break;
      case 'WARM_START':
        params['screen_to'] = 150;
        params['screen_from'] = 1;
        params['prev_time'] = _lastActionTime;
        break;
      case 'GO':
        params['screen_to'] = screenTo;
        params['screen_from'] = screenFrom;
        params['prev_time'] = _lastActionTime;
        break;
    }

    _lastActionTime = now;
    _sendMessage(5, {
      "events": [
        {
          "type": "NAV",
          "event": event,
          "userId": _userId,
          "time": now,
          "params": params,
        },
      ],
    });
  }

  void createFolder(
      String title, {
        List<int>? include,
        List<dynamic>? filters,
      }) {
    final folderId = const Uuid().v4();
    final payload = {
      "id": folderId,
      "title": title,
      "include": include ?? [],
      "filters": (filters ?? []).map((f) => f.toString()).toList(),
    };
    _sendMessage(274, payload);
    print('Создаем папку: $title (ID: $folderId)');
  }

  void updateFolder(
      String folderId, {
        String? title,
        List<int>? include,
        List<dynamic>? filters,
      }) {
    final payload = {
      "id": folderId,
      if (title != null) "title": title,
      if (include != null) "include": include,
      if (filters != null) "filters": filters.map((f) => f.toString()).toList(),
    };
    _sendMessage(274, payload);
    print('Обновляем папку: $folderId');
  }

  void deleteFolder(String folderId) {
    final payload = {
      "folderIds": [folderId],
    };
    _sendMessage(276, payload);
    print('Удаляем папку: $folderId');
  }

  void requestFolderSync() {
    _sendMessage(272, {"folderSync": 0});
    print('Запрос на обновление папок отправлен');
  }

  void clearCacheForChat(int chatId) {
    _messageCache.remove(chatId);
    if (_cacheServicesInitialized) {
      unawaited(_chatCacheService.clearChatCache(chatId));
    }
    print("Кэш для чата $chatId очищен.");
  }

  void clearChatsCache() {
    _lastChatsPayload = null;
    _lastChatsAt = null;
    print("Кэш чатов очищен.");
  }

  Contact? getCachedContact(int contactId) {
    if (_contactCache.containsKey(contactId)) {
      final contact = _contactCache[contactId]!;
      print('Контакт $contactId получен из кэша: ${contact.name}');
      return contact;
    }
    return null;
  }

  Future<Map<String, dynamic>> getNetworkStatistics() async {
    final prefs = await SharedPreferences.getInstance();

    final totalTraffic =
        prefs.getDouble('network_total_traffic') ?? (150.0 * 1024 * 1024);
    final messagesTraffic =
        prefs.getDouble('network_messages_traffic') ?? (totalTraffic * 0.15);
    final mediaTraffic =
        prefs.getDouble('network_media_traffic') ?? (totalTraffic * 0.6);
    final syncTraffic =
        prefs.getDouble('network_sync_traffic') ?? (totalTraffic * 0.1);

    final currentSpeed = _isSessionOnline ? 512.0 * 1024 : 0.0;

    final ping = 25;

    return {
      'totalTraffic': totalTraffic,
      'messagesTraffic': messagesTraffic,
      'mediaTraffic': mediaTraffic,
      'syncTraffic': syncTraffic,
      'otherTraffic': totalTraffic * 0.15,
      'currentSpeed': currentSpeed,
      'isConnected': _isSessionOnline,
      'connectionType': 'Wi-Fi',
      'signalStrength': 85,
      'ping': ping,
      'jitter': 2.5,
      'packetLoss': 0.01,
      'hourlyStats': [],
    };
  }

  bool isContactCacheValid() {
    if (_lastContactsUpdate == null) return false;
    return DateTime.now().difference(_lastContactsUpdate!) <
        ApiService._contactCacheExpiry;
  }

  void updateContactCache(List<Contact> contacts) {
    _contactCache.clear();
    for (final contact in contacts) {
      _contactCache[contact.id] = contact;
    }
    _lastContactsUpdate = DateTime.now();
    print('Кэш контактов обновлен: ${contacts.length} контактов');
  }


  void updateCachedContact(Contact contact) {
    _contactCache[contact.id] = contact;
    print('Контакт ${contact.id} обновлен в кэше: ${contact.name}');
  }

  void clearContactCache() {
    _contactCache.clear();
    _lastContactsUpdate = null;
    print("Кэш контактов очищен.");
  }

  void clearAllCaches() {
    clearContactCache();
    clearChatsCache();
    _messageCache.clear();
    clearPasswordAuthData();
    if (_cacheServicesInitialized) {
      unawaited(_cacheService.clear());
      unawaited(_chatCacheService.clearAllChatCache());
      unawaited(_avatarCacheService.clearAvatarCache());
      unawaited(ImageCacheService.instance.clearCache());
    }
    print("Все кэши очищены из-за ошибки подключения.");
  }

  Future<Map<String, dynamic>> getStatistics() async {
    await _ensureCacheServicesInitialized();

    final cacheStats = await _cacheService.getCacheStats();
    final chatCacheStats = await _chatCacheService.getChatCacheStats();
    final avatarStats = await _avatarCacheService.getAvatarCacheStats();
    final imageStats = await ImageCacheService.instance.getCacheStats();

    return {
      'api_service': {
        'is_online': _isSessionOnline,
        'is_ready': _isSessionReady,
        'cached_chats': (_lastChatsPayload?['chats'] as List?)?.length ?? 0,
        'contacts_in_memory': _contactCache.length,
        'message_cache_entries': _messageCache.length,
        'message_queue_length': _messageQueue.length,
      },
      'connection': {
        'current_url': _currentServerUrl ?? 'api.oneme.ru:443',
        'reconnect_attempts': _reconnectAttempts,
        'last_action_time': _lastActionTime,
      },
      'cache_service': cacheStats,
      'chat_cache': chatCacheStats,
      'avatar_cache': avatarStats,
      'image_cache': imageStats,
    };
  }

  void _preloadContactAvatars(List<Contact> contacts) {
    if (!_cacheServicesInitialized || contacts.isEmpty) return;
    final photoUrls = contacts.map((c) => c.photoBaseUrl).toList();
    if (photoUrls.isEmpty) return;
    unawaited(ImageCacheService.instance.preloadContactAvatars(photoUrls));
  }

  void _preloadMessageImages(List<Message> messages) {
    if (!_cacheServicesInitialized || messages.isEmpty) return;
    final urls = <String>{};
    for (final message in messages) {
      for (final attach in message.attaches) {
        final url = attach['url'] ?? attach['baseUrl'];
        if (url is String && url.isNotEmpty) {
          urls.add(url);
        }
      }
    }
    for (final url in urls) {
      unawaited(ImageCacheService.instance.preloadImage(url));
    }
  }

  Future<void> _updateMessagesCacheIfNewer(
      int chatId,
      List<Message> newMessages,
      ) async {
    try {
      final cached = await _chatCacheService.getCachedChatMessages(chatId);

      if (cached == null || cached.isEmpty) {
        await _chatCacheService.cacheChatMessages(chatId, newMessages);
        return;
      }

      final cachedIds = cached.map((m) => m.id).toSet();
      final newIds = newMessages.map((m) => m.id).toSet();

      if (newIds.every((id) => cachedIds.contains(id))) {
        bool needsUpdate = false;
        for (final newMsg in newMessages) {
          final cachedMsg = cached.firstWhere(
                (m) => m.id == newMsg.id,
            orElse: () => newMsg,
          );
          if (cachedMsg.id != newMsg.id ||
              cachedMsg.updateTime != newMsg.updateTime ||
              cachedMsg.text != newMsg.text) {
            needsUpdate = true;
            break;
          }
        }
        if (!needsUpdate) {
          return;
        }
      }

      final Map<String, Message> messagesMap = {};
      for (final msg in cached) {
        messagesMap[msg.id] = msg;
      }
      for (final msg in newMessages) {
        messagesMap[msg.id] = msg;
      }

      final mergedMessages = messagesMap.values.toList()
        ..sort((a, b) => a.time.compareTo(b.time));

      await _chatCacheService.cacheChatMessages(chatId, mergedMessages);
    } catch (e) {
      print('Ошибка обновления кеша сообщений: $e');
      await _chatCacheService.cacheChatMessages(chatId, newMessages);
    }
  }

  Map<String, dynamic> _contactToMap(Contact contact) {
    return {
      'id': contact.id,
      'name': contact.name,
      'firstName': contact.firstName,
      'lastName': contact.lastName,
      'description': contact.description,
      'photoBaseUrl': contact.photoBaseUrl,
      'isBlocked': contact.isBlocked,
      'isBlockedByMe': contact.isBlockedByMe,
      'accountStatus': contact.accountStatus,
      'status': contact.status,
      'options': contact.options,
    };
  }

  Map<String, dynamic> _mapMessageForLink(Message message) {
    final parsedId = int.tryParse(message.id);
    return {
      'sender': message.senderId,
      'id': parsedId ?? message.id,
      'time': message.time,
      'text': message.text,
      'type': 'USER',
      'cid': message.cid,
      'attaches': message.attaches,
      'elements': message.elements,
    };
  }

  void sendMessage(
      int chatId,
      String text, {
        String? replyToMessageId,
        Message? replyToMessage,
        int? cid,
        List<Map<String, dynamic>>? elements,
      }) {
    Map<String, dynamic>? replyLinkLocal;
    Map<String, dynamic>? replyLinkServer;
    if (replyToMessageId != null) {
      // Сервер ожидает messageId как строку и без лишних полей
      final parsedReplyId = int.tryParse(replyToMessageId);
      replyLinkServer = {
        "type": "REPLY",
        "messageId": parsedReplyId ?? replyToMessageId,
      };
      // Для локального превью можно хранить расширенную информацию
      replyLinkLocal = {
        "type": "REPLY",
        "messageId": replyToMessageId,
        if (replyToMessage != null)
          "message": _mapMessageForLink(replyToMessage),
        "chatId": chatId,
      };
    }

    final int clientMessageId = cid ?? DateTime.now().millisecondsSinceEpoch;
    final payload = {
      "chatId": chatId,
      "message": {
        "text": text,
        "cid": clientMessageId,
        "elements": elements ?? [],
        "attaches": [],
        "link": ?replyLinkServer,
      },
      "notify": true,
    };

    // НЕ очищаем глобальный кэш чатов при отправке сообщения!
    // Это приводит к потере данных о правах администратора во ВСЕХ чатах
    // clearChatsCache();

    final myId =
        _userId ?? (userId != null ? int.tryParse(userId!) : null) ?? 0;
    final localMessage = {
      'id': 'local_$clientMessageId',
      'sender': myId,
      'time': DateTime.now().millisecondsSinceEpoch,
      'text': text,
      'type': 'USER',
      'cid': clientMessageId,
      'attaches': [],
      'link': ?replyLinkLocal,
    };

    _emitLocal({
      'ver': 11,
      'cmd': 1,
      'seq': -1,
      'opcode': 128,
      'payload': {'chatId': chatId, 'message': localMessage},
    });

    final queueItem = QueueItem(
      id: 'msg_$clientMessageId',
      type: QueueItemType.sendMessage,
      opcode: 64,
      payload: payload,
      createdAt: DateTime.now(),
      persistent: true,
      chatId: chatId,
      cid: clientMessageId,
    );

    if (_isSessionOnline && _isSessionReady) {
      unawaited(
        _sendMessage(64, payload)
            .then((_) {
          _queueService.removeFromQueue(queueItem.id);
        })
            .catchError((e) {
          print('Ошибка отправки сообщения: $e');
          print('Payload on error: ' + payload.toString());
          _queueService.addToQueue(queueItem);
        }),
      );
    } else {
      print("Сессия не готова. Сообщение добавлено в очередь.");
      _queueService.addToQueue(queueItem);
    }
  }

  void forwardMessage(
      int targetChatId,
      Message message,
      int sourceChatId, {
        String? sourceChatName,
        String? sourceChatIconUrl,
      }) {
    final int clientMessageId = DateTime.now().millisecondsSinceEpoch;
    final linkPayload = {
      "type": "FORWARD",
      "messageId": int.tryParse(message.id) ?? 0,
      "chatId": sourceChatId,
      "message": _mapMessageForLink(message),
      "chatName": ?sourceChatName,
      "chatIconUrl": ?sourceChatIconUrl,
    };
    final payload = {
      "chatId": targetChatId,
      "message": {"cid": clientMessageId, "link": linkPayload, "attaches": []},
      "notify": true,
    };

    if (_isSessionOnline) {
      _sendMessage(64, payload);
    } else {
      _messageQueue.add({'opcode': 64, 'payload': payload});
    }
  }

  Future<void> editMessage(int chatId, String messageId, String newText) async {
    final payload = {
      "chatId": chatId,
      "messageId": messageId,
      "text": newText,
      "elements": [],
      "attachments": [],
    };

    // НЕ очищаем глобальный кэш чатов при редактировании сообщения!
    // Это приводит к потере данных о правах администратора во ВСЕХ чатах
    // clearChatsCache();

    await waitUntilOnline();

    if (!_isSessionOnline) {
      print('Сессия не онлайн, пытаемся переподключиться...');
      await reconnect();
      await waitUntilOnline();
    }

    Future<bool> sendOnce() async {
      try {
        final response = await sendRequest(67, payload).timeout(const Duration(seconds: 10));

        if (response['cmd'] == 3) {
          final error = response['payload'];
          print('Ошибка редактирования сообщения: $error');

          if (error['error'] == 'proto.state') {
            print('Ошибка состояния сессии, переподключаемся...');
            await reconnect();
            await waitUntilOnline();
            return false;
          }

          if (error['error'] == 'error.edit.invalid.message') {
            print(
              'Сообщение не может быть отредактировано: ${error['localizedMessage']}',
            );
            throw Exception(
              'Сообщение не может быть отредактировано: ${error['localizedMessage']}',
            );
          }

          return false;
        }

        return response['cmd'] == 0x100 || response['cmd'] == 256;
      } catch (e) {
        print('Ошибка при редактировании сообщения: $e');
        return false;
      }
    }

    for (int attempt = 0; attempt < 3; attempt++) {
      print(
        'Попытка редактирования сообщения $messageId (попытка ${attempt + 1}/3)',
      );
      bool ok = await sendOnce();
      if (ok) {
        print('Сообщение $messageId успешно отредактировано');
        return;
      }

      if (attempt < 2) {
        print(
          'Повторяем запрос редактирования для сообщения $messageId через 2 секунды...',
        );
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    print('Не удалось отредактировать сообщение $messageId после 3 попыток');
  }

  Future<Message?> updateChatLastMessage(int chatId) async {
    try {
      final remainingMessages = await _chatCacheService.getCachedChatMessages(
        chatId,
      );
      final newLastMessage =
      remainingMessages != null && remainingMessages.isNotEmpty
          ? (remainingMessages..sort((a, b) => b.time.compareTo(a.time))).first
          : Message(
        id: 'empty',
        senderId: 0,
        time: DateTime.now().millisecondsSinceEpoch,
        text: '',
        cid: null,
        attaches: [],
      );

      final newLastMessageJson = newLastMessage.toJson();

      final cachedChats = await _chatCacheService.getCachedChats();
      if (cachedChats != null) {
        for (var i = 0; i < cachedChats.length; i++) {
          final chatJson = cachedChats[i];
          if (chatJson['id'] == chatId) {
            chatJson['lastMessage'] = newLastMessageJson;
            await _chatCacheService.cacheChats(cachedChats);
            break;
          }
        }
      }

      if (_lastChatsPayload != null) {
        final chats = _lastChatsPayload!['chats'] as List<dynamic>;
        for (var i = 0; i < chats.length; i++) {
          final chatJson = chats[i] as Map<String, dynamic>;
          if (chatJson['id'] == chatId) {
            chatJson['lastMessage'] = newLastMessageJson;
            break;
          }
        }
      }

      // НЕ обнуляем _lastChatsPayload! Мы только что обновили lastMessage в нём
      // Обнуление приводит к потере данных о правах администратора
      // _lastChatsPayload = null;
      return newLastMessage;
    } catch (e) {
      print('Ошибка обновления lastMessage чата: $e');
      return null;
    }
  }

  Future<void> deleteMessage(
      int chatId,
      String messageId, {
        bool forMe = false,
      }) async {
    final messageIdInt = int.tryParse(messageId) ?? 0;
    final payload = {
      "chatId": chatId,
      "messageIds": [messageIdInt],
      "forMe": forMe,
      "itemType": "REGULAR",
    };

    // НЕ очищаем глобальный кэш чатов при удалении сообщения!
    // Это приводит к потере данных о правах администратора во ВСЕХ чатах
    // clearChatsCache();

    await waitUntilOnline();

    if (!_isSessionOnline) {
      print('Сессия не онлайн, пытаемся переподключиться...');
      await reconnect();
      await waitUntilOnline();
    }

    Future<bool> sendOnce() async {
      try {
        final response = await sendRequest(66, payload).timeout(const Duration(seconds: 10));

        if (response['cmd'] == 3) {
          final error = response['payload'];
          print('Ошибка удаления сообщения: $error');

          if (error['error'] == 'proto.state') {
            print('Ошибка состояния сессии, переподключаемся...');
            await reconnect();
            await waitUntilOnline();
            return false;
          }
          return false;
        }

        return response['cmd'] == 0x100 || response['cmd'] == 256;
      } catch (e) {
        print('Ошибка при удалении сообщения: $e');
        return false;
      }
    }

    for (int attempt = 0; attempt < 3; attempt++) {
      print('Попытка удаления сообщения $messageId (попытка ${attempt + 1}/3)');
      bool ok = await sendOnce();
      if (ok) {
        print('Сообщение $messageId успешно удалено');
        await _chatCacheService.removeMessageFromCache(chatId, messageId);
        await updateChatLastMessage(chatId);

        return;
      }

      if (attempt < 2) {
        print(
          'Повторяем запрос удаления для сообщения $messageId через 2 секунды...',
        );
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    print('Не удалось удалить сообщение $messageId после 3 попыток');
  }

  void sendTyping(int chatId, {String type = "TEXT"}) {
    final payload = {"chatId": chatId, "type": type};
    if (_isSessionOnline) {
      _sendMessage(65, payload);
    }
  }

  Future<void> sendVoiceMessage(
      int chatId, {
        required String localPath,
        required int durationSeconds,
        required int fileSize,
        int? senderId,
        int maxNotReadyRetries = 6,
        Function(double)? onProgress,
      }) async {
    await waitUntilOnline();

    final int cid = DateTime.now().millisecondsSinceEpoch;

    final resp82 = await sendRequest(82, {'type': 2, 'count': 1});
    final infoList = resp82['payload']?['info'];
    if (infoList is! List || infoList.isEmpty) {
      throw Exception('Неверный ответ на opcode 82: отсутствует info');
    }

    final uploadInfo = infoList.first;
    final String uploadUrl = uploadInfo['url'];
    final dynamic idCandidate =
        uploadInfo['id'] ?? uploadInfo['audioId'] ?? uploadInfo['videoId'];
    if (idCandidate == null || idCandidate is! num) {
      throw Exception('Неверный ответ на opcode 82: отсутствует id/audioId/videoId');
    }

    final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
    request.files.add(await http.MultipartFile.fromPath('file', localPath));
    final streamed = await request.send();
    onProgress?.call(0.0);
    final httpResp = await http.Response.fromStream(streamed);
    onProgress?.call(1.0);
    if (httpResp.statusCode != 200) {
      throw Exception(
        'Ошибка загрузки аудио: ${httpResp.statusCode} ${httpResp.body}',
      );
    }

    String? token;
    try {
      final decoded = jsonDecode(httpResp.body);
      if (decoded is Map) {
        token = decoded['token']?.toString();
      }
    } catch (e) {
      print('⚠️ Ошибка парсинга токена из ответа: $e');
    }

    token ??= uploadInfo['token']?.toString();

    if (token == null || token.isEmpty) {
      throw Exception('Не получен token после загрузки аудио');
    }

    Future<void> trySendWithToken() async {
      final payload = {
        'chatId': chatId,
        'message': {
          'isLive': false,
          'detectShare': false,
          'elements': [],
          'cid': cid,
          'attaches': [
            {
              '_type': 'AUDIO',
              'token': token,
              'count': durationSeconds,
              'size': fileSize,
              'sender': senderId ?? 0,
            },
          ],
        },
        'notify': true,
      };
      // НЕ очищаем глобальный кэш чатов при отправке аудио!
      // Это приводит к потере данных о правах администратора во ВСЕХ чатах
      // clearChatsCache();

      final resp64 = await sendRequest(64, payload);
      final cmd = resp64['cmd'] as int?;
      if (cmd == 0x300 || cmd == 768) {
        final err = resp64['payload'];
        if (err is Map && err['error'] == 'attachment.not.ready') {
          throw err;
        }
        throw Exception(err?.toString() ?? 'Ошибка отправки аудио');
      }
    }

    int attempt = 0;
    while (true) {
      try {
        await trySendWithToken();
        return;
      } catch (e) {
        if (e is Map && e['error'] == 'attachment.not.ready') {
          if (attempt >= maxNotReadyRetries) {
            throw Exception('attachment.not.ready (max retries exceeded)');
          }
          final backoffMs = 250 * (attempt + 1);
          await Future.delayed(Duration(milliseconds: backoffMs));
          attempt += 1;
          continue;
        }
        rethrow;
      }
    }
  }

  Future<void> sendVideoMessage(
      int chatId, {
        required String localPath,
        required int durationSeconds,
        required int fileSize,
        required int width,
        required int height,
        String? thumbnail,
        int? senderId,
        int maxNotReadyRetries = 6,
        Function(double)? onProgress,
        bool isCircle = false,
      }) async {
    await waitUntilOnline();

    final int cid = DateTime.now().millisecondsSinceEpoch;

    final resp82 = await sendRequest(82, {'type': 1, 'count': 1});
    final infoList = resp82['payload']?['info'];
    if (infoList is! List || infoList.isEmpty) {
      throw Exception('Неверный ответ на opcode 82: отсутствует info');
    }

    final uploadInfo = infoList.first;
    final String uploadUrl = uploadInfo['url'];
    final dynamic idCandidate =
        uploadInfo['id'] ?? uploadInfo['audioId'] ?? uploadInfo['videoId'];
    if (idCandidate == null || idCandidate is! num) {
      throw Exception('Неверный ответ на opcode 82: отсутствует id/audioId/videoId');
    }

    final videoId = idCandidate.toInt();

    final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
    request.files.add(await http.MultipartFile.fromPath('file', localPath));
    final streamed = await request.send();
    onProgress?.call(0.0);
    final httpResp = await http.Response.fromStream(streamed);
    onProgress?.call(1.0);
    if (httpResp.statusCode != 200) {
      throw Exception(
        'Ошибка загрузки видео: ${httpResp.statusCode} ${httpResp.body}',
      );
    }

    String? token;
    try {
      final decoded = jsonDecode(httpResp.body);
      if (decoded is Map) {
        token = decoded['token']?.toString();
      }
    } catch (e) {
      print('⚠️ Ошибка парсинга токена из ответа: $e');
    }

    token ??= uploadInfo['token']?.toString();

    if (token == null || token.isEmpty) {
      throw Exception('Не получен token после загрузки видео');
    }

    Future<void> trySendWithToken() async {
      final attachment = {
        'videoType': isCircle ? 1 : 0,
        '_type': 'VIDEO',
        'token': token,
        'duration': durationSeconds,
        'size': fileSize,
        'width': width,
        'height': height,
        'videoId': videoId,
        'sender': senderId ?? 0,
      };

      if (thumbnail != null && thumbnail.isNotEmpty) {
        attachment['thumbnail'] = thumbnail;
      }

      final payload = {
        'chatId': chatId,
        'message': {
          'isLive': false,
          'detectShare': false,
          'elements': [],
          'cid': cid,
          'attaches': [attachment],
        },
        'notify': true,
      };

      final resp64 = await sendRequest(64, payload);
      final cmd = resp64['cmd'] as int?;
      if (cmd == 0x300 || cmd == 768) {
        final err = resp64['payload'];
        if (err is Map && err['error'] == 'attachment.not.ready') {
          throw err;
        }
        throw Exception(err?.toString() ?? 'Ошибка отправки видео');
      }
    }

    int attempt = 0;
    while (true) {
      try {
        await trySendWithToken();
        return;
      } catch (e) {
        if (e is Map && e['error'] == 'attachment.not.ready') {
          if (attempt >= maxNotReadyRetries) {
            throw Exception('attachment.not.ready (max retries exceeded)');
          }
          final backoffMs = 250 * (attempt + 1);
          await Future.delayed(Duration(milliseconds: backoffMs));
          attempt += 1;
          continue;
        }
        rethrow;
      }
    }
  }

  Future<void> sendGalleryVideoMessage(
    int chatId, {
    required String localPath,
    String? caption,
    int? senderId,
    int maxNotReadyRetries = 6,
  }) async {
    await waitUntilOnline();

    final int cid = DateTime.now().millisecondsSinceEpoch;
    final file = File(localPath);
    final fileSize = await file.length();

    _emitLocal({
      'ver': 11,
      'cmd': 1,
      'seq': -1,
      'opcode': 128,
      'payload': {
        'chatId': chatId,
        'message': {
          'id': 'local_$cid',
          'sender': senderId ?? 0,
          'time': DateTime.now().millisecondsSinceEpoch,
          'text': caption?.trim() ?? '',
          'type': 'USER',
          'cid': cid,
          'attaches': [
            {'_type': 'VIDEO', 'url': 'file://$localPath', 'videoType': 0},
          ],
        },
      },
    });

    final resp82 = await sendRequest(82, {'type': 1, 'count': 1});
    final infoList = resp82['payload']?['info'];
    if (infoList is! List || infoList.isEmpty) {
      throw Exception('Неверный ответ на opcode 82: отсутствует info');
    }

    final uploadInfo = infoList.first;
    final String uploadUrl = uploadInfo['url'];
    final dynamic idCandidate =
        uploadInfo['id'] ?? uploadInfo['audioId'] ?? uploadInfo['videoId'];
    if (idCandidate == null || idCandidate is! num) {
      throw Exception('Неверный ответ на opcode 82: отсутствует id');
    }
    final videoId = idCandidate.toInt();

    final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
    request.files.add(await http.MultipartFile.fromPath('file', localPath));
    final streamed = await request.send();
    final httpResp = await http.Response.fromStream(streamed);
    if (httpResp.statusCode != 200) {
      throw Exception(
        'Ошибка загрузки видео: ${httpResp.statusCode} ${httpResp.body}',
      );
    }

    String? token;
    try {
      final decoded = jsonDecode(httpResp.body);
      if (decoded is Map) {
        token = decoded['token']?.toString();
      }
    } catch (_) {}
    token ??= uploadInfo['token']?.toString();
    if (token == null || token.isEmpty) {
      throw Exception('Не получен token после загрузки видео');
    }

    Future<void> trySend() async {
      final attachment = {
        'videoType': 0,
        '_type': 'VIDEO',
        'token': token,
        'size': fileSize,
        'videoId': videoId,
        'sender': senderId ?? 0,
      };

      final payload = {
        'chatId': chatId,
        'message': {
          'isLive': false,
          'detectShare': false,
          'elements': [],
          'text': caption?.trim() ?? '',
          'cid': cid,
          'attaches': [attachment],
        },
        'notify': true,
      };

      final resp64 = await sendRequest(64, payload);
      final cmd = resp64['cmd'] as int?;
      if (cmd == 0x300 || cmd == 768) {
        final err = resp64['payload'];
        if (err is Map && err['error'] == 'attachment.not.ready') {
          throw err;
        }
        throw Exception(err?.toString() ?? 'Ошибка отправки видео');
      }
    }

    int attempt = 0;
    while (true) {
      try {
        await trySend();
        clearChatsCache();
        return;
      } catch (e) {
        if (e is Map && e['error'] == 'attachment.not.ready') {
          if (attempt >= maxNotReadyRetries) {
            throw Exception('attachment.not.ready (max retries exceeded)');
          }
          await Future.delayed(Duration(milliseconds: 250 * (attempt + 1)));
          attempt++;
          continue;
        }
        rethrow;
      }
    }
  }
}
