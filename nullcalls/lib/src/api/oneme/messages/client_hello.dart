import 'package:uuid/uuid.dart';

final _uuid = const Uuid();

enum DeviceType {
  web('WEB');

  final String value;
  const DeviceType(this.value);
}

enum Locale {
  russian('ru');

  final String value;
  const Locale(this.value);
}

class UserAgent {
  final String deviceType;
  final String locale;
  final String deviceLocale;
  final String osVersion;
  final String deviceName;
  final String headerUserAgent;
  final String appVersion;
  final String screen;
  final String timezone;

  const UserAgent({
    required this.deviceType,
    required this.locale,
    required this.deviceLocale,
    required this.osVersion,
    required this.deviceName,
    required this.headerUserAgent,
    required this.appVersion,
    required this.screen,
    required this.timezone,
  });

  factory UserAgent.defaultAgent() {
    return const UserAgent(
      deviceType: 'WEB',
      locale: 'ru',
      deviceLocale: 'ru',
      osVersion: 'Windows',
      deviceName: 'Chrome',
      headerUserAgent:
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36',
      appVersion: '25.11.2',
      screen: '1080x1920 1.0x',
      timezone: 'Europe/Moscow',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceType': deviceType,
      'locale': locale,
      'deviceLocale': deviceLocale,
      'osVersion': osVersion,
      'deviceName': deviceName,
      'headerUserAgent': headerUserAgent,
      'appVersion': appVersion,
      'screen': screen,
      'timezone': timezone,
    };
  }
}

class ClientHello {
  final UserAgent userAgent;
  final String deviceId;

  ClientHello({
    required this.userAgent,
    required this.deviceId,
  });

  factory ClientHello.create() {
    return ClientHello(
      userAgent: UserAgent.defaultAgent(),
      deviceId: _uuid.v4(),
    );
  }

  static int get opcode => 6;

  Map<String, dynamic> toJson() {
    return {
      'userAgent': userAgent.toJson(),
      'deviceId': deviceId,
    };
  }
}
