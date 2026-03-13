class MediaSettings {
  final bool isAudioEnabled;
  final bool isVideoEnabled;
  final bool isScreenSharingEnabled;
  final bool isFastScreenSharingEnabled;
  final bool isAudioSharingEnabled;
  final bool isAnimojiEnabled;

  const MediaSettings({
    required this.isAudioEnabled,
    required this.isVideoEnabled,
    required this.isScreenSharingEnabled,
    required this.isFastScreenSharingEnabled,
    required this.isAudioSharingEnabled,
    required this.isAnimojiEnabled,
  });

  factory MediaSettings.audioOnly() {
    return const MediaSettings(
      isAudioEnabled: true,
      isVideoEnabled: false,
      isScreenSharingEnabled: false,
      isFastScreenSharingEnabled: false,
      isAudioSharingEnabled: false,
      isAnimojiEnabled: false,
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
}

class AcceptCall {
  final String command;
  final int sequence;
  final MediaSettings mediaSettings;

  const AcceptCall({
    required this.command,
    required this.sequence,
    required this.mediaSettings,
  });

  factory AcceptCall.create(int sequence) {
    return AcceptCall(
      command: 'accept-call',
      sequence: sequence,
      mediaSettings: MediaSettings.audioOnly(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'command': command,
      'sequence': sequence,
      'mediaSettings': mediaSettings.toJson(),
    };
  }
}
