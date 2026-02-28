import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gwid/widgets/contact_name_widget.dart';
import 'package:gwid/widgets/contact_avatar_widget.dart';
import 'package:gwid/services/contact_local_names_service.dart';
import 'package:gwid/api/api_service.dart';
import 'package:gwid/models/contact.dart';
import 'package:gwid/screens/chat_screen.dart';

class UserProfilePanel extends StatefulWidget {
  final int userId;
  final String? name;
  final String? firstName;
  final String? lastName;
  final String? avatarUrl;
  final String? description;
  final int myId;
  final int? currentChatId;
  final Map<String, dynamic>? contactData;
  final int? dialogChatId;

  const UserProfilePanel({
    super.key,
    required this.userId,
    this.name,
    this.firstName,
    this.lastName,
    this.avatarUrl,
    this.description,
    required this.myId,
    this.currentChatId,
    this.contactData,
    this.dialogChatId,
  });

  @override
  State<UserProfilePanel> createState() => _UserProfilePanelState();
}

class _UserProfilePanelState extends State<UserProfilePanel>
    with TickerProviderStateMixin {
  final ScrollController _nameScrollController = ScrollController();
  String? _localDescription;
  StreamSubscription? _changesSubscription;
  StreamSubscription? _wsSubscription;
  bool _isOpeningChat = false;
  bool _isInContacts = false;
  bool _isAddingToContacts = false;

  // Drag state
  double _dragProgress = 0.0; // 0.0 = collapsed, 1.0 = expanded
  double _dragStartDy = 0.0;
  double _currentDy = 0.0;
  bool _isDragging = false;

  // Constants
  static const double _avatarRadius = 40.0;
  static const double _expandedSquareSize = 200.0;
  static const double _dragThreshold = 0.4;

  String get _displayName {
    return getContactDisplayName(
      contactId: widget.userId,
      originalName: widget.name,
      originalFirstName: widget.firstName,
      originalLastName: widget.lastName,
    );
  }

  String? get _displayDescription {
    if (_localDescription != null && _localDescription!.isNotEmpty) {
      return _localDescription;
    }
    return widget.description;
  }

  @override
  void initState() {
    super.initState();
    _loadLocalDescription();
    _checkIfInContacts();

    _changesSubscription = ContactLocalNamesService().changes.listen((
      contactId,
    ) {
      if (contactId == widget.userId && mounted) {
        _loadLocalDescription();
        _checkIfInContacts();
      }
    });

    _wsSubscription = ApiService.instance.messages.listen((msg) {
      try {
        if (msg['opcode'] == 34 &&
            msg['cmd'] == 1 &&
            msg['payload'] != null &&
            msg['payload']['contact'] != null) {
          final contactJson = msg['payload']['contact'] as Map<String, dynamic>;
          final id = contactJson['id'] as int?;
          if (id == widget.userId && mounted) {
            final contact = Contact.fromJson(contactJson);
            ApiService.instance.updateContactCache([contact]);
            setState(() {
              _isInContacts = true;
            });
          }
        }
      } catch (e) {
        // ignore
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkNameLength();
    });
  }

  Future<void> _checkIfInContacts() async {
    final cached = ApiService.instance.getCachedContact(widget.userId);
    if (mounted) {
      setState(() {
        _isInContacts = cached != null;
      });
    }
  }

  Future<void> _loadLocalDescription() async {
    final localData = ContactLocalNamesService().getContactData(widget.userId);
    if (mounted) {
      setState(() {
        _localDescription = localData?['notes'] as String?;
      });
    }
  }

  @override
  void dispose() {
    _changesSubscription?.cancel();
    _wsSubscription?.cancel();
    _nameScrollController.dispose();
    super.dispose();
  }

  void _checkNameLength() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_nameScrollController.hasClients) {
        final maxScroll = _nameScrollController.position.maxScrollExtent;
        if (maxScroll > 0) {
          _startNameScroll();
        }
      }
    });
  }

  void _startNameScroll() {
    if (!_nameScrollController.hasClients) return;
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted || !_nameScrollController.hasClients) return;
      _nameScrollController
          .animateTo(
            _nameScrollController.position.maxScrollExtent,
            duration: const Duration(seconds: 3),
            curve: Curves.easeInOut,
          )
          .then((_) {
            if (!mounted) return;
            Future.delayed(const Duration(seconds: 1), () {
              if (!mounted || !_nameScrollController.hasClients) return;
              _nameScrollController
                  .animateTo(
                    0,
                    duration: const Duration(seconds: 3),
                    curve: Curves.easeInOut,
                  )
                  .then((_) {
                    if (mounted) {
                      Future.delayed(const Duration(seconds: 2), () {
                        if (mounted) _startNameScroll();
                      });
                    }
                  });
            });
          });
    });
  }

  void _onDragStart(DragStartDetails details) {
    _dragStartDy = details.globalPosition.dy;
    _currentDy = 0.0;
    _isDragging = true;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    final screenHeight = MediaQuery.of(context).size.height;
    final delta = _dragStartDy - details.globalPosition.dy;
    _currentDy = delta;
    // Максимальный drag = 60% высоты экрана
    final maxDrag = screenHeight * 0.6;
    final progress = (_currentDy / maxDrag).clamp(0.0, 1.0);
    setState(() {
      _dragProgress = progress;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    // Сначала сбрасываем _isDragging чтобы AnimatedContainer использовал duration
    setState(() {
      _isDragging = false;
      // Если отпустили больше порога — snap to expanded, иначе collapse
      if (_dragProgress >= _dragThreshold) {
        _dragProgress = 1.0;
      } else {
        _dragProgress = 0.0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final t = _dragProgress; // 0..1
    final screenHeight = MediaQuery.of(context).size.height;

    // Интерполяция размеров аватарки
    final avatarSize = _avatarRadius * 2 + (_expandedSquareSize - _avatarRadius * 2) * t;
    // borderRadius: от 50% (круг) до 16px (квадрат)
    final avatarBorderRadius = _avatarRadius * (1.0 - t) + 16.0 * t;
    // Кнопки прозрачность
    final buttonsOpacity = (1.0 - t * 2.5).clamp(0.0, 1.0);
    // Ник под аватаркой (исчезает быстро)
    final nameOpacityCenter = (1.0 - t * 3.0).clamp(0.0, 1.0);
    // Ник поверх квадрата (появляется когда t > 0.4)
    final nameOnImageOpacity = ((t - 0.4) * 3.0).clamp(0.0, 1.0);

    // Минимальная высота панели = её естественная высота (approx 300)
    // Максимальная = 70% экрана
    final minHeight = 0.0;
    final maxHeight = screenHeight * 0.70;
    final panelHeight = t > 0 ? (minHeight + (maxHeight - minHeight) * t) : null;

    return GestureDetector(
      onPanStart: _onDragStart,
      onPanUpdate: _onDragUpdate,
      onPanEnd: _onDragEnd,
      child: AnimatedContainer(
        duration: _isDragging ? Duration.zero : const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        height: panelHeight,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: t > 0 ? MainAxisSize.max : MainAxisSize.min,
          children: [
            // Drag handle + expand button
            GestureDetector(
              onTap: () {
                setState(() {
                  _isDragging = false;
                  _dragProgress = _dragProgress > 0.5 ? 0.0 : 1.0;
                });
              },
              child: Container(
                color: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      t > 0.5 ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                      size: 20,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, t > 0 ? 8 : 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Аватарка-квадрат с ником поверх
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Аватарка (морфируется)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(avatarBorderRadius),
                        child: SizedBox(
                          width: avatarSize,
                          height: avatarSize,
                          child: ContactAvatarWidget(
                            contactId: widget.userId,
                            originalAvatarUrl: widget.avatarUrl,
                            radius: avatarSize / 2,
                            fallbackText: _displayName.isNotEmpty
                                ? _displayName[0].toUpperCase()
                                : '?',
                            backgroundColor: colors.primaryContainer,
                            textColor: colors.onPrimaryContainer,
                          ),
                        ),
                      ),
                      // Ник поверх квадрата (появляется при оттягивании)
                      if (nameOnImageOpacity > 0)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Opacity(
                            opacity: nameOnImageOpacity,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.7),
                                  ],
                                ),
                                borderRadius: BorderRadius.only(
                                  bottomLeft: Radius.circular(avatarBorderRadius),
                                  bottomRight: Radius.circular(avatarBorderRadius),
                                ),
                              ),
                              padding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                              child: Align(
                                alignment: Alignment.bottomLeft,
                                child: Text(
                                  _displayName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),

                  // Ник под аватаркой (исчезает при оттягивании)
                  if (nameOpacityCenter > 0) ...[
                    SizedBox(height: 16 * (1.0 - t)),
                    Opacity(
                      opacity: nameOpacityCenter,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final textPainter = TextPainter(
                            text: TextSpan(
                              text: _displayName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            maxLines: 1,
                            textDirection: TextDirection.ltr,
                          );
                          textPainter.layout();
                          final textWidth = textPainter.size.width;
                          final needsScroll = textWidth > constraints.maxWidth;

                          if (needsScroll) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _checkNameLength();
                            });
                            return SizedBox(
                              height: 28,
                              child: SingleChildScrollView(
                                controller: _nameScrollController,
                                scrollDirection: Axis.horizontal,
                                physics: const NeverScrollableScrollPhysics(),
                                child: Text(
                                  _displayName,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          } else {
                            return Text(
                              _displayName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            );
                          }
                        },
                      ),
                    ),
                  ],

                  // Кнопки (исчезают при оттягивании)
                  if (buttonsOpacity > 0) ...[
                    SizedBox(height: 24 * (1.0 - t * 2).clamp(0.0, 1.0)),
                    Opacity(
                      opacity: buttonsOpacity,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: _buildActionButtons(colors),
                      ),
                    ),
                  ],

                  if (_displayDescription != null &&
                      _displayDescription!.isNotEmpty &&
                      buttonsOpacity > 0) ...[
                    SizedBox(height: 24 * buttonsOpacity),
                    Opacity(
                      opacity: buttonsOpacity,
                      child: Text(
                        _displayDescription!,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  SizedBox(height: MediaQuery.of(context).padding.bottom),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required ColorScheme colors,
    bool isLoading = false,
  }) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: isLoading
              ? Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                    ),
                  ),
                )
              : IconButton(
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

  Future<void> _handleWriteMessage() async {
    if (_isOpeningChat) return;
    setState(() => _isOpeningChat = true);
    try {
      int? chatId = widget.dialogChatId;
      if (chatId == null || chatId == 0) {
        chatId = await ApiService.instance.getChatIdByUserId(widget.userId);
      }
      if (chatId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не удалось открыть чат с пользователем'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => ChatScreen(
            chatId: chatId!,
            pinnedMessage: null,
            contact: Contact(
              id: widget.userId,
              name: widget.name ?? _displayName,
              firstName: widget.firstName ?? '',
              lastName: widget.lastName ?? '',
              description: widget.description,
              photoBaseUrl: widget.avatarUrl,
              accountStatus: 0,
              status: null,
              options: const [],
            ),
            myId: widget.myId,
            isGroupChat: false,
            isChannel: false,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при открытии чата: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isOpeningChat = false);
    }
  }

  Future<void> _handleOpenExistingChat() async {
    if (_isOpeningChat) return;
    final chatId = widget.dialogChatId;
    if (chatId == null || chatId == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Чат не найден'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _isOpeningChat = true);
    try {
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => ChatScreen(
            chatId: chatId,
            pinnedMessage: null,
            contact: Contact(
              id: widget.userId,
              name: widget.name ?? _displayName,
              firstName: widget.firstName ?? '',
              lastName: widget.lastName ?? '',
              description: widget.description,
              photoBaseUrl: widget.avatarUrl,
              accountStatus: 0,
              status: null,
              options: const [],
            ),
            myId: widget.myId,
            isGroupChat: false,
            isChannel: false,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при открытии чата: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isOpeningChat = false);
    }
  }

  Future<void> _handleAddToContacts() async {
    if (_isAddingToContacts || _isInContacts) return;
    setState(() => _isAddingToContacts = true);
    try {
      await ApiService.instance.addContact(widget.userId);
      await ApiService.instance.requestContactsByIds([widget.userId]);
      await _checkIfInContacts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Запрос на добавление в контакты отправлен'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при добавлении в контакты: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAddingToContacts = false);
    }
  }

  List<Widget> _buildActionButtons(ColorScheme colors) {
    final isGroupOrChannel = widget.userId < 0;

    if (isGroupOrChannel) {
      final bool isChannel = (widget.contactData != null &&
              (widget.contactData!['type']?.toString().toUpperCase() ==
                  'CHANNEL')) ||
          false;
      return [
        _buildActionButton(
          icon: isChannel ? Icons.newspaper : Icons.group,
          label: isChannel ? 'Открыть канал' : 'Открыть группу',
          onPressed: _isOpeningChat ? null : _handleOpenGroupOrChannel,
          colors: colors,
          isLoading: _isOpeningChat,
        ),
        _buildActionButton(
          icon: Icons.share,
          label: 'Поделиться',
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Скоро будет доступно'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          colors: colors,
        ),
      ];
    }

    final buttons = <Widget>[
      _buildActionButton(
        icon: Icons.phone,
        label: 'Позвонить',
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Звонков пока нету'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        colors: colors,
      ),
    ];

    if (widget.userId >= 0) {
      buttons.add(
        _buildActionButton(
          icon: Icons.person_add,
          label: _isInContacts ? 'В контактах' : 'В контакты',
          onPressed: _isInContacts || _isAddingToContacts
              ? null
              : _handleAddToContacts,
          colors: colors,
          isLoading: _isAddingToContacts,
        ),
      );

      if (widget.dialogChatId != null && widget.dialogChatId! > 0) {
        buttons.add(
          _buildActionButton(
            icon: Icons.chat,
            label: 'Открыть чат',
            onPressed: _isOpeningChat ? null : _handleOpenExistingChat,
            colors: colors,
            isLoading: _isOpeningChat,
          ),
        );
      } else {
        buttons.add(
          _buildActionButton(
            icon: Icons.message,
            label: 'Написать',
            onPressed: _isOpeningChat ? null : _handleWriteMessage,
            colors: colors,
            isLoading: _isOpeningChat,
          ),
        );
      }
    }

    return buttons;
  }

  Future<void> _handleOpenGroupOrChannel() async {
    if (_isOpeningChat) return;
    setState(() => _isOpeningChat = true);
    try {
      final chatId = widget.userId;
      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => ChatScreen(
            chatId: chatId,
            pinnedMessage: null,
            contact: Contact(
              id: widget.userId,
              name: widget.name ?? _displayName,
              firstName: '',
              lastName: '',
              description: widget.description,
              photoBaseUrl: widget.avatarUrl,
              accountStatus: 0,
              status: null,
              options: const [],
            ),
            myId: widget.myId,
            isGroupChat: chatId < 0,
            isChannel: false,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при открытии: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isOpeningChat = false);
    }
  }
}
