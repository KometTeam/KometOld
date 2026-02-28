part of 'chat_screen.dart';

// ============================================================================
// АНИМАЦИИ
// ============================================================================

/// Анимация появления нового сообщения
class _NewMessageAnimation extends StatefulWidget {
  final Widget child;

  const _NewMessageAnimation({required this.child});

  @override
  State<_NewMessageAnimation> createState() => _NewMessageAnimationState();
}

class _NewMessageAnimationState extends State<_NewMessageAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _slideValue;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    _slideValue = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.translate(
            offset: Offset(0, 30 * _slideValue.value),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ============================================================================
// РАЗДЕЛИТЕЛИ И ЧИПЫ
// ============================================================================

/// Разделитель дат между сообщениями
class _DateSeparatorChip extends StatelessWidget {
  final DateTime date;
  const _DateSeparatorChip({required this.date});

  String _formatDate(DateTime localDate) {
    final now = DateTime.now();
    if (localDate.year == now.year &&
        localDate.month == now.month &&
        localDate.day == now.day) {
      return 'Сегодня';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (localDate.year == yesterday.year &&
        localDate.month == yesterday.month &&
        localDate.day == yesterday.day) {
      return 'Вчера';
    }
    return DateFormat.yMMMMd('ru').format(localDate);
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 400),
      tween: Tween<double>(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.scale(scale: 0.8 + (0.2 * value), child: child),
        );
      },
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _formatDate(date),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ФОНЫ И ОБОИ
// ============================================================================

/// Видео фон для чата
class _VideoWallpaperBackground extends StatefulWidget {
  final String videoPath;

  const _VideoWallpaperBackground({required this.videoPath});

  @override
  State<_VideoWallpaperBackground> createState() =>
      _VideoWallpaperBackgroundState();
}

class _VideoWallpaperBackgroundState extends State<_VideoWallpaperBackground> {
  VideoPlayerController? _controller;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      final file = File(widget.videoPath);
      if (!await file.exists()) {
        setState(() {
          _errorMessage = 'Video file not found';
        });
        print('ERROR: Video file does not exist: ${widget.videoPath}');
        return;
      }

      _controller = VideoPlayerController.file(file);
      await _controller!.initialize();

      if (mounted) {
        _controller!.setVolume(0);
        _controller!.setLooping(true);
        _controller!.play();
        setState(() {});
        print('SUCCESS: Video initialized and playing');
      }
    } catch (e) {
      print('ERROR initializing video: $e');
      setState(() {
        _errorMessage = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      print('ERROR building video widget: $_errorMessage');
      return Container(
        color: Colors.black,
        child: Center(
          child: Text(
            'Error loading video\n$_errorMessage',
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller!.value.size.width,
              height: _controller!.value.size.height,
              child: VideoPlayer(_controller!),
            ),
          ),
        ),
        Container(color: Colors.black.withValues(alpha: 0.3)),
      ],
    );
  }
}

// ============================================================================
// ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
// ============================================================================

/// Открывает профиль пользователя по ID

// ============================================================================
// ДОПОЛНИТЕЛЬНЫЕ ВИДЖЕТЫ ДЛЯ ПРОФИЛЕЙ
// ============================================================================

/// Диалог профиля группы (драгаемый bottom sheet)
class GroupProfileDraggableDialog extends StatelessWidget {
  final Contact contact;

  const GroupProfileDraggableDialog({super.key, required this.contact});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 1.0,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    ContactAvatarWidget(contactId: contact.id, radius: 50),
                    const SizedBox(height: 12),
                    Text(
                      contact.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (contact.description != null &&
                        contact.description!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        contact.description!,
                        style: TextStyle(color: colors.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('О группе'),
                      onTap: () {},
                    ),
                    ListTile(
                      leading: const Icon(Icons.people_outline),
                      title: const Text('Участники'),
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Диалог профиля контакта
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colors;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 20, color: colors.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      color: onTap != null ? colors.primary : colors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class ContactProfileDialog extends StatefulWidget {
  final Contact contact;
  final bool isChannel;
  final int? myId;
  final int? currentChatId;
  final String? chatLink;
  final int? participantsCount;
  final int? messagesCount;
  final String? accessType;
  final DateTime? createdAt;
  final DateTime? joinedAt;
  final bool? isOfficial;

  const ContactProfileDialog({
    super.key,
    required this.contact,
    this.isChannel = false,
    this.myId,
    this.currentChatId,
    this.chatLink,
    this.participantsCount,
    this.messagesCount,
    this.accessType,
    this.createdAt,
    this.joinedAt,
    this.isOfficial,
  });

  @override
  State<ContactProfileDialog> createState() => _ContactProfileDialogState();
}

class _ContactProfileDialogState extends State<ContactProfileDialog> {
  String? _localDescription;
  StreamSubscription? _changesSubscription;
  bool _isInContacts = false;
  bool _isAddingContact = false;

  // Drag state
  double _dragProgress = 0.0; // 0=collapsed, 1=expanded
  double _dragStartDy = 0.0;
  bool _isDragging = false;
  static const double _dragThreshold = 0.35;

  @override
  void initState() {
    super.initState();
    _loadLocalDescription();
    _checkIfInContacts();

    _changesSubscription = ContactLocalNamesService().changes.listen((
      contactId,
    ) {
      if (contactId == widget.contact.id && mounted) {
        _loadLocalDescription();
      }
    });
  }

  void _checkIfInContacts() {
    if (mounted) {
      setState(() => _isInContacts = ApiService.instance.isRealContact(widget.contact.id));
    }
  }

  Future<void> _handleAddToContacts(BuildContext context) async {
    if (_isAddingContact || _isInContacts) return;

    // Диалог выбора имени и фамилии
    final firstNameController = TextEditingController(
      text: widget.contact.firstName.isNotEmpty
          ? widget.contact.firstName
          : widget.contact.name.split(' ').first,
    );
    final lastNameController = TextEditingController(
      text: widget.contact.lastName.isNotEmpty
          ? widget.contact.lastName
          : (widget.contact.name.split(' ').length > 1
              ? widget.contact.name.split(' ').skip(1).join(' ')
              : ''),
    );

    // Валидация — запрещаем . , и спецсимволы
    final validChars = RegExp(r'^[a-zA-Zа-яА-ЯёЁ0-9\s\-_]+$');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить в контакты'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: firstNameController,
              decoration: const InputDecoration(
                labelText: 'Имя',
                hintText: 'Введите имя',
              ),
              textCapitalization: TextCapitalization.words,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'[.,;:!?@#$%^&*()\+=\[\]{}<>|/\\~`"' "'" r']')),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lastNameController,
              decoration: const InputDecoration(
                labelText: 'Фамилия',
                hintText: 'Введите фамилию (необязательно)',
              ),
              textCapitalization: TextCapitalization.words,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'[.,;:!?@#$%^&*()\+=\[\]{}<>|/\\~`"' "'" r']')),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final fn = firstNameController.text.trim();
              if (fn.isEmpty) return;
              if (fn.isNotEmpty && !validChars.hasMatch(fn)) return;
              final ln = lastNameController.text.trim();
              if (ln.isNotEmpty && !validChars.hasMatch(ln)) return;
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final firstName = firstNameController.text.trim();
    final lastName = lastNameController.text.trim();

    setState(() => _isAddingContact = true);

    try {
      // Сначала ADD
      await ApiService.instance.addContact(widget.contact.id);
      // Потом UPDATE с именем
      await ApiService.instance.updateContactName(
        widget.contact.id,
        firstName,
        lastName,
      );
      // Сохраняем имя локально — сразу обновится везде в UI
      await ContactLocalNamesService().saveContactData(widget.contact.id, {
        'firstName': firstName,
        'lastName': lastName,
        'name': '$firstName $lastName'.trim(),
      });
      if (mounted) {
        setState(() {
          _isInContacts = true;
          _isAddingContact = false;
        });
        ApiService.instance.addRealContact(widget.contact.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$firstName добавлен в контакты'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAddingContact = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _loadLocalDescription() async {
    final localData = ContactLocalNamesService().getContactData(
      widget.contact.id,
    );
    if (mounted) {
      setState(() {
        _localDescription = localData?['notes'] as String?;
      });
    }
  }

  @override
  void dispose() {
    _changesSubscription?.cancel();
    super.dispose();
  }

  Widget _buildExpandedContent(BuildContext context, ColorScheme colors) {
    final isGroupOrChannel = widget.contact.id < 0;

    if (isGroupOrChannel) {
      // Канал/группа — инфо
      final dateFormat = DateFormat('d MMM yyyy', 'ru');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Я не знаю как фиксить баг с инфо у каналов, пожалейте мои нервы, я мучаюсь вторую неделю.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),
          // Официальный
          if (widget.isOfficial == true) ...[  
            _InfoRow(
              icon: Icons.verified,
              label: 'Статус',
              value: 'Официальный канал',
              colors: colors,
            ),
            const SizedBox(height: 8),
          ],
          // Ссылка
          if (widget.chatLink != null && widget.chatLink!.isNotEmpty) ...[
            _InfoRow(
              icon: Icons.link,
              label: 'Ссылка',
              value: widget.chatLink!,
              colors: colors,
              onTap: () async {
                final url = Uri.tryParse(widget.chatLink!);
                if (url != null && await canLaunchUrl(url)) await launchUrl(url);
              },
              trailing: IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.chatLink!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ссылка скопирована'), behavior: SnackBarBehavior.floating),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
          // Участники
          if (widget.participantsCount != null && widget.participantsCount! > 0) ...[
            _InfoRow(
              icon: Icons.people,
              label: 'Участников',
              value: widget.participantsCount.toString(),
              colors: colors,
            ),
            const SizedBox(height: 8),
          ],
          // Сообщений
          if (widget.messagesCount != null && widget.messagesCount! > 0) ...[
            _InfoRow(
              icon: Icons.message,
              label: 'Сообщений',
              value: widget.messagesCount.toString(),
              colors: colors,
            ),
            const SizedBox(height: 8),
          ],
          // Тип доступа
          if (widget.accessType != null) ...[
            _InfoRow(
              icon: widget.accessType == 'PUBLIC' ? Icons.public : Icons.lock,
              label: 'Тип',
              value: widget.accessType == 'PUBLIC' ? 'Публичный' : 'Приватный',
              colors: colors,
            ),
            const SizedBox(height: 8),
          ],
          // Дата создания
          if (widget.createdAt != null) ...[  
            _InfoRow(
              icon: Icons.calendar_today,
              label: 'Создан',
              value: dateFormat.format(widget.createdAt!),
              colors: colors,
            ),
            const SizedBox(height: 8),
          ],
          // Дата вступления
          if (widget.joinedAt != null) ...[  
            _InfoRow(
              icon: Icons.login,
              label: 'Вы вступили',
              value: dateFormat.format(widget.joinedAt!),
              colors: colors,
            ),
            const SizedBox(height: 8),
          ],
        ],
      );
    }

    // Личный чат — кнопка контакта
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isAddingContact)
          const Center(child: CircularProgressIndicator())
        else if (_isInContacts)
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.surfaceContainerHighest,
                    foregroundColor: colors.onSurfaceVariant,
                  ),
                  onPressed: null,
                  icon: const Icon(Icons.check),
                  label: const Text('У вас в контактах'),
                ),
              ),
              const SizedBox(width: 8),
              // Кнопка переименовать
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: colors.secondaryContainer,
                  foregroundColor: colors.onSecondaryContainer,
                ),
                icon: const Icon(Icons.edit),
                onPressed: () => _handleRenameContact(context),
                tooltip: 'Переименовать',
              ),
            ],
          )
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _handleAddToContacts(context),
              icon: const Icon(Icons.person_add),
              label: const Text('Добавить в контакты'),
            ),
          ),
      ],
    );
  }

  Future<void> _handleRenameContact(BuildContext context) async {
    final localData = ContactLocalNamesService().getContactData(widget.contact.id);
    final firstNameController = TextEditingController(
      text: localData?['firstName'] as String? ?? widget.contact.firstName,
    );
    final lastNameController = TextEditingController(
      text: localData?['lastName'] as String? ?? widget.contact.lastName,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Переименовать контакт'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: firstNameController,
              decoration: const InputDecoration(labelText: 'Имя'),
              textCapitalization: TextCapitalization.words,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'[.,;:!?@#$%^&*()\+=\[\]{}<>|/\\~`"' "'" r']')),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lastNameController,
              decoration: const InputDecoration(labelText: 'Фамилия'),
              textCapitalization: TextCapitalization.words,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'[.,;:!?@#$%^&*()\+=\[\]{}<>|/\\~`"' "'" r']')),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (firstNameController.text.trim().isEmpty) return;
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final firstName = firstNameController.text.trim();
    final lastName = lastNameController.text.trim();

    try {
      await ApiService.instance.updateContactName(widget.contact.id, firstName, lastName);
      await ContactLocalNamesService().saveContactData(widget.contact.id, {
        'firstName': firstName,
        'lastName': lastName,
        'name': '$firstName $lastName'.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Имя обновлено'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  void _onPanStart(DragStartDetails details) {
    _dragStartDy = details.globalPosition.dy;
    _isDragging = true;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    final screenHeight = MediaQuery.of(context).size.height;
    final delta = _dragStartDy - details.globalPosition.dy;
    // Только вверх — игнорируем drag вниз (его перехватывает dismiss)
    if (delta < 0 && _dragProgress == 0.0) return;
    final progress = ((_dragProgress * screenHeight * 0.8 + details.delta.dy * -1) / (screenHeight * 0.8)).clamp(0.0, 1.0);
    setState(() => _dragProgress = progress);
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
      _dragProgress = _dragProgress >= _dragThreshold ? 1.0 : 0.0;
    });
  }

  void _openChatWithContact(BuildContext context) async {
    try {
      final chatId = await ApiService.instance.getChatIdByUserId(
        widget.contact.id,
      );
      if (chatId == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не удалось найти чат с пользователем'),
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.only(bottom: 80, left: 8, right: 8),
            ),
          );
        }
        return;
      }

      if (!context.mounted) return;

      // Закрываем диалог профиля
      Navigator.of(context).pop();

      // Открываем чат
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => ChatScreen(
            chatId: chatId,
            pinnedMessage: null,
            contact: widget.contact,
            myId: widget.myId ?? 0,
            isGroupChat: false,
            isChannel: false,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(
          content: Text('Ошибка: $e'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 8, right: 8),
        ));
      }
    }
  }

  /// Открывает группу или канал
  void _openGroupOrChannel(BuildContext context) {
    // Закрываем диалог профиля
    Navigator.of(context).pop();

    // Открываем группу/канал напрямую
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => ChatScreen(
          chatId: widget.contact.id,
          pinnedMessage: null,
          contact: widget.contact,
          myId: widget.myId ?? 0,
          isGroupChat: widget.contact.id < 0 && !widget.isChannel,
          isChannel: widget.isChannel,
        ),
      ),
    );
  }

  void _openChannelInfo(BuildContext context) async {
    Navigator.of(context).pop(); // Закрываем профиль

    // Показываем индикатор загрузки
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final channelDetails = await ApiService.instance.getChannelDetails(
        widget.contact.id,
      );

      if (!context.mounted) return;
      Navigator.of(context).pop(); // Закрываем индикатор загрузки

      if (channelDetails == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось загрузить данные канала'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(bottom: 80, left: 8, right: 8),
          ),
        );
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ChannelSettingsScreen(
            chatId: widget.contact.id,
            channelData: channelDetails,
            myId: widget.myId ?? 0,
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // Закрываем индикатор загрузки
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: $e'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 8, right: 8),
        ),
      );
    }
  }

  /// Строит кнопки действий в зависимости от типа контакта
  Widget _buildActionButtons(BuildContext context, ColorScheme colors) {
    final isGroupOrChannel = widget.contact.id < 0;

    if (isGroupOrChannel) {
      return const SizedBox.shrink();
    }

    // Для личных чатов
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ProfileActionButton(
          icon: Icons.message,
          label: 'Написать',
          onPressed: () => _openChatWithContact(context),
          colors: colors,
        ),
        _ProfileActionButton(
          icon: Icons.call,
          label: 'Позвонить',
          onPressed: () {},
          colors: colors,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final String nickname = getContactDisplayName(
      contactId: widget.contact.id,
      originalName: widget.contact.name,
      originalFirstName: widget.contact.firstName,
      originalLastName: widget.contact.lastName,
    );
    final String description =
        (_localDescription != null && _localDescription!.isNotEmpty)
        ? _localDescription!
        : (widget.contact.description ?? '');

    final theme = context.watch<ThemeProvider>();
    final t = _dragProgress;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    // Высота панели: от минимальной до полного экрана
    final double panelMinHeight = 220.0;
    final double panelMaxHeight = screenHeight;
    final double panelHeight = panelMinHeight + (panelMaxHeight - panelMinHeight) * t;

    // Аватарка: ВСЕГДА в Stack поверх всего, позиция и размер интерполируются
    // t=0: круг 192×192, центр = центр верхней зоны (над панелью)
    // t=1: прямоугольник screenWidth × screenHeight*0.5, top=0
    final double avatarCollapsedSize = 192.0;
    final double avatarExpandedH = screenHeight * 0.52;

    // Размеры
    final double avatarW = avatarCollapsedSize + (screenWidth - avatarCollapsedSize) * t;
    final double avatarH = avatarCollapsedSize + (avatarExpandedH - avatarCollapsedSize) * t;

    // Позиция: центр аватарки в верхней зоне → top:0 left:0
    final double aboveHeight = screenHeight - panelMinHeight; // фиксированная верхняя зона при t=0
    final double centerY0 = aboveHeight / 2; // центр Y при t=0
    final double topAt0 = centerY0 - avatarCollapsedSize / 2;
    final double topAt1 = 0.0;
    final double leftAt0 = (screenWidth - avatarCollapsedSize) / 2;
    final double leftAt1 = 0.0;

    final double avatarTop = topAt0 + (topAt1 - topAt0) * t;
    final double avatarLeft = leftAt0 + (leftAt1 - leftAt0) * t;

    // borderRadius: 96 → 0
    final double avatarBR = 96.0 * (1.0 - t);

    // Кнопки и ник в шапке панели исчезают
    final double buttonsOpacity = (1.0 - t * 2.5).clamp(0.0, 1.0);
    final double nameOpacity = (1.0 - t * 2.0).clamp(0.0, 1.0);
    // Ник поверх аватарки появляется
    final double nameOnAvatarOpacity = ((t - 0.4) * 3.0).clamp(0.0, 1.0);

    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Stack(
          children: [
            // Blur фон
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: theme.profileDialogBlur,
                    sigmaY: theme.profileDialogBlur,
                  ),
                  child: Container(
                    color: Colors.black.withValues(
                      alpha: theme.profileDialogOpacity,
                    ),
                  ),
                ),
              ),
            ),

            // Нижняя панель рендерится раньше — аватарка поверх неё
            // (порядок в Stack важен — аватарка ниже в коде = поверх панели)
            // Аватарка — ОДНА, абсолютная позиция, морфирует плавно
            Positioned(
              top: avatarTop,
              left: avatarLeft,
              width: avatarW,
              height: avatarH,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(avatarBR),
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: ContactAvatarWidget(
                    contactId: widget.contact.id,
                    originalAvatarUrl: widget.contact.photoBaseUrl,
                    radius: 96,
                    fallbackText: widget.contact.name.isNotEmpty
                        ? widget.contact.name[0].toUpperCase()
                        : '?',
                  ),
                ),
              ),
            ),

            // Ник поверх аватарки (снизу слева)
            if (nameOnAvatarOpacity > 0)
              Positioned(
                top: avatarTop,
                left: avatarLeft,
                width: avatarW,
                height: avatarH,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: nameOnAvatarOpacity,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.75),
                            ],
                          ),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 40, 16, 14),
                        child: Text(
                          nickname,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Нижняя панель
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedContainer(
                duration: _isDragging
                    ? Duration.zero
                    : const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                height: panelHeight,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24 * (1.0 - t * 2).clamp(0.0, 1.0)),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, -8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Заголовок: ник + крестик
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Opacity(
                              opacity: nameOpacity,
                              child: Text(
                                nickname,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    if (description.isNotEmpty && buttonsOpacity > 0)
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: Opacity(
                            opacity: buttonsOpacity,
                            child: SingleChildScrollView(
                              child: Linkify(
                                text: description,
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 14,
                                ),
                                onOpen: (link) async {
                                  final url = Uri.tryParse(link.url);
                                  if (url != null && await canLaunchUrl(url)) {
                                    await launchUrl(url);
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (buttonsOpacity > 0) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Opacity(
                          opacity: buttonsOpacity,
                          child: _buildActionButtons(context, colors),
                        ),
                      ),
                    ],
                    // Развёрнутая панель — доп. контент
                    if (t > 0.5) ...[
                      SizedBox(height: 16 * ((t - 0.5) * 2).clamp(0.0, 1.0)),
                      Opacity(
                        opacity: ((t - 0.5) * 2).clamp(0.0, 1.0),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _buildExpandedContent(context, colors),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Вспомогательный виджет для кнопки действия в профиле
class _ProfileActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final ColorScheme colors;

  const _ProfileActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(icon, color: colors.primary),
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

// Bot Commands Panel
class _BotCommandsPanel extends StatelessWidget {
  final bool isLoading;
  final List<BotCommand> commands;
  final ValueChanged<BotCommand> onCommandTap;

  const _BotCommandsPanel({
    required this.isLoading,
    required this.commands,
    required this.onCommandTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 140),
        child: isLoading
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Загрузка команд…',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              )
            : (commands.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: Text('Нет доступных команд')),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(4),
                      itemCount: commands.length,
                      itemBuilder: (context, index) {
                        final cmd = commands[index];
                        return InkWell(
                          onTap: () => onCommandTap(cmd),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: cmd.slashCommand,
                                    style: TextStyle(
                                      color: colors.onSurface,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (cmd.description.isNotEmpty)
                                    TextSpan(
                                      text: ' ${cmd.description}',
                                      style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                        fontSize: 13,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    )),
      ),
    );
  }
}

// Komet Color Picker Bar

// Send Photos Dialog
class _SendPhotosDialog extends StatefulWidget {
  final List<XFile> images;

  const _SendPhotosDialog({required this.images});

  @override
  State<_SendPhotosDialog> createState() => _SendPhotosDialogState();
}

class _SendPhotosDialogState extends State<_SendPhotosDialog> {
  final TextEditingController _captionController = TextEditingController();

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Отправить ${widget.images.length} фото'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: widget.images.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.all(4),
                  child: Image.file(
                    File(widget.images[index].path),
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _captionController,
            decoration: const InputDecoration(
              labelText: 'Подпись',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(
              context,
              _PhotoPickerResult(
                paths: widget.images.map((e) => e.path).toList(),
                caption: _captionController.text.isEmpty
                    ? null
                    : _captionController.text,
              ),
            );
          },
          child: const Text('Отправить'),
        ),
      ],
    );
  }
}

// Wallpaper Selection Dialog
class _WallpaperSelectionDialog extends StatefulWidget {
  final int chatId;
  final Function(String) onImageSelected;
  final VoidCallback onRemoveWallpaper;

  const _WallpaperSelectionDialog({
    required this.chatId,
    required this.onImageSelected,
    required this.onRemoveWallpaper,
  });

  @override
  State<_WallpaperSelectionDialog> createState() =>
      _WallpaperSelectionDialogState();
}

class _WallpaperSelectionDialogState extends State<_WallpaperSelectionDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Выбрать обои'),
      content: const Text('Функция выбора обоев будет реализована позже'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}

// Mention Dropdown Panel
class _MentionDropdownPanel extends StatelessWidget {
  final List<Contact> users;
  final Function(Contact) onUserSelected;

  const _MentionDropdownPanel({
    required this.users,
    required this.onUserSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withAlpha(50),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: colors.outlineVariant, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onUserSelected(user),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      ContactAvatarWidget(
                        contactId: user.id,
                        originalAvatarUrl: user.photoBaseUrl,
                        radius: 16,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              getContactDisplayName(
                                contactId: user.id,
                                originalName: user.name,
                                originalFirstName: user.firstName,
                                originalLastName: user.lastName,
                              ),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (user.description?.isNotEmpty == true)
                              Text(
                                user.description!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// Edit Message Dialog
class _EditMessageDialog extends StatefulWidget {
  final String initialText;
  final Function(String) onSave;

  const _EditMessageDialog({required this.initialText, required this.onSave});

  @override
  State<_EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<_EditMessageDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Редактировать сообщение'),
      content: TextField(
        controller: _controller,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'Введите текст сообщения',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () {
            widget.onSave(_controller.text);
            Navigator.pop(context);
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

// Fake Waveform Widget
class _FakeWaveform extends StatefulWidget {
  const _FakeWaveform();

  @override
  State<_FakeWaveform> createState() => _FakeWaveformState();
}

class _FakeWaveformState extends State<_FakeWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _phase;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _phase = CurvedAnimation(parent: _controller, curve: Curves.linear);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _phase,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(16, (i) {
            final t = (_phase.value * 2 * pi) + (i * 0.55);
            final h = 6.0 + 16.0 * (0.5 + 0.5 * sin(t));
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Container(
                width: 3,
                height: h,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// Contact Presence Subtitle Widget
class _ContactPresenceSubtitle extends StatefulWidget {
  final int chatId;
  final int userId;

  const _ContactPresenceSubtitle({required this.chatId, required this.userId});

  @override
  State<_ContactPresenceSubtitle> createState() =>
      _ContactPresenceSubtitleState();
}

class _ContactPresenceSubtitleState extends State<_ContactPresenceSubtitle> {
  String _status = 'был(а) недавно';
  Timer? _typingDecayTimer;
  bool _isOnline = false;
  DateTime? _lastSeen;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();

    final lastSeen = ApiService.instance.getLastSeen(widget.userId);
    if (lastSeen != null) {
      _lastSeen = lastSeen;
      _status = _formatLastSeen(_lastSeen);
    }

    _sub = ApiService.instance.messages.listen((msg) {
      try {
        final int? opcode = msg['opcode'];
        final payload = msg['payload'];
        if (payload is! Map<String, dynamic>) return;
        if (opcode == 129) {
          final dynamic incomingChatId = payload['chatId'];
          final int? cid = incomingChatId is int
              ? incomingChatId
              : int.tryParse(incomingChatId?.toString() ?? '');
          if (cid == widget.chatId) {
            Future.microtask(() {
              if (mounted) {
                setState(() => _status = 'печатает…');
              }
            });
            _typingDecayTimer?.cancel();
            _typingDecayTimer = Timer(const Duration(seconds: 11), () {
              if (!mounted) return;
              if (_status == 'печатает…') {
                Future.microtask(() {
                  if (mounted) {
                    setState(() {
                      if (_isOnline) {
                        _status = 'онлайн';
                      } else {
                        _status = _formatLastSeen(_lastSeen);
                      }
                    });
                  }
                });
              }
            });
          }
        } else if (opcode == 132) {
          final dynamic incomingChatId = payload['chatId'];
          final int? cid = incomingChatId is int
              ? incomingChatId
              : int.tryParse(incomingChatId?.toString() ?? '');
          if (cid == widget.chatId) {
            final bool isOnline = payload['online'] == true;
            if (!mounted) return;
            _isOnline = isOnline;

            Future.microtask(() {
              if (mounted) {
                setState(() {
                  if (_status != 'печатает…') {
                    if (_isOnline) {
                      _status = 'онлайн';
                    } else {
                      final updatedLastSeen = ApiService.instance.getLastSeen(
                        widget.userId,
                      );
                      if (updatedLastSeen != null) {
                        _lastSeen = updatedLastSeen;
                      } else {
                        _lastSeen = DateTime.now();
                      }
                      _status = _formatLastSeen(_lastSeen);
                    }
                  }
                });
              }
            });
          }
        }
      } catch (e) {
        print('⚠️ Ошибка обработки статуса онлайн: $e');
      }
    });
  }

  String _formatLastSeen(DateTime? lastSeen) {
    if (lastSeen == null) return 'был(а) недавно';

    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    String timeAgo;
    if (difference.inMinutes < 1) {
      timeAgo = 'только что';
    } else if (difference.inMinutes < 60) {
      timeAgo = '${difference.inMinutes} мин. назад';
    } else if (difference.inHours < 24) {
      timeAgo = '${difference.inHours} ч. назад';
    } else if (difference.inDays < 7) {
      timeAgo = '${difference.inDays} дн. назад';
    } else {
      final day = lastSeen.day.toString().padLeft(2, '0');
      final month = lastSeen.month.toString().padLeft(2, '0');
      timeAgo = '$day.$month.${lastSeen.year}';
    }

    if (ChatDebugSettings.showExactDate) {
      final formatter = DateFormat('dd.MM.yyyy HH:mm:ss');
      return '$timeAgo (${formatter.format(lastSeen)})';
    }

    return timeAgo;
  }

  @override
  void dispose() {
    _typingDecayTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _status,
      style: TextStyle(
        fontSize: 13,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _KometSpecialMenu extends StatelessWidget {
  final Function(String) onItemSelected;

  const _KometSpecialMenu({required this.onItemSelected});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildBtn(
            context,
            Icons.color_lens_outlined,
            'Цветной текст',
            'komet.color_#',
          ),
          _buildBtn(
            context,
            Icons.animation,
            'Пульсация',
            'komet.cosmetic.pulse#',
          ),
          _buildBtn(
            context,
            Icons.stars,
            'Галактика',
            "komet.cosmetic.galaxy''",
          ),
        ],
      ),
    );
  }

  Widget _buildBtn(
    BuildContext context,
    IconData icon,
    String tooltip,
    String val,
  ) {
    return IconButton(
      icon: Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
      onPressed: () => onItemSelected(val),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    );
  }
}

