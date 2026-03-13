class StartConversationPayload {
  final bool isVideo;

  const StartConversationPayload({
    required this.isVideo,
  });

  factory StartConversationPayload.create({bool isVideo = false}) {
    return StartConversationPayload(isVideo: isVideo);
  }

  Map<String, dynamic> toJson() {
    return {
      'is_video': isVideo,
    };
  }
}
