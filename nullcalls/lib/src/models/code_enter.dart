/// Ввод кода верификации (opcode 18)
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

/// Успешная авторизация
class SuccessfulLogin {
  final String token;

  const SuccessfulLogin({required this.token});

  factory SuccessfulLogin.fromJson(Map<String, dynamic> json) {
    final tokenAttrs = json['tokenAttrs'] as Map<String, dynamic>;
    final login = tokenAttrs['LOGIN'] as Map<String, dynamic>;
    return SuccessfulLogin(
      token: login['token'] as String,
    );
  }
}
