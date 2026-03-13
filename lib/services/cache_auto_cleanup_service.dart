import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'cache_service.dart';
import 'cache_settings_service.dart';
import 'avatar_cache_service.dart';
import 'chat_cache_service.dart';
import 'profile_cache_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис автоматической очистки кэша
class CacheAutoCleanupService {
  static final CacheAutoCleanupService _instance = CacheAutoCleanupService._internal();
  factory CacheAutoCleanupService() => _instance;
  CacheAutoCleanupService._internal();

  final CacheService _cacheService = CacheService();
  final CacheSettingsService _settingsService = CacheSettingsService();
  final AvatarCacheService _avatarCacheService = AvatarCacheService();
  final ChatCacheService _chatCacheService = ChatCacheService();
  final ProfileCacheService _profileCacheService = ProfileCacheService();

  Timer? _cleanupTimer;
  bool _isRunning = false;
  bool _initialized = false;

  // Статистика последней очистки
  CleanupStats? _lastCleanupStats;

  /// Инициализирован ли сервис
  bool get isInitialized => _initialized;

  /// Идет ли сейчас очистка
  bool get isRunning => _isRunning;

  /// Статистика последней очистки
  CleanupStats? get lastCleanupStats => _lastCleanupStats;

  /// Инициализация сервиса
  Future<void> initialize() async {
    if (_initialized) return;

    await _settingsService.initialize();
    await _cacheService.initialize();
    await _avatarCacheService.initialize();
    await _chatCacheService.initialize();
    await _profileCacheService.initialize();

    _initialized = true;
    print('✅ CacheAutoCleanupService инициализирован');

    // Проверяем, нужна ли очистка при старте
    if (_settingsService.needsCleanup()) {
      print('🧹 Требуется очистка кэша при старте');
      await performCleanup();
    }

    // Запускаем периодическую проверку
    _startPeriodicCheck();
  }

  /// Запуск периодической проверки
  void _startPeriodicCheck() {
    _cleanupTimer?.cancel();

    // Проверяем каждые 15 минут
    _cleanupTimer = Timer.periodic(const Duration(minutes: 15), (_) async {
      if (_settingsService.autoCleanupEnabled && _settingsService.needsCleanup()) {
        print('🧹 Запланированная очистка кэша');
        await performCleanup();
      }
    });

    print('⏰ Периодическая проверка кэша запущена');
  }

