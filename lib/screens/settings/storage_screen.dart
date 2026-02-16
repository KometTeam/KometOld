import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import '../../utils/download_path_helper.dart';
import '../../services/cache_settings_service.dart';
import '../../services/cache_auto_cleanup_service.dart';
import '../cache_management_screen.dart';

class StorageScreen extends StatefulWidget {
  final bool isModal;

  const StorageScreen({super.key, this.isModal = false});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  StorageInfo? _storageInfo;
  bool _isLoading = true;

  // Настройки кэша
  final CacheSettingsService _cacheSettings = CacheSettingsService();
  final CacheAutoCleanupService _autoCleanup = CacheAutoCleanupService();
  
  bool _isCacheSettingsLoading = true;
  CacheTTLLevel _currentTTLLevel = CacheTTLLevel.balanced;
  bool _autoCleanupEnabled = true;
  int _autoCleanupInterval = 24;
  int _maxCacheSizeMB = 500;
  
  CacheSizeInfo? _cacheSizeInfo;
  CleanupStats? _lastCleanupStats;

  Widget buildModalContent(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildStorageChart(colors),
                const SizedBox(height: 20),

                _buildStorageDetails(colors),
                const SizedBox(height: 20),

                _buildCacheSettingsSection(colors),
                const SizedBox(height: 20),

                _buildDownloadFolderSetting(colors),
                const SizedBox(height: 20),

                _buildActionButtons(colors),
              ],
            ),
          );
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _loadStorageInfo();
    _loadCacheSettings();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadStorageInfo() async {
    try {
      final info = await _getStorageInfo();
      setState(() {
        _storageInfo = info;
        _isLoading = false;
      });
      _animationController.forward();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<StorageInfo> _getStorageInfo() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = await getApplicationCacheDirectory();

    final appSize = await _getDirectorySize(appDir);
    final cacheSize = await _getDirectorySize(cacheDir);
    final totalSize = appSize + cacheSize;

    // Расчёт размеров по типам (приблизительно)
    final messagesSize = totalSize > 0 ? (cacheSize * 0.4).round() : 0;
    final mediaSize = totalSize > 0 ? (cacheSize * 0.35).round() : 0;
    final cacheSizeAdjusted = totalSize > 0 ? (cacheSize * 0.25).round() : 0;
    final otherSize = totalSize - messagesSize - mediaSize - cacheSizeAdjusted;

    return StorageInfo(
      totalSize: totalSize,
      messagesSize: messagesSize,
      mediaSize: mediaSize,
      cacheSize: cacheSizeAdjusted,
      otherSize: otherSize,
    );
  }

  // Загрузка настроек кэша
  Future<void> _loadCacheSettings() async {
    try {
      await _cacheSettings.initialize();
      await _autoCleanup.initialize();

      final sizeInfo = await _autoCleanup.getCacheSizeInfo();

      if (mounted) {
        setState(() {
          _currentTTLLevel = _cacheSettings.currentLevel;
          _autoCleanupEnabled = _cacheSettings.autoCleanupEnabled;
          _autoCleanupInterval = _cacheSettings.autoCleanupInterval;
          _maxCacheSizeMB = _cacheSettings.maxCacheSizeMB;
          _cacheSizeInfo = sizeInfo;
          _lastCleanupStats = _autoCleanup.lastCleanupStats;
          _isCacheSettingsLoading = false;
        });
      }
    } catch (e) {
      print('Ошибка загрузки настроек кэша: $e');
      if (mounted) {
        setState(() {
          _isCacheSettingsLoading = false;
        });
      }
    }
  }

  // Смена уровня TTL
  Future<void> _setTTLLevel(CacheTTLLevel level) async {
    await _cacheSettings.setTTLLevel(level);
    setState(() {
      _currentTTLLevel = level;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Уровень кэша: ${CacheSettingsService.getLevelName(level)}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // Переключение автоочистки
  Future<void> _toggleAutoCleanup(bool value) async {
    await _cacheSettings.setAutoCleanupEnabled(value);
    setState(() {
      _autoCleanupEnabled = value;
    });
  }

  // Изменение интервала очистки
  Future<void> _setCleanupInterval(int hours) async {
    await _cacheSettings.setAutoCleanupInterval(hours);
    setState(() {
      _autoCleanupInterval = hours;
    });
  }

  // Изменение максимального размера кэша
  Future<void> _setMaxCacheSize(int mb) async {
    await _cacheSettings.setMaxCacheSizeMB(mb);
    setState(() {
      _maxCacheSizeMB = mb;
    });
  }

  Future<int> _getDirectorySize(Directory dir) async {
    int totalSize = 0;
    try {
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: false, followLinks: false)) {
          if (entity is File) {
            try {
              totalSize += await entity.length();
            } catch (e) {
              // Пропускаем файлы к которым нет доступа
              continue;
            }
          } else if (entity is Directory) {
            // Рекурсивно считаем поддиректории с обработкой ошибок
            try {
              totalSize += await _getDirectorySize(entity);
            } catch (e) {
              // Пропускаем директории к которым нет доступа
              continue;
            }
          }
        }
      }
    } on PathAccessException catch (e) {
      // Ошибка доступа - игнорируем
      print('Нет доступа к директории ${dir.path}: $e');
    } catch (e) {
      print('Ошибка при подсчете размера директории ${dir.path}: $e');
    }
    return totalSize;
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить кэш'),
        content: const Text(
          'Это действие очистит весь кэш приложения, включая кэш сообщений, медиафайлов и аватаров. '
          'Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Используем сервис автоочистки для полной очистки
      await _autoCleanup.clearAllCache();

      // Обновляем всю статистику
      await _loadStorageInfo();
      await _loadCacheSettings();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Кэш успешно очищен'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при очистке кэша: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить все данные'),
        content: const Text(
          'Это действие удалит все сообщения, медиафайлы и другие данные приложения. '
          'Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final cacheDir = await getTemporaryDirectory();

        if (await appDir.exists()) {
          await appDir.delete(recursive: true);
          await appDir.create();
        }
        if (await cacheDir.exists()) {
          await cacheDir.delete(recursive: true);
          await cacheDir.create();
        }

        await _loadStorageInfo();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Все данные успешно удалены'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка при удалении данных: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (widget.isModal) {
      return buildModalContent(context);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Хранилище'),
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _storageInfo == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.storage_outlined,
                    size: 64,
                    color: colors.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Не удалось загрузить информацию о хранилище',
                    style: TextStyle(
                      color: colors.onSurface.withValues(alpha: 0.6),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadStorageInfo,
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStorageChart(colors),

                  const SizedBox(height: 32),

                  _buildStorageDetails(colors),

                  const SizedBox(height: 32),

                  _buildCacheSettingsSection(colors),

                  const SizedBox(height: 32),

                  _buildDownloadFolderSetting(colors),

                  const SizedBox(height: 32),

                  _buildActionButtons(colors),
                ],
              ),
            ),
    );
  }

  Widget _buildStorageChart(ColorScheme colors) {
    final totalSize = _storageInfo!.totalSize;
    final usedSize =
        _storageInfo!.messagesSize +
        _storageInfo!.mediaSize +
        _storageInfo!.otherSize;
    final usagePercentage = totalSize > 0 ? usedSize / totalSize : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            'Использование хранилища',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 24),

          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  children: [
                    Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.surfaceContainerHighest,
                      ),
                    ),

                    CustomPaint(
                      size: const Size(200, 200),
                      painter: StorageChartPainter(
                        progress: usagePercentage * _animation.value,
                        colors: colors,
                        storageInfo: _storageInfo!,
                        animationValue: _animation.value,
                      ),
                    ),

                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _formatBytes(usedSize),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: colors.primary,
                            ),
                          ),
                          Text(
                            'из ${_formatBytes(totalSize)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildLegendItem(
                'Сообщения',
                _formatBytes(_storageInfo!.messagesSize),
                Colors.blue,
              ),
              _buildLegendItem(
                'Медиафайлы',
                _formatBytes(_storageInfo!.mediaSize),
                Colors.green,
              ),
              _buildLegendItem(
                'Кэш',
                _formatBytes(_storageInfo!.cacheSize),
                Colors.orange,
              ),
              _buildLegendItem(
                'Другие',
                _formatBytes(_storageInfo!.otherSize),
                Colors.grey,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, String value, Color color) {
    return Column(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildStorageDetails(ColorScheme colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Детали использования',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 16),

          _buildStorageItem(
            'Сообщения',
            _formatBytes(_storageInfo!.messagesSize),
            Icons.message_outlined,
            colors.primary,
            _calculatePercentage(_storageInfo!.messagesSize, _storageInfo!.totalSize),
          ),

          _buildStorageItem(
            'Медиафайлы',
            _formatBytes(_storageInfo!.mediaSize),
            Icons.photo_library_outlined,
            colors.secondary,
            _calculatePercentage(_storageInfo!.mediaSize, _storageInfo!.totalSize),
          ),

          _buildStorageItem(
            'Кэш',
            _formatBytes(_storageInfo!.cacheSize),
            Icons.cached,
            colors.tertiary,
            _calculatePercentage(_storageInfo!.cacheSize, _storageInfo!.totalSize),
          ),

          _buildStorageItem(
            'Другие данные',
            _formatBytes(_storageInfo!.otherSize),
            Icons.folder_outlined,
            colors.outline,
            _calculatePercentage(_storageInfo!.otherSize, _storageInfo!.totalSize),
          ),
        ],
      ),
    );
  }

  double _calculatePercentage(int size, int total) {
    if (total <= 0 || size <= 0) return 0.0;
    final pct = size / total;
    if (pct.isNaN || pct.isInfinite) return 0.0;
    return pct.clamp(0.0, 1.0);
  }

  Widget _buildStorageItem(
    String title,
    String size,
    IconData icon,
    Color color,
    double percentage,
  ) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.zero,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  size,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 60,
            height: 4,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.zero,
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: percentage,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.zero,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDownloadFolder() async {
    try {
      String? selectedDirectory;

      selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        await DownloadPathHelper.setDownloadDirectory(selectedDirectory);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Папка загрузки установлена: $selectedDirectory'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
          setState(() {});
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при выборе папки: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _resetDownloadFolder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сбросить папку загрузки'),
        content: const Text('Вернуть папку загрузки к значению по умолчанию?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DownloadPathHelper.setDownloadDirectory(null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Папка загрузки сброшена к значению по умолчанию'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {});
      }
    }
  }

  Widget _buildDownloadFolderSetting(ColorScheme colors) {
    return FutureBuilder<String>(
      future: DownloadPathHelper.getDisplayPath(),
      builder: (context, snapshot) {
        final currentPath = snapshot.data ?? 'Загрузка...';
        final isCustom =
            snapshot.hasData &&
            currentPath != 'Не указано' &&
            !currentPath.contains('Downloads') &&
            !currentPath.contains('Download');

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.folder_outlined, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Папка загрузки файлов',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Текущая папка:',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currentPath,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: colors.onSurface,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (isCustom)
                      Icon(Icons.check_circle, color: colors.primary, size: 20),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selectDownloadFolder,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Выбрать папку'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  if (isCustom) ...[
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _resetDownloadFolder,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                      ),
                      child: const Icon(Icons.refresh),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButtons(ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Действия',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _clearCache,
                icon: const Icon(Icons.cleaning_services_outlined),
                label: const Text('Очистить кэш'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _clearAllData,
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Очистить всё'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Секция настроек кэша
  Widget _buildCacheSettingsSection(ColorScheme colors) {
    if (_isCacheSettingsLoading) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.memory, color: colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Настройки кэша',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
              ),
              if (_cacheSizeInfo != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _cacheSizeInfo!.formattedSize,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Уровень TTL
          _buildCacheLevelSelector(colors),
          const SizedBox(height: 16),

          // Автоочистка
          _buildAutoCleanupToggle(colors),
          const SizedBox(height: 16),

          // Интервал очистки
          if (_autoCleanupEnabled) ...[
            _buildCleanupIntervalSelector(colors),
            const SizedBox(height: 16),
          ],

          // Максимальный размер кэша
          _buildMaxCacheSizeSelector(colors),
          const SizedBox(height: 16),

          // Настройки пользовательского режима
          if (_currentTTLLevel == CacheTTLLevel.custom) ...[
            _buildCustomTTLSettings(colors),
            const SizedBox(height: 16),
          ],

          // Кнопка подробнее
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const CacheManagementScreen(),
                ),
              );
            },
            icon: const Icon(Icons.settings_suggest_outlined),
            label: const Text('Подробнее о кэше'),
          ),

          // Статистика последней очистки
          if (_lastCleanupStats != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: colors.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Последняя очистка: ${_lastCleanupStats!.formattedFreedSpace} освобождено',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Селектор уровня кэша
  Widget _buildCacheLevelSelector(ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Уровень кэширования',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: CacheTTLLevel.values.map((level) {
              final isSelected = _currentTTLLevel == level;
              return RadioListTile<CacheTTLLevel>(
                title: Row(
                  children: [
                    Text(CacheSettingsService.getLevelIcon(level)),
                    const SizedBox(width: 8),
                    Text(
                      CacheSettingsService.getLevelName(level),
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  CacheSettingsService.getLevelDescription(level),
                  style: const TextStyle(fontSize: 12),
                ),
                value: level,
                groupValue: _currentTTLLevel,
                onChanged: (value) {
                  if (value != null) _setTTLLevel(value);
                },
                dense: true,
                activeColor: colors.primary,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // Переключатель автоочистки
  Widget _buildAutoCleanupToggle(ColorScheme colors) {
    return SwitchListTile(
      title: const Text('Автоматическая очистка'),
      subtitle: Text(
        _autoCleanupEnabled
            ? 'Кэш будет очищаться автоматически'
            : 'Очистка только вручную',
        style: const TextStyle(fontSize: 12),
      ),
      value: _autoCleanupEnabled,
      onChanged: _toggleAutoCleanup,
      activeColor: colors.primary,
      contentPadding: EdgeInsets.zero,
    );
  }

  // Селектор интервала очистки
  Widget _buildCleanupIntervalSelector(ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Интервал очистки',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _buildIntervalChip(colors, 6, '6 часов'),
            _buildIntervalChip(colors, 12, '12 часов'),
            _buildIntervalChip(colors, 24, '1 день'),
            _buildIntervalChip(colors, 48, '2 дня'),
            _buildIntervalChip(colors, 168, '7 дней'),
          ],
        ),
      ],
    );
  }

  Widget _buildIntervalChip(ColorScheme colors, int hours, String label) {
    final isSelected = _autoCleanupInterval == hours;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _setCleanupInterval(hours),
      selectedColor: colors.primaryContainer,
      labelStyle: TextStyle(
        color: isSelected ? colors.onPrimaryContainer : colors.onSurface,
        fontSize: 12,
      ),
    );
  }

  // Селектор максимального размера кэша
  Widget _buildMaxCacheSizeSelector(ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Максимальный размер кэша',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.onSurface,
              ),
            ),
            Text(
              _maxCacheSizeMB == 0 ? 'Без ограничений' : '$_maxCacheSizeMB MB',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Slider(
          value: _maxCacheSizeMB.toDouble(),
          min: 0,
          max: 2000,
          divisions: 20,
          label: _maxCacheSizeMB == 0 ? 'Без ограничений' : '$_maxCacheSizeMB MB',
          onChanged: (value) => _setMaxCacheSize(value.round()),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Без ограничений', style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.6))),
            Text('2 GB', style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.6))),
          ],
        ),
      ],
    );
  }

  // Настройки пользовательского TTL
  Widget _buildCustomTTLSettings(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, color: colors.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                'Пользовательские настройки TTL',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // TTL для чатов
          _buildCustomTTLSlider(
            colors: colors,
            label: 'Чаты',
            icon: Icons.chat_bubble_outline,
            currentValue: _cacheSettings.currentSettings.chatsTTL.inMinutes,
            min: 15,
            max: 1440, // 24 часа
            divisions: 20,
            onChanged: (value) => _updateCustomTTL(chatsTTL: Duration(minutes: value.round())),
          ),
          
          // TTL для контактов
          _buildCustomTTLSlider(
            colors: colors,
            label: 'Контакты',
            icon: Icons.contacts_outlined,
            currentValue: _cacheSettings.currentSettings.contactsTTL.inHours,
            min: 1,
            max: 72, // 3 дня
            divisions: 18,
            unit: 'ч',
            onChanged: (value) => _updateCustomTTL(contactsTTL: Duration(hours: value.round())),
          ),
          
          // TTL для сообщений
          _buildCustomTTLSlider(
            colors: colors,
            label: 'Сообщения',
            icon: Icons.message_outlined,
            currentValue: _cacheSettings.currentSettings.messagesTTL.inMinutes,
            min: 15,
            max: 720, // 12 часов
            divisions: 15,
            onChanged: (value) => _updateCustomTTL(messagesTTL: Duration(minutes: value.round())),
          ),
          
          // TTL для аватарок
          _buildCustomTTLSlider(
            colors: colors,
            label: 'Аватарки',
            icon: Icons.person_outline,
            currentValue: _cacheSettings.currentSettings.avatarsTTL.inDays,
            min: 1,
            max: 30, // 30 дней
            divisions: 15,
            unit: 'дн',
            onChanged: (value) => _updateCustomTTL(avatarsTTL: Duration(days: value.round())),
          ),
          
          // TTL для файлов
          _buildCustomTTLSlider(
            colors: colors,
            label: 'Файлы',
            icon: Icons.folder_outlined,
            currentValue: _cacheSettings.currentSettings.filesTTL.inHours,
            min: 1,
            max: 168, // 7 дней
            divisions: 20,
            unit: 'ч',
            onChanged: (value) => _updateCustomTTL(filesTTL: Duration(hours: value.round())),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomTTLSlider({
    required ColorScheme colors,
    required String label,
    required IconData icon,
    required int currentValue,
    required double min,
    required double max,
    required int divisions,
    String unit = '',
    required ValueChanged<double> onChanged,
  }) {
    String valueText;
    if (unit == 'дн') {
      valueText = '$currentValue дн.';
    } else if (unit == 'ч') {
      valueText = '$currentValue ч.';
    } else {
      // минуты
      if (currentValue >= 60) {
        valueText = '${(currentValue / 60).toStringAsFixed(1)} ч.';
      } else {
        valueText = '$currentValue мин.';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: colors.onSurface.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.onSurface.withValues(alpha: 0.8),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  valueText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: currentValue.toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            activeColor: colors.primary,
            inactiveColor: colors.surfaceContainerHighest,
          ),
        ],
      ),
    );
  }

  Future<void> _updateCustomTTL({
    Duration? chatsTTL,
    Duration? contactsTTL,
    Duration? messagesTTL,
    Duration? avatarsTTL,
    Duration? filesTTL,
  }) async {
    await _cacheSettings.setCustomTTL(
      chatsTTL: chatsTTL,
      contactsTTL: contactsTTL,
      messagesTTL: messagesTTL,
      avatarsTTL: avatarsTTL,
      filesTTL: filesTTL,
    );
    setState(() {});
  }
}

