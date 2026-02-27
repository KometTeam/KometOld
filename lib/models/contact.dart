class Contact {
  final int id;
  final String name;
  final String firstName;
  final String lastName;
  final String? description;
  final String? photoBaseUrl;
  final bool isBlocked;
  final bool isBlockedByMe;
  final int accountStatus;
  final String? status;
  final List<String> options;
  final String? link;

  Contact({
    required this.id,
    required this.name,
    required this.firstName,
    required this.lastName,
    this.description,
    this.photoBaseUrl,
    this.isBlocked = false,
    this.isBlockedByMe = false,
    this.accountStatus = 0,
    this.status,
    this.options = const [],
    this.link,
  });

  bool get isBot => options.contains('BOT');

  bool get isUserBlocked => isBlockedByMe || isBlocked;

  Contact copyWith({
    int? id,
    String? name,
    String? firstName,
    String? lastName,
    String? description,
    String? photoBaseUrl,
    bool? isBlocked,
    bool? isBlockedByMe,
    int? accountStatus,
    String? status,
    List<String>? options,
  }) {
    return Contact(
      id: id ?? this.id,
      name: name ?? this.name,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      description: description ?? this.description,
      photoBaseUrl: photoBaseUrl ?? this.photoBaseUrl,
      isBlocked: isBlocked ?? this.isBlocked,
      isBlockedByMe: isBlockedByMe ?? this.isBlockedByMe,
      accountStatus: accountStatus ?? this.accountStatus,
      status: status ?? this.status,
      options: options ?? this.options,
      link: link ?? this.link,
    );
  }

  factory Contact.fromJson(Map<String, dynamic> json) {
    final namesGroup = json['names'] as List?;
    final nameData = (namesGroup != null && namesGroup.isNotEmpty)
        ? namesGroup[0]
        : null;
    final userId = json['id'] as int;

    String finalFirstName = json['firstName']?.toString() ?? '';
    String finalLastName = json['lastName']?.toString() ?? '';
    String finalName =
        json['name']?.toString() ??
        json['username']?.toString() ??
        userId.toString();

    if (nameData != null) {
      finalFirstName = nameData['firstName'] ?? finalFirstName;
      finalLastName = nameData['lastName'] ?? finalLastName;
      final fullName = '$finalFirstName $finalLastName'.trim();
      String rawName = nameData['name'] ?? finalName;
      if (rawName.startsWith('ID ')) {
        final maybeId = rawName.substring(3);
        if (RegExp(r'^\d+$').hasMatch(maybeId)) {
          rawName = maybeId;
        }
      }
      finalName = fullName.isNotEmpty ? fullName : rawName;
    } else {
      final fullName = '$finalFirstName $finalLastName'.trim();
      if (fullName.isNotEmpty) {
        finalName = fullName;
      }
    }

    final status = json['status'];
    final isBlocked = status == 'BLOCKED';

    return Contact(
      id: userId,
      name: finalName,
      firstName: finalFirstName,
      lastName: finalLastName,
      description: json['description'],
      photoBaseUrl: json['baseUrl'],
      isBlocked: isBlocked,
      isBlockedByMe: isBlocked,
      accountStatus: json['accountStatus'] ?? 0,
      status: json['status'],
      options: List<String>.from(json['options'] ?? []),
      link: json['link']?.toString(),
    );
  }
}
