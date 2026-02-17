import 'package:flutter/material.dart';
import '../../models/chat.dart';
import '../../models/contact.dart';
import '../../utils/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Оптимизированный элемент списка чатов с минимальными перерисовками
class OptimizedChatListItem extends StatelessWidget {
  final Chat chat;
  final Contact? contact;
  final bool isSavedMessages;
  final bool isGroupChat;
  final bool isChannel;
  final bool isSelected;
  final bool isTyping;
  final bool isOnline;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? draftText;
  final int unreadCount;
  final bool isMuted;
  final DateTime? lastMessageTime;
  final String? lastMessageText;
  final bool isForwardedMode;

  const OptimizedChatListItem({
    super.key,
    required this.chat,
    this.contact,
    required this.isSavedMessages,
    required this.isGroupChat,
    required this.isChannel,
    this.isSelected = false,
    this.isTyping = false,
    this.isOnline = false,
    required this.onTap,
    this.onLongPress,
    this.draftText,
    this.unreadCount = 0,
    this.isMuted = false,
    this.lastMessageTime,
    this.lastMessageText,
    this.isForwardedMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = context.watch<ThemeProvider>();
    
    // Определяем контакт для отображения
    final displayContact = _getDisplayContact();
    final displayName = _getDisplayName(displayContact);
    final avatarUrl = _getAvatarUrl(displayContact);
    
    return RepaintBoundary(
      child: Material(
        color: isSelected ? colors.primaryContainer.withValues(alpha: 0.3) : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          splashColor: colors.primary.withValues(alpha: 0.1),
          highlightColor: colors.primary.withValues(alpha: 0.05),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: theme.chatCompactMode ? 8 : 12,
            ),
            child: Row(
              children: [
                _buildAvatar(colors, avatarUrl, displayName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTitleRow(colors, displayName),
                      const SizedBox(height: 4),
                      _buildSubtitleRow(colors),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildTrailingColumn(colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Contact _getDisplayContact() {
    if (isSavedMessages) {
      return Contact(
        id: chat.id,
        name: 'Избранное',
        firstName: '',
        lastName: '',
        photoBaseUrl: null,
        description: null,
        isBlocked: false,
        isBlockedByMe: false,
      );
    }
    
    if (contact == null && (isChannel || isGroupChat)) {
      return Contact(
        id: chat.id,
        name: isChannel ? (chat.title ?? 'Канал') : (chat.title ?? 'Группа'),
        firstName: '',
        lastName: '',
        photoBaseUrl: chat.baseIconUrl,
        description: chat.description,
        isBlocked: false,
        isBlockedByMe: false,
      );
    }
    
    return contact!;
  }

  String _getDisplayName(Contact displayContact) {
    if (isSavedMessages) return 'Избранное';
    if (displayContact.name.isNotEmpty) return displayContact.name;
    if (displayContact.firstName.isNotEmpty || displayContact.lastName.isNotEmpty) {
      return '${displayContact.firstName} ${displayContact.lastName}'.trim();
    }
    return 'Неизвестный';
  }

  String? _getAvatarUrl(Contact displayContact) {
    if (isSavedMessages) return null;
    return displayContact.photoBaseUrl ?? chat.baseIconUrl;
  }

  Widget _buildAvatar(ColorScheme colors, String? avatarUrl, String displayName) {
    final initials = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    
    return Stack(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: colors.primaryContainer,
          backgroundImage: avatarUrl != null 
              ? CachedNetworkImageProvider(avatarUrl)
              : null,
          child: avatarUrl == null
              ? Text(
                  initials,
                  style: TextStyle(
                    color: colors.onPrimaryContainer,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                )
              : null,
        ),
        if (isOnline && !isGroupChat && !isChannel)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: colors.surface, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTitleRow(ColorScheme colors, String displayName) {
    return Row(
      children: [
        Expanded(
          child: Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.w500,
              color: colors.onSurface,
            ),
          ),
        ),
        // УБРАНО: Индикатор активного звонка временно отключен из-за багов с videoConversation
        // TODO: вернуть когда будет стабильно
        // if (chat.hasActiveCall) ...[
        //   Container(
        //     padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        //     margin: const EdgeInsets.only(right: 4),
        //     decoration: BoxDecoration(
        //       color: Colors.green,
        //       borderRadius: BorderRadius.circular(8),
        //     ),
        //     child: Row(
        //       mainAxisSize: MainAxisSize.min,
        //       children: [
        //         const Icon(
        //           Icons.phone,
        //           size: 12,
        //           color: Colors.white,
        //         ),
        //         const SizedBox(width: 4),
        //         Text(
        //           '${chat.videoConversation?.participantsCount ?? 0}',
        //           style: const TextStyle(
        //             fontSize: 11,
        //             fontWeight: FontWeight.bold,
        //             color: Colors.white,
        //           ),
        //         ),
        //       ],
        //     ),
        //   ),
        // ],
        if (isMuted)
          Icon(
            Icons.volume_off,
            size: 16,
            color: colors.onSurfaceVariant,
          ),
      ],
    );
  }

  Widget _buildSubtitleRow(ColorScheme colors) {
    final messageText = isTyping 
        ? 'печатает...'
        : (draftText ?? lastMessageText ?? chat.lastMessage.text);
    
    final messageColor = isTyping 
        ? colors.primary 
        : (draftText != null ? colors.error : colors.onSurfaceVariant);
    
    return Text(
      messageText,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 14,
        color: messageColor,
        fontStyle: draftText != null ? FontStyle.italic : FontStyle.normal,
      ),
    );
  }

  Widget _buildTrailingColumn(ColorScheme colors) {
    // Используем lastMessageTime или конвертируем время из сообщения
    final timeToFormat = lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(chat.lastMessage.time);
    final timeText = _formatTime(timeToFormat);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timeText,
          style: TextStyle(
            fontSize: 12,
            color: unreadCount > 0 ? colors.primary : colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        if (unreadCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isMuted ? colors.surfaceContainerHighest : colors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              unreadCount > 99 ? '99+' : unreadCount.toString(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isMuted ? colors.onSurfaceVariant : colors.onPrimary,
              ),
            ),
          )
        else if (isForwardedMode)
          Icon(
            Icons.arrow_forward_ios,
            size: 16,
            color: colors.onSurfaceVariant,
          ),
      ],
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(time.year, time.month, time.day);
    
    if (messageDate == today) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Вчера';
    } else {
      return '${time.day.toString().padLeft(2, '0')}.${time.month.toString().padLeft(2, '0')}';
    }
  }
}

/// Оптимизированный заголовок секции для списка чатов
class OptimizedSectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onTap;
  final IconData? icon;

  const OptimizedSectionHeader({
    super.key,
    required this.title,
    this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: colors.primary),
              const SizedBox(width: 8),
            ],
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.primary,
              ),
            ),
            const Spacer(),
            if (onTap != null)
              InkWell(
                onTap: onTap,
                child: Text(
                  'Все',
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
