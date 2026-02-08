import 'package:meta/meta.dart';
import 'message.dart';

/// Модель чата
@immutable
class Chat {
  final int id;
  final int ownerId;
  final Message lastMessage;
  final List<int> participantIds;
  final int newMessages;
  final String? title;
  final String? type;
  final String? baseIconUrl;
  final String? description;
  final int? participantsCount;
  final Message? pinnedMessage;

  const Chat({
    required this.id,
    required this.ownerId,
    required this.lastMessage,
    required this.participantIds,
    required this.newMessages,
    this.title,
    this.type,
    this.baseIconUrl,
    this.description,
    this.participantsCount,
    this.pinnedMessage,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    final participantsMap = json['participants'] as Map<String, dynamic>? ?? {};
    final participantIds = participantsMap.keys
        .map((id) => int.tryParse(id) ?? 0)
        .where((id) => id != 0)
        .toList();

    final lastMessage = json['lastMessage'] != null
        ? Message.fromJson(json['lastMessage'] as Map<String, dynamic>)
        : Message(
            id: 'empty',
            senderId: 0,
            time: DateTime.now().millisecondsSinceEpoch,
            text: '',
          );

    final pinnedMessage = json['pinnedMessage'] != null
        ? Message.fromJson(json['pinnedMessage'] as Map<String, dynamic>)
        : null;

    return Chat(
      id: json['id'] ?? 0,
      ownerId: json['owner'] ?? 0,
      lastMessage: lastMessage,
      participantIds: participantIds,
      newMessages: json['newMessages'] ?? 0,
      title: json['title'] as String?,
      type: json['type'] as String?,
      baseIconUrl: json['baseIconUrl'] as String?,
      description: json['description'] as String?,
      participantsCount: json['participantsCount'] as int?,
      pinnedMessage: pinnedMessage,
    );
  }

  bool get isGroup => type == 'CHAT' || participantIds.length > 2;
  bool get isChannel => type == 'CHANNEL';
  bool get isPrivate => !isGroup && !isChannel;

  List<int> get groupParticipantIds => participantIds;
  int get onlineParticipantsCount => participantIds.length;

  String get displayTitle {
    if (title != null && title!.isNotEmpty) return title!;
    if (isGroup) return 'Группа ${participantIds.length}';
    return 'Чат';
  }

  Chat copyWith({
    Message? lastMessage,
    int? newMessages,
    String? title,
    String? type,
    String? baseIconUrl,
    Message? pinnedMessage,
  }) {
    return Chat(
      id: id,
      ownerId: ownerId,
      lastMessage: lastMessage ?? this.lastMessage,
      participantIds: participantIds,
      newMessages: newMessages ?? this.newMessages,
      title: title ?? this.title,
      type: type ?? this.type,
      baseIconUrl: baseIconUrl ?? this.baseIconUrl,
      description: description,
      participantsCount: participantsCount,
      pinnedMessage: pinnedMessage ?? this.pinnedMessage,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Chat &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Chat(id: $id, title: $displayTitle, type: $type)';
}
