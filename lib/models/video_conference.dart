class VideoConference {
  final ConferenceOwner owner;
  final int chatId;
  final String conferenceId;
  final String callName;
  final String joinLink;
  final List<int> previewParticipantIds;
  final int? approxParticipantsCount;
  final int type;
  final int startAt;
  final String callType;

  VideoConference({
    required this.owner,
    required this.chatId,
    required this.conferenceId,
    required this.callName,
    required this.joinLink,
    required this.previewParticipantIds,
    this.approxParticipantsCount,
    required this.type,
    required this.startAt,
    required this.callType,
  });

  factory VideoConference.fromJson(Map<String, dynamic> json) {
    // Безопасный парсинг owner - может отсутствовать
    ConferenceOwner? ownerInstance;
    try {
      final ownerJson = json['owner'];
      if (ownerJson != null && ownerJson is Map<String, dynamic>) {
        ownerInstance = ConferenceOwner.fromJson(ownerJson);
      }
    } catch (e) {
      print('⚠️ VideoConference.fromJson: Ошибка парсинга owner: $e');
    }
    
    // Безопасный парсинг previewParticipantIds
    List<int> participantIds = [];
    try {
      final idsJson = json['previewParticipantIds'];
      if (idsJson != null && idsJson is List) {
        participantIds = idsJson.map((id) => id is int ? id : int.tryParse(id.toString()) ?? 0).toList();
      }
    } catch (e) {
      print('⚠️ VideoConference.fromJson: Ошибка парсинга previewParticipantIds: $e');
    }
    
    return VideoConference(
      owner: ownerInstance ?? ConferenceOwner(
        id: 0,
        baseUrl: '',
        baseRawUrl: '',
        photoId: 0,
        names: [],
        updateTime: 0,
      ),
      chatId: json['chatId'] ?? 0,
      conferenceId: json['conferenceId'] ?? json['conversationId'] ?? '',
      callName: json['callName'] ?? '',
      joinLink: json['joinLink'] ?? '',
      previewParticipantIds: participantIds,
      approxParticipantsCount: json['approxParticipantsCount'] as int?,
      type: json['type'] ?? 0,
      startAt: json['startAt'] ?? 0,
      callType: json['callType'] ?? 'AUDIO',
    );
  }

  bool get isAudioOnly => callType == 'AUDIO';
  bool get isVideoCall => callType == 'VIDEO';
  
  int get participantsCount => approxParticipantsCount ?? previewParticipantIds.length;
}

class ConferenceOwner {
  final int id;
  final String baseUrl;
  final String baseRawUrl;
  final int photoId;
  final List<ConferenceName> names;
  final int updateTime;

  ConferenceOwner({
    required this.id,
    required this.baseUrl,
    required this.baseRawUrl,
    required this.photoId,
    required this.names,
    required this.updateTime,
  });

  factory ConferenceOwner.fromJson(Map<String, dynamic> json) {
    // Безопасный парсинг names
    List<ConferenceName> namesList = [];
    try {
      final namesJson = json['names'];
      if (namesJson != null && namesJson is List) {
        namesList = namesJson
            .map((n) {
              try {
                return ConferenceName.fromJson(n is Map<String, dynamic> ? n : {});
              } catch (e) {
                print('⚠️ ConferenceOwner.fromJson: Ошибка парсинга name: $e');
                return null;
              }
            })
            .whereType<ConferenceName>()
            .toList();
      }
    } catch (e) {
      print('⚠️ ConferenceOwner.fromJson: Ошибка парсинга names list: $e');
    }
    
    return ConferenceOwner(
      id: json['id'] ?? 0,
      baseUrl: json['baseUrl'] ?? '',
      baseRawUrl: json['baseRawUrl'] ?? '',
      photoId: json['photoId'] ?? 0,
      names: namesList,
      updateTime: json['updateTime'] ?? 0,
    );
  }

  String get displayName {
    if (names.isEmpty) return 'Unknown';
    return names.first.name;
  }
}

class ConferenceName {
  final String name;
  final String firstName;
  final String lastName;
  final String type;

  ConferenceName({
    required this.name,
    required this.firstName,
    required this.lastName,
    required this.type,
  });

  factory ConferenceName.fromJson(Map<String, dynamic> json) {
    return ConferenceName(
      name: json['name'] ?? '',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      type: json['type'] ?? '',
    );
  }
}

class ConversationConnection {
  final int stamp;
  final PeerId peerId;
  final String endpoint;
  final ConversationParams conversationParams;
  final Conversation conversation;

  ConversationConnection({
    required this.stamp,
    required this.peerId,
    required this.endpoint,
    required this.conversationParams,
    required this.conversation,
  });

