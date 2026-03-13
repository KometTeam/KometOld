class Credentials {
  final String ufrag;
  final String password;

  const Credentials({
    required this.ufrag,
    required this.password,
  });

  factory Credentials.fromJson(Map<String, dynamic> json) {
    return Credentials(
      ufrag: json['ufrag'] as String,
      password: json['password'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ufrag': ufrag,
      'password': password,
    };
  }
}
