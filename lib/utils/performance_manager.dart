import 'package:flutter/material.dart';
import 'dart:async';

/// Менеджер производительности приложения
class PerformanceManager {
  static final PerformanceManager _instance = PerformanceManager._internal();
  factory PerformanceManager() => _instance;
  PerformanceManager._internal();

  bool _isLowEndDevice = false;
  bool _isBatterySaver = false;
  double _targetFps = 60.0;
  
  bool get isLowEndDevice => _isLowEndDevice;
  bool get isBatterySaver => _isBatterySaver;
  double get targetFps => _targetFps;
  bool get shouldOptimize => _isLowEndDevice || _isBatterySaver;

  void initialize({bool isLowEnd = false, bool batterySaver = false}) {
    _isLowEndDevice = isLowEnd;
    _isBatterySaver = batterySaver;
    _targetFps = shouldOptimize ? 30.0 : 60.0;
  }

  void setBatterySaver(bool value) {
    _isBatterySaver = value;
    _targetFps = shouldOptimize ? 30.0 : 60.0;
  }
}

/// Оптимизированный ChangeNotifier с троттлингом уведомлений
class OptimizedChangeNotifier extends ChangeNotifier {
  Timer? _notifyTimer;
  bool _isNotifying = false;
  
  void notifyListenersThrottled({Duration delay = const Duration(milliseconds: 16)}) {
    if (_isNotifying) return;
    
    _isNotifying = true;
    _notifyTimer?.cancel();
    _notifyTimer = Timer(delay, () {
      _isNotifying = false;
      notifyListeners();
    });
  }

  void notifyListenersDebounced({Duration delay = const Duration(milliseconds: 100)}) {
    _notifyTimer?.cancel();
    _notifyTimer = Timer(delay, notifyListeners);
  }

  @override
  void dispose() {
    _notifyTimer?.cancel();
    super.dispose();
  }
}

/// Менеджер кэша виджетов для предотвращения лишних пересозданий
class WidgetCacheManager {
  static final WidgetCacheManager _instance = WidgetCacheManager._internal();
  factory WidgetCacheManager() => _instance;
  WidgetCacheManager._internal();

  final Map<String, Widget> _widgetCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Duration _cacheValidity = const Duration(minutes: 5);

  Widget? getCachedWidget(String key) {
    final timestamp = _cacheTimestamps[key];
    if (timestamp == null) return null;
    
    if (DateTime.now().difference(timestamp) > _cacheValidity) {
      _widgetCache.remove(key);
      _cacheTimestamps.remove(key);
      return null;
    }
    
    return _widgetCache[key];
  }

  void cacheWidget(String key, Widget widget) {
    _widgetCache[key] = widget;
    _cacheTimestamps[key] = DateTime.now();
  }

  void clearCache() {
    _widgetCache.clear();
    _cacheTimestamps.clear();
  }

  void removeFromCache(String key) {
    _widgetCache.remove(key);
    _cacheTimestamps.remove(key);
  }
}

/// Оптимизированный скролл контроллер с пагинацией
class OptimizedScrollController extends ScrollController {
  final VoidCallback? onLoadMore;
  final double loadMoreThreshold;
  bool _isLoadingMore = false;
  Timer? _throttleTimer;

  OptimizedScrollController({
    this.onLoadMore,
    this.loadMoreThreshold = 200.0,
  }) {
    addListener(_onScroll);
  }

  void _onScroll() {
    if (_isLoadingMore || onLoadMore == null) return;
    if (_throttleTimer?.isActive ?? false) return;

    final maxScroll = position.maxScrollExtent;
    final currentScroll = position.pixels;
    
    if (maxScroll - currentScroll <= loadMoreThreshold) {
      _isLoadingMore = true;
      onLoadMore!();
      
      // Троттлинг чтобы не вызывать слишком часто
      _throttleTimer = Timer(const Duration(milliseconds: 500), () {
        _isLoadingMore = false;
      });
    }
  }

  void resetLoadingState() {
    _isLoadingMore = false;
    _throttleTimer?.cancel();
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    removeListener(_onScroll);
    super.dispose();
  }
}

/// Утилиты для оптимизации отрисовки
class RenderingOptimizations {
  /// Отключает анимации для слабых устройств
  static Animation<T> optimizeAnimation<T>(Animation<T> animation) {
    if (PerformanceManager().shouldOptimize) {
      // Для слабых устройств возвращаем упрощенную анимацию
      return AlwaysStoppedAnimation<T>(animation.value);
    }
    return animation;
  }

  /// Оптимизирует частоту кадров
  static Duration getFrameDuration() {
    final targetFps = PerformanceManager().targetFps;
    return Duration(milliseconds: (1000 / targetFps).round());
  }

  /// Проверяет нужно ли использовать упрощенный рендеринг
  static bool get useSimplifiedRendering => PerformanceManager().shouldOptimize;

  /// Размер кэша для ListView
  static double get listViewCacheExtent => 
      PerformanceManager().shouldOptimize ? 100.0 : 250.0;

  /// Максимальное количество элементов для рендеринга за кадр
  static int get maxItemsPerFrame => 
      PerformanceManager().shouldOptimize ? 5 : 10;
}

/// Миксин для оптимизации видимости виджетов
 mixin VisibilityOptimizationMixin<T extends StatefulWidget> on State<T> {
  bool _isVisible = true;
  bool _isInViewport = true;
  
  bool get isVisible => _isVisible && _isInViewport;
  bool get shouldRender => _isVisible;

  void onVisibilityChanged(bool visible) {
    if (_isVisible != visible) {
      _isVisible = visible;
      onRenderStateChanged();
    }
  }

  void onViewportChanged(bool inViewport) {
    if (_isInViewport != inViewport) {
      _isInViewport = inViewport;
      onRenderStateChanged();
    }
  }

  void onRenderStateChanged() {
    // Переопределить в подклассе
  }
}
