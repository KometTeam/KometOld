import 'package:flutter/material.dart';
import '../../../models/message.dart';
import '../../../models/contact.dart';
import '../../../widgets/contact_avatar_widget.dart';
import '../../../widgets/contact_name_widget.dart';

/// Упрощенный виджет элемента сообщения
class ChatMessageItem extends StatelessWidget {
  final Message message;
  final bool isMe;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onReplyTap;
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
              child: ContactAvatarWidget(
                contactId: message.senderId,
                originalAvatarUrl: senderContact?.photoBaseUrl,
                radius: 18,
                fallbackText: senderContact?.name?.isNotEmpty == true 
                    ? senderContact!.name![0].toUpperCase() 
                    : '?',
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
  final VoidCallback? onReplyTap;
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
        if (showSenderInfo)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 2),
            child: ContactNameWidget(
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
            onTap: onReplyTap,
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
              if (message.text?.isNotEmpty ?? false)
                SelectableText(
                  message.text!,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                  ),
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
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.primary,
              width: 2,
            ),
          ),
        ),
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.7),
            fontSize: 13,
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
