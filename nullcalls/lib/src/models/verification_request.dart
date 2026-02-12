/// Запрос на отправку кода верификации (opcode 17)
class VerificationRequest {
  final String phone;
  final String type;
  final String language;

  const VerificationRequest({
    required this.phone,
    required this.type,
    required this.language,
  });

  factory VerificationRequest.create(String phone) {
    return VerificationRequest(
      phone: phone,
      type: 'START_AUTH',
      language: 'ru',
    );
  }

  static int get opcode => 17;

  Map<String, dynamic> toJson() {
    return {
      'phone': phone,
      'type': type,
      'language': language,
    };
  }
}

/// Ответ с токеном верификации
class VerificationToken {
  final String token;

  const VerificationToken({required this.token});

  factory VerificationToken.fromJson(Map<String, dynamic> json) {
    return VerificationToken(
      token: json['token'] as String,
    );
  }
}
