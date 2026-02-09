import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/chat_input_controller.dart';

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
                // Reply indicator
                if (controller.replyingToMessage != null)
                  _ReplyIndicator(
                    message: controller.replyingToMessage!,
                    onCancel: controller.clearReply,
                  ),
                
                // Input row
                Row(
                  children: [
                    // Attach button
                    IconButton(
                      onPressed: onAttachTap,
                      icon: const Icon(Icons.attach_file),
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    
                    // Text field
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
                    
                    // Send or voice button
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
  final dynamic message;
  final VoidCallback onCancel;
  
  const _ReplyIndicator({
    required this.message,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
                  message.text ?? '',
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
