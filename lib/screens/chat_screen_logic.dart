part of 'chat_screen.dart';

extension on _ChatScreenState {
  // Message Operations
  Future<void> _sendMessage() async {
    final originalText = _textController.text.trim();
    if (originalText.isEmpty) return;

    if (_actualMyId == null) {
      _showErrorSnackBar('Подождите, чат загружается...');
      return;
    }

    try {
      final theme = context.read<ThemeProvider>();
      if (_currentContact.isBlockedByMe && !theme.blockBypass) {
        _showErrorSnackBar(
          'Нельзя отправить сообщение заблокированному пользователю',
        );
        return;
      }

      if (_isEncryptionRestrictionActive(originalText)) {
        _showInfoSnackBar('Нее, так нельзя)');
        return;
      }

      final textToSend = _prepareTextToSend(originalText);
      final int tempCid = DateTime.now().millisecondsSinceEpoch;
      final List<Map<String, dynamic>> elements = _captureMentions();

      if (!_validateMentions(elements)) {
        elements.clear();
      }

      final tempMessage = _createTempMessage(
        text: textToSend,
        cid: tempCid,
        elements: elements,
      );
      final replyIdForServer = _replyingToMessage?.id;
      final replyMsgForLocal = _replyingToMessage;
      _addMessage(tempMessage);
      _clearInputState();
      _sendToServer(
        text: textToSend,
        cid: tempCid,
        elements: elements,
        replyToMessageId: replyIdForServer,
        replyToMessage: replyMsgForLocal,
      );
      _handleReadReceipts();
      // Сбрасываем локальный кэш чата для обновления данных
      if (widget.isChannel || widget.isGroupChat) {
        _invalidateCache();
        _setStateIfMounted(() {});
      }
    } catch (e, stackTrace) {
      print('ОШИБКА в _sendMessage: $e');
      print(stackTrace);
      _showErrorSnackBar('Не удалось отправить сообщение');
    }
  }

  bool _isEncryptionRestrictionActive(String text) {
    return _encryptionConfigForCurrentChat != null &&
        _encryptionConfigForCurrentChat!.password.isNotEmpty &&
        _sendEncryptedForCurrentChat &&
        (text == 'kometSM' || text == 'kometSM.');
  }

  String _prepareTextToSend(String original) {
    if (_encryptionConfigForCurrentChat != null &&
        _encryptionConfigForCurrentChat!.password.isNotEmpty &&
        _sendEncryptedForCurrentChat &&
        !ChatEncryptionService.isEncryptedMessage(original)) {
      return ChatEncryptionService.encryptWithPassword(
        _encryptionConfigForCurrentChat!.password,
        original,
      );
    }
    return original;
  }

  List<Map<String, dynamic>> _captureMentions() {
    return _mentions.map((m) {
      return {'entityId': m.entityId, 'type': m.type, 'length': m.length};
    }).toList();
  }

  bool _validateMentions(List<Map<String, dynamic>> elements) {
    for (final element in elements) {
      if (element['type'] == 'USER_MENTION') {
        final entityId = element['entityId'];
        if (entityId == null || entityId is! int || entityId <= 0) {
          return false;
        }
      }
    }
    return true;
  }

  Message _createTempMessage({
    required String text,
    required int cid,
    required List<Map<String, dynamic>> elements,
  }) {
    return Message.fromJson({
      'id': 'local_$cid',
      'text': text,
      'time': cid,
      'sender': _actualMyId ?? widget.myId,
      'cid': cid,
      'type': 'USER',
      'attaches': [],
      'elements': elements,
      'link': _buildReplyLink(),
    });
  }

  Map<String, dynamic>? _buildReplyLink() {
    if (_replyingToMessage == null) return null;
    final replyId =
        int.tryParse(_replyingToMessage!.id) ?? _replyingToMessage!.id;
    return {
      'type': 'REPLY',
      'messageId': replyId,
      'chatId': widget.chatId, // use real chatId instead of 0
      'message': {
        'sender': _replyingToMessage!.senderId,
        'id': replyId,
        'time': _replyingToMessage!.time,
        'text': _replyingToMessage!.text,
        'type': 'USER',
        'cid': _replyingToMessage!.cid,
        'attaches': _replyingToMessage!.attaches,
      },
    };
  }

  void _clearInputState() {
    _textController.clear();
    _setStateIfMounted(() {
      _replyingToMessage = null;
      _mentions.clear();
    });
    ChatCacheService().clearChatInputState(widget.chatId);
    widget.onDraftChanged?.call(widget.chatId, null);
  }

  void _sendToServer({
    required String text,
    required int cid,
    required List<Map<String, dynamic>> elements,
    String? replyToMessageId,
    Message? replyToMessage,
  }) {
    ApiService.instance.sendMessage(
      widget.chatId,
      text,
      replyToMessageId: replyToMessageId,
      replyToMessage: replyToMessage,
      cid: cid,
      elements: elements,
    );
  }

  void _handleReadReceipts() {
    ChatReadSettingsService.instance.getSettings(widget.chatId).then((
      readSettings,
    ) {
      final shouldReadOnAction = readSettings != null
          ? (!readSettings.disabled && readSettings.readOnAction)
          : context.read<ThemeProvider>().debugReadOnAction;

      if (shouldReadOnAction && _messages.isNotEmpty) {
        ApiService.instance.markMessageAsRead(widget.chatId, _messages.last.id);
      }
    });
  }

