import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/message.dart';
import '../../../models/contact.dart';
import '../../../widgets/contact_avatar_widget.dart';
import '../../../widgets/contact_name_widget.dart';
import '../../../widgets/user_profile_panel.dart';
import '../../../api/api_service.dart';

/// Упрощенный виджет элемента сообщения
class ChatMessageItem extends StatelessWidget {
  final Message message;
  final bool isMe;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Function(String messageId)? onReplyTap;
  final bool showAvatar;
  final bool isGrouped;
  final bool isGroupChat;
  final Contact? senderContact;
  
  const ChatMessageItem({
    super.key,
    required this.message,
    required this.isMe,
    this.onTap,
    this.onLongPress,
    this.onReplyTap,
    this.showAvatar = true,
    this.isGrouped = false,
    this.isGroupChat = false,
    this.senderContact,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showSenderInfo = !isMe && isGroupChat && showAvatar;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Аватарка отправителя (только для чужих сообщений в групповых чатах)
          if (showSenderInfo)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 4),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openUserProfile(context, message.senderId),
                  child: ContactAvatarWidget(
                    contactId: message.senderId,
                    originalAvatarUrl: senderContact?.photoBaseUrl,
                    radius: 18,
                    fallbackText: () {
                      final name = senderContact?.name;
                      if (name != null && name.isNotEmpty) {
                        return name[0].toUpperCase();
                      }
                      return '?';
                    }(),
                  ),
                ),
              ),
            )
          else if (!isMe && isGroupChat)
            // Placeholder для выравнивания
            const SizedBox(width: 36),
          
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              child: GestureDetector(
                onTap: onTap,
                onLongPress: onLongPress,
                child: _MessageContent(
                  message: message,
                  isMe: isMe,
                  theme: theme,
                  onReplyTap: onReplyTap,
                  showSenderInfo: showSenderInfo,
                  senderContact: senderContact,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageContent extends StatelessWidget {
  final Message message;
  final bool isMe;
  final ThemeData theme;
  final Function(String messageId)? onReplyTap;
  final bool showSenderInfo;
  final Contact? senderContact;
  
  const _MessageContent({
    required this.message,
    required this.isMe,
    required this.theme,
    this.onReplyTap,
    this.showSenderInfo = false,
    this.senderContact,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isMe 
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    
    final textColor = isMe
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
    
    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Имя отправителя (только для чужих сообщений в групповых чатах)
        // Для каналов (senderId == 0) показываем 'Канал' или имя контакта
        if (showSenderInfo)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 2),
            child: message.senderId == 0
                ? Text(
                    senderContact?.name ?? 'Канал',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : ContactNameWidget(
                    contactId: message.senderId,
                    originalName: senderContact?.name,
                    originalFirstName: senderContact?.firstName,
                    originalLastName: senderContact?.lastName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
          ),
        
        // Reply preview
        if (message.isReply && message.link != null)
          _ReplyPreview(
            link: message.link!,
            theme: theme,
            onTap: () {
              // Получаем ID сообщения из link и вызываем onReplyTap
              final replyMessage = message.link!['message'] as Map<String, dynamic>?;
              final messageId = replyMessage?['id']?.toString();
              if (messageId != null && onReplyTap != null) {
                onReplyTap!(messageId);
              }
            },
          ),
        
        // Message bubble
        Container(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Text content
              if (message.text.isNotEmpty)
                LayoutBuilder(
                  builder: (context, constraints) {
                    return SelectableText(
                      message.text,
                      key: ValueKey('msg_text_${message.id}'),
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                      ),
                    );
                  },
                ),
              
              // Attachments indicator
              if (message.attaches.isNotEmpty)
                _AttachmentsIndicator(
                  count: message.attaches.length,
                  theme: theme,
                ),
              
              const SizedBox(height: 4),
              
              // Time and status
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(message.time),
                    style: TextStyle(
                      color: textColor.withOpacity(0.6),
                      fontSize: 11,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    _MessageStatusIndicator(
                      status: message.status,
                      theme: theme,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  String _formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _ReplyPreview extends StatelessWidget {
  final Map<String, dynamic> link;
  final ThemeData theme;
  final VoidCallback? onTap;
  
  const _ReplyPreview({
    required this.link,
    required this.theme,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final replyMessage = link['message'] as Map<String, dynamic>?;
    final text = replyMessage?['text'] as String? ?? '';
    
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(
                color: theme.colorScheme.primary,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.reply,
                size: 14,
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text.isNotEmpty ? text : 'Медиафайл',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentsIndicator extends StatelessWidget {
  final int count;
  final ThemeData theme;
  
  const _AttachmentsIndicator({
    required this.count,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.attachment,
            size: 14,
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
          const SizedBox(width: 4),
          Text(
            '$count вложений',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageStatusIndicator extends StatelessWidget {
  final String? status;
  final ThemeData theme;
  
  const _MessageStatusIndicator({
    this.status,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    
    switch (status) {
      case 'READ':
        icon = Icons.done_all;
        color = theme.colorScheme.primary;
        break;
      case 'DELIVERED':
        icon = Icons.done_all;
        color = theme.colorScheme.onSurface.withOpacity(0.5);
        break;
      case 'SENT':
        icon = Icons.done;
        color = theme.colorScheme.onSurface.withOpacity(0.5);
        break;
      default:
        icon = Icons.access_time;
        color = theme.colorScheme.onSurface.withOpacity(0.3);
    }
    
    return Icon(
      icon,
      size: 14,
      color: color,
    );
  }
}

/// Открывает профиль пользователя
void _openUserProfile(BuildContext context, int userId) {
  final myIdStr = ApiService.instance.userId;
  final myId = myIdStr != null ? int.tryParse(myIdStr) : null;
  if (myId == null) return;
  
  final contact = ApiService.instance.getCachedContact(userId);
  
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => UserProfilePanel(
      userId: userId,
      name: contact?.name,
      firstName: contact?.firstName,
      lastName: contact?.lastName,
      avatarUrl: contact?.photoBaseUrl,
      description: contact?.description,
      myId: myId,
      currentChatId: null,
      contactData: null,
      dialogChatId: null,
    ),
  );
}
