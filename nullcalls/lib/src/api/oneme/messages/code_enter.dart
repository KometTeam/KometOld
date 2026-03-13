class CodeEnter {
  final String token;
  final String verifyCode;
  final String authTokenType;

  const CodeEnter({
    required this.token,
    required this.verifyCode,
    required this.authTokenType,
  });

  factory CodeEnter.create(String token, String verifyCode) {
    return CodeEnter(
      token: token,
      verifyCode: verifyCode,
      authTokenType: 'CHECK_CODE',
    );
  }

  static int get opcode => 18;

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'verifyCode': verifyCode,
      'authTokenType': authTokenType,
    };
  }
}
