import 'package:meta/meta.dart';

/// Модель профиля пользователя
@immutable
class Profile {
  final int id;
  final String phone;
  final String firstName;
  final String lastName;
  final String? description;
  final String? photoBaseUrl;
  final int photoId;
  final int updateTime;
  final List<String> options;
  final int accountStatus;
  final List<ProfileOption> profileOptions;

  const Profile({
    required this.id,
    required this.phone,
    required this.firstName,
    required this.lastName,
    this.description,
    this.photoBaseUrl,
    required this.photoId,
    required this.updateTime,
    required this.options,
    required this.accountStatus,
    required this.profileOptions,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    final profileData = json['contact'] as Map<String, dynamic>? ?? json;
    final names = profileData['names'] as List<dynamic>? ?? [];
    final nameData = names.isNotEmpty 
        ? names[0] as Map<String, dynamic> 
        : const <String, dynamic>{};

    return Profile(
      id: profileData['id'] ?? 0,
      phone: profileData['phone']?.toString() ?? '',
      firstName: nameData['firstName'] ?? '',
      lastName: nameData['lastName'] ?? '',
      description: profileData['description'] as String?,
      photoBaseUrl: profileData['baseUrl'] as String?,
      photoId: profileData['photoId'] ?? 0,
      updateTime: profileData['updateTime'] ?? 0,
      options: List<String>.from(profileData['options'] ?? []),
      accountStatus: profileData['accountStatus'] ?? 0,
      profileOptions: (json['profileOptions'] as List<dynamic>?)
              ?.map((o) => ProfileOption.fromJson(o as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  String get displayName {
    final fullName = '$firstName $lastName'.trim();
    return fullName.isNotEmpty ? fullName : 'Пользователь';
  }

  String get initials {
    final first = firstName.isNotEmpty ? firstName[0] : '';
    final last = lastName.isNotEmpty ? lastName[0] : '';
    return '$first$last'.toUpperCase();
  }

  String get formattedPhone {
    if (phone.length == 11 && phone.startsWith('7')) {
      return '+7 (${phone.substring(1, 4)}) ${phone.substring(4, 7)}-${phone.substring(7, 9)}-${phone.substring(9)}';
    }
    return phone;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'phone': phone,
    'firstName': firstName,
    'lastName': lastName,
    'description': description,
    'photoBaseUrl': photoBaseUrl,
    'photoId': photoId,
    'updateTime': updateTime,
    'options': options,
    'accountStatus': accountStatus,
    'profileOptions': profileOptions.map((o) => o.toJson()).toList(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Profile &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Profile(id: $id, name: $displayName)';
}

/// Опция профиля
@immutable
class ProfileOption {
  final String key;
  final dynamic value;

  const ProfileOption({required this.key, required this.value});

  factory ProfileOption.fromJson(Map<String, dynamic> json) => ProfileOption(
        key: json['key'] as String,
        value: json['value'],
      );

  Map<String, dynamic> toJson() => {'key': key, 'value': value};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileOption &&
          runtimeType == other.runtimeType &&
          key == other.key;

  @override
  int get hashCode => key.hashCode;
}
