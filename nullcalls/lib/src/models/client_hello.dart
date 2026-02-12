import 'package:uuid/uuid.dart';

final _uuid = const Uuid();

/// Модель для handshake сообщения (opcode 6)
class ClientHello {
  final String mtInstanceId;
  final int clientSessionId;
  final String deviceId;
  final Map<String, dynamic> userAgent;

  ClientHello({
    required this.mtInstanceId,
    required this.clientSessionId,
    required this.deviceId,
    required this.userAgent,
  });

  factory ClientHello.create({
    String? mtInstanceId,
    int? clientSessionId,
    String? deviceId,
  }) {
    return ClientHello(
      mtInstanceId: mtInstanceId ?? _uuid.v4(),
      clientSessionId: clientSessionId ?? 1,
      deviceId: deviceId ?? _uuid.v4(),
      userAgent: _defaultUserAgent(),
    );
  }

  static int get opcode => 6;

  Map<String, dynamic> toJson() {
    return {
      'mt_instanceid': mtInstanceId,
      'clientSessionId': clientSessionId,
      'deviceId': deviceId,
      'userAgent': userAgent,
    };
  }

  static Map<String, dynamic> _defaultUserAgent() {
    return {
      'deviceType': 'ANDROID',
      'locale': 'ru',
      'deviceLocale': 'ru',
      'osVersion': 'Android 14',
      'deviceName': 'Samsung Galaxy S23',
      'appVersion': '25.21.3',
      'screen': 'xxhdpi 480dpi 1080x2340',
      'timezone': 'Europe/Moscow',
      'pushDeviceType': 'GCM',
      'arch': 'arm64-v8a',
      'buildNumber': 6498,
    };
  }
}
