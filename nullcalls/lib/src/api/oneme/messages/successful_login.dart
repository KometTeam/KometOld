class Login {
  final String token;

  const Login({required this.token});

  factory Login.fromJson(Map<String, dynamic> json) {
    return Login(token: json['token'] as String);
  }
}

class TokenAttributes {
  final Login login;

  const TokenAttributes({required this.login});

  factory TokenAttributes.fromJson(Map<String, dynamic> json) {
    return TokenAttributes(
      login: Login.fromJson(json['LOGIN'] as Map<String, dynamic>),
    );
  }
}

class SuccessfulLogin {
  final TokenAttributes tokenAttributes;

  const SuccessfulLogin({required this.tokenAttributes});

  factory SuccessfulLogin.fromJson(Map<String, dynamic> json) {
    return SuccessfulLogin(
      tokenAttributes: TokenAttributes.fromJson(
        json['tokenAttrs'] as Map<String, dynamic>,
      ),
    );
  }

  String get token => tokenAttributes.login.token;
}
