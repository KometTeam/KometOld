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
        _showErrorSnackBar('Нельзя отправить сообщение заблокированному пользователю');
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

      final tempMessage = _createTempMessage(text: textToSend, cid: tempCid, elements: elements);
      _addMessage(tempMessage);
      _clearInputState();
      _sendToServer(text: textToSend, cid: tempCid, elements: elements);
      _handleReadReceipts();
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
      return ChatEncryptionService.encryptWithPassword(_encryptionConfigForCurrentChat!.password, original);
    }
    return original;
  }

  List<Map<String, dynamic>> _captureMentions() {
    return _mentions.map((m) {
      return {
        'entityId': m.entityId,
        'type': m.type,
        'length': m.length,
      };
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
    final replyId = int.tryParse(_replyingToMessage!.id) ?? _replyingToMessage!.id;
    return {
      'type': 'REPLY',
      'messageId': replyId,
      'chatId': 0,
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
    setState(() {
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
  }) {
    ApiService.instance.sendMessage(
      widget.chatId,
      text,
      replyToMessageId: _replyingToMessage?.id,
      replyToMessage: _replyingToMessage,
      cid: cid,
      elements: elements,
    );
  }

  void _handleReadReceipts() {
    ChatReadSettingsService.instance.getSettings(widget.chatId).then((readSettings) {
      final shouldReadOnAction = readSettings != null
          ? (!readSettings.disabled && readSettings.readOnAction)
          : context.read<ThemeProvider>().debugReadOnAction;

      if (shouldReadOnAction && _messages.isNotEmpty) {
        ApiService.instance.markMessageAsRead(widget.chatId, _messages.last.id);
      }
    });
  }

  void _cancelPendingMessage(Message message) {
    final cid = message.cid ?? int.tryParse(message.id.replaceFirst('local_', ''));
    if (cid != null) {
      MessageQueueService().removeFromQueue('msg_$cid');
    }
    _removeMessages([message.id]);
    ApiService.instance.updateChatLastMessage(widget.chatId).then((newLastMessage) {
      widget.onLastMessageChanged?.call(newLastMessage);
    });
  }

  Future<void> _retryPendingMessage(Message message) async {
    final cid = message.cid ?? int.tryParse(message.id.replaceFirst('local_', ''));
    if (cid == null) return;

    MessageQueueService().removeFromQueue('msg_$cid');

    String? replyToId;
    Message? replyToMessage;
    final link = message.link;
    if (link is Map<String, dynamic> && link['type'] == 'REPLY') {
      final dynamic replyId = link['messageId'] ?? link['message']?['id'];
      if (replyId != null) replyToId = replyId.toString();
      final replyMessageMap = link['message'];
      if (replyMessageMap is Map<String, dynamic>) {
        replyToMessage = Message.fromJson(
          replyMessageMap.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    }

    ApiService.instance.sendMessage(
      widget.chatId,
      message.text,
      replyToMessageId: replyToId,
      replyToMessage: replyToMessage,
      cid: cid,
      elements: message.elements,
    );
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
              await ApiService.instance.editMessage(widget.chatId, message.id, newText.trim());
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
      final result = await ApiService.instance.getChatsAndContacts(force: false);
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

      if (contactProfile != null && contactProfile['id'] != null && contactProfile['id'] != 0) {
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
          print('[ChatScreen] Не удалось добавить собственный профиль в кэш: $e');
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
        await ChatCacheService().cacheChatContacts(widget.chatId, contactsToCache);
      }

      if (mounted) {
        setState(() {
          _isIdReady = true;
        });
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
              setState(() {});
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
              (payload['chat'] != null && payload['chat']['participants'] != null)) {
            _loadMentionableUsers().then((_) {
              if (mounted) setState(() {});
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
              setState(() {
                _currentContact = contact;
              });
            }
          });
        }
      });

      _itemPositionsListener.itemPositions.addListener(() {
        final positions = _itemPositionsListener.itemPositions.value;
        if (positions.isNotEmpty) {
          final bottomItemPosition = positions.firstWhere((p) => p.index == 0, orElse: () => positions.first);
          final isAtBottom = bottomItemPosition.index == 0 && bottomItemPosition.itemLeadingEdge <= 0.25;
          _isUserAtBottom = isAtBottom;
          if (isAtBottom) _isScrollingToBottom = false;
          _showScrollToBottomNotifier.value = !isAtBottom && !_isScrollingToBottom;

          if (positions.isNotEmpty && _chatItems.isNotEmpty) {
            final maxIndex = positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);
            if (maxIndex > _maxViewedIndex) _maxViewedIndex = maxIndex;

            final shouldLoadByViewedCount = maxIndex >= _ChatScreenState._loadMoreThreshold &&
                (maxIndex - _lastLoadedAtViewedIndex) >= _ChatScreenState._loadMoreThreshold;
            final threshold = _chatItems.length > 5 ? 3 : 1;
            final isNearTop = maxIndex >= _chatItems.length - threshold;

            if ((isNearTop || shouldLoadByViewedCount) && _hasMore && !_isLoadingMore && _messages.isNotEmpty && _oldestLoadedTime != null) {
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
              setState(() {
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
        setState(() {
          _isLoadingHistory = false;
        });
      }
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
      final opcode = message['opcode'];
      final cmd = message['cmd'];
      final seq = message['seq'];
      final payload = message['payload'];
      if (payload is! Map<String, dynamic>) return;

      final dynamic incomingChatId = payload['chatId'] ?? payload['chat']?['id'];
      final int? chatIdNormalized = incomingChatId is int ? incomingChatId : int.tryParse(incomingChatId?.toString() ?? '');
      final shouldCheckChatId = opcode != 178 || (opcode == 178 && payload.containsKey('chatId'));

      if (shouldCheckChatId && (chatIdNormalized == null || chatIdNormalized != widget.chatId)) return;

      if (opcode == 64 && (cmd == 0x100 || cmd == 256)) {
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
        Future.microtask(() {
          if (mounted) _updateMessage(newMessage);
        });
      } else if (opcode == 128) {
        final messageMap = payload['message'];
        if (messageMap is! Map<String, dynamic>) return;
        final newMessage = Message.fromJson(messageMap);
        if (newMessage.status == 'REMOVED') {
          _removeMessages([newMessage.id]);
        } else {
          unawaited(ChatCacheService().addMessageToCache(widget.chatId, newMessage));
          Future.microtask(() {
            if (!mounted) return;
            final hasSameId = _messages.any((m) => m.id == newMessage.id);
            final hasSameCid = newMessage.cid != null && _messages.any((m) => m.cid != null && m.cid == newMessage.cid);
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
          final int? cid = contactIdAny is int ? contactIdAny : int.tryParse(contactIdAny.toString());
          if (cid != null) {
            final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            final isOnline = payload['online'] == true;
            ApiService.instance.updatePresenceData({
              cid.toString(): {'seen': currentTime, 'on': isOnline ? 'ON' : 'OFF'},
            });
          }
        }
      } else if (opcode == 67) {
        final messageMap = payload['message'];
        if (messageMap is! Map<String, dynamic>) return;
        final editedMessage = Message.fromJson(messageMap);
        Future.microtask(() {
          if (mounted) _updateMessage(editedMessage);
        });
      } else if (opcode == 66 || opcode == 142) {
        final rawMessageIds = payload['messageIds'] as List<dynamic>? ?? [];
        final deletedMessageIds = rawMessageIds.map((id) => id.toString()).toList();
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
              if (mounted) setState(() {});
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

          final readerId = payload['userId'] ?? payload['contactId'] ?? payload['uid'] ?? payload['sender'];
          final int? readerIdInt = _parseMessageId(readerId);
          if (readerIdInt != null && _actualMyId != null && readerIdInt == _actualMyId) return;

          final dynamic rawMessageId = payload['messageId'] ?? payload['id'];
          final int? messageId = _parseMessageId(rawMessageId);
          final String? messageIdStr = rawMessageId?.toString();

          if (messageId != null) {
            if (_lastPeerReadMessageId == null || messageId > _lastPeerReadMessageId!) {
              setState(() {
                _lastPeerReadMessageId = messageId;
                _lastPeerReadMessageIdStr = messageIdStr;
              });
            }
          } else if (messageIdStr != null && messageIdStr.isNotEmpty) {
            if (_lastPeerReadMessageIdStr == null || messageIdStr.compareTo(_lastPeerReadMessageIdStr!) >= 0) {
              setState(() {
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
    setState(() => _isLoadingHistory = true);
    _maxViewedIndex = 0;
    _lastLoadedAtViewedIndex = 0;

    final loadChatQueueItem = QueueItem(
      id: 'load_chat_${widget.chatId}',
      type: QueueItemType.loadChat,
      opcode: 49,
      payload: {
        "chatId": widget.chatId,
        "from": DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
        "forward": 0,
        "backward": _ChatScreenState._pageSize,
        "getMessages": true,
      },
      createdAt: DateTime.now(),
      persistent: false,
      chatId: widget.chatId,
    );
    MessageQueueService().addToQueue(loadChatQueueItem);

    final chatCacheService = ChatCacheService();
    List<Message>? cachedMessages = await chatCacheService.getCachedChatMessages(widget.chatId);
    bool hasCache = cachedMessages != null && cachedMessages.isNotEmpty;

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
        if (mounted) {
          setState(() {
            _isLoadingHistory = false;
          });
        }
      });
      _updatePinnedMessage();
      if (_messages.isEmpty && !widget.isChannel) _loadEmptyChatSticker();
    }

    List<Message> allMessages = [];
    try {
      allMessages = await ApiService.instance.getMessageHistory(widget.chatId, force: true).timeout(
        const Duration(seconds: 10),
        onTimeout: () => <Message>[],
      );
      if (allMessages.isNotEmpty) MessageQueueService().removeFromQueue('load_chat_${widget.chatId}');

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

        final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
        if (themeProvider.showDeletedMessages && hasCache) {
          for (final cachedMsg in _messages) {
            if (!serverMessageIds.contains(cachedMsg.id) && !cachedMsg.id.startsWith('local_')) {
              messagesMap[cachedMsg.id] = cachedMsg.copyWith(isDeleted: true);
            }
          }
        }

        if (themeProvider.viewRedactHistory && hasCache) {
          for (final cachedMsg in _messages) {
            final serverMsg = messagesMap[cachedMsg.id];
            if (serverMsg != null) {
              if (cachedMsg.originalText != null && serverMsg.originalText == null) {
                messagesMap[cachedMsg.id] = serverMsg.copyWith(originalText: cachedMsg.originalText);
              } else if (cachedMsg.text != serverMsg.text &&
                  cachedMsg.text.isNotEmpty &&
                  (serverMsg.isEdited || serverMsg.updateTime != null) &&
                  serverMsg.originalText == null) {
                messagesMap[cachedMsg.id] = serverMsg.copyWith(originalText: cachedMsg.text);
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

        mergedMessages = messagesMap.values.toList()..sort((a, b) => a.time.compareTo(b.time));
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

      final idsToFetch = senderIds.where((id) => !_contactDetailsCache.containsKey(id)).toList();
      if (idsToFetch.isNotEmpty) {
        final newContacts = await ApiService.instance.fetchContactsByIds(idsToFetch);
        for (final contact in newContacts) {
          _contactDetailsCache[contact.id] = contact;
        }
        if (newContacts.isNotEmpty) {
          await ChatCacheService().cacheChatContacts(widget.chatId, _contactDetailsCache.values.toList());
        }
      }

      if (mergedMessages.isNotEmpty) {
        await chatCacheService.cacheChatMessages(widget.chatId, mergedMessages);
      }

      if (widget.isGroupChat) await _loadGroupParticipants();

      final page = _anyOptimize ? _optPage : _ChatScreenState._pageSize;
      final slice = mergedMessages.length > page ? mergedMessages.sublist(mergedMessages.length - page) : mergedMessages;
      final bool hasAnyMessages = mergedMessages.isNotEmpty;
      final bool serverHasMore = allMessages.length >= 30;
      final bool nextHasMore = hasServerData
          ? serverHasMore || mergedMessages.length > slice.length
          : (_hasMore && hasAnyMessages);

      _buildChatItems();

      Future.microtask(() {
        if (!mounted) return;
        setState(() {
          _messages
            ..clear()
            ..addAll(slice);
          _oldestLoadedTime = _messages.isNotEmpty ? _messages.first.time : null;
          _hasMore = nextHasMore;
          _isLoadingHistory = false;
        });
        _messagesToAnimate.clear();
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
        setState(() {
          _isLoadingHistory = false;
        });
      }
    }

    final readSettings = await ChatReadSettingsService.instance.getSettings(widget.chatId);
    final theme = context.read<ThemeProvider>();
    final shouldReadOnEnter = readSettings != null
        ? (!readSettings.disabled && readSettings.readOnEnter)
        : theme.debugReadOnEnter;

    if (shouldReadOnEnter && _messages.isNotEmpty) {
      ApiService.instance.markMessageAsRead(widget.chatId, _messages.last.id);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    if (_messages.isEmpty || _oldestLoadedTime == null) {
      _hasMore = false;
      return;
    }

    _isLoadingMore = true;
    try {
      final olderMessages = await ApiService.instance.loadOlderMessagesByTimestamp(
        widget.chatId,
        _oldestLoadedTime!,
        backward: 30,
      );

      if (!mounted) return;
      if (olderMessages.isEmpty) {
        _hasMore = false;
        _isLoadingMore = false;
        setState(() {});
        return;
      }

      final existingMessageIds = _messages.map((m) => m.id).toSet();
      final newMessages = olderMessages.where((m) => !existingMessageIds.contains(m.id)).toList();
      if (newMessages.isEmpty) {
        _hasMore = false;
        _isLoadingMore = false;
        setState(() {});
        return;
      }

      final hydratedOlder = _hydrateLinksSequentially(newMessages, initialKnown: _buildKnownMessagesMap());
      final oldItemsCount = _chatItems.length;
      _messages.insertAll(0, hydratedOlder);
      _oldestLoadedTime = _messages.first.time;
      _hasMore = olderMessages.length >= 30;
      _buildChatItems();
      final addedItemsCount = _chatItems.length - oldItemsCount;
      _lastLoadedAtViewedIndex = _maxViewedIndex + addedItemsCount;
      _isLoadingMore = false;

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        });
      }
      _updatePinnedMessage();
    } catch (e) {
      print('[ChatScreen] Ошибка при загрузке старых сообщений: $e');
      if (mounted) {
        _isLoadingMore = false;
        _hasMore = false;
        setState(() {});
      }
    }
  }

  // Message Updates & Helpers
  void _addMessage(Message message, {bool forceScroll = false}) {
    final normalizedMessage = _hydrateLinkFromKnown(message, _buildKnownMessagesMap());
    if (_messages.any((m) => m.id == normalizedMessage.id)) return;

    final allMessages = [..._messages, normalizedMessage]..sort((a, b) => a.time.compareTo(b.time));
    unawaited(ChatCacheService().cacheChatMessages(widget.chatId, allMessages));

    final wasAtBottom = _isUserAtBottom;
    final isMyMessage = normalizedMessage.senderId == _actualMyId;
    final lastMessage = _messages.isNotEmpty ? _messages.last : null;
    _messages.add(normalizedMessage);
    _messagesToAnimate.add(normalizedMessage.id);

    final hasPhoto = normalizedMessage.attaches.any((a) => a['_type'] == 'PHOTO');
    if (hasPhoto) _updateCachedPhotos();

    final currentDate = DateTime.fromMillisecondsSinceEpoch(normalizedMessage.time).toLocal();
    final lastDate = lastMessage != null ? DateTime.fromMillisecondsSinceEpoch(lastMessage.time).toLocal() : null;

    if (lastMessage == null || !_isSameDay(currentDate, lastDate!)) {
      _chatItems.add(DateSeparatorItem(currentDate));
    }

    final lastMessageItem = _chatItems.isNotEmpty && _chatItems.last is MessageItem ? _chatItems.last as MessageItem : null;
    final isGrouped = _isMessageGrouped(normalizedMessage, lastMessageItem?.message);
    final isFirstInGroup = lastMessageItem == null || !isGrouped;
    final isLastInGroup = true;

    if (isGrouped && lastMessageItem != null) {
      _chatItems.removeLast();
      _chatItems.add(MessageItem(
        lastMessageItem.message,
        isFirstInGroup: lastMessageItem.isFirstInGroup,
        isLastInGroup: false,
        isGrouped: lastMessageItem.isGrouped,
      ));
    }

    _chatItems.add(MessageItem(normalizedMessage, isFirstInGroup: isFirstInGroup, isLastInGroup: isLastInGroup, isGrouped: isGrouped));
    _updatePinnedMessage();

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
          _invalidateCache();
          if ((wasAtBottom || isMyMessage || forceScroll) && _itemScrollController.isAttached) {
            _itemScrollController.jumpTo(index: 0);
          }
        }
      });
    }
  }

  void _updateMessage(Message updatedMessage) {
    int? index = _messages.indexWhere((m) => m.id == updatedMessage.id);
    if (index == -1 && updatedMessage.cid != null) {
      index = _messages.indexWhere((m) => m.cid != null && m.cid == updatedMessage.cid);
    }

    if (index != -1 && index < _messages.length) {
      final oldMessage = _messages[index];
      final hydratedUpdate = _hydrateLinkFromKnown(updatedMessage, _buildKnownMessagesMap());
      final finalMessage = hydratedUpdate.link != null ? hydratedUpdate : hydratedUpdate.copyWith(link: oldMessage.link);

      final finalMessageWithOriginalText = (() {
        if (finalMessage.originalText != null) return finalMessage;
        if (oldMessage.originalText != null) return finalMessage.copyWith(originalText: oldMessage.originalText);
        if ((finalMessage.isEdited || finalMessage.updateTime != null) && finalMessage.text != oldMessage.text) {
          return finalMessage.copyWith(originalText: oldMessage.text);
        }
        return finalMessage;
      })();

      final oldHasPhoto = oldMessage.attaches.any((a) => a['_type'] == 'PHOTO');
      final newHasPhoto = finalMessageWithOriginalText.attaches.any((a) => a['_type'] == 'PHOTO');

      _messages[index] = finalMessageWithOriginalText;
      unawaited(ChatCacheService().cacheChatMessages(widget.chatId, _messages));

      if (mounted) {
        setState(() {});
        _invalidateCache();
      }
      if (oldHasPhoto != newHasPhoto) _updateCachedPhotos();

      final chatItemIndex = _chatItems.indexWhere((item) =>
      item is MessageItem &&
          (item.message.id == oldMessage.id ||
              item.message.id == updatedMessage.id ||
              (updatedMessage.cid != null && item.message.cid != null && item.message.cid == updatedMessage.cid)));

      if (chatItemIndex != -1) {
        final oldItem = _chatItems[chatItemIndex] as MessageItem;
        _chatItems[chatItemIndex] = MessageItem(
          finalMessage,
          isFirstInGroup: oldItem.isFirstInGroup,
          isLastInGroup: oldItem.isLastInGroup,
          isGrouped: oldItem.isGrouped,
        );
        if (mounted) setState(() {});
      } else {
        _buildChatItems();
        if (mounted) setState(() {});
      }
    } else {
      ApiService.instance.getMessageHistory(widget.chatId, force: true).then((fresh) {
        if (!mounted) return;
        _messages
          ..clear()
          ..addAll(fresh);
        _buildChatItems();
        Future.microtask(() {
          if (mounted) setState(() {});
        });
      }).catchError((_) {});
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
            if (mounted) setState(() {});
          } else {
            _removeMessages([messageId]);
          }
        }
      }
    }
  }

  void _removeMessages(List<String> messageIds) {
    _deletingMessageIds.addAll(messageIds);
    if (mounted) setState(() {});

    Future.delayed(const Duration(milliseconds: 300), () {
      final removedCount = _messages.length;
      _messages.removeWhere((message) => messageIds.contains(message.id));
      final actuallyRemoved = removedCount - _messages.length;

      if (actuallyRemoved > 0) {
        _deletingMessageIds.removeAll(messageIds);
        for (final messageId in messageIds) {
          unawaited(ChatCacheService().removeMessageFromCache(widget.chatId, messageId));
        }
        _buildChatItems();
        if (mounted) setState(() {});
      }
    });
  }

  void _updateMessageReaction(String messageId, Map<String, dynamic> reactionInfo) {
    final messageIndex = _messages.indexWhere((m) => m.id == messageId);
    if (messageIndex != -1) {
      final message = _messages[messageIndex];
      final updatedMessage = message.copyWith(reactionInfo: reactionInfo);
      _messages[messageIndex] = updatedMessage;

      if (_sendingReactions.remove(messageId)) {}
      _buildChatItems();
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
    }
  }

  void _updateReactionOptimistically(String messageId, String emoji) {
    final messageIndex = _messages.indexWhere((m) => m.id == messageId);
    if (messageIndex != -1) {
      final message = _messages[messageIndex];
      final currentReactionInfo = message.reactionInfo ?? {};
      final currentCounters = List<Map<String, dynamic>>.from(currentReactionInfo['counters'] ?? []);
      final existingCounterIndex = currentCounters.indexWhere((counter) => counter['reaction'] == emoji);

      if (existingCounterIndex != -1) {
        currentCounters[existingCounterIndex]['count'] = (currentCounters[existingCounterIndex]['count'] as int) + 1;
      } else {
        currentCounters.add({'reaction': emoji, 'count': 1});
      }

      final updatedReactionInfo = {
        ...currentReactionInfo,
        'counters': currentCounters,
        'yourReaction': emoji,
        'totalCount': currentCounters.fold<int>(0, (sum, counter) => sum + (counter['count'] as int)),
      };

      _messages[messageIndex] = message.copyWith(reactionInfo: updatedReactionInfo);
      _sendingReactions.add(messageId);
      _buildChatItems();
      if (mounted) setState(() {});
    }
  }

  void _removeReactionOptimistically(String messageId) {
    final messageIndex = _messages.indexWhere((m) => m.id == messageId);
    if (messageIndex != -1) {
      final message = _messages[messageIndex];
      final currentReactionInfo = message.reactionInfo ?? {};
      final yourReaction = currentReactionInfo['yourReaction'] as String?;

      if (yourReaction != null) {
        final currentCounters = List<Map<String, dynamic>>.from(currentReactionInfo['counters'] ?? []);
        final counterIndex = currentCounters.indexWhere((counter) => counter['reaction'] == yourReaction);

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
          'totalCount': currentCounters.fold<int>(0, (sum, counter) => sum + (counter['count'] as int)),
        };

        _messages[messageIndex] = message.copyWith(reactionInfo: updatedReactionInfo);
        _sendingReactions.add(messageId);
        _buildChatItems();
        if (mounted) setState(() {});
      }
    }
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

  Message _hydrateLinkFromKnown(Message message, Map<String, Message> knownMessages) {
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

  List<Message> _hydrateLinksSequentially(List<Message> messages, {Map<String, Message>? initialKnown}) {
    final known = initialKnown != null ? Map<String, Message>.from(initialKnown) : <String, Message>{};
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
    return date1.year == date2.year && date1.month == date2.month && date1.day == date2.day;
  }

  bool _isMessageGrouped(Message currentMessage, Message? previousMessage) {
    if (previousMessage == null) return false;
    final currentTime = DateTime.fromMillisecondsSinceEpoch(currentMessage.time);
    final previousTime = DateTime.fromMillisecondsSinceEpoch(previousMessage.time);
    final timeDifference = currentTime.difference(previousTime).inMinutes;
    return currentMessage.senderId == previousMessage.senderId && timeDifference <= 5;
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
      if (_currentContact.id != null) {
        _mentionableUsers = [_currentContact];
      } else {
        _mentionableUsers = [];
      }
      return;
    }

    List<int> participantIds = [];
    final chatData = ApiService.instance.lastChatsPayload;
    if (chatData != null) {
      final chats = chatData['chats'] as List<dynamic>?;
      final currentChat = chats?.firstWhere((chat) => chat['id'] == widget.chatId, orElse: () => null);

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
      participantIds = _contactDetailsCache.keys.where((id) => id != (_actualMyId ?? widget.myId)).toList();
    }

    if (participantIds.isEmpty) {
      setState(() => _mentionableUsers = []);
      return;
    }

    final idsToFetch = participantIds.where((id) => !_contactDetailsCache.containsKey(id)).toList();
    if (idsToFetch.isNotEmpty) {
      try {
        final contacts = await ApiService.instance.fetchContactsByIds(idsToFetch);
        for (final contact in contacts) {
          if (contact.id != null) _contactDetailsCache[contact.id] = contact;
        }
      } catch (e) {
        print('Ошибка загрузки контактов для пингов: $e');
      }
    }

    setState(() {
      _mentionableUsers = participantIds
          .where((id) => _contactDetailsCache.containsKey(id))
          .map((id) => _contactDetailsCache[id]!)
          .where((contact) => contact.id != null && contact.id != 0)
          .toList();
    });
  }

  void _handleMentionFiltering(String text) {
    final cursorPosition = _textController.selection.baseOffset;
    if (cursorPosition > 0) {
      int atPosition = -1;
      for (int i = cursorPosition - 1; i >= 0; i--) {
        if (text[i] == '@') {
          atPosition = i;
          break;
        } else if (text[i] == ' ' || text[i] == '\n') break;
      }

      if (atPosition != -1) {
        _mentionQuery = text.substring(atPosition + 1, cursorPosition).toLowerCase();
        _mentionStartPosition = atPosition;

        _filteredMentionableUsers = _mentionableUsers.where((user) {
          final username = user.name.toLowerCase();
          final displayName = getContactDisplayName(
            contactId: user.id,
            originalName: user.name,
            originalFirstName: user.firstName,
            originalLastName: user.lastName,
          ).toLowerCase();
          return username.startsWith(_mentionQuery) || displayName.startsWith(_mentionQuery);
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

          final aStartsWith = aName.startsWith(_mentionQuery) || aDisplay.startsWith(_mentionQuery);
          final bStartsWith = bName.startsWith(_mentionQuery) || bDisplay.startsWith(_mentionQuery);

          if (aStartsWith && !bStartsWith) return -1;
          if (!aStartsWith && bStartsWith) return 1;
          return aDisplay.compareTo(bDisplay);
        });

        if (!_showMentionDropdown) {
          setState(() {
            _showMentionDropdown = true;
          });
        } else {
          setState(() {});
        }
      } else {
        if (_showMentionDropdown) {
          setState(() => _showMentionDropdown = false);
        }
      }
    } else {
      if (_showMentionDropdown) {
        setState(() => _showMentionDropdown = false);
      }
    }
  }

  void _insertMention(Contact user) {
    if (_mentionStartPosition == null) return;
    if (user.id == null || user.id == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка: не удалось получить ID пользователя')),
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
      selection: TextSelection.collapsed(offset: _mentionStartPosition! + mentionText.length),
    );

    _mentions.add(Mention(
      from: _mentionStartPosition!,
      length: mentionText.length,
      entityId: user.id,
      entityName: user.name,
    ));

    setState(() {
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
      setState(() => _showBotCommandsPanel = shouldShowPanel);
    } else if (shouldShowPanel) {
      setState(() {});
    }

    if (shouldShowPanel) _ensureBotCommandsLoaded();
  }

  Future<void> _ensureBotCommandsLoaded() async {
    if (!_currentContact.isBot) return;
    final botId = _currentContact.id;
    if (_botCommandsForBotId == botId && _botCommands.isNotEmpty) return;
    if (_isLoadingBotCommands) return;

    setState(() => _isLoadingBotCommands = true);
    try {
      final seq = await ApiService.instance.sendRawRequest(145, {'botId': botId});
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
      setState(() {
        _botCommandsForBotId = botId;
        _botCommands = commands;
      });
    } catch (e) {
      if (!mounted || _currentContact.id != botId) return;
      setState(() {
        _botCommandsForBotId = botId;
        _botCommands = const [];
      });
    } finally {
      if (!mounted || _currentContact.id != botId) return;
      setState(() => _isLoadingBotCommands = false);
    }
  }

  void _applyBotCommandToInput(BotCommand command) {
    final text = command.slashCommand;
    _textController.text = text;
    _textController.selection = TextSelection.collapsed(offset: text.length);
    setState(() => _showBotCommandsPanel = false);
    _textFocusNode.requestFocus();
  }

  Future<_PhotoPickerResult?> _pickPhotosFlow(BuildContext context) async {
    try {
      final ImagePicker picker = ImagePicker();
      final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Выбрать из галереи'),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Сделать фото'),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
            ],
          ),
        ),
      );

      if (choice == null) return null;

      List<XFile>? pickedFiles;
      if (choice == 'gallery') {
        pickedFiles = await picker.pickMultiImage();
      } else if (choice == 'camera') {
        final file = await picker.pickImage(source: ImageSource.camera);
        if (file != null) pickedFiles = [file];
      }

      if (pickedFiles == null || pickedFiles.isEmpty) return null;

      final caption = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Добавить подпись?'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Подпись к фото (необязательно)'),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Пропустить')),
            TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Добавить')),
          ],
        ),
      );

      return _PhotoPickerResult(paths: pickedFiles.map((f) => f.path).toList(), caption: caption);
    } catch (e) {
      print('Ошибка выбора фото: $e');
      return null;
    }
  }

  // Settings & Cache
  Future<void> _loadInputState() async {
    try {
      final state = await ChatCacheService().getChatInputState(widget.chatId);
      if (state != null && mounted) {
        final text = state['text'] as String? ?? '';
        final elements = (state['elements'] as List<dynamic>?)?.map((e) => e as Map<String, dynamic>).toList() ?? [];
        final replyingToMessageData = state['replyingToMessage'] as Map<String, dynamic>?;

        _textController.text = text;
        _mentions.clear();
        _textController.elements.addAll(elements);
        if (replyingToMessageData != null) {
          try {
            final message = Message.fromJson(replyingToMessageData);
            setState(() => _replyingToMessage = message);
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

  Future<void> _loadSpecialMessagesSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _specialMessagesEnabled = prefs.getBool('special_messages_enabled') ?? true;
    });
  }

  Future<void> _loadEncryptionConfig() async {
    try {
      final config = await ChatEncryptionService.getConfigForChat(widget.chatId);
      if (mounted) {
        setState(() {
          _encryptionConfigForCurrentChat = config;
          _isEncryptionPasswordSetForCurrentChat = config != null && config.password.isNotEmpty;
          _sendEncryptedForCurrentChat = config?.sendEncrypted ?? true;
        });
      }
    } catch (e) {
      print('Ошибка загрузки конфигурации шифрования: $e');
    }
  }

  Future<void> _loadCachedContacts() async {
    final chatContacts = await ChatCacheService().getCachedChatContacts(widget.chatId);
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

  Future<void> _loadContactIfNeeded(int contactId) async {
    if (_contactDetailsCache.containsKey(contactId) || _loadingContactIds.contains(contactId)) return;
    _loadingContactIds.add(contactId);

    try {
      final contacts = await ApiService.instance.fetchContactsByIds([contactId]);
      if (contacts.isNotEmpty && mounted) {
        final contact = contacts.first;
        _contactDetailsCache[contact.id] = contact;
        await ChatCacheService().cacheChatContacts(widget.chatId, _contactDetailsCache.values.toList());
        if (!mounted) return;
        setState(() {});
      }
    } catch (e) {
      // ignore
    } finally {
      _loadingContactIds.remove(contactId);
    }
  }

  Future<void> _loadGroupParticipants() async {
    try {
      final chatData = ApiService.instance.lastChatsPayload;
      if (chatData == null) return;

      final chats = chatData['chats'] as List<dynamic>?;
      if (chats == null) return;

      final currentChat = chats.firstWhere((chat) => chat['id'] == widget.chatId, orElse: () => null);
      if (currentChat == null) return;

      final participants = currentChat['participants'] as Map<String, dynamic>?;
      if (participants == null || participants.isEmpty) return;

      final participantIds = participants.keys.map((id) => int.tryParse(id)).where((id) => id != null).cast<int>().toList();
      if (participantIds.isEmpty) return;

      final idsToFetch = participantIds.where((id) => !_contactDetailsCache.containsKey(id)).toList();
      if (idsToFetch.isEmpty) return;

      final contacts = await ApiService.instance.fetchContactsByIds(idsToFetch);
      if (contacts.isNotEmpty && mounted) {
        setState(() {
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
    final cachedContact = ApiService.instance.getCachedContact(widget.contact.id);
    if (cachedContact != null) {
      _currentContact = cachedContact;
      if (mounted) setState(() {});
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
      _cachedCurrentGroupChat = chats.firstWhere((chat) => chat['id'] == widget.chatId, orElse: () => null);
      return _cachedCurrentGroupChat;
    } catch (e) {
      return null;
    }
  }

  bool _isCurrentUserAdmin() {
    final currentChat = _getCurrentGroupChat();
    if (currentChat != null && _actualMyId != null) {
      final admins = currentChat['admins'] as List<dynamic>? ?? [];
      return admins.contains(_actualMyId);
    }
    return false;
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
          SnackBar(content: Text('Ошибка при отправке стикера: $e'), backgroundColor: Colors.red),
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
        final random = DateTime.now().millisecondsSinceEpoch % availableStickerIds.length;
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
            .timeout(const Duration(seconds: 5), onTimeout: () => throw TimeoutException('Timeout'));

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
            setState(() {
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
        print('[ChatScreen] Ошибка при загрузке стикера для пустого чата (попытка ${attempt + 1}/$maxRetries): $e');
        if (attempt < maxRetries - 1) {
          await Future.delayed(retryDelay);
        }
      }
    }

    // После всех неудачных попыток оставляем _emptyChatSticker как null
    // EmptyChatWidget покажет fallback иконку вместо индикатора загрузки
    print('[ChatScreen] Не удалось загрузить стикер после $maxRetries попыток');
  }

  void _updateCachedPhotos() {
    final List<Map<String, dynamic>> allPhotos = [];
    for (final msg in _messages) {
      for (final attach in msg.attaches) {
        if (attach['_type'] == 'PHOTO') {
          final photo = Map<String, dynamic>.from(attach);
          photo['_messageId'] = msg.id;
          allPhotos.add(photo);
        }
      }
    }
    _cachedAllPhotos = allPhotos.reversed.toList();
  }

  void _updatePinnedMessage() {
    Message? latestPinned;
    for (int i = _messages.length - 1; i >= 0; i--) {
      final message = _messages[i];
      final controlAttach = message.attaches.firstWhere((a) => a['_type'] == 'CONTROL', orElse: () => const {});
      if (controlAttach.isNotEmpty && controlAttach['event'] == 'pin') {
        final pinnedMessageData = controlAttach['pinnedMessage'];
        if (pinnedMessageData != null && pinnedMessageData is Map<String, dynamic>) {
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
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
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

      final currentDate = DateTime.fromMillisecondsSinceEpoch(currentMessage.time).toLocal();
      final previousDate = previousMessage != null
          ? DateTime.fromMillisecondsSinceEpoch(previousMessage.time).toLocal()
          : null;

      if (previousMessage == null || !_isSameDay(currentDate, previousDate!)) {
        items.add(DateSeparatorItem(currentDate));
      }

      final isGrouped = _isMessageGrouped(currentMessage, previousMessage);
      final isFirstInGroup = previousMessage == null || !_isMessageGrouped(currentMessage, previousMessage);
      final isLastInGroup = i == source.length - 1 || !_isMessageGrouped(source[i + 1], currentMessage);

      items.add(MessageItem(currentMessage, isFirstInGroup: isFirstInGroup, isLastInGroup: isLastInGroup, isGrouped: isGrouped));
    }
    _chatItems = items;

    if (_isVoiceUploading || _isVoiceUploadFailed) {
      _chatItems.add(VoicePreviewItem(
        isUploading: _isVoiceUploading,
        progress: _voiceUploadProgress,
        isFailed: _isVoiceUploadFailed,
        onRetry: _isVoiceUploadFailed && _cachedVoicePath != null ? () => _retrySendVoiceMessage() : null,
      ));
    }
    _updateCachedPhotos();
  }

  // Input Helpers
  void _resetDraftFormattingIfNeeded(String newText) {
    if (newText.isEmpty) {
      _textController.elements.clear();
      _mentions.clear();
    }
  }

  void _updateTextSelectionState() {
    final selection = _textController.selection;
    final hasSelection = selection.isValid && !selection.isCollapsed && selection.end > selection.start;
    if (_hasTextSelection != hasSelection) {
      setState(() => _hasTextSelection = hasSelection);
    }
  }

  void _startSelectionCheck() {
    _stopSelectionCheck();
    _selectionCheckTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_textFocusNode.hasFocus) {
        _stopSelectionCheck();
        return;
      }
      _updateTextSelectionState();
    });
  }

  void _stopSelectionCheck() {
    _selectionCheckTimer?.cancel();
    _selectionCheckTimer = null;
  }

  Future<void> _handleTextChangedForKometColor() async {
    final prefs = await SharedPreferences.getInstance();
    final autoCompleteEnabled = prefs.getBool('komet_auto_complete_enabled') ?? false;

    if (!autoCompleteEnabled) {
      if (_showKometColorPicker) {
        setState(() {
          _showKometColorPicker = false;
          _currentKometColorPrefix = null;
        });
      }
      return;
    }

    final text = _textController.text;
    final cursorPos = _textController.selection.baseOffset;
    const prefix1 = 'komet.color_#';
    const prefix2 = 'komet.cosmetic.pulse#';

    String? detectedPrefix;
    int? prefixStartPos;

    for (final prefix in [prefix1, prefix2]) {
      int searchStart = 0;
      int lastFound = -1;
      while (true) {
        final found = text.indexOf(prefix, searchStart);
        if (found == -1 || found > cursorPos) break;
        if (found + prefix.length <= cursorPos) lastFound = found;
        searchStart = found + 1;
      }

      if (lastFound != -1) {
        final afterPrefix = text.substring(lastFound + prefix.length, cursorPos);
        if (afterPrefix.isEmpty || afterPrefix.trim().isEmpty) {
          final afterCursor = cursorPos < text.length ? text.substring(cursorPos) : '';
          if (afterCursor.length < 7 || !RegExp(r"^[0-9A-Fa-f]{6}'").hasMatch(afterCursor)) {
            detectedPrefix = prefix;
            prefixStartPos = lastFound;
            break;
          }
        }
      }
    }

    if (detectedPrefix != null && prefixStartPos != null) {
      final after = text.substring(prefixStartPos + detectedPrefix.length, cursorPos);
      if (after.isEmpty || after.trim().isEmpty) {
        if (!_showKometColorPicker || _currentKometColorPrefix != detectedPrefix) {
          setState(() {
            _showKometColorPicker = true;
            _currentKometColorPrefix = detectedPrefix;
          });
        }
        return;
      }
    }

    if (_showKometColorPicker) {
      setState(() {
        _showKometColorPicker = false;
        _currentKometColorPrefix = null;
      });
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
    setState(() => _replyingToMessage = message);
    _saveInputState();
  }

  void _cancelReply() {
    setState(() => _replyingToMessage = null);
  }

  void _applyTextFormat(String type) {
    final isEncryptionActive = _encryptionConfigForCurrentChat != null &&
        _encryptionConfigForCurrentChat!.password.isNotEmpty &&
        _sendEncryptedForCurrentChat;
    if (isEncryptionActive) return;

    final selection = _textController.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final from = selection.start;
    final length = selection.end - selection.start;
    if (length <= 0) return;

    setState(() {
      _textController.elements.add({'type': type, 'from': from, 'length': length});
      _textController.selection = selection;
    });
  }

  // Get sender name from message
  String _getSenderName(Message message) {
    final senderId = message.senderId;
    if (senderId == null) return 'Неизвестно';

    if (_contactDetailsCache.containsKey(senderId)) {
      return _contactDetailsCache[senderId]!.name;
    }

    if (senderId == widget.myId || senderId == _actualMyId) {
      return 'Вы';
    }

    return 'Пользователь';
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
              opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
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
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

}
