/// Запрос токена для звонков (opcode 158)
class CallTokenRequest {
  const CallTokenRequest();

  static int get opcode => 158;

  Map<String, dynamic> toJson() {
    return {};
  }
}

/// Ответ с токеном для звонков
class CallToken {
  final String token;

  const CallToken({required this.token});

  factory CallToken.fromJson(Map<String, dynamic> json) {
    return CallToken(
      token: json['token'] as String,
    );
  }
}
