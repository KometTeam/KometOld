/// URL-адреса и константы приложения
class AppUrls {
  AppUrls._();

  /// WebSocket endpoints
  static const List<String> websocketUrls = [
    'wss://ws-api.oneme.ru:443/websocket',
    'wss://ws-api.oneme.ru/websocket',
    'wss://ws-api.oneme.ru:8443/websocket',
    'ws://ws-api.oneme.ru:80/websocket',
    'ws://ws-api.oneme.ru/websocket',
    'ws://ws-api.oneme.ru:8080/websocket',
  ];

  static const String webOrigin = 'https://web.max.ru';

  /// Используется на экране Terms of Service
  static const String legalUrl = 'https://legal.max.ru/ps';

  static const String telegramChannel = 'https://t.me/TeamKomet';

  /// Префикс ссылки для присоединения к группе
  static const String joinLinkPrefix = 'https://max.ru/join/';

  /// Префикс ссылки для поиска по ID
  static const String idLinkPrefix = 'https://max.ru/id';

  /// URL для проверки whitelist (тестовые билды)
  static const String whitelistCheckUrl = 'https://wl.liarts.ru/wl';
}
