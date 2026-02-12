class ParticipantExternalId {
  final String id;

  const ParticipantExternalId({required this.id});

  factory ParticipantExternalId.fromJson(Map<String, dynamic> json) {
    return ParticipantExternalId(
      id: json['id'] as String,
    );
  }
}

class Participant {
  final ParticipantExternalId externalId;
  final int id;

  const Participant({
    required this.externalId,
    required this.id,
  });

  factory Participant.fromJson(Map<String, dynamic> json) {
    return Participant(
      externalId: ParticipantExternalId.fromJson(
        json['externalId'] as Map<String, dynamic>,
      ),
      id: json['id'] as int,
    );
  }
}

class Conversation {
  final List<Participant> participants;

  const Conversation({required this.participants});

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      participants: (json['participants'] as List)
          .map((e) => Participant.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ServerHello {
  final Conversation conversation;

  const ServerHello({required this.conversation});

  factory ServerHello.fromJson(Map<String, dynamic> json) {
    return ServerHello(
      conversation: Conversation.fromJson(
        json['conversation'] as Map<String, dynamic>,
      ),
    );
  }

  int? findUserIdByExternalId(String externalId) {
    for (final participant in conversation.participants) {
      if (participant.externalId.id == externalId) {
        return participant.id;
      }
    }
    return null;
  }
}
