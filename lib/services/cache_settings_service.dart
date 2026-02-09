import 'package:shared_preferences/shared_preferences.dart';
import '../utils/fresh_mode_helper.dart';

/// Предустановленные уровни TTL (времени жизни кэша)
enum CacheTTLLevel {
  /// Минимальный кэш - экономия памяти (1 час)
  minimal,
  /// Сбалансированный - оптимально для большинства (24 часа)
  balanced,
  /// Агрессивный кэш - максимальная производительность (7 дней)
  aggressive,
  /// Пользовательский уровень
  custom,
}

/// Настройки TTL для разных типов кэша
class CacheTTLSettings {
  final Duration chatsTTL;
  final Duration contactsTTL;
  final Duration messagesTTL;
  final Duration avatarsTTL;
  final Duration filesTTL;
  final Duration stickersTTL;
  final Duration audioTTL;
  final Duration profileTTL;

  const CacheTTLSettings({
    required this.chatsTTL,
    required this.contactsTTL,
    required this.messagesTTL,
    required this.avatarsTTL,
    required this.filesTTL,
    required this.stickersTTL,
    required this.audioTTL,
    required this.profileTTL,
  });

  /// Минимальные настройки (экономия памяти)
  static const minimal = CacheTTLSettings(
    chatsTTL: Duration(hours: 1),
    contactsTTL: Duration(hours: 6),
    messagesTTL: Duration(minutes: 30),
    avatarsTTL: Duration(hours: 12),
    filesTTL: Duration(hours: 6),
    stickersTTL: Duration(days: 1),
    audioTTL: Duration(hours: 2),
    profileTTL: Duration(days: 7),
  );

  /// Сбалансированные настройки (по умолчанию)
  static const balanced = CacheTTLSettings(
    chatsTTL: Duration(hours: 6),
    contactsTTL: Duration(hours: 24),
    messagesTTL: Duration(hours: 2),
    avatarsTTL: Duration(days: 7),
    filesTTL: Duration(days: 3),
    stickersTTL: Duration(days: 14),
    audioTTL: Duration(days: 1),
    profileTTL: Duration(days: 30),
  );

  /// Агрессивные настройки (максимум производительности)
  static const aggressive = CacheTTLSettings(
    chatsTTL: Duration(days: 7),
    contactsTTL: Duration(days: 30),
    messagesTTL: Duration(days: 3),
    avatarsTTL: Duration(days: 30),
    filesTTL: Duration(days: 14),
    stickersTTL: Duration(days: 30),
    audioTTL: Duration(days: 7),
    profileTTL: Duration(days: 90),
  );

  /// Получить настройки по уровню
  static CacheTTLSettings fromLevel(CacheTTLLevel level) {
    switch (level) {
      case CacheTTLLevel.minimal:
        return minimal;
      case CacheTTLLevel.balanced:
        return balanced;
      case CacheTTLLevel.aggressive:
        return aggressive;
      case CacheTTLLevel.custom:
        return balanced;
    }
  }
}

/// Сервис для управления настройками TTL кэша
class CacheSettingsService {
  static final CacheSettingsService _instance = CacheSettingsService._internal();
  factory CacheSettingsService() => _instance;
  CacheSettingsService._internal();

  SharedPreferences? _prefs;
  bool _initialized = false;

  // Ключи для SharedPreferences
  static const String _ttlLevelKey = 'cache_ttl_level';
  static const String _autoCleanupEnabledKey = 'cache_auto_cleanup_enabled';
  static const String _autoCleanupIntervalKey = 'cache_auto_cleanup_interval';
  static const String _maxCacheSizeMBKey = 'cache_max_size_mb';
  static const String _lastCleanupKey = 'cache_last_cleanup_time';

  // Кастомные TTL (в минутах)
  static const String _customChatsTTLKey = 'cache_custom_chats_ttl';
  static const String _customContactsTTLKey = 'cache_custom_contacts_ttl';
  static const String _customMessagesTTLKey = 'cache_custom_messages_ttl';
  static const String _customAvatarsTTLKey = 'cache_custom_avatars_ttl';
  static const String _customFilesTTLKey = 'cache_custom_files_ttl';

  /// Текущий уровень TTL
  CacheTTLLevel _currentLevel = CacheTTLLevel.balanced;
  
  /// Кастомные настройки (если выбран level = custom)
  CacheTTLSettings? _customSettings;

