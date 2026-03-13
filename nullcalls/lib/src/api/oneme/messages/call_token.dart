class CallToken {
  final String token;

  const CallToken({required this.token});

  factory CallToken.fromJson(Map<String, dynamic> json) {
    return CallToken(
      token: json['token'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'token': token,
    };
  }
}