  factory ConversationConnection.fromJson(Map<String, dynamic> json) {
    return ConversationConnection(
      stamp: json['stamp'] ?? 0,
      peerId: PeerId.fromJson(json['peerId'] ?? {}),
      endpoint: json['endpoint'] ?? '',
      conversationParams: ConversationParams.fromJson(json['conversationParams'] ?? {}),
      conversation: Conversation.fromJson(json['conversation'] ?? {}),
    );
  }
}

class PeerId {
  final int id;

  PeerId({required this.id});

  factory PeerId.fromJson(Map<String, dynamic> json) {
    return PeerId(id: json['id'] ?? 0);
  }
}

class ConversationParams {
  final TurnConfig turn;
  final StunConfig stun;
  final int serverTime;
  final int activityTimeout;

  ConversationParams({
    required this.turn,
    required this.stun,
    required this.serverTime,
    required this.activityTimeout,
  });

  factory ConversationParams.fromJson(Map<String, dynamic> json) {
    return ConversationParams(
      turn: TurnConfig.fromJson(json['turn'] ?? {}),
      stun: StunConfig.fromJson(json['stun'] ?? {}),
      serverTime: json['serverTime'] ?? 0,
      activityTimeout: json['activityTimeout'] ?? 120000,
    );
  }
}

class TurnConfig {
  final List<String> urls;
  final String username;
  final String credential;

  TurnConfig({
    required this.urls,
    required this.username,
    required this.credential,
  });

  factory TurnConfig.fromJson(Map<String, dynamic> json) {
    return TurnConfig(
      urls: List<String>.from(json['urls'] ?? []),
      username: json['username'] ?? '',
      credential: json['credential'] ?? '',
    );
  }
}

class StunConfig {
  final List<String> urls;

  StunConfig({required this.urls});

  factory StunConfig.fromJson(Map<String, dynamic> json) {
    return StunConfig(
      urls: List<String>.from(json['urls'] ?? []),
    );
  }
}

class Conversation {
  final String id;
  final String state;
  final String topology;
  final List<ConferenceParticipant> participants;
  final int participantsLimit;
  final List<String> features;
  final List<String> turnServers;
  final String joinLink;
  final String clientType;
  final int handCount;

  Conversation({
    required this.id,
    required this.state,
    required this.topology,
    required this.participants,
    required this.participantsLimit,
    required this.features,
    required this.turnServers,
    required this.joinLink,
    required this.clientType,
    required this.handCount,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] ?? '',
      state: json['state'] ?? '',
      topology: json['topology'] ?? '',
      participants: (json['participants'] as List<dynamic>?)
              ?.map((p) => ConferenceParticipant.fromJson(p))
              .toList() ??
          [],
      participantsLimit: json['participantsLimit'] ?? 0,
      features: List<String>.from(json['features'] ?? []),
      turnServers: List<String>.from(json['turnServers'] ?? []),
      joinLink: json['joinLink'] ?? '',
      clientType: json['clientType'] ?? '',
      handCount: json['handCount'] ?? 0,
    );
  }
}

class ConferenceParticipant {
  final ParticipantExternalId externalId;
  final String state;
  final MediaSettings mediaSettings;
  final PeerId peerId;
  final int id;

  ConferenceParticipant({
    required this.externalId,
    required this.state,
    required this.mediaSettings,
    required this.peerId,
    required this.id,
  });

  factory ConferenceParticipant.fromJson(Map<String, dynamic> json) {
    return ConferenceParticipant(
      externalId: ParticipantExternalId.fromJson(json['externalId'] ?? {}),
      state: json['state'] ?? '',
      mediaSettings: MediaSettings.fromJson(json['mediaSettings'] ?? {}),
      peerId: PeerId.fromJson(json['peerId'] ?? {}),
      id: json['id'] ?? 0,
    );
  }
}

class ParticipantExternalId {
  final String type;
  final String id;

  ParticipantExternalId({
    required this.type,
    required this.id,
  });

  factory ParticipantExternalId.fromJson(Map<String, dynamic> json) {
    return ParticipantExternalId(
      type: json['type'] ?? '',
      id: json['id']?.toString() ?? '',
    );
  }
}

class MediaSettings {
  final bool isAudioEnabled;
  final bool isVideoEnabled;
  final bool isScreenSharingEnabled;
  final bool isFastScreenSharingEnabled;
  final bool isAudioSharingEnabled;
  final bool isAnimojiEnabled;

  MediaSettings({
    this.isAudioEnabled = false,
    this.isVideoEnabled = false,
    this.isScreenSharingEnabled = false,
    this.isFastScreenSharingEnabled = false,
    this.isAudioSharingEnabled = false,
    this.isAnimojiEnabled = false,
  });