  /// Автоматическая очистка включена
  bool _autoCleanupEnabled = true;
  
  /// Интервал автоматической очистки (в часах)
  int _autoCleanupInterval = 24;
  
  /// Максимальный размер кэша в MB (0 = без ограничений)
  int _maxCacheSizeMB = 500;

  /// Инициализирован ли сервис
  bool get isInitialized => _initialized;

  /// Текущий уровень TTL
  CacheTTLLevel get currentLevel => _currentLevel;

  /// Автоочистка включена
  bool get autoCleanupEnabled => _autoCleanupEnabled;

  /// Интервал автоочистки в часах
  int get autoCleanupInterval => _autoCleanupInterval;

  /// Максимальный размер кэша в MB
  int get maxCacheSizeMB => _maxCacheSizeMB;

  /// Получить текущие настройки TTL
  CacheTTLSettings get currentSettings {
    if (_currentLevel == CacheTTLLevel.custom && _customSettings != null) {
      return _customSettings!;
    }
    return CacheTTLSettings.fromLevel(_currentLevel);
  }

  /// Инициализация сервиса
  Future<void> initialize() async {
    if (_initialized) return;

    _prefs = await FreshModeHelper.getSharedPreferences();
    await _loadSettings();
    
    _initialized = true;
    print('✅ CacheSettingsService инициализирован (level: $_currentLevel)');
  }

  /// Загрузка настроек из SharedPreferences
  Future<void> _loadSettings() async {
    if (_prefs == null) return;

    // Загружаем уровень TTL
    final levelIndex = _prefs!.getInt(_ttlLevelKey) ?? 1; // balanced по умолчанию
    _currentLevel = CacheTTLLevel.values[levelIndex.clamp(0, CacheTTLLevel.values.length - 1)];

    // Загружаем настройки автоочистки
    _autoCleanupEnabled = _prefs!.getBool(_autoCleanupEnabledKey) ?? true;
    _autoCleanupInterval = _prefs!.getInt(_autoCleanupIntervalKey) ?? 24;
    _maxCacheSizeMB = _prefs!.getInt(_maxCacheSizeMBKey) ?? 500;

    // Загружаем кастомные TTL
    if (_currentLevel == CacheTTLLevel.custom) {
      _customSettings = CacheTTLSettings(
        chatsTTL: Duration(minutes: _prefs!.getInt(_customChatsTTLKey) ?? 360),
        contactsTTL: Duration(minutes: _prefs!.getInt(_customContactsTTLKey) ?? 1440),
        messagesTTL: Duration(minutes: _prefs!.getInt(_customMessagesTTLKey) ?? 120),
        avatarsTTL: Duration(days: _prefs!.getInt(_customAvatarsTTLKey) ?? 7),
        filesTTL: Duration(hours: _prefs!.getInt(_customFilesTTLKey) ?? 72),
        stickersTTL: CacheTTLSettings.balanced.stickersTTL,
        audioTTL: CacheTTLSettings.balanced.audioTTL,
        profileTTL: CacheTTLSettings.balanced.profileTTL,
      );
    }
  }

  /// Установить уровень TTL
  Future<void> setTTLLevel(CacheTTLLevel level) async {
    _currentLevel = level;
    await _prefs?.setInt(_ttlLevelKey, level.index);
    print('✅ Уровень TTL изменен на: $level');
  }

  /// Установить кастомные настройки TTL
  Future<void> setCustomTTL({
    Duration? chatsTTL,
    Duration? contactsTTL,
    Duration? messagesTTL,
    Duration? avatarsTTL,
    Duration? filesTTL,
  }) async {
    _currentLevel = CacheTTLLevel.custom;
    await _prefs?.setInt(_ttlLevelKey, CacheTTLLevel.custom.index);

    _customSettings = CacheTTLSettings(
      chatsTTL: chatsTTL ?? CacheTTLSettings.balanced.chatsTTL,
      contactsTTL: contactsTTL ?? CacheTTLSettings.balanced.contactsTTL,
      messagesTTL: messagesTTL ?? CacheTTLSettings.balanced.messagesTTL,
      avatarsTTL: avatarsTTL ?? CacheTTLSettings.balanced.avatarsTTL,
      filesTTL: filesTTL ?? CacheTTLSettings.balanced.filesTTL,
      stickersTTL: CacheTTLSettings.balanced.stickersTTL,
      audioTTL: CacheTTLSettings.balanced.audioTTL,
      profileTTL: CacheTTLSettings.balanced.profileTTL,
    );

    // Сохраняем кастомные значения
    if (chatsTTL != null) await _prefs?.setInt(_customChatsTTLKey, chatsTTL.inMinutes);
    if (contactsTTL != null) await _prefs?.setInt(_customContactsTTLKey, contactsTTL.inMinutes);
    if (messagesTTL != null) await _prefs?.setInt(_customMessagesTTLKey, messagesTTL.inMinutes);
    if (avatarsTTL != null) await _prefs?.setInt(_customAvatarsTTLKey, avatarsTTL.inDays);
    if (filesTTL != null) await _prefs?.setInt(_customFilesTTLKey, filesTTL.inHours);

    print('✅ Кастомные настройки TTL сохранены');
  }

