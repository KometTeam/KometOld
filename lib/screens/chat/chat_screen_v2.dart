import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/contact.dart';
import '../../models/message.dart';
import '../../widgets/contact_name_widget.dart';
import '../../widgets/contact_avatar_widget.dart';
import 'controllers/chat_controller.dart';
import 'controllers/chat_input_controller.dart';
import 'widgets/chat_message_list.dart';
import 'widgets/input/chat_input_bar.dart';
import '../../utils/theme_provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

/// Упрощенный экран чата (v2)
///
/// Использует ChatController и ChatInputController для разделения
/// логики и UI. Предназначен для постепенной замены ChatScreen.
class ChatScreenV2 extends StatefulWidget {
  final int chatId;
  final Contact contact;
  final int myId;
  final bool isGroupChat;
  final bool isChannel;
  final int? participantCount;
  final Message? pinnedMessage;

  const ChatScreenV2({
    super.key,
    required this.chatId,
    required this.contact,
    required this.myId,
    this.isGroupChat = false,
    this.isChannel = false,
    this.participantCount,
    this.pinnedMessage,
  });

  @override
  State<ChatScreenV2> createState() => _ChatScreenV2State();
}

class _ChatScreenV2State extends State<ChatScreenV2> {
  late ChatController _chatController;
  late ChatInputController _inputController;

  @override
  void initState() {
    super.initState();
    _chatController = ChatController(
      chatId: widget.chatId,
      isGroupChat: widget.isGroupChat,
      isChannel: widget.isChannel,
    );
    _inputController = ChatInputController(chatId: widget.chatId);

    _chatController.initialize();
  }

  @override
  void dispose() {
    _chatController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _chatController),
        ChangeNotifierProvider.value(value: _inputController),
      ],
      child: Scaffold(
        appBar: _buildAppBar(),
        body: Column(
          children: [
            // Message list
            Expanded(
              child: ChatMessageList(
                controller: _chatController,
                myId: widget.myId,
                onMessageLongPress: _showMessageOptions,
                onLoadMore: _chatController.loadMoreMessages,
                isGroupChat: widget.isGroupChat || widget.isChannel,
                isChannel: widget.isChannel,
                onGoToMessage: (messageId) =>
                    _chatController.scrollToMessage(messageId),
              ),
            ),

            // Input bar
            ChatInputBar(
              onAttachTap: _showAttachMenu,
              onVoiceTap: _startVoiceRecording,
              onSpecialTap: _showSpecialMenu,
            ),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: Row(
        children: [
          ContactAvatarWidget(
            contactId: widget.contact.id,
            originalAvatarUrl: widget.contact.photoBaseUrl,
            radius: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ContactNameWidget(
                  contactId: widget.contact.id,
                  originalName: widget.contact.name,
                  originalFirstName: widget.contact.firstName,
                  originalLastName: widget.contact.lastName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.isGroupChat || widget.isChannel)
                  Text(
                    '${widget.participantCount ?? 0} участников',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  )
                else
                  Text(
                    'онлайн',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(onPressed: _showChatMenu, icon: const Icon(Icons.more_vert)),
      ],
    );
  }

  void _showMessageOptions(Message message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Ответить'),
              onTap: () {
                Navigator.pop(context);
                final senderName = message.senderId == widget.myId
                    ? 'Вы'
                    : widget.isGroupChat
                        ? null
                        : widget.contact.name;
                _inputController.setReplyTo(message, senderName: senderName);
              },
            ),
            if (message.senderId == widget.myId)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Редактировать'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Edit
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Копировать'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Copy
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Удалить', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                // TODO: Delete
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('Фото или видео'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Pick image
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_present),
              title: const Text('Файл'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Pick file
              },
            ),
            ListTile(
              leading: const Icon(Icons.location_on),
              title: const Text('Геопозиция'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Location
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSpecialMenu() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    if (!themeProvider.specialMessagesEnabled) return;

    final colors = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
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
                  'Спецэффекты',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.color_lens_outlined),
                        label: const Text('Цветной текст'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _inputController.insertKometPrefix('komet.color_#');
                          _openColorPickerDialog();
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
                        icon: const Icon(Icons.animation),
                        label: const Text('Пульсация'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _inputController.insertKometPrefix(
                            'komet.cosmetic.pulse#',
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.stars),
                        label: const Text('Галактика'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _inputController.insertKometPrefix(
                            "komet.cosmetic.galaxy''",
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openColorPickerDialog() {
    Color pickedColor = Colors.white;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Выберите цвет'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickedColor,
              onColorChanged: (color) => pickedColor = color,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                final hex = pickedColor.value
                    .toRadixString(16)
                    .padLeft(8, '0')
                    .substring(2)
                    .toUpperCase();
                final text = _inputController.textController.text;
                final offset =
                    _inputController.textController.selection.baseOffset;
                if (offset > 0) {
                  _inputController.textController.text = text.replaceRange(
                    offset,
                    offset,
                    hex,
                  );
                }
                Navigator.pop(ctx);
              },
              child: const Text('Выбрать'),
            ),
          ],
        );
      },
    );
  }

  void _startVoiceRecording() {
    // TODO: Voice recording
  }

  void _showChatMenu() {
    final colors = Theme.of(context).colorScheme;
    // Open the menu below the AppBar, spanning the available width.
    const RelativeRect position = RelativeRect.fromLTRB(
      0,
      kToolbarHeight,
      0,
      0,
    );

    showMenu(
      context: context,
      position: position,
      items: [
        const PopupMenuItem(
          value: 'search',
          child: Row(
            children: [Icon(Icons.search), SizedBox(width: 8), Text('Поиск')],
          ),
        ),
        const PopupMenuItem(
          value: 'mute',
          child: Row(
            children: [
              Icon(Icons.notifications_off),
              SizedBox(width: 8),
              Text('Отключить уведомления'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'clear',
          child: Row(
            children: [
              Icon(Icons.delete_sweep, color: colors.error),
              const SizedBox(width: 8),
              Text('Очистить историю', style: TextStyle(color: colors.error)),
            ],
          ),
        ),
      ],
    );
  }
}
