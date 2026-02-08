import 'package:meta/meta.dart';

/// Модель сообщения в чате
@immutable
class Message {
  final String id;
  final String text;
  final int time;
  final int senderId;
  final String? status;
  final int? updateTime;
  final List<Map<String, dynamic>> attaches;
  final int? cid;
  final Map<String, dynamic>? reactionInfo;
  final Map<String, dynamic>? link;
  final List<Map<String, dynamic>> elements;
  final bool isDeleted;
  final String? originalText;

  const Message({
    required this.id,
    required this.text,
    required this.time,
    required this.senderId,
    this.status,
    this.updateTime,
    this.attaches = const [],
    this.cid,
    this.reactionInfo,
    this.link,
    this.elements = const [],
    this.isDeleted = false,
    this.originalText,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    final senderId = json['sender'] is int ? json['sender'] as int : 0;
    final time = json['time'] is int ? json['time'] as int : 0;

    final rawText = json['text'] ?? '';
    final parsedText = rawText is String
        ? rawText.replaceAll(r'\r\n', '\n').replaceAll(r'\n', '\n')
        : '';

    return Message(
      id: json['id']?.toString() ?? 'local_${DateTime.now().millisecondsSinceEpoch}',
      text: json['text'] ?? '',
      time: time,
      senderId: senderId,
      status: json['status'] as String?,
      updateTime: json['updateTime'] as int?,
      attaches: _parseList(json['attaches']),
      cid: json['cid'] as int?,
      reactionInfo: json['reactionInfo'] as Map<String, dynamic>?,
      link: json['link'] as Map<String, dynamic>?,
      elements: _parseList(json['elements']),
      isDeleted: json['isDeleted'] ?? false,
      originalText: json['originalText'] as String?,
    );
  }

  static List<Map<String, dynamic>> _parseList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Message copyWith({
    String? id,
    String? text,
    int? time,
    int? senderId,
    String? status,
    int? updateTime,
    List<Map<String, dynamic>>? attaches,
    int? cid,
    Map<String, dynamic>? reactionInfo,
    Map<String, dynamic>? link,
    List<Map<String, dynamic>>? elements,
    bool? isDeleted,
    String? originalText,
  }) {
    return Message(
      id: id ?? this.id,
      text: text ?? this.text,
      time: time ?? this.time,
      senderId: senderId ?? this.senderId,
      status: status ?? this.status,
      updateTime: updateTime ?? this.updateTime,
      attaches: attaches ?? this.attaches,
      cid: cid ?? this.cid,
      reactionInfo: reactionInfo ?? this.reactionInfo,
      link: link ?? this.link,
      elements: elements ?? this.elements,
      isDeleted: isDeleted ?? this.isDeleted,
      originalText: originalText ?? this.originalText,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'time': time,
    'sender': senderId,
    'status': status,
    'updateTime': updateTime,
    'cid': cid,
    'attaches': attaches,
    'link': link,
    'reactionInfo': reactionInfo,
    'elements': elements,
    'isDeleted': isDeleted,
    'originalText': originalText,
  };

  bool get isEdited => status == 'EDITED';
  bool get isReply => link != null && link!['type'] == 'REPLY';
  bool get isForwarded => link != null && link!['type'] == 'FORWARD';
  bool get hasFileAttach => attaches.any(
    (a) => (a['_type'] ?? a['type']) == 'FILE',
  );

  bool canEdit(int currentUserId) {
    if (isDeleted) return false;
    if (senderId != currentUserId) return false;
    if (attaches.isNotEmpty) return false;

    final hoursSinceCreation = 
        (DateTime.now().millisecondsSinceEpoch - time) / (1000 * 60 * 60);
    return hoursSinceCreation <= 24;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Message &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Message(id: $id, text: $text, senderId: $senderId)';
}

/// Модель упоминания пользователя
@immutable
class Mention {
  final int from;
  final int length;
  final int entityId;
  final String entityName;

  const Mention({
    required this.from,
    required this.length,
    required this.entityId,
    required this.entityName,
  });

  Map<String, dynamic> toJson() => {
    'type': 'USER_MENTION',
    'from': from,
    'length': length,
    'entityId': entityId,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Mention &&
          runtimeType == other.runtimeType &&
          entityId == other.entityId &&
          from == other.from;

  @override
  int get hashCode => Object.hash(entityId, from);
}
