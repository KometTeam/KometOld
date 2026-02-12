class TurnServer {
  final List<String> urls;
  final String username;
  final String password;

  const TurnServer({
    required this.urls,
    required this.username,
    required this.password,
  });

  factory TurnServer.fromJson(Map<String, dynamic> json) {
    return TurnServer(
      urls: (json['urls'] as List).cast<String>(),
      username: json['username'] as String,
      password: json['credential'] as String,
    );
  }
}

class StunServer {
  final List<String> urls;

  const StunServer({required this.urls});

  factory StunServer.fromJson(Map<String, dynamic> json) {
    return StunServer(
      urls: (json['urls'] as List).cast<String>(),
    );
  }
}

class StartedConversationInfo {
  final TurnServer turnServer;
  final StunServer stunServer;
  final String endpoint;

  const StartedConversationInfo({
    required this.turnServer,
    required this.stunServer,
    required this.endpoint,
  });

  factory StartedConversationInfo.fromJson(Map<String, dynamic> json) {
    return StartedConversationInfo(
      turnServer: TurnServer.fromJson(json['turn_server'] as Map<String, dynamic>),
      stunServer: StunServer.fromJson(json['stun_server'] as Map<String, dynamic>),
      endpoint: json['endpoint'] as String,
    );
  }
}
