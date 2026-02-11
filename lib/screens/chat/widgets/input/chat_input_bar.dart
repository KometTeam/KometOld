import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/chat_input_controller.dart';
import '../../../../models/message.dart';

/// Упрощенная панель ввода сообщений
class ChatInputBar extends StatelessWidget {
  final VoidCallback? onAttachTap;
  final VoidCallback? onCameraTap;
  final VoidCallback? onVoiceTap;
  
  const ChatInputBar({
    super.key,
    this.onAttachTap,
    this.onCameraTap,
    this.onVoiceTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Consumer<ChatInputController>(
      builder: (context, controller, child) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outlineVariant.withOpacity(0.5),
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (controller.replyingToMessage != null)
                  _ReplyIndicator(
                    message: controller.replyingToMessage!,
                    onCancel: controller.clearReply,
                  ),
                
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: onAttachTap,
                      icon: const Icon(Icons.attach_file),
                      color: theme.colorScheme.onSurfaceVariant,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                    ),
                    
                    Expanded(
                      child: TextField(
                        controller: controller.textController,
                        focusNode: controller.focusNode,
                        decoration: InputDecoration(
                          hintText: 'Сообщение...',
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                              color: theme.colorScheme.primary,
                              width: 1,
                            ),
                          ),
                        ),
                        maxLines: 5,
                        minLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => controller.sendMessage(),
                      ),
                    ),
                    
                    if (controller.hasText)
                      _SendButton(
                        isSending: controller.isSending,
                        onPressed: controller.sendMessage,
                      )
                    else
                      IconButton(
                        onPressed: onVoiceTap,
                        icon: const Icon(Icons.mic),
                        color: theme.colorScheme.onSurfaceVariant,
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
}

class _ReplyIndicator extends StatelessWidget {
  final Message message;
  final VoidCallback onCancel;
  
  const _ReplyIndicator({
    required this.message,
    required this.onCancel,
  });

  String? _getPhotoUrl() {
    if (message.attaches.isEmpty) return null;
    
    for (final attach in message.attaches) {
      final type = attach['_type'] ?? attach['type'];
      if (type == 'PHOTO' || type == 'IMAGE') {
        final url = attach['url'] ?? attach['baseUrl'];
        if (url is String && url.isNotEmpty) {
          return url;
        }
      }
    }
    return null;
  }

  String _getPreviewText() {
    if (message.attaches.isNotEmpty) {
      final hasPhoto = message.attaches.any((a) {
        final type = a['_type'] ?? a['type'];
        return type == 'PHOTO' || type == 'IMAGE';
      });
      
      if (hasPhoto && message.text.isEmpty) {
        return 'Фото';
      }
    }
    return message.text;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photoUrl = _getPhotoUrl();
    
    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.primary,
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          if (photoUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                photoUrl,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 40,
                    height: 40,
                    color: theme.colorScheme.surfaceContainer,
                    child: Icon(
                      Icons.image,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    width: 40,
                    height: 40,
                    color: theme.colorScheme.surfaceContainer,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
          ],
          
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ответ',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _getPreviewText(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool isSending;
  final VoidCallback onPressed;
  
  const _SendButton({
    required this.isSending,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    if (isSending) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary,
          ),
        ),
      );
    }
    
    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        Icons.send,
        color: theme.colorScheme.primary,
      ),
    );
  }
}
