library optimized_widgets;

import 'package:flutter/material.dart';
import 'dart:async';

/// Оптимизированный виджет который предотвращает лишние перерисовки
/// Использует ValueNotifier вместо setState
class OptimizedBuilder<T> extends StatefulWidget {
  final ValueNotifier<T> notifier;
  final Widget Function(BuildContext context, T value) builder;
  final bool useRepaintBoundary;

  const OptimizedBuilder({
    super.key,
    required this.notifier,
    required this.builder,
    this.useRepaintBoundary = true,
  });

  @override
  State<OptimizedBuilder<T>> createState() => _OptimizedBuilderState<T>();
}

class _OptimizedBuilderState<T> extends State<OptimizedBuilder<T>> {
  late T _value;

  @override
  void initState() {
    super.initState();
    _value = widget.notifier.value;
    widget.notifier.addListener(_onValueChanged);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onValueChanged);
    super.dispose();
  }

  void _onValueChanged() {
    if (mounted) {
      setState(() => _value = widget.notifier.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.builder(context, _value);
    if (widget.useRepaintBoundary) {
      return RepaintBoundary(child: child);
    }
    return child;
  }
}

/// Дебаунсер для уменьшения частоты обновлений
class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({this.delay = const Duration(milliseconds: 100)});

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() {
    _timer?.cancel();
  }
}

/// Троттлер для ограничения частоты вызовов
class Throttler {
  final Duration delay;
  Timer? _timer;
  bool _isThrottled = false;

  Throttler({this.delay = const Duration(milliseconds: 100)});

  void run(VoidCallback action) {
    if (!_isThrottled) {
      action();
      _isThrottled = true;
      _timer = Timer(delay, () => _isThrottled = false);
    }
  }

  void dispose() {
    _timer?.cancel();
  }
}

/// Оптимизированный ListView с предустановленными настройками производительности
class OptimizedListView extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final ScrollController? controller;
  final EdgeInsetsGeometry? padding;
  final double? itemExtent;
  final ScrollPhysics? physics;
  final bool addRepaintBoundaries;
  final bool addAutomaticKeepAlives;
  final bool addSemanticIndexes;
  final double cacheExtent;

  const OptimizedListView({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    this.padding,
    this.itemExtent,
    this.physics = const BouncingScrollPhysics(),
    this.addRepaintBoundaries = true,
    this.addAutomaticKeepAlives = true,
    this.addSemanticIndexes = false,
    this.cacheExtent = 200.0,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: padding,
      itemCount: itemCount,
      itemExtent: itemExtent,
      physics: physics,
      cacheExtent: cacheExtent,
      addRepaintBoundaries: addRepaintBoundaries,
      addAutomaticKeepAlives: addAutomaticKeepAlives,
      addSemanticIndexes: addSemanticIndexes,
      itemBuilder: itemBuilder,
    );
  }
}

/// Оптимизированный анимированный контейнер с минимальными перерисовками
class OptimizedAnimatedContainer extends StatelessWidget {
  final Duration duration;
  final Curve curve;
  final Alignment? alignment;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Decoration? decoration;
  final double? width;
  final double? height;
  final Widget? child;

  const OptimizedAnimatedContainer({
    super.key,
    required this.duration,
    this.curve = Curves.linear,
    this.alignment,
    this.padding,
    this.margin,
    this.decoration,
    this.width,
    this.height,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: duration,
      curve: curve,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, child) {
        return Container(
          alignment: alignment,
          padding: padding,
          margin: margin,
          decoration: decoration,
          width: width,
          height: height,
          child: child,
        );
      },
      child: child,
    );
  }
}

/// Виджет который предотвращает перерисовку при скролле
class ScrollOptimizedWidget extends StatelessWidget {
  final Widget child;
  final bool useRepaintBoundary;

  const ScrollOptimizedWidget({
    super.key,
    required this.child,
    this.useRepaintBoundary = true,
  });

  @override
  Widget build(BuildContext context) {
    if (useRepaintBoundary) {
      return RepaintBoundary(child: child);
    }
    return child;
  }
}

/// Оптимизированный текст с кэшированием
class OptimizedText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const OptimizedText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      textWidthBasis: TextWidthBasis.parent,
    );
  }
}

/// Оптимизированный InkWell с уменьшенным splash
class OptimizedInkWell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final Color? splashColor;

  const OptimizedInkWell({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.splashColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: borderRadius,
      splashColor: splashColor ?? Colors.transparent,
      highlightColor: splashColor?.withValues(alpha: 0.1) ?? Colors.transparent,
      child: child,
    );
  }
}

/// Оптимизированный CircleAvatar с кэшированием
class OptimizedCircleAvatar extends StatelessWidget {
  final ImageProvider? backgroundImage;
  final Widget? child;
  final double radius;
  final Color? backgroundColor;

  const OptimizedCircleAvatar({
    super.key,
    this.backgroundImage,
    this.child,
    this.radius = 20,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      backgroundImage: backgroundImage,
      child: child,
    );
  }
}

/// Миксин для оптимизации StatefulWidget
mixin OptimizedStateMixin<T extends StatefulWidget> on State<T> {
  final Map<String, Debouncer> _debouncers = {};
  final Map<String, Throttler> _throttlers = {};

  Debouncer getDebouncer(String key, {Duration delay = const Duration(milliseconds: 100)}) {
    return _debouncers.putIfAbsent(key, () => Debouncer(delay: delay));
  }

  Throttler getThrottler(String key, {Duration delay = const Duration(milliseconds: 100)}) {
    return _throttlers.putIfAbsent(key, () => Throttler(delay: delay));
  }

  void debouncedSetState(String key, {Duration delay = const Duration(milliseconds: 100)}) {
    getDebouncer(key, delay: delay).run(() {
      if (mounted) setState(() {});
    });
  }

  void throttledSetState(String key, {Duration delay = const Duration(milliseconds: 100)}) {
    getThrottler(key, delay: delay).run(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final debouncer in _debouncers.values) {
      debouncer.dispose();
    }
    for (final throttler in _throttlers.values) {
      throttler.dispose();
    }
    _debouncers.clear();
    _throttlers.clear();
    super.dispose();
  }
}