  /// Включить/выключить автоочистку
  Future<void> setAutoCleanupEnabled(bool enabled) async {
    _autoCleanupEnabled = enabled;
    await _prefs?.setBool(_autoCleanupEnabledKey, enabled);
    print('✅ Автоочистка ${enabled ? 'включена' : 'выключена'}');
  }

  /// Установить интервал автоочистки (в часах)
  Future<void> setAutoCleanupInterval(int hours) async {
    _autoCleanupInterval = hours.clamp(1, 168); // от 1 часа до 7 дней
    await _prefs?.setInt(_autoCleanupIntervalKey, _autoCleanupInterval);
    print('✅ Интервал автоочистки: $_autoCleanupInterval часов');
  }

  /// Установить максимальный размер кэша (MB)
  Future<void> setMaxCacheSizeMB(int mb) async {
    _maxCacheSizeMB = mb.clamp(0, 5000); // от 0 (без ограничений) до 5GB
    await _prefs?.setInt(_maxCacheSizeMBKey, _maxCacheSizeMB);
    print('✅ Максимальный размер кэша: $_maxCacheSizeMB MB');
  }

  /// Обновить время последней очистки
  Future<void> updateLastCleanupTime() async {
    await _prefs?.setInt(_lastCleanupKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Получить время последней очистки
  DateTime? getLastCleanupTime() {
    final timestamp = _prefs?.getInt(_lastCleanupKey);
    if (timestamp != null) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    return null;
  }

  /// Проверить, нужна ли очистка
  bool needsCleanup() {
    if (!_autoCleanupEnabled) return false;

    final lastCleanup = getLastCleanupTime();
    if (lastCleanup == null) return true;

    final nextCleanup = lastCleanup.add(Duration(hours: _autoCleanupInterval));
    return DateTime.now().isAfter(nextCleanup);
  }

  /// Получить название уровня на русском
  static String getLevelName(CacheTTLLevel level) {
    switch (level) {
      case CacheTTLLevel.minimal:
        return 'Минимальный';
      case CacheTTLLevel.balanced:
        return 'Сбалансированный';
      case CacheTTLLevel.aggressive:
        return 'Агрессивный';
      case CacheTTLLevel.custom:
        return 'Пользовательский';
    }
  }

  /// Получить описание уровня
  static String getLevelDescription(CacheTTLLevel level) {
    switch (level) {
      case CacheTTLLevel.minimal:
        return 'Минимальное использование памяти, чаще загрузка данных';
      case CacheTTLLevel.balanced:
        return 'Оптимальный баланс между скоростью и памятью';
      case CacheTTLLevel.aggressive:
        return 'Максимальная производительность, больше памяти';
      case CacheTTLLevel.custom:
        return 'Настройте TTL под свои нужды';
    }
  }

  /// Получить иконку для уровня
  static String getLevelIcon(CacheTTLLevel level) {
    switch (level) {
      case CacheTTLLevel.minimal:
        return '🍃';
      case CacheTTLLevel.balanced:
        return '⚖️';
      case CacheTTLLevel.aggressive:
        return '🚀';
      case CacheTTLLevel.custom:
        return '⚙️';
    }
  }

  /// Сбросить настройки к значениям по умолчанию
  Future<void> resetToDefaults() async {
    await setTTLLevel(CacheTTLLevel.balanced);
    await setAutoCleanupEnabled(true);
    await setAutoCleanupInterval(24);
    await setMaxCacheSizeMB(500);
    _customSettings = null;
    print('✅ Настройки кэша сброшены к значениям по умолчанию');
  }
}