  void _editMessage(Message message) {
    if (!message.canEdit(_actualMyId!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.isDeleted
                ? 'Удаленное сообщение нельзя редактировать'
                : message.attaches.isNotEmpty
                ? 'Сообщения с вложениями нельзя редактировать'
                : 'Сообщение можно редактировать только в течение 24 часов',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _EditMessageDialog(
        initialText: message.text,
        onSave: (newText) async {
          if (newText.trim().isNotEmpty && newText != message.text) {
            final optimistic = message.copyWith(
              text: newText.trim(),
              status: 'EDITED',
              updateTime: DateTime.now().millisecondsSinceEpoch,
              originalText: message.originalText ?? message.text,
            );
            _updateMessage(optimistic);

            try {
              await ApiService.instance.editMessage(
                widget.chatId,
                message.id,
                newText.trim(),
              );
              widget.onChatUpdated?.call();
            } catch (e) {
              _updateMessage(message);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Ошибка редактирования: $e'),
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                );
              }
            }
          }
        },
      ),
    );
  }

  void _forwardMessage(Message message) {
    print(' _forwardMessage вызван для: ${message.id}');
    _showForwardDialog(message);
  }

  // Инициация звонка
  void _initiateCall() async {
    // Проверяем, есть ли уже активный НЕ минимизированный звонок
    if (FloatingCallManager.instance.hasActiveCall && 
        !FloatingCallManager.instance.isMinimized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ У вас уже есть активный звонок'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    
    // Показываем диалог с опцией DATA_CHANNEL
    final enableDataChannel = await showDialog<bool>(
      context: context,
      builder: (context) => _OutgoingCallDialog(
        contactName: widget.contact.name,
      ),
    );
    
    // Если пользователь отменил - выходим
    if (enableDataChannel == null) return;
    
    try {
      // Вызываем API для инициации звонка
      final response = await ApiService.instance.initiateCall(
        widget.contact.id,
        isVideo: false,
      );

      // Отправляем событие START_CALL
      await ApiService.instance.sendCallEvent(
        eventType: 'START_CALL',
        conversationId: response.conversationId,
      );

      // Если дошли сюда, значит сервер ответил успешно
      if (!mounted) return;
      
      // Получаем полную информацию о контакте для аватарки
      String? avatarUrl;
      try {
        final contacts = await ApiService.instance.fetchContactsByIds([widget.contact.id]);
        if (contacts.isNotEmpty && contacts.first.photoBaseUrl != null) {
          avatarUrl = contacts.first.photoBaseUrl;
        }
      } catch (e) {
        print('⚠️ Не удалось загрузить аватарку контакта: $e');
      }
      
      // Открываем экран звонка через CallOverlayService
      CallOverlayService.instance.showCall(
        context,
        callData: response,
        contactId: widget.contact.id,
        contactName: widget.contact.name,
        contactAvatarUrl: avatarUrl,
        isVideo: false,
        isOutgoing: true,
        enableDataChannel: enableDataChannel, // Передаем флаг
      );
      
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Ошибка: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _showForwardDialog(Message message) async {
    print(' _showForwardDialog вызван для сообщения: ${message.id}');

    Map<String, dynamic>? chatData = ApiService.instance.lastChatsPayload;
    if (chatData == null || chatData['chats'] == null) {
      print(' chatData пуст, загружаем...');
      chatData = await _loadChatsIfNeeded();
    }

    if (chatData == null || chatData['chats'] == null) {
      print(' Не удалось загрузить чаты для пересылки');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Список чатов не загружен'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!mounted) {
      print('Виджет не смонтирован');
      return;
    }

    print(' Открываем экран выбора чата для пересылки');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChatsScreen(
          hasScaffold: true,
          isForwardMode: true,
          onForwardChatSelected: (Chat chat) {
            Navigator.of(context).pop();
            _performForward(message, chat.id);
          },
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _loadChatsIfNeeded() async {
    try {
      final result = await ApiService.instance.getChatsAndContacts(
        force: false,
      );
      if (result['chats'] == null || (result['chats'] as List).isEmpty) {
        return await ApiService.instance.getChatsAndContacts(force: true);
      }
      return result;
    } catch (e) {
      return null;
    }
  }

  void _performForward(Message message, int targetChatId) {
    ApiService.instance.forwardMessage(
      targetChatId,
      message,
      widget.chatId,
      sourceChatName: _currentContact.name,
      sourceChatIconUrl: _currentContact.photoBaseUrl,
    );
  }

  Future<void> _initializeChat() async {
    print('🔘 _initializeChat: начало для chatId=${widget.chatId}');
    try {
      await _loadCachedContacts();
      final prefs = await SharedPreferences.getInstance();

      if (!widget.isGroupChat && !widget.isChannel) {
        _contactDetailsCache[widget.contact.id] = widget.contact;
      }

      final profileData = ApiService.instance.lastChatsPayload?['profile'];
      final contactProfile = profileData?['contact'] as Map<String, dynamic>?;

      if (contactProfile != null &&
          contactProfile['id'] != null &&
          contactProfile['id'] != 0) {
        // Безопасное получение ID из SharedPreferences
        final userIdStr = prefs.getString('userId');
        if (userIdStr != null && userIdStr.isNotEmpty) {
          _actualMyId = int.tryParse(userIdStr);
        }
        // Если из prefs не получилось, берем из профиля
        _actualMyId ??= contactProfile['id'] as int?;

        try {
          final myContact = Contact.fromJson(contactProfile);
          if (_actualMyId != null) {
            _contactDetailsCache[_actualMyId!] = myContact;
          }
        } catch (e) {
          print(
            '[ChatScreen] Не удалось добавить собственный профиль в кэш: $e',
          );
        }
      } else if (_actualMyId == null) {
        // БЕЗОПАСНОЕ ПОЛУЧЕНИЕ ID
        final userIdStr = prefs.getString('userId');
        if (userIdStr != null && userIdStr.isNotEmpty) {
          _actualMyId = int.tryParse(userIdStr);
        }
        // Если всё еще null, берем из widget.myId, который мы исправили на шаге 1
        _actualMyId ??= widget.myId;
      }

      if (!widget.isGroupChat && !widget.isChannel) {
        final contactsToCache = _contactDetailsCache.values.toList();
        await ChatCacheService().cacheChatContacts(
          widget.chatId,
          contactsToCache,
        );
      }

      _loadContactDetails();
      _checkContactCache();

      if (widget.isGroupChat || widget.isChannel) {
        await _loadGroupParticipants();
        await _loadMentionableUsers();
        if (_mentionableUsers.isEmpty) {
          var retryCount = 0;
          Timer.periodic(const Duration(milliseconds: 600), (timer) async {
            if (!mounted || _mentionableUsers.isNotEmpty || retryCount >= 10) {
              timer.cancel();
              return;
            }
            retryCount++;
            await _loadGroupParticipants();
            await _loadMentionableUsers();
            if (_mentionableUsers.isNotEmpty && mounted) {
              _setStateIfMounted(() {});
              timer.cancel();
            }
          });
        }
      } else {
        await _loadMentionableUsers();
      }

      ApiService.instance.messages.listen((msg) {
        final payload = msg['payload'];
        if (payload != null &&
            payload['chatId'] == widget.chatId &&
            (widget.isGroupChat || widget.isChannel) &&
            (msg['opcode'] == 64 || msg['opcode'] == 128)) {
          if (payload['participants'] != null ||
              (payload['chat'] != null &&
                  payload['chat']['participants'] != null)) {
            _loadMentionableUsers().then((_) {
              _setStateIfMounted(() {});
            });
          }
        }
      });

      if (!ApiService.instance.isContactCacheValid()) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) ApiService.instance.getBlockedContacts();
        });
      }

      ApiService.instance.contactUpdates.listen((contact) {
        if (widget.chatId == 0) return;
        if (contact.id == _currentContact.id && mounted) {
          ApiService.instance.updateCachedContact(contact);
          Future.microtask(() {
            if (mounted) {
              _setStateIfMounted(() {
                _currentContact = contact;
              });
            }
          });
        }
      });

      _itemPositionsListener.itemPositions.addListener(() {
        final positions = _itemPositionsListener.itemPositions.value;
        if (positions.isNotEmpty) {
          final bottomItemPosition = positions.firstWhere(
            (p) => p.index == 0,
            orElse: () => positions.first,
          );
          final isAtBottom =
              bottomItemPosition.index == 0 &&
              bottomItemPosition.itemLeadingEdge <= 0.25;
          _isUserAtBottom = isAtBottom;
          if (isAtBottom) _isScrollingToBottom = false;
          _showScrollToBottomNotifier.value =
              !isAtBottom && !_isScrollingToBottom;

          if (positions.isNotEmpty && _chatItems.isNotEmpty) {
            final maxIndex = positions
                .map((p) => p.index)
                .reduce((a, b) => a > b ? a : b);
            if (maxIndex > _maxViewedIndex) _maxViewedIndex = maxIndex;

            final shouldLoadByViewedCount =
                maxIndex >= _ChatScreenState._loadMoreThreshold &&
                (maxIndex - _lastLoadedAtViewedIndex) >=
                    _ChatScreenState._loadMoreThreshold;
            final threshold = _chatItems.length > 5 ? 3 : 1;
            final isNearTop = maxIndex >= _chatItems.length - threshold;

            if ((isNearTop || shouldLoadByViewedCount) &&
                _hasMore &&
                !_isLoadingMore &&
                _messages.isNotEmpty &&
                _oldestLoadedTime != null) {
              Future.microtask(() {
                if (mounted && _hasMore && !_isLoadingMore) _loadMore();
              });
            }
          }
        }
      });

      _searchController.addListener(() {
        if (_searchController.text.isEmpty && _searchResults.isNotEmpty) {
          Future.microtask(() {
            if (mounted) {
              _setStateIfMounted(() {
                _searchResults.clear();
                _currentResultIndex = -1;
              });
            }
          });
        } else if (_searchController.text.isNotEmpty) {
          _performSearch(_searchController.text);
        }
      });

      _loadHistoryAndListen();
    } catch (e, stackTrace) {
      print('[ChatScreen] Критическая ошибка в _initializeChat: $e');
      print(stackTrace);
      // Гарантированный сброс загрузки при любой ошибке инициализации
      if (mounted) {
        _setStateIfMounted(() {
          _isLoadingHistory = false;
        });
      }
    }
  }

  Future<void> _ensureContactsCached(List<int> contactIds) async {
    final idsToFetch = contactIds
        .where((id) => id != 0 && !_contactDetailsCache.containsKey(id))
        .toList();
    if (idsToFetch.isEmpty) return;

    try {
      final contacts = await ApiService.instance.fetchContactsByIds(idsToFetch);
      for (final contact in contacts) {
        _contactDetailsCache[contact.id] = contact;
      }
      _setStateIfMounted(() {});
    } catch (e) {
      debugPrint('Error fetching missing contacts: $e');
    }
  }

  void _loadHistoryAndListen() {
    print('🔘 _loadHistoryAndListen: начало для chatId=${widget.chatId}');
    _paginateInitialLoad();

    ApiService.instance.reconnectionComplete.listen((_) {
      if (mounted && ApiService.instance.currentActiveChatId == widget.chatId) {
        _paginateInitialLoad();
      }
    });

    _apiSubscription = ApiService.instance.messages.listen((message) {
      if (!mounted) return;

      // Обработка события завершения фоновой загрузки сообщений
      final messageType = message['type'];
      if (messageType == 'messages_loaded') {
        final loadedChatId = message['chatId'];
        if (loadedChatId == widget.chatId) {
          final messages = message['messages'] as List<Message>?;
          final newCount = message['newCount'] as int? ?? 0;
          if (messages != null && newCount > 0) {
            print('📥 Фоновая загрузка: получено $newCount новых сообщений');
            const int preloadedMessagesLimit =
                _ChatScreenState._historyLoadBatch;
            final hydratedMessages = _hydrateLinksSequentially(messages);
            _messages
              ..clear()
              ..addAll(hydratedMessages);
            _oldestLoadedTime = _messages.isNotEmpty
                ? _messages.first.time
                : null;
            _hasMore = _messages.length >= preloadedMessagesLimit;
            _buildChatItems();
            _setStateIfMounted(() {});
          }
        }
        return;
      }

      final opcode = message['opcode'];
      final cmd = message['cmd'];
      final seq = message['seq'];
      final payload = message['payload'];
      if (payload is! Map<String, dynamic>) return;

      final dynamic incomingChatId =
          payload['chatId'] ?? payload['chat']?['id'];
      final int? chatIdNormalized = incomingChatId is int
          ? incomingChatId
          : int.tryParse(incomingChatId?.toString() ?? '');
      final shouldCheckChatId =
          opcode != 178 || (opcode == 178 && payload.containsKey('chatId'));

      if (shouldCheckChatId &&
          (chatIdNormalized == null || chatIdNormalized != widget.chatId))
        return;

      if (opcode == 64 && (cmd == 0x100 || cmd == 256)) {
        // Обновляем данные чата если они пришли (включая список админов)
        if (payload['chat'] != null && payload['chat'] is Map<String, dynamic>) {
          print('✅ [ChatScreen] Получены данные чата в opcode 64, обновляем');
          ApiService.instance.updateChatInCacheFromJson(payload['chat'] as Map<String, dynamic>);
          _invalidateCache(); // Сбрасываем локальный кэш
        } else {
          print('⚠️ [ChatScreen] payload[\'chat\'] отсутствует в opcode 64');
        }
        
        final messageMap = payload['message'];
        if (messageMap is! Map<String, dynamic>) return;
        final newMessage = Message.fromJson(messageMap);
        final messageId = newMessage.id;
        if (messageId.isNotEmpty && !messageId.startsWith('local_')) {
          final queueService = MessageQueueService();
          if (newMessage.cid != null) {
            final queueItem = queueService.findByCid(newMessage.cid!);
            if (queueItem != null) queueService.removeFromQueue(queueItem.id);
          }
        }
        
        // Добавляем в кэш (с сохранением link из локального сообщения)
        unawaited(
          ChatCacheService().addMessageToCache(widget.chatId, newMessage),
        );
        
        // Если идёт загрузка истории, откладываем обработку
        if (_isLoadingHistory) {
          _pendingMessagesDuringLoad.add(newMessage);
          return;
        }
        Future.microtask(() {
          if (mounted) _updateMessage(newMessage);
        });
      } else if (opcode == 128) {
        // Обновляем данные чата если они пришли (включая список админов)
        if (payload['chat'] != null && payload['chat'] is Map<String, dynamic>) {
          print('✅ [ChatScreen] Получены данные чата в opcode 128, обновляем');
          ApiService.instance.updateChatInCacheFromJson(payload['chat'] as Map<String, dynamic>);
          _invalidateCache(); // Сбрасываем локальный кэш
        } else {
          print('⚠️ [ChatScreen] payload[\'chat\'] отсутствует в opcode 128');
        }
        
        final messageMap = payload['message'];
        if (messageMap is! Map<String, dynamic>) return;
        final newMessage = Message.fromJson(messageMap);
        if (newMessage.status == 'REMOVED') {
          _removeMessages([newMessage.id]);
        } else {
          unawaited(
            ChatCacheService().addMessageToCache(widget.chatId, newMessage),
          );

          // Если идёт загрузка истории, откладываем обработку сообщения
          if (_isLoadingHistory) {
            _pendingMessagesDuringLoad.add(newMessage);
            return;
          }

          Future.microtask(() {
            if (!mounted) return;
            final hasSameId = _messages.any((m) => m.id == newMessage.id);
            final hasSameCid =
                newMessage.cid != null &&
                _messages.any((m) => m.cid != null && m.cid == newMessage.cid);
            if (hasSameId || hasSameCid) {
              _updateMessage(newMessage);
            } else {
              _addMessage(newMessage);
            }
          });
        }
      } else if (opcode == 132) {
        final dynamic contactIdAny = payload['contactId'] ?? payload['userId'];
        if (contactIdAny != null) {
          final int? cid = contactIdAny is int
              ? contactIdAny
              : int.tryParse(contactIdAny.toString());
          if (cid != null) {
            final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            final isOnline = payload['online'] == true;
            ApiService.instance.updatePresenceData({
              cid.toString(): {
                'seen': currentTime,
                'on': isOnline ? 'ON' : 'OFF',
              },
            });
          }
        }
      } else if (opcode == 67) {
        final messageMap = payload['message'];
        if (messageMap is! Map<String, dynamic>) return;
        final editedMessage = Message.fromJson(messageMap);
        // Если идёт загрузка истории, откладываем обработку
        if (_isLoadingHistory) {
          _pendingMessagesDuringLoad.add(editedMessage);
          return;
        }
        Future.microtask(() {
          if (mounted) _updateMessage(editedMessage);
        });
      } else if (opcode == 66 || opcode == 142) {
        final rawMessageIds = payload['messageIds'] as List<dynamic>? ?? [];
        final deletedMessageIds = rawMessageIds
            .map((id) => id.toString())
            .toList();
        if (deletedMessageIds.isNotEmpty) {
          Future.microtask(() {
            if (mounted) _handleDeletedMessages(deletedMessageIds);
          });
        }
      } else if (opcode == 178) {
        if (cmd == 0x100 || cmd == 256) {
          final messageId = _pendingReactionSeqs[seq];
          if (messageId != null) {
            _pendingReactionSeqs.remove(seq);
            _updateMessageReaction(messageId, payload['reactionInfo'] ?? {});
          } else {
            if (_sendingReactions.isNotEmpty) {
              _sendingReactions.clear();
              _buildChatItems();
              _setStateIfMounted(() {});
            }
          }
        }
        if (cmd == 0) {
          final messageId = payload['messageId'] as String?;
          final reactionInfo = payload['reactionInfo'] as Map<String, dynamic>?;
          if (messageId != null && reactionInfo != null) {
            Future.microtask(() {
              if (mounted) _updateMessageReaction(messageId, reactionInfo);
            });
          }
        }
      } else if (opcode == 179) {
        final messageId = payload['messageId'] as String?;
        final reactionInfo = payload['reactionInfo'] as Map<String, dynamic>?;
        if (messageId != null) {
          Future.microtask(() {
            if (mounted) _updateMessageReaction(messageId, reactionInfo ?? {});
          });
        }
      } else if (opcode == 50) {
        final dynamic type = payload['type'];
        if (type == 'READ_MESSAGE') {
          final int? receiptChatId = _parseChatId(payload['chatId']);
          if (receiptChatId == null || receiptChatId != widget.chatId) return;

          final readerId =
              payload['userId'] ??
              payload['contactId'] ??
              payload['uid'] ??
              payload['sender'];
          final int? readerIdInt = _parseMessageId(readerId);
          if (readerIdInt != null &&
              _actualMyId != null &&
              readerIdInt == _actualMyId)
            return;

          final dynamic rawMessageId = payload['messageId'] ?? payload['id'];
          final int? messageId = _parseMessageId(rawMessageId);
          final String? messageIdStr = rawMessageId?.toString();

          if (messageId != null) {
            if (_lastPeerReadMessageId == null ||
                messageId > _lastPeerReadMessageId!) {
              _setStateIfMounted(() {
                _lastPeerReadMessageId = messageId;
                _lastPeerReadMessageIdStr = messageIdStr;
              });
            }
          } else if (messageIdStr != null && messageIdStr.isNotEmpty) {
            if (_lastPeerReadMessageIdStr == null ||
                messageIdStr.compareTo(_lastPeerReadMessageIdStr!) >= 0) {
              _setStateIfMounted(() {
                _lastPeerReadMessageIdStr = messageIdStr;
              });
            }
          }
        }
      }
    });
  }

  Future<void> _paginateInitialLoad() async {
    print('🔘 _paginateInitialLoad: начало для chatId=${widget.chatId}');
    _setStateIfMounted(() => _isLoadingHistory = true);
    _maxViewedIndex = 0;
    _lastLoadedAtViewedIndex = 0;
    const int initialLimit = _ChatScreenState._historyLoadBatch;
    const int initialMaxMessages = _ChatScreenState._historyLoadBatch;

    final loadChatQueueItem = QueueItem(
      id: 'load_chat_${widget.chatId}',
      type: QueueItemType.loadChat,
      opcode: 49,
      payload: {
        "chatId": widget.chatId,
        "from": DateTime.now()
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
        "forward": 0,
        "backward": initialLimit,
        "getMessages": true,
      },
      createdAt: DateTime.now(),
      persistent: false,
      chatId: widget.chatId,
    );
    MessageQueueService().addToQueue(loadChatQueueItem);

    final chatCacheService = ChatCacheService();
    List<Message>? cachedMessages = await chatCacheService
        .getCachedChatMessages(widget.chatId);
    bool hasCache = cachedMessages != null && cachedMessages.isNotEmpty;

    // Если есть кэш - показываем сразу, но всё равно обновляем с сервера
    if (hasCache) {
      if (!mounted) return;
      _messages.clear();
      _messages.addAll(_hydrateLinksSequentially(cachedMessages));
      if (_messages.isNotEmpty) _oldestLoadedTime = _messages.first.time;
      _hasMore = true;

      if (widget.isGroupChat) await _loadGroupParticipants();
      _buildChatItems();
      _messagesToAnimate.clear();

      Future.microtask(() {
        _setStateIfMounted(() {
          // Не снимаем флаг загрузки, так как грузим с сервера
        });
      });
      _updatePinnedMessage();
      if (_messages.isEmpty && !widget.isChannel) _loadEmptyChatSticker();
    }

    List<Message> allMessages = [];
    try {
      // Загружаем стартовый батч истории и при необходимости догружаем дальше.
      allMessages = await ApiService.instance
          .getMessageHistory(
            widget.chatId,
            force: true,
            initialLimit: initialLimit,
            maxMessages: initialMaxMessages,
            onInitialLoaded: (initial) {
              // Вызывается когда загружена первая партия истории
              if (!mounted) return;
              print(
                '⚡ Быстрая загрузка: ${initial.length} сообщений показаны моментально',
              );

              // Обновляем UI только если ещё не показали кэш или кэш пустой
              if (!hasCache || _messages.isEmpty) {
                _messages.clear();
                _messages.addAll(_hydrateLinksSequentially(initial));
                if (_messages.isNotEmpty)
                  _oldestLoadedTime = _messages.first.time;
                _hasMore = initial.length >= initialLimit;

                _buildChatItems();
                _messagesToAnimate.clear();

                _setStateIfMounted(() {
                  _isLoadingHistory =
                      false; // Снимаем флаг после быстрой загрузки
                });

                _updatePinnedMessage();
                if (_messages.isEmpty && !widget.isChannel)
                  _loadEmptyChatSticker();
              }
            },
            onCompleteLoaded: (all) {
              // Вызывается когда загружены все сообщения (до 30)
              if (!mounted) return;
              print('✅ Полная загрузка: ${all.length} сообщений');

              // Обновляем полный список
              _messages.clear();
              _messages.addAll(_hydrateLinksSequentially(all));
              if (_messages.isNotEmpty)
                _oldestLoadedTime = _messages.first.time;
              _hasMore = all.length >= initialMaxMessages;

              _buildChatItems();

              // Снимаем флаг если ещё не снят
              if (_isLoadingHistory) {
                _setStateIfMounted(() => _isLoadingHistory = false);
              }
            },
          )
          .timeout(const Duration(seconds: 10), onTimeout: () => <Message>[]);

      if (allMessages.isNotEmpty) {
        MessageQueueService().removeFromQueue('load_chat_${widget.chatId}');
      }

      if (!mounted) return;
      final bool hasServerData = allMessages.isNotEmpty;
      List<Message> mergedMessages;

      if (hasServerData) {
        final Map<String, Message> messagesMap = {};
        final Set<String> serverMessageIds = {};
        for (final msg in allMessages) {
          messagesMap[msg.id] = msg;
          serverMessageIds.add(msg.id);
        }

        final themeProvider = Provider.of<ThemeProvider>(
          context,
          listen: false,
        );
        if (themeProvider.showDeletedMessages && hasCache) {
          for (final cachedMsg in _messages) {
            if (!serverMessageIds.contains(cachedMsg.id) &&
                !cachedMsg.id.startsWith('local_')) {
              messagesMap[cachedMsg.id] = cachedMsg.copyWith(isDeleted: true);
            }
          }
        }

        if (themeProvider.viewRedactHistory && hasCache) {
          for (final cachedMsg in _messages) {
            final serverMsg = messagesMap[cachedMsg.id];
            if (serverMsg != null) {
              if (cachedMsg.originalText != null &&
                  serverMsg.originalText == null) {
                messagesMap[cachedMsg.id] = serverMsg.copyWith(
                  originalText: cachedMsg.originalText,
                );
              } else if (cachedMsg.text != serverMsg.text &&
                  cachedMsg.text.isNotEmpty &&
                  (serverMsg.isEdited || serverMsg.updateTime != null) &&
                  serverMsg.originalText == null) {
                messagesMap[cachedMsg.id] = serverMsg.copyWith(
                  originalText: cachedMsg.text,
                );
              }
            }
          }
        }

        final cidMap = <int, Message>{};
        for (final msg in messagesMap.values) {
          final cid = msg.cid;
          if (cid != null) {
            final existing = cidMap[cid];
            if (existing == null || !existing.id.startsWith('local_')) {
              cidMap[cid] = msg;
            } else if (!msg.id.startsWith('local_')) {
              cidMap[cid] = msg;
              messagesMap.remove(existing.id);
              messagesMap[msg.id] = msg;
            }
          }
        }

        mergedMessages = messagesMap.values.toList()
          ..sort((a, b) => a.time.compareTo(b.time));
      } else {
        mergedMessages = List<Message>.from(_messages);
      }

      mergedMessages = _hydrateLinksSequentially(mergedMessages);
      final Set<int> senderIds = {};
      for (final message in mergedMessages) {
        senderIds.add(message.senderId);
        if (message.isReply && message.link?['message']?['sender'] != null) {
          final replySenderId = message.link!['message']!['sender'];
          if (replySenderId is int) senderIds.add(replySenderId);
        }
      }
      senderIds.remove(0);

      final idsToFetch = senderIds
          .where((id) => !_contactDetailsCache.containsKey(id))
          .toList();
      if (idsToFetch.isNotEmpty) {
        final newContacts = await ApiService.instance.fetchContactsByIds(
          idsToFetch,
        );
        for (final contact in newContacts) {
          _contactDetailsCache[contact.id] = contact;
        }
        if (newContacts.isNotEmpty) {
          await ChatCacheService().cacheChatContacts(
            widget.chatId,
            _contactDetailsCache.values.toList(),
          );
        }
      }

      if (mergedMessages.isNotEmpty) {
        await chatCacheService.cacheChatMessages(widget.chatId, mergedMessages);
      }

      if (widget.isGroupChat) await _loadGroupParticipants();

      final int page;
      if (_anyOptimize) {
        page = _optPage < initialLimit ? initialLimit : _optPage;
      } else {
        page = _ChatScreenState._pageSize;
      }
      final slice = mergedMessages.length > page
          ? mergedMessages.sublist(mergedMessages.length - page)
          : mergedMessages;
      final bool hasAnyMessages = mergedMessages.isNotEmpty;
      final bool serverHasMore = allMessages.length >= initialMaxMessages;
      final bool nextHasMore = hasServerData
          ? (_hasMore || serverHasMore || mergedMessages.length > slice.length)
          : (_hasMore && hasAnyMessages);

      // Сначала обновляем _messages, затем строим элементы чата
      _messages
        ..clear()
        ..addAll(slice);
      _oldestLoadedTime = _messages.isNotEmpty ? _messages.first.time : null;
      _hasMore = nextHasMore;

      _buildChatItems();
      _messagesToAnimate.clear();

      Future.microtask(() {
        _setStateIfMounted(() {
          _isLoadingHistory = false;
        });

        // Обрабатываем сообщения, пришедшие во время загрузки
        _processPendingMessages();

        if (_messages.isNotEmpty) {
          _jumpToBottom();
          _updatePinnedMessage();
        } else if (!widget.isChannel) {
          _loadEmptyChatSticker();
        }
      });
    } catch (e) {
      print("[ChatScreen] Ошибка при загрузке истории сообщений: $e");
      if (mounted && !_isDisposed) {
        _setStateIfMounted(() {
          _isLoadingHistory = false;
        });
        // Обрабатываем отложенные сообщения даже при ошибке
        _processPendingMessages();
      }
    }

    final readSettings = await ChatReadSettingsService.instance.getSettings(
      widget.chatId,
    );
    final theme = context.read<ThemeProvider>();
    final shouldReadOnEnter = readSettings != null
        ? (!readSettings.disabled && readSettings.readOnEnter)
        : theme.debugReadOnEnter;

    if (shouldReadOnEnter && _messages.isNotEmpty) {
      ApiService.instance.markMessageAsRead(widget.chatId, _messages.last.id);
    }
  }

  // Обработка сообщений, пришедших во время загрузки истории
  void _processPendingMessages() {
    if (_pendingMessagesDuringLoad.isEmpty) return;

    print(
      '[ChatScreen] Обработка ${_pendingMessagesDuringLoad.length} отложенных сообщений',
    );

    final pending = List<Message>.from(_pendingMessagesDuringLoad);
    _pendingMessagesDuringLoad.clear();

    for (final newMessage in pending) {
      if (!mounted) return;

      final hasSameId = _messages.any((m) => m.id == newMessage.id);
      final hasSameCid =
          newMessage.cid != null &&
          _messages.any((m) => m.cid != null && m.cid == newMessage.cid);

      if (hasSameId || hasSameCid) {
        _updateMessage(newMessage);
      } else {
        _addMessage(newMessage);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    if (_messages.isEmpty || _oldestLoadedTime == null) {
      _hasMore = false;
      return;
    }

    _isLoadingMore = true;
    const int loadMoreBatchSize = _ChatScreenState._historyLoadBatch;
    // Не уменьшаем timestamp на 1: иначе можно пропустить сообщения
    // с тем же временем, что и текущая верхняя граница.
    final int requestFromTimestamp = _oldestLoadedTime!;
    bool shouldRebuild = false;
    bool shouldUpdatePinned = false;
    try {
      final olderMessages = await ApiService.instance
          .loadOlderMessagesByTimestamp(
            widget.chatId,
            requestFromTimestamp,
            backward: loadMoreBatchSize,
          );

      if (!mounted) return;
      if (olderMessages.isEmpty) {
        _hasMore = false;
        shouldRebuild = true;
        return;
      }

      final existingMessageIds = _messages.map((m) => m.id).toSet();
      final existingMessageCids = _messages
          .where((m) => m.cid != null)
          .map((m) => m.cid!)
          .toSet();
      final newMessages = olderMessages
          .where(
            (m) =>
                !existingMessageIds.contains(m.id) &&
                (m.cid == null || !existingMessageCids.contains(m.cid)),
          )
          .toList();
      if (newMessages.isEmpty) {
        final oldestResponseTime = olderMessages.first.time;
        final madeProgress = oldestResponseTime < _oldestLoadedTime!;
        if (madeProgress) {
          _oldestLoadedTime = oldestResponseTime;
          _hasMore = olderMessages.length >= loadMoreBatchSize;
        } else {
          _hasMore = false;
        }
        shouldRebuild = true;
        return;
      }

      final hydratedOlder = _hydrateLinksSequentially(
        newMessages,
        initialKnown: _buildKnownMessagesMap(),
      );
      final oldItemsCount = _chatItems.length;
      _messages.insertAll(0, hydratedOlder);
      _oldestLoadedTime = _messages.first.time;
      _hasMore = olderMessages.length >= loadMoreBatchSize;
      _buildChatItems();
      final addedItemsCount = _chatItems.length - oldItemsCount;
      _lastLoadedAtViewedIndex = _maxViewedIndex + addedItemsCount;
      shouldRebuild = true;
      shouldUpdatePinned = true;
    } catch (e) {
      print('[ChatScreen] Ошибка при загрузке старых сообщений: $e');
    } finally {
      _isLoadingMore = false;
      if (mounted && shouldRebuild) {
        _setStateIfMounted(() {});
      }
      if (mounted && shouldUpdatePinned) {
        _updatePinnedMessage();
      }
    }
  }

  // Message Updates & Helpers
  void _addMessage(Message message, {bool forceScroll = false}) {
    final normalizedMessage = _hydrateLinkFromKnown(
      message,
      _buildKnownMessagesMap(),
    );
    if (_messages.any((m) => m.id == normalizedMessage.id)) return;

    final allMessages = [..._messages, normalizedMessage]
      ..sort((a, b) => a.time.compareTo(b.time));
    unawaited(ChatCacheService().cacheChatMessages(widget.chatId, allMessages));

    final wasAtBottom = _isUserAtBottom;
    final isMyMessage = normalizedMessage.senderId == _actualMyId;
    final lastMessage = _messages.isNotEmpty ? _messages.last : null;
    _messages.add(normalizedMessage);
    _messagesToAnimate.add(normalizedMessage.id);

    final currentDate = DateTime.fromMillisecondsSinceEpoch(
      normalizedMessage.time,
    ).toLocal();
    final lastDate = lastMessage != null
        ? DateTime.fromMillisecondsSinceEpoch(lastMessage.time).toLocal()
        : null;

    if (lastMessage == null || !_isSameDay(currentDate, lastDate!)) {
      _chatItems.add(DateSeparatorItem(currentDate));
    }

    final lastMessageItem =
        _chatItems.isNotEmpty && _chatItems.last is MessageItem
        ? _chatItems.last as MessageItem
        : null;
    final isGrouped = _isMessageGrouped(
      normalizedMessage,
      lastMessageItem?.message,
    );
    final isFirstInGroup = lastMessageItem == null || !isGrouped;
    final isLastInGroup = true;

    if (isGrouped && lastMessageItem != null) {
      _chatItems.removeLast();
      _chatItems.add(
        MessageItem(
          lastMessageItem.message,
          isFirstInGroup: lastMessageItem.isFirstInGroup,
          isLastInGroup: false,
          isGrouped: lastMessageItem.isGrouped,
        ),
      );
    }

    _chatItems.add(
      MessageItem(
        normalizedMessage,
        isFirstInGroup: isFirstInGroup,
        isLastInGroup: isLastInGroup,
        isGrouped: isGrouped,
      ),
    );
    _updatePinnedMessage();

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _setStateIfMounted(() {});
          _invalidateCache();
          if ((wasAtBottom || isMyMessage || forceScroll) &&
              _itemScrollController.isAttached) {
            _itemScrollController.jumpTo(index: 0);
          }
        }
      });
    }
  }

  void _updateMessage(Message updatedMessage) {
    int? index = _messages.indexWhere((m) => m.id == updatedMessage.id);
    if (index == -1 && updatedMessage.cid != null) {
      index = _messages.indexWhere(
        (m) => m.cid != null && m.cid == updatedMessage.cid,
      );
    }

    if (index != -1 && index < _messages.length) {
      final oldMessage = _messages[index];
      final hydratedUpdate = _hydrateLinkFromKnown(
        updatedMessage,
        _buildKnownMessagesMap(),
      );
      final finalMessage = hydratedUpdate.link != null
          ? hydratedUpdate
          : hydratedUpdate.copyWith(link: oldMessage.link);

      final finalMessageWithOriginalText = (() {
        if (finalMessage.originalText != null) return finalMessage;
        if (oldMessage.originalText != null)
          return finalMessage.copyWith(originalText: oldMessage.originalText);
        if ((finalMessage.isEdited || finalMessage.updateTime != null) &&
            finalMessage.text != oldMessage.text) {
          return finalMessage.copyWith(originalText: oldMessage.text);
        }
        return finalMessage;
      })();

      _messages[index] = finalMessageWithOriginalText;
      unawaited(ChatCacheService().cacheChatMessages(widget.chatId, _messages));

      if (mounted) {
        _setStateIfMounted(() {});
        _invalidateCache();
      }
      final chatItemIndex = _chatItems.indexWhere(
        (item) =>
            item is MessageItem &&
            (item.message.id == oldMessage.id ||
                item.message.id == updatedMessage.id ||
                (updatedMessage.cid != null &&
                    item.message.cid != null &&
                    item.message.cid == updatedMessage.cid)),
      );

      if (chatItemIndex != -1) {
        final oldItem = _chatItems[chatItemIndex] as MessageItem;
        _chatItems[chatItemIndex] = MessageItem(
          finalMessage,
          isFirstInGroup: oldItem.isFirstInGroup,
          isLastInGroup: oldItem.isLastInGroup,
          isGrouped: oldItem.isGrouped,
        );
        _setStateIfMounted(() {});
      } else {
        _buildChatItems();
        _setStateIfMounted(() {});
      }
    } else {
      ApiService.instance
          .getMessageHistory(widget.chatId, force: true)
          .then((fresh) {
            if (!mounted) return;
            _messages
              ..clear()
              ..addAll(fresh);
            _buildChatItems();
            Future.microtask(() {
              _setStateIfMounted(() {});
            });
          })
          .catchError((_) {});
    }
  }

  void _handleDeletedMessages(List<String> deletedMessageIds) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final showDeletedMessages = themeProvider.showDeletedMessages;

    for (final messageId in deletedMessageIds) {
      if (_deletingMessageIds.contains(messageId)) continue;

      final messageIndex = _messages.indexWhere((m) => m.id == messageId);
      if (messageIndex != -1) {
        final message = _messages[messageIndex];
        final isMyMessage = message.senderId == _actualMyId;

        if (isMyMessage) {
          _removeMessages([messageId]);
        } else {
          if (showDeletedMessages) {
            _messages[messageIndex] = message.copyWith(isDeleted: true);
            _buildChatItems();
            _setStateIfMounted(() {});
          } else {
            _removeMessages([messageId]);
          }
        }
      }
    }
  }

  int _getVisualIndex(int index) {
    return _chatItems.length - 1 - index;
  }

  void _scrollToMessage(String messageId) {
    if (messageId.isEmpty) return;
    int index = _chatItems.indexWhere((item) {
      if (item is MessageItem) return item.message.id == messageId;
      return false;
    });

    if (index != -1 && _itemScrollController.isAttached) {
      // Clear previous highlight
      _setStateIfMounted(() {
        _highlightedMessageId = messageId;
      });

      // Clear highlight after delay
      Timer(const Duration(seconds: 2), () {
        if (_highlightedMessageId == messageId) {
          _setStateIfMounted(() {
            _highlightedMessageId = null;
          });
        }
      });

      final visualIndex = _getVisualIndex(index);
      _itemScrollController.scrollTo(
        index: visualIndex,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _removeMessages(List<String> messageIds) {
    _deletingMessageIds.addAll(messageIds);
    _setStateIfMounted(() {});

    Future.delayed(const Duration(milliseconds: 300), () {
      final removedCount = _messages.length;
      _messages.removeWhere((message) => messageIds.contains(message.id));
      final actuallyRemoved = removedCount - _messages.length;

      if (actuallyRemoved > 0) {
        _deletingMessageIds.removeAll(messageIds);
        for (final messageId in messageIds) {
          unawaited(
            ChatCacheService().removeMessageFromCache(widget.chatId, messageId),
          );
        }
        _buildChatItems();
        _setStateIfMounted(() {});
      }
    });
  }

  Future<void> _deleteMessageForAll(String messageId) async {
    try {
      await ApiService.instance.deleteMessage(
        widget.chatId,
        messageId,
        forMe: false,
      );
      // Локально удаляем сообщение
      _removeMessages([messageId]);
    } catch (e) {
      print('[_deleteMessageForAll] Ошибка удаления сообщения для всех: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка удаления: $e')));
      }
    }
  }

  void _updateMessageReaction(
    String messageId,
    Map<String, dynamic> reactionInfo,
  ) {
    final messageIndex = _messages.indexWhere((m) => m.id == messageId);
    if (messageIndex != -1) {
      final message = _messages[messageIndex];
      final updatedMessage = message.copyWith(reactionInfo: reactionInfo);
      _messages[messageIndex] = updatedMessage;

      if (_sendingReactions.remove(messageId)) {}
      _buildChatItems();
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _setStateIfMounted(() {});
        });
      }
    }
  }

  void _updateReactionOptimistically(String messageId, String emoji) {
    final messageIndex = _messages.indexWhere((m) => m.id == messageId);
    if (messageIndex != -1) {
      final message = _messages[messageIndex];
      final currentReactionInfo = message.reactionInfo ?? {};
      final currentCounters = List<Map<String, dynamic>>.from(
        currentReactionInfo['counters'] ?? [],
      );
      final existingCounterIndex = currentCounters.indexWhere(
        (counter) => counter['reaction'] == emoji,
      );

      if (existingCounterIndex != -1) {
        currentCounters[existingCounterIndex]['count'] =
            (currentCounters[existingCounterIndex]['count'] as int) + 1;
      } else {
        currentCounters.add({'reaction': emoji, 'count': 1});
      }

      final updatedReactionInfo = {
        ...currentReactionInfo,
        'counters': currentCounters,
        'yourReaction': emoji,
        'totalCount': currentCounters.fold<int>(
          0,
          (sum, counter) => sum + (counter['count'] as int),
        ),
      };

      _messages[messageIndex] = message.copyWith(
        reactionInfo: updatedReactionInfo,
      );
      _sendingReactions.add(messageId);
      _buildChatItems();
      _setStateIfMounted(() {});
      // Scroll operations
      // Removed clashing _scrollToMessage and _getVisualIndex (moved to logic.dart)
    }
  }

  void _removeReactionOptimistically(String messageId) {
    final messageIndex = _messages.indexWhere((m) => m.id == messageId);
    if (messageIndex != -1) {
      final message = _messages[messageIndex];
      final currentReactionInfo = message.reactionInfo ?? {};
      final yourReaction = currentReactionInfo['yourReaction'] as String?;

      if (yourReaction != null) {
        final currentCounters = List<Map<String, dynamic>>.from(
          currentReactionInfo['counters'] ?? [],
        );
        final counterIndex = currentCounters.indexWhere(
          (counter) => counter['reaction'] == yourReaction,
        );

        if (counterIndex != -1) {
          final currentCount = currentCounters[counterIndex]['count'] as int;
          if (currentCount > 1) {
            currentCounters[counterIndex]['count'] = currentCount - 1;
          } else {
            currentCounters.removeAt(counterIndex);
          }
        }

        final updatedReactionInfo = {
          ...currentReactionInfo,
          'counters': currentCounters,
          'yourReaction': null,
          'totalCount': currentCounters.fold<int>(
            0,
            (sum, counter) => sum + (counter['count'] as int),
          ),
        };

        _messages[messageIndex] = message.copyWith(
          reactionInfo: updatedReactionInfo,
        );
        _sendingReactions.add(messageId);
        _buildChatItems();
        _setStateIfMounted(() {});
      }
    }
  }

  void _sendReaction(String messageId, String emoji) {
    _updateReactionOptimistically(messageId, emoji);
    ApiService.instance
        .sendReaction(widget.chatId, messageId, emoji)
        .catchError((e) {
          print('[_sendReaction] Ошибка отправки реакции: $e');
          // Откат оптимистичного обновления при ошибке
          _removeReactionOptimistically(messageId);
          return -1;
        });
  }

  void _removeReaction(String messageId) {
    final messageIndex = _messages.indexWhere((m) => m.id == messageId);
    if (messageIndex == -1) return;

    final message = _messages[messageIndex];
    final currentReaction = message.reactionInfo?['yourReaction'] as String?;
    if (currentReaction == null) return;

    _removeReactionOptimistically(messageId);
    ApiService.instance.removeReaction(widget.chatId, messageId).catchError((
      e,
    ) {
      print('[_removeReaction] Ошибка удаления реакции: $e');
      // Восстановление реакции при ошибке
      _updateReactionOptimistically(messageId, currentReaction);
      return -1;
    });
  }

  // Data Helpers
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

  Map<String, Message> _buildKnownMessagesMap() {
    final map = <String, Message>{};
    for (final msg in _messages) {
      map[msg.id] = msg;
      final cidKey = msg.cid?.toString();
      if (cidKey != null) map[cidKey] = msg;
    }
    return map;
  }

  Message _hydrateLinkFromKnown(
    Message message,
    Map<String, Message> knownMessages,
  ) {
    final link = message.link;
    if (link == null || link['message'] != null) return message;

    final dynamic linkMessageId = link['messageId'];
    if (linkMessageId == null) return message;

    final messageKey = linkMessageId.toString();
    final referenced = knownMessages[messageKey];
    if (referenced == null) return message;

    final updatedLink = Map<String, dynamic>.from(link);
    updatedLink['message'] = _mapMessageForLink(referenced);
    return message.copyWith(link: updatedLink);
  }

  List<Message> _hydrateLinksSequentially(
    List<Message> messages, {
    Map<String, Message>? initialKnown,
  }) {
    final known = initialKnown != null
        ? Map<String, Message>.from(initialKnown)
        : <String, Message>{};
    final result = <Message>[];

    for (final message in messages) {
      final hydrated = _hydrateLinkFromKnown(message, known);
      result.add(hydrated);
      known[hydrated.id] = hydrated;
      final cidKey = hydrated.cid?.toString();
      if (cidKey != null) known[cidKey] = hydrated;
    }
    return result;
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  bool _isMessageGrouped(Message currentMessage, Message? previousMessage) {
    if (previousMessage == null) return false;
    final currentTime = DateTime.fromMillisecondsSinceEpoch(
      currentMessage.time,
    );
    final previousTime = DateTime.fromMillisecondsSinceEpoch(
      previousMessage.time,
    );
    final timeDifference = currentTime.difference(previousTime).inMinutes;
    return currentMessage.senderId == previousMessage.senderId &&
        timeDifference <= 5;
  }

  int? _parseMessageId(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return int.tryParse(value.toString());
  }

  int? _parseChatId(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return int.tryParse(value.toString());
  }

  // Mention & Command Logic
  Future<void> _loadMentionableUsers() async {
    if (!widget.isGroupChat && !widget.isChannel) {
      _mentionableUsers = [_currentContact];
      return;
    }

    List<int> participantIds = [];
    final chatData = ApiService.instance.lastChatsPayload;
    if (chatData != null) {
      final chats = chatData['chats'] as List<dynamic>?;
      final currentChat = chats?.firstWhere(
        (chat) => chat['id'] == widget.chatId,
        orElse: () => null,
      );

      if (currentChat != null) {
        final dynamic participantsData = currentChat['participants'];
        if (participantsData is Map<String, dynamic>) {
          participantIds = participantsData.keys
              .map((id) => int.tryParse(id))
              .where((id) => id != null && id != (_actualMyId ?? widget.myId))
              .cast<int>()
              .toList();
        } else if (participantsData is List<dynamic>) {
          participantIds = participantsData
              .map((p) => p is int ? p : int.tryParse(p.toString()))
              .where((id) => id != null && id != (_actualMyId ?? widget.myId))
              .cast<int>()
              .toList();
        }
      }
    }

    if (participantIds.isEmpty && _contactDetailsCache.isNotEmpty) {
      participantIds = _contactDetailsCache.keys
          .where((id) => id != (_actualMyId ?? widget.myId))
          .toList();
    }

    if (participantIds.isEmpty) {
      _setStateIfMounted(() => _mentionableUsers = []);
      return;
    }

    final idsToFetch = participantIds
        .where((id) => !_contactDetailsCache.containsKey(id))
        .toList();
    if (idsToFetch.isNotEmpty) {
      try {
        final contacts = await ApiService.instance.fetchContactsByIds(
          idsToFetch,
        );
        for (final contact in contacts) {
          _contactDetailsCache[contact.id] = contact;
        }
      } catch (e) {
        print('Ошибка загрузки контактов для пингов: $e');
      }
    }

    _setStateIfMounted(() {
      _mentionableUsers = participantIds
          .where((id) => _contactDetailsCache.containsKey(id))
          .map((id) => _contactDetailsCache[id]!)
          .where((contact) => contact.id != 0)
          .toList();
    });
  }

  // ignore: unused_element
  void _handleMentionFiltering(String text) {
    final cursorPosition = _textController.selection.baseOffset;
    if (cursorPosition > 0) {
      int atPosition = -1;
      for (int i = cursorPosition - 1; i >= 0; i--) {
        if (text[i] == '@') {
          atPosition = i;
          break;
        } else if (text[i] == ' ' || text[i] == '\n')
          break;
      }

      if (atPosition != -1) {
        _mentionQuery = text
            .substring(atPosition + 1, cursorPosition)
            .toLowerCase();
        _mentionStartPosition = atPosition;

        _filteredMentionableUsers = _mentionableUsers.where((user) {
          final username = user.name.toLowerCase();
          final displayName = getContactDisplayName(
            contactId: user.id,
            originalName: user.name,
            originalFirstName: user.firstName,
            originalLastName: user.lastName,
          ).toLowerCase();
          return username.startsWith(_mentionQuery) ||
              displayName.startsWith(_mentionQuery);
        }).toList();

        _filteredMentionableUsers.sort((a, b) {
          final aName = a.name.toLowerCase();
          final bName = b.name.toLowerCase();
          final aDisplay = getContactDisplayName(
            contactId: a.id,
            originalName: a.name,
            originalFirstName: a.firstName,
            originalLastName: a.lastName,
          ).toLowerCase();
          final bDisplay = getContactDisplayName(
            contactId: b.id,
            originalName: b.name,
            originalFirstName: b.firstName,
            originalLastName: b.lastName,
          ).toLowerCase();

          final aStartsWith =
              aName.startsWith(_mentionQuery) ||
              aDisplay.startsWith(_mentionQuery);
          final bStartsWith =
              bName.startsWith(_mentionQuery) ||
              bDisplay.startsWith(_mentionQuery);

          if (aStartsWith && !bStartsWith) return -1;
          if (!aStartsWith && bStartsWith) return 1;
          return aDisplay.compareTo(bDisplay);
        });

        if (!_showMentionDropdown) {
          _setStateIfMounted(() {
            _showMentionDropdown = true;
          });
        } else {
          _setStateIfMounted(() {});
        }
      } else {
        if (_showMentionDropdown) {
          _setStateIfMounted(() => _showMentionDropdown = false);
        }
      }
    } else {
      if (_showMentionDropdown) {
        _setStateIfMounted(() => _showMentionDropdown = false);
      }
    }
  }

  void _insertMention(Contact user) {
    if (_mentionStartPosition == null) return;
    if (user.id == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка: не удалось получить ID пользователя'),
        ),
      );
      return;
    }

    final currentText = _textController.text;
    final cursorPosition = _textController.selection.baseOffset;
    final beforeAt = currentText.substring(0, _mentionStartPosition!);
    final afterCursor = currentText.substring(cursorPosition);
    final mentionText = user.name;
    final newText = beforeAt + mentionText + afterCursor;

    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: _mentionStartPosition! + mentionText.length,
      ),
    );

    _mentions.add(
      Mention(
        from: _mentionStartPosition!,
        length: mentionText.length,
        entityId: user.id,
        entityName: user.name,
      ),
    );

    _setStateIfMounted(() {
      _showMentionDropdown = false;
      _mentionQuery = '';
      _mentionStartPosition = null;
    });

    _textFocusNode.requestFocus();
  }

  void _handleChatInputChanged(String text) {
    _resetDraftFormattingIfNeeded(text);
    if (text.isNotEmpty) _scheduleTypingPing();

    final shouldShowPanel = _currentContact.isBot && text.startsWith('/');
    if (shouldShowPanel != _showBotCommandsPanel) {
      _setStateIfMounted(() => _showBotCommandsPanel = shouldShowPanel);
    } else if (shouldShowPanel) {
      _setStateIfMounted(() {});
    }

    if (shouldShowPanel) _ensureBotCommandsLoaded();
  }

  Future<void> _ensureBotCommandsLoaded() async {
    if (!_currentContact.isBot) return;
    final botId = _currentContact.id;
    if (_botCommandsForBotId == botId && _botCommands.isNotEmpty) return;
    if (_isLoadingBotCommands) return;

    _setStateIfMounted(() => _isLoadingBotCommands = true);
    try {
      final seq = await ApiService.instance.sendRawRequest(145, {
        'botId': botId,
      });
      if (seq == -1) throw Exception('Не удалось отправить запрос команд бота');

      final resp = await ApiService.instance.messages
          .firstWhere((m) => m['seq'] == seq && m['opcode'] == 145)
          .timeout(const Duration(seconds: 10));

      final payload = resp['payload'] as Map<String, dynamic>?;
      final commandsJson = (payload?['commands'] as List<dynamic>?) ?? const [];

      final commands = commandsJson
          .whereType<Map>()
          .map((e) => BotCommand.fromJson(Map<String, dynamic>.from(e)))
          .where((c) => c.name.isNotEmpty)
          .toList(growable: false);

      if (!mounted) return;
      _setStateIfMounted(() {
        _botCommandsForBotId = botId;
        _botCommands = commands;
      });
    } catch (e) {
      if (!mounted || _currentContact.id != botId) return;
      _setStateIfMounted(() {
        _botCommandsForBotId = botId;
        _botCommands = const [];
      });
    } finally {
      if (mounted && _currentContact.id == botId) {
        _setStateIfMounted(() => _isLoadingBotCommands = false);
      } else {
        _isLoadingBotCommands = false;
      }
    }
  }

  void _applyBotCommandToInput(BotCommand command) {
    final text = command.slashCommand;
    _textController.text = text;
    _textController.selection = TextSelection.collapsed(offset: text.length);
    _setStateIfMounted(() => _showBotCommandsPanel = false);
    _textFocusNode.requestFocus();
  }

  // Settings & Cache
  Future<void> _loadInputState() async {
    try {
      final state = await ChatCacheService().getChatInputState(widget.chatId);
      if (state != null && mounted) {
        final text = state['text'] as String? ?? '';
        final elements =
            (state['elements'] as List<dynamic>?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            [];
        final replyingToMessageData =
            state['replyingToMessage'] as Map<String, dynamic>?;

        _textController.text = text;
        _mentions.clear();
        _textController.elements.addAll(elements);
        if (replyingToMessageData != null) {
          try {
            final message = Message.fromJson(replyingToMessageData);
            _setStateIfMounted(() => _replyingToMessage = message);
          } catch (e) {
            print('Ошибка восстановления сообщения для ответа: $e');
          }
        }
      }
    } catch (e) {
      print('Ошибка загрузки состояния ввода: $e');
    }
  }

  Future<void> _saveInputState() async {
    try {
      final text = _textController.text;
      final elements = _textController.elements;

      Map<String, dynamic>? replyingToMessageData;
      if (_replyingToMessage != null) {
        replyingToMessageData = {
          'id': _replyingToMessage!.id,
          'sender': _replyingToMessage!.senderId,
          'text': _replyingToMessage!.text,
          'time': _replyingToMessage!.time,
          'type': 'USER',
          'cid': _replyingToMessage!.cid,
          'attaches': _replyingToMessage!.attaches,
        };
      }

      final draftData = text.trim().isNotEmpty
          ? {
              'text': text,
              'elements': elements,
              'replyingToMessage': replyingToMessageData,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            }
          : null;

      await ChatCacheService().saveChatInputState(
        widget.chatId,
        text: text,
        elements: elements,
        replyingToMessage: replyingToMessageData,
      );

      widget.onDraftChanged?.call(widget.chatId, draftData);
    } catch (e) {
      print('Ошибка сохранения состояния ввода: $e');
    }
  }

  void _toggleKometSpecialMenu() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    if (!themeProvider.specialMessagesEnabled) return;

    if (_sparkleMenuOverlay != null) {
      _sparkleMenuOverlay!.remove();
      _sparkleMenuOverlay = null;
      _setStateIfMounted(() {});
      return;
    }

    final RenderBox? buttonBox =
        _sparkleButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (buttonBox == null) return;

    _sparkleMenuOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleKometSpecialMenu,
              child: Container(color: Colors.transparent),
            ),
          ),
          CompositedTransformFollower(
            link: _sparkleLayerLink,
            showWhenUnlinked: false,
            followerAnchor: Alignment.bottomCenter,
            targetAnchor: Alignment.topCenter,
            offset: const Offset(0, -12),
            child: Material(
              color: Colors.transparent,
              child: IntrinsicWidth(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: _KometSpecialMenu(
                    onItemSelected: (value) {
                      _toggleKometSpecialMenu();
                      if (value.contains('#')) {
                        _insertKometPrefix(value);
                        _openColorPickerDialog(value);
                      } else {
                        _insertKometPrefix(value);
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sparkleMenuOverlay != null && mounted) {
        final renderObject = _sparkleButtonKey.currentContext
            ?.findRenderObject();
        if (renderObject != null) {
          Overlay.of(context).insert(_sparkleMenuOverlay!);
          _setStateIfMounted(() {});
        } else {
          _sparkleMenuOverlay = null;
        }
      }
    });
  }

  void _insertKometPrefix(String prefix) {
    final text = _textController.text;
    final selection = _textController.selection;
    final start = selection.start == -1 ? text.length : selection.start;
    final end = selection.end == -1 ? text.length : selection.end;

    // Insert only up to # if present
    final String actualPrefix = prefix.contains('#')
        ? prefix.substring(0, prefix.indexOf('#') + 1)
        : prefix;

    final newText =
        text.substring(0, start) + actualPrefix + text.substring(end);
    _textController.text = newText;
    _textController.selection = TextSelection.collapsed(
      offset: start + actualPrefix.length,
    );
    _textFocusNode.requestFocus();
  }

  void _openColorPickerDialog(String prefix) {
    Color pickedColor = Colors.white;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Выберите цвет"),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickedColor,
            onColorChanged: (color) => pickedColor = color,
            enableAlpha: false,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Отмена"),
          ),
          FilledButton(
            onPressed: () {
              final hex = pickedColor.value
                  .toRadixString(16)
                  .substring(2)
                  .toUpperCase();
              final text = _textController.text;
              final pos = _textController.selection.baseOffset;

              // Insert hex and "'' "
              final toInsert = "$hex'' ";
              final newText =
                  text.substring(0, pos) + toInsert + text.substring(pos);
              _textController.text = newText;
              _textController.selection = TextSelection.collapsed(
                offset: pos + toInsert.length,
              );

              _setStateIfMounted(() {});

              Navigator.pop(context);
              _textFocusNode.requestFocus();
            },
            child: const Text("Готово"),
          ),
        ],
      ),
    );
  }

  Future<void> _loadEncryptionConfig() async {
    try {
      final config = await ChatEncryptionService.getConfigForChat(
        widget.chatId,
      );
      if (mounted) {
        _setStateIfMounted(() {
          _encryptionConfigForCurrentChat = config;
          _isEncryptionPasswordSetForCurrentChat =
              config != null && config.password.isNotEmpty;
          _sendEncryptedForCurrentChat = config?.sendEncrypted ?? true;
        });
      }
    } catch (e) {
      print('Ошибка загрузки конфигурации шифрования: $e');
    }
  }

  Future<void> _loadCachedContacts() async {
    final chatContacts = await ChatCacheService().getCachedChatContacts(
      widget.chatId,
    );
    if (chatContacts != null && chatContacts.isNotEmpty) {
      for (final contact in chatContacts) {
        _contactDetailsCache[contact.id] = contact;
      }
      return;
    }

    final cachedContacts = await ChatCacheService().getCachedContacts();
    if (cachedContacts != null && cachedContacts.isNotEmpty) {
      for (final contact in cachedContacts) {
        _contactDetailsCache[contact.id] = contact;
        if (contact.id == widget.myId && _actualMyId == null) {
          final prefs = await SharedPreferences.getInstance();
          _actualMyId = int.parse(prefs.getString('userId')!);
        }
      }
    }
  }

  void _loadContactDetails() {
    final chatData = ApiService.instance.lastChatsPayload;
    if (chatData != null && chatData['contacts'] != null) {
      final contactsJson = chatData['contacts'] as List<dynamic>;
      for (var contactJson in contactsJson) {
        final contact = Contact.fromJson(contactJson);
        _contactDetailsCache[contact.id] = contact;
      }
    }
  }

  Future<void> _loadGroupParticipants() async {
    try {
      final chatData = ApiService.instance.lastChatsPayload;
      if (chatData == null) return;

      final chats = chatData['chats'] as List<dynamic>?;
      if (chats == null) return;

      final currentChat = chats.firstWhere(
        (chat) => chat['id'] == widget.chatId,
        orElse: () => null,
      );
      if (currentChat == null) return;

      final participants = currentChat['participants'] as Map<String, dynamic>?;
      if (participants == null || participants.isEmpty) return;

      final participantIds = participants.keys
          .map((id) => int.tryParse(id))
          .where((id) => id != null)
          .cast<int>()
          .toList();
      if (participantIds.isEmpty) return;

      final idsToFetch = participantIds
          .where((id) => !_contactDetailsCache.containsKey(id))
          .toList();
      if (idsToFetch.isEmpty) return;

      final contacts = await ApiService.instance.fetchContactsByIds(idsToFetch);
      if (contacts.isNotEmpty && mounted) {
        _setStateIfMounted(() {
          for (final contact in contacts) {
            _contactDetailsCache[contact.id] = contact;
          }
        });
        await ChatCacheService().cacheChatContacts(widget.chatId, contacts);
      }
    } catch (e) {
      print('ERROR loadGroupParticipants: $e');
    }
  }

  void _checkContactCache() {
    if (widget.chatId == 0) return;
    final cachedContact = ApiService.instance.getCachedContact(
      widget.contact.id,
    );
    if (cachedContact != null) {
      _currentContact = cachedContact;
      _setStateIfMounted(() {});
    }
  }

  void _invalidateCache() {
    _cachedCurrentGroupChat = null;
  }

  Map<String, dynamic>? _getCurrentGroupChat() {
    if (_cachedCurrentGroupChat != null) return _cachedCurrentGroupChat;
    final chatData = ApiService.instance.lastChatsPayload;
    if (chatData == null || chatData['chats'] == null) return null;

    final chats = chatData['chats'] as List<dynamic>;
    try {
      _cachedCurrentGroupChat = chats.firstWhere(
        (chat) => chat['id'] == widget.chatId,
        orElse: () => null,
      );
      return _cachedCurrentGroupChat;
    } catch (e) {
      return null;
    }
  }

  // Stickers & Media
  Future<void> _sendEmptyChatSticker() async {
    if (_emptyChatSticker == null) return;
    final stickerId = _emptyChatSticker!['stickerId'] as int?;
    if (stickerId == null) return;

    try {
      final cid = DateTime.now().millisecondsSinceEpoch;
      final payload = {
        "chatId": widget.chatId,
        "message": {
          "cid": cid,
          "attaches": [
            {"_type": "STICKER", "stickerId": stickerId},
          ],
        },
        "notify": true,
      };
      unawaited(ApiService.instance.sendRawRequest(64, payload));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при отправке стикера: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadEmptyChatSticker() async {
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 2);

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final availableStickerIds = [272821, 295349, 13571];
        final random =
            DateTime.now().millisecondsSinceEpoch % availableStickerIds.length;
        final selectedStickerId = availableStickerIds[random];
        final seq = await ApiService.instance.sendRawRequest(28, {
          "type": "STICKER",
          "ids": [selectedStickerId],
        });

        if (seq == -1) {
          // Если запрос не удался, попробуем еще раз
          if (attempt < maxRetries - 1) {
            await Future.delayed(retryDelay);
            continue;
          }
          return;
        }

        final response = await ApiService.instance.messages
            .firstWhere((msg) => msg['seq'] == seq && msg['opcode'] == 28)
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () => throw TimeoutException('Timeout'),
            );

        if (response.isEmpty || response['payload'] == null) {
          if (attempt < maxRetries - 1) {
            await Future.delayed(retryDelay);
            continue;
          }
          return;
        }

        final stickers = response['payload']['stickers'] as List?;
        if (stickers != null && stickers.isNotEmpty) {
          final sticker = stickers.first as Map<String, dynamic>;
          final stickerId = sticker['id'] as int?;
          if (mounted) {
            _setStateIfMounted(() {
              _emptyChatSticker = {...sticker, 'stickerId': stickerId};
            });
          }
          return; // Успешно загрузили
        } else {
          // Стикеры не найдены, попробуем другой ID
          if (attempt < maxRetries - 1) {
            await Future.delayed(retryDelay);
            continue;
          }
        }
      } catch (e) {
        print(
          '[ChatScreen] Ошибка при загрузке стикера для пустого чата (попытка ${attempt + 1}/$maxRetries): $e',
        );
        if (attempt < maxRetries - 1) {
          await Future.delayed(retryDelay);
        }
      }
    }

    // После всех неудачных попыток оставляем _emptyChatSticker как null
    // EmptyChatWidget покажет fallback иконку вместо индикатора загрузки
    print('[ChatScreen] Не удалось загрузить стикер после $maxRetries попыток');
  }

  void _updatePinnedMessage() {
    Message? latestPinned;
    for (int i = _messages.length - 1; i >= 0; i--) {
      final message = _messages[i];
      final controlAttach = message.attaches.firstWhere(
        (a) => a['_type'] == 'CONTROL',
        orElse: () => const {},
      );
      if (controlAttach.isNotEmpty && controlAttach['event'] == 'pin') {
        final pinnedMessageData = controlAttach['pinnedMessage'];
        if (pinnedMessageData != null &&
            pinnedMessageData is Map<String, dynamic>) {
          try {
            latestPinned = Message.fromJson(pinnedMessageData);
            break;
          } catch (e) {
            print('[ChatScreen] Ошибка парсинга закрепленного сообщения: $e');
          }
        }
      }
    }
    if (mounted) {
      _pinnedMessage = latestPinned;
      _pinnedMessageNotifier.value = latestPinned;
    }
  }

  // Chat Items Building
  void _buildChatItems() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _buildChatItems();
      });
      return;
    }

    final List<ChatItem> items = [];
    final source = _messages;

    for (int i = 0; i < source.length; i++) {
      final currentMessage = source[i];
      final previousMessage = (i > 0) ? source[i - 1] : null;

      final currentDate = DateTime.fromMillisecondsSinceEpoch(
        currentMessage.time,
      ).toLocal();
      final previousDate = previousMessage != null
          ? DateTime.fromMillisecondsSinceEpoch(previousMessage.time).toLocal()
          : null;

      if (previousMessage == null || !_isSameDay(currentDate, previousDate!)) {
        items.add(DateSeparatorItem(currentDate));
      }

      final isGrouped = _isMessageGrouped(currentMessage, previousMessage);
      final isFirstInGroup =
          previousMessage == null ||
          !_isMessageGrouped(currentMessage, previousMessage);
      final isLastInGroup =
          i == source.length - 1 ||
          !_isMessageGrouped(source[i + 1], currentMessage);

      items.add(
        MessageItem(
          currentMessage,
          isFirstInGroup: isFirstInGroup,
          isLastInGroup: isLastInGroup,
          isGrouped: isGrouped,
        ),
      );
    }
    _chatItems = items;

    if (_isVoiceUploading || _isVoiceUploadFailed) {
      _chatItems.add(
        VoicePreviewItem(
          isUploading: _isVoiceUploading,
          progress: _voiceUploadProgress,
          isFailed: _isVoiceUploadFailed,
          onRetry: _isVoiceUploadFailed && _cachedVoicePath != null
              ? () => _retrySendVoiceMessage()
              : null,
        ),
      );
    }
  }

  // Input Helpers
  void _resetDraftFormattingIfNeeded(String newText) {
    if (newText.isEmpty) {
      _textController.elements.clear();
      _mentions.clear();
    }
  }

  void _scheduleTypingPing() {
    final now = DateTime.now();
    if (now.difference(_lastTypingSentAt) >= const Duration(seconds: 9)) {
      ApiService.instance.sendTyping(widget.chatId, type: "TEXT");
      _lastTypingSentAt = now;
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 9), () {
      if (!mounted) return;
      if (_textController.text.isNotEmpty) {
        ApiService.instance.sendTyping(widget.chatId, type: "TEXT");
        _lastTypingSentAt = DateTime.now();
        _scheduleTypingPing();
      }
    });
  }

  void _replyToMessage(Message message) {
    _setStateIfMounted(() => _replyingToMessage = message);
    _saveInputState();
  }

  // Get sender name from message
  String _getSenderName(Message message) {
    final senderId = message.senderId;

    if (_contactDetailsCache.containsKey(senderId)) {
      return _contactDetailsCache[senderId]!.name;
    }

    if (senderId == widget.myId || senderId == _actualMyId) {
      return 'Вы';
    }

    return 'Пользователь';
  }

  void _setStateIfMounted(VoidCallback fn) {
    if (mounted) {
      // ignore: invalid_use_of_protected_member
      setState(fn);
    }
  }
}

Future<void> openUserProfileById(BuildContext context, int userId) async {
  var contact = ApiService.instance.getCachedContact(userId);

  if (contact == null) {
    try {
      final contacts = await ApiService.instance.fetchContactsByIds([userId]);
      if (contacts.isNotEmpty) contact = contacts.first;
    } catch (e) {
      print('[openUserProfileById] Ошибка загрузки контакта $userId: $e');
    }
  }

  if (contact != null) {
    final contactData = contact;
    final isGroup = contactData.id < 0;

    if (isGroup) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => GroupProfileDraggableDialog(contact: contactData),
      );
    } else {
      Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.transparent,
          pageBuilder: (context, animation, secondaryAnimation) {
            return ContactProfileDialog(
              contact: contactData,
              myId: int.tryParse(ApiService.instance.userId ?? ''),
            );
          },
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOutCubic,
              ),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 350),
        ),
      );
    }
  } else {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ошибка'),
        content: Text('Не удалось загрузить информацию о пользователе $userId'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
