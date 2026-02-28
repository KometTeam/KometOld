import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../../models/message.dart';

import '../controllers/chat_controller.dart';
import 'chat_message_item.dart';

/// Проверяет, сгруппировано ли сообщение с предыдущим (один отправитель подряд)
bool _isGroupedWithPrevious(List<Message> messages, int index) {
  if (index >= messages.length - 1) return false;
  final current = messages[messages.length - 1 - index];
  final previous = messages[messages.length - 2 - index];
  return current.senderId == previous.senderId;
}

/// Виджет списка сообщений чата
class ChatMessageList extends StatelessWidget {
  final ChatController controller;
  final int myId;
  final Function(Message)? onMessageTap;
  final Function(Message)? onMessageLongPress;
  final Function(Message)? onReplyTap;
  final Function(Message)? onEditTap;
  final Function(Message)? onDeleteTap;
  final Function(String messageId)? onGoToMessage;
  final VoidCallback? onLoadMore;
  final bool isGroupChat;
  final bool isChannel;
  
  const ChatMessageList({
    super.key,
    required this.controller,
    required this.myId,
    this.onMessageTap,
    this.onMessageLongPress,
    this.onReplyTap,
    this.onEditTap,
    this.onDeleteTap,
    this.onGoToMessage,
    this.onLoadMore,
    this.isGroupChat = false,
    this.isChannel = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        if (controller.isLoading && controller.messages.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (controller.messages.isEmpty) {
          return _EmptyState(
            onRefresh: controller.loadMessages,
          );
        }
        
        return _MessageListView(
          messages: controller.messages,
          myId: myId,
          isLoadingMore: controller.isLoadingMore,
          onMessageTap: onMessageTap,
          onMessageLongPress: onMessageLongPress,
          onReplyTap: onReplyTap,
          onGoToMessage: onGoToMessage,
          onLoadMore: onLoadMore,
          isGroupChat: isGroupChat,
          isChannel: isChannel,
          controller: controller,
        );
      },
    );
  }
}

class _MessageListView extends StatefulWidget {
  final List<Message> messages;
  final int myId;
  final bool isLoadingMore;
  final Function(Message)? onMessageTap;
  final Function(Message)? onMessageLongPress;
  final Function(Message)? onReplyTap;
  final Function(String messageId)? onGoToMessage;
  final VoidCallback? onLoadMore;
  final bool isGroupChat;
  final bool isChannel;
  final ChatController controller;
  
  const _MessageListView({
    required this.messages,
    required this.myId,
    this.isLoadingMore = false,
    this.onMessageTap,
    this.onMessageLongPress,
    this.onReplyTap,
    this.onGoToMessage,
    this.onLoadMore,
    this.isGroupChat = false,
    this.isChannel = false,
    required this.controller,
  });

  @override
  State<_MessageListView> createState() => _MessageListViewState();
}

class _MessageListViewState extends State<_MessageListView> {
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener = ItemPositionsListener.create();
  
  @override
  void initState() {
    super.initState();
    _positionsListener.itemPositions.addListener(_onScroll);
    // Регистрируем scroll controller в ChatController
    widget.controller.setScrollController(_scrollController, _positionsListener);
  }
  
  void _onScroll() {
    final positions = _positionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    
    // В ScrollablePositionedList с reverse=true:
    // - индекс 0 = новые сообщения (внизу)
    // - индекс itemCount-1 = старые сообщения (вверху)
    // Подгружаем старые сообщения, когда maxIndex приближается к концу списка
    final maxIndex = positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);
    final threshold = widget.messages.length - 10;
    
    if (maxIndex >= threshold && !widget.isLoadingMore && widget.controller.hasMoreMessages) {
      widget.onLoadMore?.call();
    }
  }
  
  void scrollToBottom() {
    if (!_scrollController.isAttached) return;
    _scrollController.jumpTo(index: 0);
  }
  
  @override
  Widget build(BuildContext context) {
    return ScrollablePositionedList.builder(
      itemScrollController: _scrollController,
      itemPositionsListener: _positionsListener,
      itemCount: widget.messages.length + (widget.isLoadingMore ? 1 : 0),
      reverse: true,
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      minCacheExtent: 200.0,
      addRepaintBoundaries: true,
      addAutomaticKeepAlives: false,
      addSemanticIndexes: false,
      itemBuilder: (context, index) {
        if (index == widget.messages.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }
        
        final message = widget.messages[widget.messages.length - 1 - index];
        final isMe = message.senderId == widget.myId;
        final isGrouped = _isGroupedWithPrevious(widget.messages, index);
        final senderContact = widget.controller.getContact(message.senderId);
        
        return ChatMessageItem(
          message: message,
          isMe: isMe,
          onTap: () => widget.onMessageTap?.call(message),
          onLongPress: () => widget.onMessageLongPress?.call(message),
          onReplyTap: widget.onGoToMessage,
          isGroupChat: widget.isGroupChat,
          isChannel: widget.isChannel,
          isGrouped: isGrouped,
          senderContact: senderContact,
        );
      },
    );
  }
  
  @override
  void dispose() {
    _positionsListener.itemPositions.removeListener(_onScroll);
    super.dispose();
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onRefresh;
  
  const _EmptyState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'Нет сообщений',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Начните общение прямо сейчас',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Обновить'),
          ),
        ],
      ),
    );
  }
}