  factory MediaSettings.fromJson(Map<String, dynamic> json) {
    return MediaSettings(
      isAudioEnabled: json['isAudioEnabled'] ?? false,
      isVideoEnabled: json['isVideoEnabled'] ?? false,
      isScreenSharingEnabled: json['isScreenSharingEnabled'] ?? false,
      isFastScreenSharingEnabled: json['isFastScreenSharingEnabled'] ?? false,
      isAudioSharingEnabled: json['isAudioSharingEnabled'] ?? false,
      isAnimojiEnabled: json['isAnimojiEnabled'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isAudioEnabled': isAudioEnabled,
      'isVideoEnabled': isVideoEnabled,
      'isScreenSharingEnabled': isScreenSharingEnabled,
      'isFastScreenSharingEnabled': isFastScreenSharingEnabled,
      'isAudioSharingEnabled': isAudioSharingEnabled,
      'isAnimojiEnabled': isAnimojiEnabled,
    };
  }

  MediaSettings copyWith({
    bool? isAudioEnabled,
    bool? isVideoEnabled,
    bool? isScreenSharingEnabled,
    bool? isFastScreenSharingEnabled,
    bool? isAudioSharingEnabled,
    bool? isAnimojiEnabled,
  }) {
    return MediaSettings(
      isAudioEnabled: isAudioEnabled ?? this.isAudioEnabled,
      isVideoEnabled: isVideoEnabled ?? this.isVideoEnabled,
      isScreenSharingEnabled: isScreenSharingEnabled ?? this.isScreenSharingEnabled,
      isFastScreenSharingEnabled: isFastScreenSharingEnabled ?? this.isFastScreenSharingEnabled,
      isAudioSharingEnabled: isAudioSharingEnabled ?? this.isAudioSharingEnabled,
      isAnimojiEnabled: isAnimojiEnabled ?? this.isAnimojiEnabled,
    );
  }
}

// Модель для уведомления participant-joined
class ParticipantJoinedNotification {
  final int stamp;
  final int participantId;
  final ConferenceParticipant participant;
  final MediaSettings mediaSettings;
  final String notification;
  final String type;

  ParticipantJoinedNotification({
    required this.stamp,
    required this.participantId,
    required this.participant,
    required this.mediaSettings,
    required this.notification,
    required this.type,
  });

  factory ParticipantJoinedNotification.fromJson(Map<String, dynamic> json) {
    return ParticipantJoinedNotification(
      stamp: json['stamp'] ?? 0,
      participantId: json['participantId'] ?? 0,
      participant: ConferenceParticipant.fromJson(json['participant'] ?? {}),
      mediaSettings: MediaSettings.fromJson(json['mediaSettings'] ?? {}),
      notification: json['notification'] ?? '',
      type: json['type'] ?? '',
    );
  }
}

// Модель для уведомления registered-peer
class RegisteredPeerNotification {
  final int stamp;
  final PeerId peerId;
  final String platform;
  final String clientType;
  final String notification;
  final int participantId;
  final String participantType;
  final String type;

  RegisteredPeerNotification({
    required this.stamp,
    required this.peerId,
    required this.platform,
    required this.clientType,
    required this.notification,
    required this.participantId,
    required this.participantType,
    required this.type,
  });

  factory RegisteredPeerNotification.fromJson(Map<String, dynamic> json) {
    return RegisteredPeerNotification(
      stamp: json['stamp'] ?? 0,
      peerId: PeerId.fromJson(json['peerId'] ?? {}),
      platform: json['platform'] ?? '',
      clientType: json['clientType'] ?? '',
      notification: json['notification'] ?? '',
      participantId: json['participantId'] ?? 0,
      participantType: json['participantType'] ?? '',
      type: json['type'] ?? '',
    );
  }
}

// Модель для transmit-data команды
class TransmitDataCommand {
  final String command;
  final int sequence;
  final int participantId;
  final Map<String, dynamic> data;
  final String participantType;

  TransmitDataCommand({
    required this.command,
    required this.sequence,
    required this.participantId,
    required this.data,
    required this.participantType,
  });

  factory TransmitDataCommand.fromJson(Map<String, dynamic> json) {
    return TransmitDataCommand(
      command: json['command'] ?? '',
      sequence: json['sequence'] ?? 0,
      participantId: json['participantId'] ?? 0,
      data: json['data'] as Map<String, dynamic>? ?? {},
      participantType: json['participantType'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'command': command,
      'sequence': sequence,
      'participantId': participantId,
      'data': data,
      'participantType': participantType,
    };
  }
}
