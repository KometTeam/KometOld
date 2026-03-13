import 'dart:ui' show PointerDeviceKind;
import 'package:animated_list_plus/animated_list_plus.dart';
import 'package:animated_list_plus/transitions.dart';
import 'package:flutter/material.dart';
import 'package:gwid/models/chat.dart';
import 'package:gwid/models/contact.dart';
import 'package:gwid/models/chat_folder.dart';

class ChatsListPage extends StatefulWidget {
  final ChatFolder? folder;
  final List<Chat> allChats;
  final int myId;
  final Map<int, Contact> contacts;
  final String searchQuery;
  final Widget Function(Chat, int, ChatFolder?) buildChatListItem;
  final bool Function(Chat) isSavedMessages;
  final bool Function(Chat, ChatFolder)? chatBelongsToFolder;

  const ChatsListPage({
    super.key,
    required this.folder,
    required this.allChats,
    required this.myId,
    required this.contacts,
    required this.searchQuery,
    required this.buildChatListItem,
    required this.isSavedMessages,
    this.chatBelongsToFolder,
  });

  @override
  State<ChatsListPage> createState() => _ChatsListPageState();
}

class _ChatsListPageState extends State<ChatsListPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Chat> _buildSortedList() {
    List<Chat> chatsForFolder = widget.allChats;

    if (widget.folder != null && widget.chatBelongsToFolder != null) {
      chatsForFolder = widget.allChats
          .where((chat) => widget.chatBelongsToFolder!(chat, widget.folder!))
          .toList();
    }

    chatsForFolder = List.of(chatsForFolder);
    chatsForFolder.sort((a, b) {
      final aPinned = a.favIndex > 0;
      final bPinned = b.favIndex > 0;
      if (aPinned && bPinned) return a.favIndex.compareTo(b.favIndex);
      if (aPinned) return -1;
      if (bPinned) return 1;
      return b.lastMessage.time.compareTo(a.lastMessage.time);
    });

    if (widget.searchQuery.isNotEmpty) {
      final query = widget.searchQuery.toLowerCase();
      chatsForFolder = chatsForFolder.where((chat) {
        final isSavedMessages = widget.isSavedMessages(chat);
        if (isSavedMessages) {
          return "избранное".contains(query);
        }
        final otherParticipantId = chat.participantIds.firstWhere(
          (id) => id != widget.myId,
          orElse: () => 0,
        );
        final contact = widget.contacts[otherParticipantId];
        final contactName = contact?.name.toLowerCase() ?? '';
        final contactIdStr = otherParticipantId.toString();
        return contactName.contains(query) || contactIdStr.contains(query);
      }).toList();
    }

    return chatsForFolder;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final chatsForFolder = _buildSortedList();

    if (chatsForFolder.isEmpty) {
      return Center(
        child: Text(
          widget.folder == null ? 'Нет чатов' : 'В этой папке пока нет чатов',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final idToIndex = {
      for (var i = 0; i < chatsForFolder.length; i++) chatsForFolder[i].id: i,
    };

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.trackpad,
        },
      ),
      child: ImplicitlyAnimatedList<Chat>(
        items: chatsForFolder,
        itemBuilder: (context, animation, chat, index) {
          return SizeFadeTransition(
            animation: animation,
            child: widget.buildChatListItem(chat, index, widget.folder),
          );
        },
        areItemsTheSame: (a, b) => a.id == b.id,
        updateItemBuilder: (context, animation, chat) {
          return widget.buildChatListItem(
            chat,
            idToIndex[chat.id] ?? 0,
            widget.folder,
          );
        },
        spawnIsolate: false,
      ),
    );
  }
}
