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
                onGoToMessage: (messageId) => _chatController.scrollToMessage(messageId),
              ),
            ),
            
            // Input bar
            ChatInputBar(
              onAttachTap: _showAttachMenu,
              onVoiceTap: _startVoiceRecording,
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
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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
        IconButton(
          onPressed: _showChatMenu,
          icon: const Icon(Icons.more_vert),
        ),
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
                _inputController.setReplyTo(message);
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

  void _startVoiceRecording() {
    // TODO: Voice recording
  }

  void _showChatMenu() {
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(100, 80, 0, 0),
      items: [
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
          value: 'mute',
          child: Row(
            children: [
              Icon(Icons.notifications_off),
              SizedBox(width: 8),
              Text('Отключить уведомления'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'clear',
          child: Row(
            children: [
              Icon(Icons.delete_sweep, color: Colors.red),
              SizedBox(width: 8),
              Text('Очистить историю', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }
}
