import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/chat_input_controller.dart';
import '../../../../models/message.dart';

/// Упрощенная панель ввода сообщений
class ChatInputBar extends StatelessWidget {
  final VoidCallback? onAttachTap;
  final VoidCallback? onCameraTap;
  final VoidCallback? onVoiceTap;
  final VoidCallback? onSpecialTap;

  const ChatInputBar({
    super.key,
    this.onAttachTap,
    this.onCameraTap,
    this.onVoiceTap,
    this.onSpecialTap,
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
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (controller.replyingToMessage != null)
                    _ReplyIndicator(
                      message: controller.replyingToMessage!,
                      senderName: controller.replyingToSenderName,
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
                    IconButton(
                      onPressed: onSpecialTap,
                      icon: Icon(
                        Icons.auto_awesome_rounded,
                        color: theme.colorScheme.primary,
                      ),
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
                        contextMenuBuilder: (context, editableTextState) {
                          final List<ContextMenuButtonItem> buttonItems =
                              editableTextState.contextMenuButtonItems;

                          buttonItems.insertAll(0, [
                            ContextMenuButtonItem(
                              label: 'Жирный',
                              onPressed: () {
                                editableTextState.hideToolbar();
                                controller.toggleStyle('STRONG');
                              },
                            ),
                            ContextMenuButtonItem(
                              label: 'Курсив',
                              onPressed: () {
                                editableTextState.hideToolbar();
                                controller.toggleStyle('EMPHASIZED');
                              },
                            ),
                            ContextMenuButtonItem(
                              label: 'Зачеркнуть',
                              onPressed: () {
                                editableTextState.hideToolbar();
                                controller.toggleStyle('STRIKETHROUGH');
                              },
                            ),
                            ContextMenuButtonItem(
                              label: 'Подчеркнуть',
                              onPressed: () {
                                editableTextState.hideToolbar();
                                controller.toggleStyle('UNDERLINE');
                              },
                            ),
                            ContextMenuButtonItem(
                              label: 'Цитата',
                              onPressed: () {
                                editableTextState.hideToolbar();
                                controller.toggleStyle('QUOTE');
                              },
                            ),
                            ContextMenuButtonItem(
                              label: 'Убрать стили',
                              onPressed: () {
                                editableTextState.hideToolbar();
                                controller.clearSelectionStyles();
                              },
                            ),
                            ContextMenuButtonItem(
                              label: 'Галактика',
                              onPressed: () {
                                editableTextState.hideToolbar();
                                controller.formatSelection(
                                  "komet.cosmetic.galaxy'",
                                  "'",
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

                    if (controller.hasText)
                      _SendButton(
                        isSending: controller.isSending,
                        onPressed: controller.sendMessage,
                      )
                    else
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, animation) {
                          return RotationTransition(
                            turns: Tween<double>(
                              begin: 0.8,
                              end: 1.0,
                            ).animate(animation),
                            child: ScaleTransition(
                              scale: animation,
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: IconButton(
                          key: ValueKey<bool>(controller.isVideoMode),
                          onPressed: controller.toggleRecordMode,
                          icon: Icon(
                            controller.isVideoMode ? Icons.videocam : Icons.mic,
                          ),
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReplyIndicator extends StatelessWidget {
  final Message message;
  final String? senderName;
  final VoidCallback onCancel;

  const _ReplyIndicator({
    required this.message,
    required this.onCancel,
    this.senderName,
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
    if (message.text.isNotEmpty) return message.text;
    if (message.attaches.isNotEmpty) {
      final hasPhoto = message.attaches.any((a) {
        final type = a['_type'] ?? a['type'];
        return type == 'PHOTO' || type == 'IMAGE';
      });
      if (hasPhoto) return 'Фото';
      return 'Медиафайл';
    }
    return 'Сообщение';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photoUrl = _getPhotoUrl();
    final displayName = senderName ?? 'Ответ';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (photoUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                photoUrl,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 36,
                    height: 36,
                    color: theme.colorScheme.surfaceContainer,
                    child: Icon(
                      Icons.image,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    width: 36,
                    height: 36,
                    color: theme.colorScheme.surfaceContainer,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
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
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _getPreviewText(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 4),
          // Кнопка закрытия — фиксированный размер, не может пропасть
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              onPressed: onCancel,
              icon: const Icon(Icons.close, size: 16),
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool isSending;
  final VoidCallback onPressed;

  const _SendButton({required this.isSending, required this.onPressed});

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
      icon: Icon(Icons.send, color: theme.colorScheme.primary),
    );
  }
}
