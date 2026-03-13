class LoginData {
  final String uid;
  final String sessionKey;
  final String sessionSecretKey;
  final String apiServer;
  final String externalUserId;

  const LoginData({
    required this.uid,
    required this.sessionKey,
    required this.sessionSecretKey,
    required this.apiServer,
    required this.externalUserId,
  });

  factory LoginData.fromJson(Map<String, dynamic> json) {
    return LoginData(
      uid: json['uid'] as String,
      sessionKey: json['session_key'] as String,
      sessionSecretKey: json['session_secret_key'] as String,
      apiServer: json['api_server'] as String,
      externalUserId: json['external_user_id'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'session_key': sessionKey,
      'session_secret_key': sessionSecretKey,
      'api_server': apiServer,
      'external_user_id': externalUserId,
    };
  }
}
