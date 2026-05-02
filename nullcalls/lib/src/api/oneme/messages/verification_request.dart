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
