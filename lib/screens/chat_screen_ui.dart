part of 'chat_screen.dart';

extension on _ChatScreenState {
  // Helper для субтитра группы
  Widget _buildGroupSubtitle() {
    // Пытаемся получить информацию о чате из кэша
    final chatData = ApiService.instance.lastChatsPayload;
    final chats = chatData?['chats'] as List?;

    Chat? currentChat;
    if (chats != null) {
      for (final chatJson in chats) {
        try {
          final chat = Chat.tryFromJson(chatJson as Map<String, dynamic>);
          if (chat != null && chat.id == widget.chatId) {
            currentChat = chat;
            break;
          }
        } catch (e) {
          // Игнорируем ошибки парсинга
        }
      }
    }

    // Проверяем есть ли активный звонок
    if (currentChat?.hasActiveCall ?? false) {
      return Text(
        'Активный звонок',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.green,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    // Обычный субтитр
    return Text(
      widget.isChannel
          ? "${widget.participantCount ?? 0} подписчиков"
          : "${widget.participantCount ?? 0} участников",
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  // AppBar
  AppBar _buildAppBar() {
    final theme = context.read<ThemeProvider>();

    if (_isSearching) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _stopSearch,
          tooltip: 'Закрыть поиск',
        ),
        title: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Поиск по сообщениям...',
            border: InputBorder.none,
          ),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        actions: [
          if (_searchResults.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Text(
                  '${_currentResultIndex + 1} из ${_searchResults.length}',
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: _searchResults.isNotEmpty ? _navigateToNextResult : null,
            tooltip: 'Следующий (более старый) результат',
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: _searchResults.isNotEmpty
                ? _navigateToPreviousResult
                : null,
            tooltip: 'Предыдущий (более новый) результат',
          ),
        ],
      );
    }

    return AppBar(
      titleSpacing: 4.0,
      backgroundColor: theme.useGlassPanels ? Colors.transparent : null,
      elevation: theme.useGlassPanels ? 0 : null,
      flexibleSpace: theme.useGlassPanels
          ? ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: theme.topBarBlur,
                  sigmaY: theme.topBarBlur,
                ),
                child: Container(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: theme.topBarOpacity),
                ),
              ),
            )
          : null,
      leading: widget.isDesktopMode
          ? null
          : IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
      actions: [
        // Кнопка звонка только для обычных пользователей (не группы, не каналы, не боты, не MAX)
        if (!widget.isGroupChat &&
            !widget.isChannel &&
            widget.chatId != 0 &&
            widget.chatId != 1 && // MAX chat
            !widget.contact.isBot)
          IconButton(
            onPressed: _initiateCall,
            icon: const Icon(Icons.call),
            tooltip: 'Позвонить',
          ),
        // ОТКЛЮЧЕНО: Групповые звонки (критические баги)
        // if (widget.isGroupChat && widget.chatId != 0)
        //   IconButton(
        //     onPressed: _handleGroupCall,
        //     icon: const Icon(Icons.call),
        //     tooltip: 'Групповой звонок',
        //   ),
        if (widget.isGroupChat)
          IconButton(
            onPressed: () {
              if (_actualMyId == null) return;
              Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      GroupSettingsScreen(
                        chatId: widget.chatId,
                        initialContact: _currentContact,
                        myId: _actualMyId!,
                        onChatUpdated: widget.onChatUpdated,
                      ),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        return SlideTransition(
                          position:
                              Tween<Offset>(
                                begin: const Offset(1.0, 0.0),
                                end: Offset.zero,
                              ).animate(
                                CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutCubic,
                                ),
                              ),
                          child: FadeTransition(
                            opacity: CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOut,
                            ),
                            child: child,
                          ),
                        );
                      },
                  transitionDuration: const Duration(milliseconds: 350),
                ),
              );
            },
            icon: const Icon(Icons.settings),
            tooltip: 'Настройки группы',
          ),
        // Иконка шестеренки для админов каналов
        if (widget.isChannel && _isChannelAdmin())
          IconButton(
            onPressed: _openChannelSettings,
            icon: const Icon(Icons.settings),
            tooltip: 'Настройки канала',
          ),
        PopupMenuButton<String>(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onSelected: (value) {
            if (value == 'search') {
              _startSearch();
            } else if (value == 'block') {
              _showBlockDialog();
            } else if (value == 'unblock') {
              _showUnblockDialog();
            } else if (value == 'wallpaper') {
              _showWallpaperDialog();
            } else if (value == 'notification_settings') {
              _showNotificationSettings();
            } else if (value == 'clear_history') {
              _showClearHistoryDialog();
            } else if (value == 'delete_chat') {
              _showDeleteChatDialog();
            } else if (value == 'leave_group' || value == 'leave_channel') {
              _showLeaveGroupDialog();
            } else if (value == 'encryption_password') {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (context) => ChatEncryptionSettingsScreen(
                        chatId: widget.chatId,
                        isPasswordSet: _isEncryptionPasswordSetForCurrentChat,
                      ),
                    ),
                  )
                  .then((_) => _loadEncryptionConfig());
            } else if (value == 'media') {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ChatMediaScreen(
                    chatId: widget.chatId,
                    chatTitle: _currentContact.name,
                    messages: _messages,
                    onGoToMessage: (messageId) {
                      _scrollToMessage(messageId);
                    },
                  ),
                ),
              );
            } else if (value == 'channel_settings') {
              _openChannelSettings();
            }
          },
          itemBuilder: (context) {
            bool amIAdmin = false;
            if (widget.isGroupChat) {
              final currentChat = _getCurrentGroupChat();
              if (currentChat != null) {
                final admins = currentChat['admins'] as List<dynamic>? ?? [];
                if (_actualMyId != null) {
                  amIAdmin = admins.contains(_actualMyId);
                }
              }
            }
            final bool canDeleteChat = !widget.isGroupChat || amIAdmin;

            final bool isEncryptionPasswordSet =
                _isEncryptionPasswordSetForCurrentChat;

            return [
              // Настройки канала для админов
              if (widget.isChannel && _isChannelAdmin())
                const PopupMenuItem(
                  value: 'channel_settings',
                  child: Row(
                    children: [
                      Icon(Icons.settings, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('Настройки канала'),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'encryption_password',
                child: Row(
                  children: [
                    Icon(
                      Icons.lock,
                      color: isEncryptionPasswordSet
                          ? Colors.green
                          : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isEncryptionPasswordSet
                          ? 'Пароль шифрования установлен'
                          : 'Пароль от шифрования',
                      style: TextStyle(
                        color: isEncryptionPasswordSet
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'search',
                child: Row(
                  children: [
                    Icon(Icons.search),
                    SizedBox(width: 8),
                    Text('Поиск'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'media',
                child: Row(
                  children: [
                    Icon(Icons.photo_library),
                    SizedBox(width: 8),
                    Text('Медиа, файлы и ссылки'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'wallpaper',
                child: Row(
                  children: [
                    Icon(Icons.wallpaper),
                    SizedBox(width: 8),
                    Text('Обои'),
                  ],
                ),
              ),
              if (!widget.isGroupChat && !widget.isChannel) ...[
                if (_currentContact.isBlockedByMe)
                  const PopupMenuItem(
                    value: 'unblock',
                    child: Row(
                      children: [
                        Icon(Icons.person_add, color: Colors.green),
                        SizedBox(width: 8),
                        Text('Разблокировать'),
                      ],
                    ),
                  )
                else
                  const PopupMenuItem(
                    value: 'block',
                    child: Row(
                      children: [
                        Icon(Icons.block, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Заблокировать'),
                      ],
                    ),
                  ),
              ],
              const PopupMenuItem(
                value: 'notification_settings',
                child: Row(
                  children: [
                    Icon(Icons.notifications_outlined),
                    SizedBox(width: 8),
                    Text('Настройки уведомлений'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              if (!widget.isChannel)
                const PopupMenuItem(
                  value: 'clear_history',
                  child: Row(
                    children: [
                      Icon(Icons.clear_all, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Очистить историю'),
                    ],
                  ),
                ),

              if (widget.isGroupChat)
                const PopupMenuItem(
                  value: 'leave_group',
                  child: Row(
                    children: [
                      Icon(Icons.exit_to_app, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Выйти из группы'),
                    ],
                  ),
                ),

              if (widget.isChannel)
                const PopupMenuItem(
                  value: 'leave_channel',
                  child: Row(
                    children: [
                      Icon(Icons.exit_to_app, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Покинуть канал'),
                    ],
                  ),
                ),

              if (canDeleteChat && !widget.isChannel)
                const PopupMenuItem(
                  value: 'delete_chat',
                  child: Row(
                    children: [
                      Icon(Icons.delete_forever, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Удалить чат'),
                    ],
                  ),
                ),
            ];
          },
        ),
      ],
      title: Row(
        children: [
          GestureDetector(
            onTap: _showContactProfile,
            child: Hero(
              tag: 'contact_avatar_${widget.contact.id}',
              child: widget.chatId == 0
                  ? CircleAvatar(
                      radius: 18,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      child: Icon(
                        Icons.bookmark,
                        size: 20,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    )
                  : ContactAvatarWidget(
                      contactId: widget.contact.id,
                      originalAvatarUrl: widget.contact.photoBaseUrl,
                      radius: 18,
                      fallbackText: widget.contact.name.isNotEmpty
                          ? widget.contact.name[0].toUpperCase()
                          : '?',
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: _showContactProfile,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ContactNameWidget(
                          contactId: widget.contact.id,
                          originalName: widget.contact.name,
                          originalFirstName: widget.contact.firstName,
                          originalLastName: widget.contact.lastName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (context
                          .watch<ThemeProvider>()
                          .debugShowMessageCount) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.ultraOptimizeChats
                                ? Colors.red.withValues(alpha: 0.7)
                                : theme.optimizeChats
                                ? Colors.orange.withValues(alpha: 0.7)
                                : Colors.blue.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_messages.length}${theme.ultraOptimizeChats
                                ? 'U'
                                : theme.optimizeChats
                                ? 'O'
                                : ''}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 2),
                  if (widget.isGroupChat || widget.isChannel)
                    _buildGroupSubtitle()
                  else if (widget.chatId != 0)
                    _ContactPresenceSubtitle(
                      chatId: widget.chatId,
                      userId: widget.contact.id,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Chat Background
  Widget _buildChatBackground(ThemeProvider provider) {
    if (!provider.useCustomChatWallpaper) {
      return Container(color: Theme.of(context).scaffoldBackgroundColor);
    }

    // Use wallpaper from ThemeProvider
    switch (provider.chatWallpaperType) {
      case ChatWallpaperType.solid:
        return Container(color: provider.chatWallpaperColor1);
      case ChatWallpaperType.gradient:
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                provider.chatWallpaperColor1,
                provider.chatWallpaperColor2,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        );
      case ChatWallpaperType.image:
        if (provider.chatWallpaperImagePath != null) {
          Widget imageWidget = Image.file(
            File(provider.chatWallpaperImagePath!),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          );
          if (provider.chatWallpaperImageBlur > 0)
            imageWidget = ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: provider.chatWallpaperImageBlur,
                sigmaY: provider.chatWallpaperImageBlur,
              ),
              child: imageWidget,
            );
          return imageWidget;
        }
        break;
      case ChatWallpaperType.komet:
      case ChatWallpaperType.video:
        break;
    }

    return Container(color: Theme.of(context).scaffoldBackgroundColor);
  }

  Widget _buildChatWallpaper(ThemeProvider provider) {
    if (!provider.useCustomChatWallpaper) {
      return const SizedBox.shrink();
    }

    // Check if video wallpaper
    if (provider.chatWallpaperType == ChatWallpaperType.video &&
        provider.chatWallpaperVideoPath != null &&
        provider.chatWallpaperVideoPath!.isNotEmpty) {
      return _VideoWallpaperBackground(
        videoPath: provider.chatWallpaperVideoPath!,
      );
    }

    return const SizedBox.shrink();
  }

  // Connection Banner
  Widget _buildConnectionBanner() {
    // Use real connection state from ApiService for accurate status
    final isConnected = ApiService.instance.isActuallyConnected;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: isConnected ? 0 : 32,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade700, Colors.orange.shade600],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: isConnected
          ? const SizedBox.shrink()
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Нет соединения...',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
    );
  }

  // Send or Mic Button
  Widget _buildSendOrMicButton({
    required bool isBlocked,
    required bool isSmall,
  }) {
    final colors = Theme.of(context).colorScheme;

    return ValueListenableBuilder(
      valueListenable: _textController,
      builder: (context, value, child) {
        if (_isVoiceRecordingUi) {
          final padding = EdgeInsets.all(isSmall ? 10 : 6);
          final baseIconSize = isSmall ? 20.0 : 24.0;
          final baseDiameter = baseIconSize + 2 * (isSmall ? 10.0 : 6.0);

          // Показываем прогресс если идет загрузка
          if (_isVoiceUploading) {
            return SizedBox(
              width: baseDiameter,
              height: baseDiameter,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Circular progress indicator
                  SizedBox(
                    width: baseDiameter,
                    height: baseDiameter,
                    child: CircularProgressIndicator(
                      value: _voiceUploadProgress,
                      strokeWidth: 2.5,
                      backgroundColor: colors.primary.withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                    ),
                  ),
                  // Icon в центре
                  Container(
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(isSmall ? 8 : 5),
                      child: Icon(
                        Icons.upload_rounded,
                        color: colors.onPrimary,
                        size: isSmall ? 16 : 18,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: _sendVoiceMessage,
            child: Container(
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: padding,
                child: Icon(
                  Icons.send_rounded,
                  color: colors.onPrimary,
                  size: isSmall ? 20 : 24,
                ),
              ),
            ),
          );
        }

        final hasText = _textController.text.trim().isNotEmpty;
        final showSend = hasText;

        Color backgroundColor;
        if (isBlocked) {
          backgroundColor = colors.onSurface.withValues(alpha: 0.2);
        } else {
          backgroundColor = colors.primary;
        }

        Color iconColor;
        if (isBlocked) {
          iconColor = colors.onSurface.withValues(alpha: 0.5);
        } else {
          iconColor = colors.onPrimary;
        }

        Widget icon;
        VoidCallback? onTap;

        // Блокируем отправку пока нет ID
        if (_actualMyId == null) {
          onTap = () {};
        }

        final recordIcon = _isVideoRecordMode
            ? Icons.videocam_rounded
            : Icons.mic_rounded;

        if (showSend) {
          icon = Icon(
            Icons.send_rounded,
            color: iconColor,
            size: isSmall ? 20 : 24,
          );
          onTap = (!isBlocked) ? _sendMessage : null;
        } else {
          // Нет текста: показываем mic или camera с анимацией переключения
          icon = AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) {
              return RotationTransition(
                turns: Tween<double>(begin: 0.8, end: 1.0).animate(animation),
                child: ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
              );
            },
            child: Icon(
              recordIcon,
              key: ValueKey<bool>(_isVideoRecordMode),
              color: iconColor,
              size: isSmall ? 20 : 24,
            ),
          );
          // Короткое нажатие — переключить режим
          onTap = (!isBlocked)
              ? () {
                  // ignore: invalid_use_of_protected_member
                  setState(() => _isVideoRecordMode = !_isVideoRecordMode);
                }
              : null;
        }

        final padding = EdgeInsets.all(isSmall ? 10 : 6);
        final baseIconSize = isSmall ? 20.0 : 24.0;
        final baseDiameter = baseIconSize + 2 * (isSmall ? 10.0 : 6.0);

        // Если идет загрузка голосового - показываем кружок прогресса
        if (_isVoiceUploading) {
          return SizedBox(
            width: baseDiameter,
            height: baseDiameter,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Circular progress indicator
                SizedBox(
                  width: baseDiameter,
                  height: baseDiameter,
                  child: CircularProgressIndicator(
                    value: _voiceUploadProgress,
                    strokeWidth: 2.5,
                    backgroundColor: colors.primary.withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                  ),
                ),
                // Icon в центре
                Container(
                  decoration: BoxDecoration(
                    color: colors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(isSmall ? 8 : 5),
                    child: Icon(
                      Icons.upload_rounded,
                      color: colors.onPrimary,
                      size: isSmall ? 16 : 18,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: (!isBlocked && !showSend)
              ? () {
                  if (_isVideoRecordMode) {
                    _startVideoRecordingUi();
                  } else {
                    _startVoiceRecordingUi();
                  }
                }
              : null,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: Tween<double>(begin: 0.85, end: 1.0).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Container(
              key: ValueKey<String>(
                showSend ? 'send' : (_isVideoRecordMode ? 'video' : 'mic'),
              ),
              decoration: BoxDecoration(
                color: backgroundColor,
                shape: BoxShape.circle,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: onTap,
                  child: Padding(padding: padding, child: icon),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Text Input
  Widget _buildTextInput() {
    if (widget.isChannel) {
      bool amIAdmin = false;
      final currentChat = _getCurrentGroupChat();
      if (currentChat != null && _actualMyId != null) {
        final admins = currentChat['admins'] as List<dynamic>? ?? [];
        final owner = currentChat['owner'] as int?;
        amIAdmin = admins.contains(_actualMyId) || owner == _actualMyId;
      }

      if (!amIAdmin) {
        return const SizedBox.shrink();
      }
    }

    final theme = context.watch<ThemeProvider>();
    final isBlocked = _currentContact.isBlockedByMe && !theme.blockBypass;

    if (_isVideoRecordingUi) {
      final colors = Theme.of(context).colorScheme;
      final inputBar = Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 10.0,
            ),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              bottom: false,
              child: _buildVideoRecordingBar(
                isBlocked: isBlocked,
                isGlass: false,
              ),
            ),
          ),
          // Send/stop button
          Positioned(
            right: 12,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: _sendVideoMessage,
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.send_rounded,
                      color: colors.onPrimary,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );

      return _wrapInputWithPanels(inputBar);
    }

    if (_isVoiceRecordingUi) {
      final inputBar = Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 10.0,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              bottom: false,
              child: _buildVoiceRecordingBar(
                isBlocked: isBlocked,
                isGlass: false,
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (!isBlocked && !_isVoiceRecordingPaused)
                  ? (_) => _handleRecordCancelDragStart()
                  : null,
              onHorizontalDragUpdate: (!isBlocked && !_isVoiceRecordingPaused)
                  ? (details) => _handleRecordCancelDragUpdate(details)
                  : null,
              onHorizontalDragEnd: (!isBlocked && !_isVoiceRecordingPaused)
                  ? (_) => _handleRecordCancelDragEnd()
                  : null,
              child: Align(
                alignment: Alignment.centerRight,
                child: _buildSendOrMicButton(
                  isBlocked: isBlocked,
                  isSmall: false,
                ),
              ),
            ),
          ),
          Positioned(
            right:
                12 +
                _ChatScreenState._recordSendButtonSpace +
                _ChatScreenState._recordButtonGap,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: (!isBlocked) ? _toggleVoiceRecordingPause : null,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      _isVoiceRecordingPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      color: Theme.of(context).colorScheme.onPrimary,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );

      return _wrapInputWithPanels(inputBar);
    }

    final sendButton = _buildSendOrMicButton(
      isBlocked: isBlocked,
      isSmall: false,
    );

    Widget inputBar = Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon: Icon(
              Icons.attach_file,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: _onAttachPressed,
            tooltip: 'Прикрепить файл',
          ),
          IconButton(
            icon: Icon(
              Icons.auto_awesome_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            onPressed: _toggleKometSpecialMenu,
            tooltip: 'Спецэффекты',
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_replyingToMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 3,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _getSenderName(_replyingToMessage!),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _replyingToMessage!.text.isNotEmpty
                                    ? _replyingToMessage!.text
                                    : _replyingToMessage!.attaches.isNotEmpty
                                    ? 'Медиафайл'
                                    : 'Сообщение',
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () {
                            // ignore: invalid_use_of_protected_member
                            setState(() {
                              _replyingToMessage = null;
                            });
                          },
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                if (_editingMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.edit, size: 16, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Редактирование сообщения',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () {
                            // ignore: invalid_use_of_protected_member
                            setState(() {
                              _editingMessage = null;
                              _textController.clear();
                            });
                          },
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                Container(
                  constraints: const BoxConstraints(
                    minHeight: 40,
                    maxHeight: 120,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _isMobilePlatform
                      ? TextField(
                          controller: _textController,
                          focusNode: _textFocusNode,
                          maxLines: null,
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            hintText: 'Сообщение',
                            border: InputBorder.none,
                            hintStyle: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          onChanged: (text) {
                            _handleChatInputChanged(text);
                          },
                        )
                      : FocusableActionDetector(
                          focusNode: _textFocusNode,
                          shortcuts: {
                            // Enter - отправить сообщение
                            const SingleActivator(LogicalKeyboardKey.enter):
                                const SendMessageIntent(),
                            // Shift+Enter - новая строка
                            const SingleActivator(
                              LogicalKeyboardKey.enter,
                              shift: true,
                            ): const NewLineIntent(),
                          },
                          actions: {
                            SendMessageIntent:
                                CallbackAction<SendMessageIntent>(
                                  onInvoke: (_) {
                                    final text = _textController.text;
                                    if (text.trim().isNotEmpty) {
                                      if (_editingMessage != null) {
                                        _editMessage(_editingMessage!);
                                      } else {
                                        _sendMessage();
                                      }
                                    }
                                    return null;
                                  },
                                ),
                            NewLineIntent: CallbackAction<NewLineIntent>(
                              onInvoke: (_) {
                                final text = _textController.text;
                                final selection = _textController.selection;
                                final newText =
                                    text.substring(0, selection.start) +
                                    '\n' +
                                    text.substring(selection.end);
                                _textController.text = newText;
                                _textController.selection =
                                    TextSelection.collapsed(
                                      offset: selection.start + 1,
                                    );
                                _handleChatInputChanged(_textController.text);
                                return null;
                              },
                            ),
                          },
                          child: TextField(
                            controller: _textController,
                            maxLines: null,
                            textInputAction: TextInputAction.send,
                            decoration: InputDecoration(
                              hintText:
                                  'Сообщение (Enter - отправить, Shift+Enter - новая строка)',
                              border: InputBorder.none,
                              hintStyle: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.4),
                                fontSize: 13,
                              ),
                            ),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            onChanged: (text) {
                              _handleChatInputChanged(text);
                            },
                            contextMenuBuilder: (context, editableTextState) {
                              final List<ContextMenuButtonItem> buttonItems =
                                  editableTextState.contextMenuButtonItems;

                              buttonItems.insertAll(0, [
                                ContextMenuButtonItem(
                                  label: 'Жирный',
                                  onPressed: () {
                                    editableTextState.hideToolbar();
                                    _toggleStyle('STRONG');
                                  },
                                ),
                                ContextMenuButtonItem(
                                  label: 'Курсив',
                                  onPressed: () {
                                    editableTextState.hideToolbar();
                                    _toggleStyle('EMPHASIZED');
                                  },
                                ),
                                ContextMenuButtonItem(
                                  label: 'Зачеркнуть',
                                  onPressed: () {
                                    editableTextState.hideToolbar();
                                    _toggleStyle('STRIKETHROUGH');
                                  },
                                ),
                                ContextMenuButtonItem(
                                  label: 'Подчеркнуть',
                                  onPressed: () {
                                    editableTextState.hideToolbar();
                                    _toggleStyle('UNDERLINE');
                                  },
                                ),
                                ContextMenuButtonItem(
                                  label: 'Цитата',
                                  onPressed: () {
                                    editableTextState.hideToolbar();
                                    _toggleStyle('QUOTE');
                                  },
                                ),
                                ContextMenuButtonItem(
                                  label: 'Убрать стили',
                                  onPressed: () {
                                    editableTextState.hideToolbar();
                                    _clearSelectionStyles();
                                  },
                                ),
                                ContextMenuButtonItem(
                                  label: 'Галактика',
                                  onPressed: () {
                                    editableTextState.hideToolbar();
                                    final selection = _textController.selection;
                                    if (selection.start < 0) return;
                                    final text = _textController.text;
                                    final selectedText = text.substring(
                                      selection.start,
                                      selection.end,
                                    );
                                    final newText = text.replaceRange(
                                      selection.start,
                                      selection.end,
                                      "komet.cosmetic.galaxy'$selectedText'",
                                    );
                                    _textController.text = newText;
                                    _textController.selection = TextSelection(
                                      baseOffset: selection.start + 22,
                                      extentOffset: selection.end + 22,
                                    );
                                  },
                                ),
                              ]);

                              return AdaptiveTextSelectionToolbar.buttonItems(
                                anchors: editableTextState.contextMenuAnchors,
                                buttonItems: buttonItems,
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.only(bottom: 6), child: sendButton),
        ],
      ),
    );

    return _wrapInputWithPanels(inputBar);
  }

  Widget _wrapInputWithPanels(Widget inputBar) {
    if (_showBotCommandsPanel) {
      final query = _textController.text.toLowerCase();
      final filteredCommands = _botCommands.where((cmd) {
        return cmd.slashCommand.toLowerCase().startsWith(query);
      }).toList();

      if (filteredCommands.isNotEmpty || _isLoadingBotCommands) {
        inputBar = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _BotCommandsPanel(
                isLoading: _isLoadingBotCommands,
                commands: filteredCommands,
                onCommandTap: _applyBotCommandToInput,
              ),
            ),
            inputBar,
          ],
        );
      }
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
        child: inputBar,
      ),
    );
  }

  // Snackbars
  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 8, right: 8),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // Search
  void _startSearch() {
    // ignore: invalid_use_of_protected_member
    setState(() {
      _isSearching = true;
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      _searchFocusNode.requestFocus();
    });
  }

  void _stopSearch() {
    // ignore: invalid_use_of_protected_member
    setState(() {
      _isSearching = false;
      _searchController.clear();
      _searchResults.clear();
      _currentResultIndex = 0;
    });
  }

  void _performSearch(String query) {
    if (query.isEmpty) {
      // ignore: invalid_use_of_protected_member
      setState(() {
        _searchResults.clear();
        _currentResultIndex = 0;
      });
      return;
    }

    final results = <Message>[];
    final lowerQuery = query.toLowerCase();

    for (final message in _messages) {
      if (message.text.toLowerCase().contains(lowerQuery)) {
        results.add(message);
      }
    }

    // ignore: invalid_use_of_protected_member
    setState(() {
      _searchResults = results;
      _currentResultIndex = results.isNotEmpty ? 0 : 0;
    });

    if (results.isNotEmpty) {
      _scrollToResult();
    }
  }

  void _navigateToNextResult() {
    if (_searchResults.isEmpty) return;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _currentResultIndex = (_currentResultIndex + 1) % _searchResults.length;
    });
    _scrollToResult();
  }

  void _navigateToPreviousResult() {
    if (_searchResults.isEmpty) return;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _currentResultIndex =
          (_currentResultIndex - 1 + _searchResults.length) %
          _searchResults.length;
    });
    _scrollToResult();
  }

  void _scrollToResult() {
    if (_searchResults.isEmpty) return;
    final targetMessage = _searchResults[_currentResultIndex];
    _scrollToMessage(targetMessage.id);
  }

  // Scroll operations handled in logic.dart

  void _jumpToBottom() {
    if (_chatItems.isEmpty) return;
    if (!_itemScrollController.isAttached) return;

    // Получаем текущую позицию
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) {
      // Если позиции неизвестны, просто телепортируемся
      _itemScrollController.jumpTo(index: 0);
      return;
    }

    // Находим самый верхний видимый элемент
    final maxVisibleIndex = positions
        .map((p) => p.index)
        .reduce((a, b) => a > b ? a : b);

    // Если далеко (больше 10 элементов от низа), делаем гибридный скролл
    _itemScrollController.jumpTo(index: 0);
  }

  void _scrollToPinnedMessage() {
    final pinned = _pinnedMessage;
    if (pinned == null) return;

    int? targetChatItemIndex;
    for (int i = 0; i < _chatItems.length; i++) {
      final item = _chatItems[i];
      if (item is MessageItem) {
        final msg = item.message;
        if (msg.id == pinned.id ||
            (msg.cid != null && pinned.cid != null && msg.cid == pinned.cid)) {
          targetChatItemIndex = i;
          break;
        }
      }
    }

    if (targetChatItemIndex == null) return;
    if (!_itemScrollController.isAttached) return;

    final visualIndex = _getVisualIndex(targetChatItemIndex);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_itemScrollController.isAttached) return;
      _itemScrollController.scrollTo(
        index: visualIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  // Dialogs
  void _showContactProfile() {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (context, animation, secondaryAnimation) {
          return ContactProfileDialog(
            contact: widget.contact,
            isChannel: widget.isChannel,
            myId: _actualMyId,
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

  void _showComplaintDialog(String messageId) {
    showDialog(
      context: context,
      builder: (context) =>
          ComplaintDialog(messageId: messageId, chatId: widget.chatId),
    );
  }

  void _showBlockDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Заблокировать пользователя?'),
        content: Text(
          'Вы больше не будете получать сообщения от ${widget.contact.name}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ApiService.instance
                  .blockContact(widget.contact.id)
                  .then((_) {
                    // ignore: invalid_use_of_protected_member
                    setState(() {
                      _currentContact = Contact(
                        id: _currentContact.id,
                        name: _currentContact.name,
                        firstName: _currentContact.firstName,
                        lastName: _currentContact.lastName,
                        description: _currentContact.description,
                        photoBaseUrl: _currentContact.photoBaseUrl,
                        isBlocked: _currentContact.isBlocked,
                        isBlockedByMe: true,
                        accountStatus: _currentContact.accountStatus,
                        status: _currentContact.status,
                      );
                    });
                    widget.onChatUpdated?.call();
                  })
                  .catchError((error) {
                    _showErrorSnackBar('Ошибка блокировки');
                  });
            },
            child: const Text(
              'Заблокировать',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _showUnblockDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Разблокировать пользователя?'),
        content: Text(
          'Вы снова сможете получать сообщения от ${widget.contact.name}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ApiService.instance
                  .unblockContact(widget.contact.id)
                  .then((_) {
                    // ignore: invalid_use_of_protected_member
                    setState(() {
                      _currentContact = Contact(
                        id: _currentContact.id,
                        name: _currentContact.name,
                        firstName: _currentContact.firstName,
                        lastName: _currentContact.lastName,
                        description: _currentContact.description,
                        photoBaseUrl: _currentContact.photoBaseUrl,
                        isBlocked: _currentContact.isBlocked,
                        isBlockedByMe: false,
                        accountStatus: _currentContact.accountStatus,
                        status: _currentContact.status,
                      );
                    });
                    widget.onChatUpdated?.call();
                  })
                  .catchError((error) {
                    _showErrorSnackBar('Ошибка разблокировки');
                  });
            },
            child: const Text('Разблокировать'),
          ),
        ],
      ),
    );
  }

  // Main body builder
  Widget _buildBody() {
    final theme = context.watch<ThemeProvider>();

    return Container(
      color: theme.useCustomChatWallpaper
          ? Colors.transparent
          : Theme.of(context).scaffoldBackgroundColor,
      child: Stack(
        children: [
          // Background
          if (theme.useCustomChatWallpaper)
            Positioned.fill(child: _buildChatBackground(theme)),

          // Video wallpaper (if any)
          if (theme.chatWallpaperType == ChatWallpaperType.video &&
              theme.chatWallpaperVideoPath != null)
            Positioned.fill(child: _buildChatWallpaper(theme)),

          // Main content
          Column(
            children: [
              // Connection banner
              _buildConnectionBanner(),

              // Pinned message
              if (_pinnedMessage != null)
                PinnedMessageWidget(
                  pinnedMessage: _pinnedMessage!,
                  contacts: _contactDetailsCache,
                  myId: _actualMyId ?? 0,
                  onTap: _scrollToPinnedMessage,
                  onClose: () {
                    // ignore: invalid_use_of_protected_member
                    setState(() {
                      _pinnedMessage = null;
                    });
                  },
                ),

              // Messages list
              Expanded(
                child: _isLoadingHistory && _messages.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty && !widget.isChannel
                    ? EmptyChatWidget(
                        sticker: _emptyChatSticker,
                        onStickerTap: _sendEmptyChatSticker,
                      )
                    : ScrollablePositionedList.builder(
                        itemCount: _chatItems.length,
                        itemScrollController: _itemScrollController,
                        itemPositionsListener: _itemPositionsListener,
                        reverse: true,
                        itemBuilder: (context, index) {
                          final item =
                              _chatItems[_chatItems.length - 1 - index];
                          return RepaintBoundary(child: _buildChatItem(item));
                        },
                      ),
              ),

              // Text input
              _buildTextInput(),
            ],
          ),

          // Floating video circle preview (Telegram-style)
          if (_isVideoRecordingUi) _buildVideoCirclePreview(),

          // Scroll-to-bottom FAB
          Positioned(
            right: 16,
            bottom: 80,
            child: ValueListenableBuilder<bool>(
              valueListenable: _showScrollToBottomNotifier,
              builder: (context, showButton, child) {
                return AnimatedScale(
                  scale: showButton ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: AnimatedOpacity(
                    opacity: showButton ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: FloatingActionButton.small(
                      heroTag: 'scroll_to_bottom',
                      onPressed: _jumpToBottom,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      elevation: 3,
                      child: const Icon(Icons.keyboard_arrow_down),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemMessage(Message message, Map<String, dynamic> control) {
    String text = '';
    final event = control['event']?.toString();

    if (event == 'new') {
      text = 'Чат создан: ${control['title'] ?? ''}';
    } else if (event == 'join') {
      text = 'Пользователь присоединился к чату';
    } else if (event == 'leave') {
      text = 'Пользователь покинул чат';
    } else {
      text = message.text;
    }

    if (text.isEmpty) return const SizedBox.shrink();

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildChatItem(ChatItem item) {
    if (item is MessageItem) {
      final controlAttach = item.message.attaches.firstWhere(
        (a) => (a['_type'] ?? a['type']) == 'CONTROL',
        orElse: () => {},
      );

      if (controlAttach.isNotEmpty) {
        return _buildSystemMessage(item.message, controlAttach);
      }

      final senderContact = _contactDetailsCache[item.message.senderId];
      // Для каналов (senderId == 0) используем имя канала из контакта
      // Для групп и личных чатов - имя отправителя или ID
      String senderName;
      if (item.message.senderId == 0) {
        senderName = widget.contact.name;
      } else if (senderContact != null) {
        senderName = senderContact.name;
      } else {
        senderName = 'ID ${item.message.senderId}';
      }

      final isMe = item.message.senderId == _actualMyId;

      MessageReadStatus? readStatus;
      if (isMe) {
        final messageIdInt = int.tryParse(item.message.id);
        final messageTime = item.message.time; // timestamp когда отправлено

        // Проверяем прочитанность по трем источникам (в порядке приоритета):
        // 1. opcode 130 (новая система) - использует message.time
        // 2. opcode 50 (_lastPeerReadMessageId, старая система) - использует message ID
        // 3. message.status из сервера

        if (MessageReadStatusService().isMessageRead(
          widget.chatId,
          messageTime,
        )) {
          // opcode 130 - новая система (проверка по timestamp)
          readStatus = MessageReadStatus.read;
        } else if (messageIdInt != null &&
            _lastPeerReadMessageId != null &&
            messageIdInt <= _lastPeerReadMessageId!) {
          // opcode 50 - старая система (READ_MESSAGE, проверка по ID)
          readStatus = MessageReadStatus.read;
        } else if (item.message.status == 'READ') {
          // Статус из сервера
          readStatus = MessageReadStatus.read;
        } else if (item.message.status == 'SENDING' ||
            item.message.id.startsWith('local_')) {
          readStatus = MessageReadStatus.sending;
        } else {
          // Дефолт: отправлено
          readStatus = MessageReadStatus.sent;
        }
      }

      final isHighlighted = _highlightedMessageId == item.message.id;

      // Ensure name is loaded
      if (item.message.senderId != 0 &&
          !_contactDetailsCache.containsKey(item.message.senderId)) {
        _ensureContactsCached([item.message.senderId]);
      }

      // Ensure forwarded author is loaded
      if (item.message.isForwarded && item.message.link != null) {
        final fwdMsg = item.message.link!['message'] as Map?;
        final fwdSender = fwdMsg?['sender'] as int?;
        if (fwdSender != null && !_contactDetailsCache.containsKey(fwdSender)) {
          _ensureContactsCached([fwdSender]);
        }
      }

      // Check admin rights for channels/groups
      bool canDeleteAnyMessage = false;
      if (widget.isChannel || widget.isGroupChat) {
        final currentChat = _getCurrentGroupChat();
        if (currentChat != null && _actualMyId != null) {
          final admins = currentChat['admins'] as List<dynamic>? ?? [];
          final owner = currentChat['owner'] as int?;
          canDeleteAnyMessage =
              admins.contains(_actualMyId) || owner == _actualMyId;
        }
      }

      final bool canDeleteForAll =
          (isMe && item.message.canEdit(_actualMyId ?? 0)) ||
          canDeleteAnyMessage;

      // Расшифровка сообщения если нужно
      String? decryptedText;
      if (ChatEncryptionService.isEncryptedMessage(item.message.text) &&
          _encryptionConfigForCurrentChat != null &&
          _encryptionConfigForCurrentChat!.password.isNotEmpty) {
        decryptedText = ChatEncryptionService.decryptWithPassword(
          _encryptionConfigForCurrentChat!.password,
          item.message.text,
        );
      }

      final allPhotos = _cachedAllPhotos;

      final bubble = ChatMessageBubble(
        key: ValueKey(item.message.id),
        message: item.message,
        contactDetailsCache: _contactDetailsCache,
        isMe: isMe,
        allPhotos: allPhotos.isNotEmpty ? allPhotos : null,
        isFirstInGroup: item.isFirstInGroup,
        isLastInGroup: item.isLastInGroup,
        isGrouped: item.isGrouped,
        isGroupChat: widget.isGroupChat,
        isChannel: widget.isChannel,
        senderName: (item.isFirstInGroup) ? senderName : null,
        myUserId: _actualMyId ?? 0,
        chatId: widget.chatId,
        readStatus: readStatus,
        isHighlighted: isHighlighted,
        canDeleteForAll: canDeleteForAll,
        canEditMessage: isMe && item.message.canEdit(_actualMyId ?? 0),
        isEncryptionPasswordSet: _isEncryptionPasswordSetForCurrentChat,
        decryptedText: decryptedText,
        onReply: () => _replyToMessage(item.message),
        onReplyTap: (messageId) => _scrollToMessage(messageId),
        onEdit: () => _editMessage(item.message),
        onForward: () => _forwardMessage(item.message),
        onDelete: () => _removeMessages([item.message.id]),
        onComplain: () => _showComplaintDialog(item.message.id),
        onDeleteForMe: () => _removeMessages([item.message.id]),
        onDeleteForAll: canDeleteForAll
            ? () => _deleteMessageForAll(item.message.id)
            : null,
        onReaction: (emoji) => _sendReaction(item.message.id, emoji),
        onRemoveReaction: () => _removeReaction(item.message.id),
      );

      return bubble;
    } else if (item is DateSeparatorItem) {
      return _DateSeparatorChip(date: item.date);
    } else if (item is VoicePreviewItem) {
      return _buildVoicePreviewBubble(item);
    }
    return const SizedBox.shrink();
  }

  bool _isChannelAdmin() {
    final currentChat = _getCurrentGroupChat();
    if (currentChat != null && _actualMyId != null) {
      final admins = currentChat['admins'] as List<dynamic>? ?? [];
      final owner = currentChat['owner'] as int?;
      return admins.contains(_actualMyId) || owner == _actualMyId;
    }
    return false;
  }

  void _openChannelSettings() async {
    if (_isOpeningChannelSettings) {
      print('⚠️ [ChannelSettings] Уже открывается, игнорируем');
      return;
    }

    _isOpeningChannelSettings = true;
    if (_actualMyId == null) {
      print('⚠️ [ChannelSettings] _actualMyId null');
      _isOpeningChannelSettings = false;
      return;
    }

    try {
      print(
        '📋 [ChannelSettings] Начинаем загрузку данных канала ${widget.chatId}...',
      );

      // Сохраняем контекст ДО await
      final navigatorContext = context;

      print('📋 [ChannelSettings] Вызываем getChannelDetails с timeout...');
      final channelDetails = await ApiService.instance
          .getChannelDetails(widget.chatId)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              print('⏱️ [ChannelSettings] Timeout при загрузке данных канала');
              throw TimeoutException(
                'Таймаут загрузки данных канала',
                const Duration(seconds: 10),
              );
            },
          );
      print('✅ [ChannelSettings] Данные канала получены');

      if (!mounted) {
        print('⚠️ [ChannelSettings] Widget не mounted после загрузки');
        return;
      }

      if (channelDetails == null) {
        print('⚠️ [ChannelSettings] channelDetails null, показываем ошибку');
        ScaffoldMessenger.of(navigatorContext).showSnackBar(
          const SnackBar(
            content: Text('Не удалось загрузить данные канала'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(bottom: 80, left: 8, right: 8),
          ),
        );
      }

      final safeChannelDetails =
          channelDetails ?? <String, dynamic>{'id': widget.chatId};

      print('📋 [ChannelSettings] Открываем ChannelSettingsScreen...');
      Navigator.of(navigatorContext).push(
        MaterialPageRoute(
          builder: (ctx) => ChannelSettingsScreen(
            chatId: widget.chatId,
            channelData: safeChannelDetails,
            myId: _actualMyId!,
          ),
        ),
      );
      print('✅ [ChannelSettings] Экран открыт');
    } catch (e, stackTrace) {
      print('❌ [ChannelSettings] Ошибка открытия настроек канала: $e');
      print('❌ [ChannelSettings] Stack: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 80, left: 8, right: 8),
          ),
        );
      }
    } finally {
      _isOpeningChannelSettings = false;
      print('✅ [ChannelSettings] Флаг _isOpeningChannelSettings сброшен');
    }
  }

  void _showWallpaperDialog() {
    showDialog(
      context: context,
      builder: (context) => _WallpaperSelectionDialog(
        chatId: widget.chatId,
        onImageSelected: (imagePath) {
          _setChatWallpaper(imagePath);
        },
        onRemoveWallpaper: () {
          _removeChatWallpaper();
        },
      ),
    );
  }

  void _showClearHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить историю?'),
        content: const Text(
          'Это действие удалит все сообщения в этом чате для вас. Другие участники по-прежнему смогут их видеть.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ApiService.instance
                  .clearChatHistory(widget.chatId)
                  .then((_) {
                    // ignore: invalid_use_of_protected_member
                    setState(() {
                      _messages.clear();
                      _chatItems.clear();
                    });
                    widget.onLastMessageChanged?.call(null);
                  })
                  .catchError((error) {
                    _showErrorSnackBar('Ошибка очистки истории');
                  });
            },
            child: const Text(
              'Очистить',
              style: TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteChatDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить чат?'),
        content: const Text(
          'Это действие удалит чат и всю историю сообщений без возможности восстановления.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ApiService.instance
                  .clearChatHistory(widget.chatId)
                  .then((_) {
                    widget.onChatRemoved?.call();
                    Navigator.of(context).pop();
                  })
                  .catchError((error) {
                    _showErrorSnackBar('Ошибка удаления чата');
                  });
            },
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showNotificationSettings() {
    showDialog(
      context: context,
      builder: (context) => ChatNotificationSettingsDialog(
        chatId: widget.chatId,
        chatName: _currentContact.name,
        isGroupChat: widget.isGroupChat,
        isChannel: widget.isChannel,
      ),
    );
  }

  void _showLeaveGroupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.isChannel ? 'Покинуть канал?' : 'Выйти из группы?'),
        content: Text(
          widget.isChannel
              ? 'Вы больше не будете получать сообщения из этого канала.'
              : 'Вы больше не будете участником этой группы.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                ApiService.instance.leaveGroup(widget.chatId);
                widget.onChatRemoved?.call();
                if (mounted) {
                  Navigator.of(context).pop();
                }
              } catch (error) {
                if (mounted) {
                  _showErrorSnackBar('Ошибка выхода');
                }
              }
            },
            child: Text(
              widget.isChannel ? 'Покинуть' : 'Выйти',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setChatWallpaper(String imagePath) async {
    try {
      final theme = context.read<ThemeProvider>();
      await theme.setChatSpecificWallpaper(widget.chatId, imagePath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка установки обоев: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 80, left: 8, right: 8),
          ),
        );
      }
    }
  }

  Future<void> _removeChatWallpaper() async {
    try {
      final theme = context.read<ThemeProvider>();
      await theme.setChatSpecificWallpaper(widget.chatId, null);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка удаления обоев: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 80, left: 8, right: 8),
          ),
        );
      }
    }
  }

  // Photo/File operations
  Future<void> _onAttachPressed() async {
    if (_isMobilePlatform) {
      if (!mounted) return;
      final colors = Theme.of(context).colorScheme;

      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: colors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: colors.outlineVariant,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const Text(
                    'Отправить вложение',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: colors.primary.withValues(
                              alpha: 0.10,
                            ),
                            foregroundColor: colors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 12,
                            ),
                          ),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Фото / видео'),
                          onPressed: () async {
                            final isEncryptionActive =
                                _encryptionConfigForCurrentChat != null &&
                                _encryptionConfigForCurrentChat!
                                    .password
                                    .isNotEmpty &&
                                _sendEncryptedForCurrentChat;
                            if (isEncryptionActive) {
                              Navigator.of(ctx).pop();
                              return;
                            }
                            Navigator.of(ctx).pop();
                            final result = await _pickPhotosFlow(context);
                            if (!mounted) return;
                            if (result != null && result.paths.isNotEmpty) {
                              await ApiService.instance.sendPhotoMessages(
                                widget.chatId,
                                localPaths: result.paths,
                                caption: result.caption,
                                senderId: _actualMyId,
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: colors.outlineVariant),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 12,
                            ),
                          ),
                          icon: const Icon(Icons.insert_drive_file_outlined),
                          label: const Text('Файл с устройства'),
                          onPressed: () async {
                            final isEncryptionActive =
                                _encryptionConfigForCurrentChat != null &&
                                _encryptionConfigForCurrentChat!
                                    .password
                                    .isNotEmpty &&
                                _sendEncryptedForCurrentChat;
                            if (isEncryptionActive) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Нельзя отправлять медиа при включенном шифровании',
                                    ),
                                    backgroundColor: Colors.orange,
                                    behavior: SnackBarBehavior.floating,
                                    margin: EdgeInsets.only(bottom: 80, left: 8, right: 8),
                                  ),
                                );
                              }
                              Navigator.of(ctx).pop();
                              return;
                            }
                            Navigator.of(ctx).pop();
                            await ApiService.instance.sendFileMessage(
                              widget.chatId,
                              senderId: _actualMyId,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: colors.outlineVariant),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 12,
                            ),
                          ),
                          icon: const Icon(Icons.person_outline),
                          label: const Text('Поделиться контактом'),
                          onPressed: () async {
                            Navigator.of(ctx).pop();
                            final selectedContact = await Navigator.of(context)
                                .push(
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const ContactSelectionScreen(),
                                  ),
                                );
                            if (selectedContact != null && mounted) {
                              await ApiService.instance.sendContactMessage(
                                widget.chatId,
                                contactId: selectedContact,
                                senderId: _actualMyId,
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: colors.outlineVariant),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 12,
                            ),
                          ),
                          icon: const Icon(Icons.auto_awesome_outlined),
                          label: const Text('Спецэффекты'),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _toggleKometSpecialMenu();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      'Скоро здесь появятся последние отправленные файлы.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else {
      final isEncryptionActive =
          _encryptionConfigForCurrentChat != null &&
          _encryptionConfigForCurrentChat!.password.isNotEmpty &&
          _sendEncryptedForCurrentChat;
      if (isEncryptionActive) {
        return;
      }
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Отправить вложение'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop('media'),
              child: const Row(
                children: [
                  Icon(Icons.photo_library_outlined),
                  SizedBox(width: 8),
                  Text('Фото / видео'),
                ],
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop('file'),
              child: const Row(
                children: [
                  Icon(Icons.insert_drive_file_outlined),
                  SizedBox(width: 8),
                  Text('Файл с устройства'),
                ],
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop('contact'),
              child: const Row(
                children: [
                  Icon(Icons.person_outline),
                  SizedBox(width: 8),
                  Text('Поделиться контактом'),
                ],
              ),
            ),
          ],
        ),
      );

      if (choice == 'media') {
        final result = await _pickPhotosFlow(context);
        if (result != null && result.paths.isNotEmpty) {
          await ApiService.instance.sendPhotoMessages(
            widget.chatId,
            localPaths: result.paths,
            caption: result.caption,
            senderId: _actualMyId,
          );
        }
      } else if (choice == 'file') {
        await ApiService.instance.sendFileMessage(
          widget.chatId,
          senderId: _actualMyId,
        );
      } else if (choice == 'contact') {
        final selectedContact = await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const ContactSelectionScreen(),
          ),
        );
        if (selectedContact != null && mounted) {
          await ApiService.instance.sendContactMessage(
            widget.chatId,
            contactId: selectedContact,
            senderId: _actualMyId,
          );
        }
      }
    }
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
                title: const Text('Выбрать фото из галереи'),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.video_library),
                title: const Text('Выбрать видео из галереи'),
                onTap: () => Navigator.pop(context, 'video'),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Сделать фото'),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: const Text('Снять видео'),
                onTap: () => Navigator.pop(context, 'camera_video'),
              ),
            ],
          ),
        ),
      );

      if (choice == null) return null;

      List<XFile>? pickedFiles;

      if (choice == 'gallery') {
        pickedFiles = await picker.pickMultiImage();
      } else if (choice == 'video') {
        final file = await picker.pickVideo(source: ImageSource.gallery);
        if (file != null) pickedFiles = [file];
      } else if (choice == 'camera') {
        final file = await picker.pickImage(source: ImageSource.camera);
        if (file != null) pickedFiles = [file];
      } else if (choice == 'camera_video') {
        final file = await picker.pickVideo(source: ImageSource.camera);
        if (file != null) pickedFiles = [file];
      }

      if (pickedFiles == null || pickedFiles.isEmpty) return null;

      final caption = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Добавить подпись?'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Подпись к фото (необязательно)',
            ),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Пропустить'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Добавить'),
            ),
          ],
        ),
      );

      return _PhotoPickerResult(
        paths: pickedFiles.map((f) => f.path).toList(),
        caption: caption,
      );
    } catch (e) {
      print('Ошибка выбора фото: $e');
      return null;
    }
  }
}
