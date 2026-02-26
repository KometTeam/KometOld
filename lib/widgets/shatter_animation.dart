import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Анимация разбивания как душа из Undertale.
/// Делает скриншот дочернего виджета, разбивает на осколки и анимирует их разлёт.
class ShatterAnimation extends StatefulWidget {
  final Widget child;
  final bool shatter; // когда true — запускает анимацию
  final VoidCallback? onComplete;
  final Duration duration;

  const ShatterAnimation({
    super.key,
    required this.child,
    required this.shatter,
    this.onComplete,
    this.duration = const Duration(milliseconds: 700),
  });

  @override
  State<ShatterAnimation> createState() => _ShatterAnimationState();
}

class _ShatterAnimationState extends State<ShatterAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  ui.Image? _snapshot;
  bool _capturing = false;
  bool _shattered = false;
  final GlobalKey _repaintKey = GlobalKey();

  // Сетка осколков: cols x rows
  static const int cols = 6;
  static const int rows = 4;

  // Параметры каждого осколка (генерируются один раз)
  late final List<_ShardData> _shards;
  final Random _rng = Random(42);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete?.call();
      }
    });
    _shards = _generateShards();
  }

  List<_ShardData> _generateShards() {
    final shards = <_ShardData>[];
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        // Случайное направление разлёта — больше вниз и в стороны
        final angle = _rng.nextDouble() * 2 * pi;
        final speed = 80.0 + _rng.nextDouble() * 200.0;
        final rotSpeed = (_rng.nextDouble() - 0.5) * 6.0; // рад
        final delay = _rng.nextDouble() * 0.15; // небольшая задержка старта
        shards.add(_ShardData(
          col: c,
          row: r,
          vx: cos(angle) * speed,
          vy: sin(angle) * speed + 60, // гравитация вниз
          rotationEnd: rotSpeed,
          delay: delay,
        ));
      }
    }
    return shards;
  }

  @override
  void didUpdateWidget(ShatterAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shatter && !oldWidget.shatter && !_shattered) {
      _startShatter();
    }
  }

  Future<void> _startShatter() async {
    if (_capturing || _shattered) return;
    _capturing = true;

    // Делаем скриншот виджета
    await Future.delayed(const Duration(milliseconds: 16)); // один кадр
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.0);
      if (mounted) {
        setState(() {
          _snapshot = image;
          _shattered = true;
        });
        _controller.forward();
      }
    } catch (e) {
      debugPrint('ShatterAnimation: ошибка снимка: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _snapshot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shattered || _snapshot == null) {
      // Ещё не разбился — показываем оригинал
      return RepaintBoundary(
        key: _repaintKey,
        child: widget.child,
      );
    }

    // Разбился — показываем осколки
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        // Высота схлопывается после 60% анимации
        final collapseT = t > 0.6 ? ((t - 0.6) / 0.4).clamp(0.0, 1.0) : 0.0;
        final heightFactor = 1.0 - collapseT;

        return ClipRect(
          child: Align(
            heightFactor: heightFactor,
            child: SizedBox(
              width: double.infinity,
              height: 72, // высота строки чата
              child: CustomPaint(
                painter: _ShatterPainter(
                  image: _snapshot!,
                  shards: _shards,
                  t: t,
                  cols: cols,
                  rows: rows,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ShardData {
  final int col;
  final int row;
  final double vx; // скорость X
  final double vy; // скорость Y
  final double rotationEnd; // конечный угол поворота
  final double delay; // задержка старта [0..1]

  const _ShardData({
    required this.col,
    required this.row,
    required this.vx,
    required this.vy,
    required this.rotationEnd,
    required this.delay,
  });
}

class _ShatterPainter extends CustomPainter {
  final ui.Image image;
  final List<_ShardData> shards;
  final double t; // 0→1
  final int cols;
  final int rows;

  _ShatterPainter({
    required this.image,
    required this.shards,
    required this.t,
    required this.cols,
    required this.rows,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();

    final shardW = size.width / cols;
    final shardH = size.height / rows;
    final srcShardW = imgW / cols;
    final srcShardH = imgH / rows;

    final paint = Paint();

    for (final shard in shards) {
      // Нормализуем t с учётом задержки
      final localT = ((t - shard.delay) / (1.0 - shard.delay)).clamp(0.0, 1.0);
      if (localT <= 0) continue;

      // Ease out кубическая для позиции
      final ease = 1.0 - pow(1.0 - localT, 3).toDouble();

      final dx = shard.vx * ease * 0.5;
      final dy = shard.vy * ease * 0.5;
      final rotation = shard.rotationEnd * ease;
      final opacity = (1.0 - localT * localT).clamp(0.0, 1.0);
      final scale = 1.0 - localT * 0.3;

      // Центр осколка
      final cx = shard.col * shardW + shardW / 2;
      final cy = shard.row * shardH + shardH / 2;

      // Исходный прямоугольник в изображении
      final srcRect = Rect.fromLTWH(
        shard.col * srcShardW,
        shard.row * srcShardH,
        srcShardW,
        srcShardH,
      );

      // Целевой прямоугольник
      final dstRect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: shardW,
        height: shardH,
      );

      canvas.save();
      canvas.translate(cx + dx, cy + dy);
      canvas.rotate(rotation);
      canvas.scale(scale);
      canvas.translate(-cx, -cy);

      paint.color = Colors.white.withValues(alpha: opacity);

      // Рисуем кусок изображения с opacity
      final colorFilter = ColorFilter.mode(
        Colors.white.withValues(alpha: opacity),
        BlendMode.modulate,
      );
      canvas.saveLayer(
        dstRect.inflate(20),
        Paint()..colorFilter = colorFilter,
      );
      canvas.drawImageRect(image, srcRect, dstRect, Paint());
      canvas.restore();

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ShatterPainter old) => old.t != t;
}