  /// Остановка сервиса
  void dispose() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    print('🛑 CacheAutoCleanupService остановлен');
  }

  /// Выполнить очистку кэша
  Future<CleanupStats> performCleanup({bool force = false}) async {
    if (_isRunning && !force) {
      print('⚠️ Очистка уже выполняется');
      return _lastCleanupStats ?? CleanupStats.empty();
    }

    _isRunning = true;
    final stopwatch = Stopwatch()..start();

    print('🧹 Начинаем очистку кэша...');

    final stats = CleanupStats();

    try {
      // 1. Очистка устаревших файлов по TTL
      await _cleanupExpiredFiles(stats);

      // 2. Очистка по максимальному размеру
      await _cleanupBySizeLimit(stats);

      // 3. Очистка старых записей в SharedPreferences
      await _cleanupExpiredPrefs(stats);

      // 4. Очистка памяти
      await _cleanupMemoryCache(stats);

      // Обновляем время очистки
      await _settingsService.updateLastCleanupTime();

      stopwatch.stop();
      stats.duration = stopwatch.elapsed;

      _lastCleanupStats = stats;

      print('✅ Очистка кэша завершена за ${stats.duration.inMilliseconds}ms');
      print('   Удалено файлов: ${stats.deletedFiles}');
      print('   Освобождено: ${stats.freedSpaceMB.toStringAsFixed(2)} MB');

    } catch (e, stackTrace) {
      print('❌ Ошибка при очистке кэша: $e');
      print(stackTrace);
    } finally {
      _isRunning = false;
    }

    return stats;
  }

  /// Очистка устаревших файлов
  Future<void> _cleanupExpiredFiles(CleanupStats stats) async {
    final cacheDir = await getApplicationCacheDirectory();
    final settings = _settingsService.currentSettings;

    final directories = {
      'images': settings.filesTTL,
      'audio': settings.audioTTL,
      'stickers': settings.stickersTTL,
      'avatars': settings.avatarsTTL,
      'files': settings.filesTTL,
    };

    for (final entry in directories.entries) {
      final dir = Directory('${cacheDir.path}/${entry.key}');
      if (!await dir.exists()) continue;

      final ttl = entry.value;
      final cutoffTime = DateTime.now().subtract(ttl);

      try {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File) {
            try {
              final stat = await entity.stat();
              if (stat.modified.isBefore(cutoffTime)) {
                final size = await entity.length();
                await entity.delete();
                stats.deletedFiles++;
                stats.freedSpaceBytes += size;
              }
            } catch (e) {
              // Игнорируем ошибки доступа к файлам
            }
          }
        }
      } catch (e) {
        print('⚠️ Ошибка очистки директории ${entry.key}: $e');
      }
    }
  }

  /// Очистка по лимиту размера
  Future<void> _cleanupBySizeLimit(CleanupStats stats) async {
    final maxSizeMB = _settingsService.maxCacheSizeMB;
    if (maxSizeMB <= 0) return; // 0 = без ограничений

    final cacheDir = await getApplicationCacheDirectory();
    final maxSizeBytes = maxSizeMB * 1024 * 1024;

    // Собираем все файлы с их размерами
    final List<_CacheFileInfo> files = [];
    int totalSize = 0;

    try {
      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            final size = await entity.length();
            files.add(_CacheFileInfo(
              file: entity,
              size: size,
              lastAccessed: stat.accessed,
              lastModified: stat.modified,
            ));
            totalSize += size;
          } catch (e) {
            // Игнорируем ошибки
          }
        }
      }
    } catch (e) {
      print('⚠️ Ошибка подсчета размера кэша: $e');
      return;
    }

    // Если размер превышает лимит, удаляем самые старые файлы
    if (totalSize > maxSizeBytes) {
      // Сортируем по времени последнего доступа (старые в начало)
      files.sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));

      int targetSize = totalSize;
      for (final fileInfo in files) {
        if (targetSize <= maxSizeBytes * 0.8) break; // Оставляем 80% от лимита

        try {
          await fileInfo.file.delete();
          stats.deletedFiles++;
          stats.freedSpaceBytes += fileInfo.size;
          targetSize -= fileInfo.size;
        } catch (e) {
          // Игнорируем ошибки
        }
      }
    }
  }

  /// Очистка устаревших записей в SharedPreferences
  Future<void> _cleanupExpiredPrefs(CleanupStats stats) async {
    final prefs = await SharedPreferences.getInstance();
    final settings = _settingsService.currentSettings;

    final keys = prefs.getKeys().where((key) => key.startsWith('cache_'));
    final now = DateTime.now();

    for (final key in keys) {
      try {
        final data = prefs.getString(key);
        if (data == null) continue;

        // Парсим JSON для проверки timestamp
        // Простая проверка - если ключ содержит timestamp и он просрочен
        if (key.contains('chat') && now.difference(
          DateTime.fromMillisecondsSinceEpoch(
            prefs.getInt('${key}_timestamp') ?? now.millisecondsSinceEpoch
          )
        ) > settings.chatsTTL) {
          await prefs.remove(key);
          stats.deletedPrefs++;
        }
      } catch (e) {
        // Игнорируем ошибки парсинга
      }
    }
  }

  /// Очистка кэша в памяти
  Future<void> _cleanupMemoryCache(CleanupStats stats) async {
    // Очищаем устаревшие записи в ChatCacheService
    // (реализовано в самом сервисе при доступе)

    // Очищаем старые аватарки из памяти
    // (реализовано в AvatarCacheService)
  }

  /// Получить информацию о размере кэша
  Future<CacheSizeInfo> getCacheSizeInfo() async {
    final cacheDir = await getApplicationCacheDirectory();
    int totalSize = 0;
    int fileCount = 0;
    final Map<String, int> sizesByType = {};

    try {
      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File) {
          try {
            final size = await entity.length();
            totalSize += size;
            fileCount++;

            // Определяем тип по пути
            final path = entity.path;
            String type = 'other';
            if (path.contains('/avatars/')) {
              type = 'avatars';
            } else if (path.contains('/images/')) {
              type = 'images';
            } else if (path.contains('/audio/')) {
              type = 'audio';
            } else if (path.contains('/stickers/')) {
              type = 'stickers';
            } else if (path.contains('/files/')) {
              type = 'files';
            } else if (path.contains('/chats/')) {
              type = 'chats';
            }

            sizesByType[type] = (sizesByType[type] ?? 0) + size;
          } catch (e) {
            // Игнорируем ошибки
          }
        }
      }
    } catch (e) {
      print('⚠️ Ошибка подсчета размера кэша: $e');
    }

    return CacheSizeInfo(
      totalSizeBytes: totalSize,
      fileCount: fileCount,
      sizesByType: sizesByType,
    );
  }

  /// Принудительная очистка всего кэша
  Future<void> clearAllCache() async {
    print('🗑️ Принудительная очистка всего кэша...');

    await _cacheService.clear();
    await _avatarCacheService.clearAvatarCache();
    await _chatCacheService.clearAllChatCache();
    await _profileCacheService.clearProfileCache();

    await _settingsService.updateLastCleanupTime();

    print('✅ Весь кэш очищен');
  }
}

/// Информация о размере кэша
class CacheSizeInfo {
  final int totalSizeBytes;
  final int fileCount;
  final Map<String, int> sizesByType;

  CacheSizeInfo({
    required this.totalSizeBytes,
    required this.fileCount,
    required this.sizesByType,
  });

  double get totalSizeMB => totalSizeBytes / (1024 * 1024);

  String get formattedSize {
    if (totalSizeBytes < 1024) return '$totalSizeBytes B';
    if (totalSizeBytes < 1024 * 1024) {
      return '${(totalSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (totalSizeBytes < 1024 * 1024 * 1024) {
      return '${(totalSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(totalSizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Статистика очистки
class CleanupStats {
  int deletedFiles = 0;
  int deletedPrefs = 0;
  int freedSpaceBytes = 0;
  Duration duration = Duration.zero;

  CleanupStats();

  CleanupStats.empty();

  double get freedSpaceMB => freedSpaceBytes / (1024 * 1024);

  String get formattedFreedSpace {
    if (freedSpaceBytes < 1024) return '$freedSpaceBytes B';
    if (freedSpaceBytes < 1024 * 1024) {
      return '${(freedSpaceBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${freedSpaceMB.toStringAsFixed(2)} MB';
  }
}

/// Информация о файле в кэше
class _CacheFileInfo {
  final File file;
  final int size;
  final DateTime lastAccessed;
  final DateTime lastModified;

  _CacheFileInfo({
    required this.file,
    required this.size,
    required this.lastAccessed,
    required this.lastModified,
  });
}
