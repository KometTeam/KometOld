import 'package:uuid/uuid.dart';

final _uuid = const Uuid();

class SessionData {
  final String token;
  final String clientType;
  final String clientVersion;
  final String deviceId;
  final int version;

  const SessionData({
    required this.token,
    required this.clientType,
    required this.clientVersion,
    required this.deviceId,
    required this.version,
  });

  factory SessionData.create(String token) {
    return SessionData(
      token: token,
      clientType: 'SDK_JS',
      clientVersion: '1.1',
      deviceId: _uuid.v4(),
      version: 3,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'auth_token': token,
      'client_type': clientType,
      'client_version': clientVersion,
      'device_id': deviceId,
      'version': version,
    };
  }
}