class StorageInfo {
  final int totalSize;
  final int messagesSize;
  final int mediaSize;
  final int cacheSize;
  final int otherSize;

  StorageInfo({
    required this.totalSize,
    required this.messagesSize,
    required this.mediaSize,
    required this.cacheSize,
    required this.otherSize,
  });
}

class StorageChartPainter extends CustomPainter {
  final double progress;
  final ColorScheme colors;
  final StorageInfo storageInfo;
  final double animationValue;

  StorageChartPainter({
    required this.progress,
    required this.colors,
    required this.storageInfo,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.butt;

    paint.color = colors.surfaceContainerHighest;
    canvas.drawCircle(center, radius, paint);

    final totalSize = storageInfo.totalSize;
    if (totalSize > 0) {
      final messagesRatio = storageInfo.messagesSize / totalSize;
      final mediaRatio = storageInfo.mediaSize / totalSize;
      final cacheRatio = storageInfo.cacheSize / totalSize;
      final otherRatio = storageInfo.otherSize / totalSize;

      double currentAngle = -pi / 2;

      if (messagesRatio > 0) {
        paint.color = Colors.blue;
        final sweepAngle = 2 * pi * messagesRatio * animationValue;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          currentAngle,
          sweepAngle,
          false,
          paint,
        );
        currentAngle += sweepAngle;
      }

      if (mediaRatio > 0) {
        paint.color = Colors.green;
        final sweepAngle = 2 * pi * mediaRatio * animationValue;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          currentAngle,
          sweepAngle,
          false,
          paint,
        );
        currentAngle += sweepAngle;
      }

      if (cacheRatio > 0) {
        paint.color = Colors.orange;
        final sweepAngle = 2 * pi * cacheRatio * animationValue;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          currentAngle,
          sweepAngle,
          false,
          paint,
        );
        currentAngle += sweepAngle;
      }

      if (otherRatio > 0) {
        paint.color = Colors.grey;
        final sweepAngle = 2 * pi * otherRatio * animationValue;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          currentAngle,
          sweepAngle,
          false,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is StorageChartPainter &&
        (oldDelegate.progress != progress ||
            oldDelegate.animationValue != animationValue);
  }
}
