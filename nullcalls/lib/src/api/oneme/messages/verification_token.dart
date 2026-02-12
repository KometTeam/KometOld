class VerificationToken {
  final String token;

  const VerificationToken({required this.token});

  factory VerificationToken.fromJson(Map<String, dynamic> json) {
    return VerificationToken(
      token: json['token'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'token': token,
    };
  }
}
