import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class ShatterAnimation extends StatefulWidget {
  final Widget child;
  final bool shatter;
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
  OverlayEntry? _overlayEntry;

  static const int cols = 6;
  static const int rows = 4;

  late final List<_ShardData> _shards;
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    _rng; // ensure initialized
    _shards = _generateShards();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _overlayEntry?.remove();
        _overlayEntry = null;
        widget.onComplete?.call();
      }
    });
  }

  List<_ShardData> _generateShards() {
    final rng = Random(12345);
    final shards = <_ShardData>[];
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final angle = rng.nextDouble() * 2 * pi;
        final speed = 100.0 + rng.nextDouble() * 250.0;
        final rotSpeed = (rng.nextDouble() - 0.5) * 8.0;
        final delay = rng.nextDouble() * 0.12;
        shards.add(_ShardData(
          col: c,
          row: r,
          vx: cos(angle) * speed,
          vy: sin(angle) * speed + 80,
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

    await Future.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;

    try {
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      // Получаем глобальную позицию виджета
      final box = _repaintKey.currentContext!.findRenderObject() as RenderBox;
      final globalOffset = box.localToGlobal(Offset.zero);
      final size = box.size;

      final image = await boundary.toImage(pixelRatio: 2.0);

      if (!mounted) return;

      setState(() {
        _snapshot = image;
        _shattered = true;
      });

      // Рендерим осколки через Overlay поверх всего
      _overlayEntry = OverlayEntry(
        builder: (context) => _ShatterOverlay(
          image: image,
          shards: _shards,
          controller: _controller,
          globalOffset: globalOffset,
          size: size,
          cols: cols,
          rows: rows,
        ),
      );

      Overlay.of(context).insert(_overlayEntry!);
      _controller.forward();
    } catch (e) {
      debugPrint('ShatterAnimation error: $e');
    }
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _controller.dispose();
    _snapshot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_shattered) {
      // После разбивания — схлопываем высоту
      return AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final collapseT = _controller.value > 0.55
              ? ((_controller.value - 0.55) / 0.45).clamp(0.0, 1.0)
              : 0.0;
          final heightFactor = 1.0 - collapseT;
          return ClipRect(
            child: Align(
              heightFactor: heightFactor,
              child: Opacity(opacity: 0, child: widget.child),
            ),
          );
        },
      );
    }

    return RepaintBoundary(
      key: _repaintKey,
      child: widget.child,
    );
  }
}

class _ShatterOverlay extends StatelessWidget {
  final ui.Image image;
  final List<_ShardData> shards;
  final AnimationController controller;
  final Offset globalOffset;
  final Size size;
  final int cols;
  final int rows;

  const _ShatterOverlay({
    required this.image,
    required this.shards,
    required this.controller,
    required this.globalOffset,
    required this.size,
    required this.cols,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Positioned(
          left: 0,
          top: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _ShatterPainter(
                image: image,
                shards: shards,
                t: controller.value,
                cols: cols,
                rows: rows,
                origin: globalOffset,
                size: size,
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
  final double vx;
  final double vy;
  final double rotationEnd;
  final double delay;

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
  final double t;
  final int cols;
  final int rows;
  final Offset origin;
  final Size size;

  _ShatterPainter({
    required this.image,
    required this.shards,
    required this.t,
    required this.cols,
    required this.rows,
    required this.origin,
    required this.size,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();

    final shardW = size.width / cols;
    final shardH = size.height / rows;
    final srcShardW = imgW / cols;
    final srcShardH = imgH / rows;

    for (final shard in shards) {
      final localT = ((t - shard.delay) / (1.0 - shard.delay)).clamp(0.0, 1.0);
      if (localT <= 0) continue;

      final ease = 1.0 - pow(1.0 - localT, 3).toDouble();

      final dx = shard.vx * ease * 0.55;
      final dy = shard.vy * ease * 0.55;
      final rotation = shard.rotationEnd * ease;
      final opacity = (1.0 - localT * localT).clamp(0.0, 1.0);
      final scale = 1.0 - localT * 0.25;

      // Мировые координаты центра осколка
      final worldCx = origin.dx + shard.col * shardW + shardW / 2;
      final worldCy = origin.dy + shard.row * shardH + shardH / 2;

      final srcRect = Rect.fromLTWH(
        shard.col * srcShardW,
        shard.row * srcShardH,
        srcShardW,
        srcShardH,
      );

      final dstRect = Rect.fromCenter(
        center: Offset(worldCx, worldCy),
        width: shardW,
        height: shardH,
      );

      canvas.save();
      canvas.translate(worldCx + dx, worldCy + dy);
      canvas.rotate(rotation);
      canvas.scale(scale);
      canvas.translate(-worldCx, -worldCy);

      canvas.saveLayer(
        dstRect.inflate(30),
        Paint()
          ..colorFilter = ColorFilter.mode(
            Colors.white.withValues(alpha: opacity),
            BlendMode.modulate,
          ),
      );
      canvas.drawImageRect(image, srcRect, dstRect, Paint());
      canvas.restore();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ShatterPainter old) => old.t != t;
}
