import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Анимированный mesh gradient фон для экрана звонка
/// Создаёт плавно движущиеся цветные блобы на основе акцентного цвета
class AnimatedMeshGradient extends StatefulWidget {
  final Color accentColor;
  final Widget? child;
  
  const AnimatedMeshGradient({
    super.key,
    required this.accentColor,
    this.child,
  });

  @override
  State<AnimatedMeshGradient> createState() => _AnimatedMeshGradientState();
}

class _AnimatedMeshGradientState extends State<AnimatedMeshGradient>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<Color> _blobColors;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(); // Бесконечный повтор с 0 до 1
    
    _generateColors();
  }
  
  @override
  void didUpdateWidget(AnimatedMeshGradient oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accentColor != widget.accentColor) {
      _generateColors();
    }
  }

  /// Генерирует 4 цвета на основе акцентного цвета
  /// Используем HSL для плавных переходов
  void _generateColors() {
    final hsl = HSLColor.fromColor(widget.accentColor);
    
    _blobColors = [
      // Основной акцентный цвет
      widget.accentColor,
      
      // Сдвиг по hue на +20° (близкий аналоговый)
      hsl.withHue((hsl.hue + 20) % 360)
          .withLightness(math.min(hsl.lightness + 0.05, 0.7))
          .toColor(),
      
      // Сдвиг по hue на -20° (близкий аналоговый)
      hsl.withHue((hsl.hue - 20 + 360) % 360)
          .withLightness(math.min(hsl.lightness + 0.08, 0.75))
          .toColor(),
      
      // Сдвиг по hue на +40° (умеренный сдвиг)
      hsl.withHue((hsl.hue + 40) % 360)
          .withSaturation(math.min(hsl.saturation + 0.05, 1.0))
          .withLightness(math.min(hsl.lightness + 0.03, 0.65))
          .toColor(),
    ];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _MeshGradientPainter(
            animation: _controller.value,
            colors: _blobColors,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// CustomPainter для отрисовки движущихся блобов
class _MeshGradientPainter extends CustomPainter {
  final double animation;
  final List<Color> colors;
  
  _MeshGradientPainter({
    required this.animation,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Тёмный фон
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0A0A0A),
    );

    // Параметры блобов - компактные
    // ВАЖНО: Все скорости целые числа для идеального цикла!
    final blobData = [
      _BlobData(
        radiusMultiplier: 0.10,
        speedX: 1.0, // Целое число
        speedY: 1.0, // Целое число
        offsetX: 0.0,
        offsetY: 0.0,
        phaseX: 0.0,
        phaseY: math.pi / 4,
      ),
      _BlobData(
        radiusMultiplier: 0.12,
        speedX: 1.0, // Целое число
        speedY: 2.0, // Целое число
        offsetX: 0.08,
        offsetY: 0.06,
        phaseX: math.pi / 2,
        phaseY: math.pi / 3,
      ),
      _BlobData(
        radiusMultiplier: 0.09,
        speedX: 2.0, // Целое число
        speedY: 1.0, // Целое число
        offsetX: -0.06,
        offsetY: 0.08,
        phaseX: math.pi,
        phaseY: math.pi / 6,
      ),
      _BlobData(
        radiusMultiplier: 0.11,
        speedX: 1.0, // Целое число
        speedY: 1.0, // Целое число
        offsetX: 0.08,
        offsetY: -0.06,
        phaseX: 3 * math.pi / 2,
        phaseY: math.pi / 2,
      ),
    ];

    // Рисуем каждый блоб
    for (int i = 0; i < blobData.length && i < colors.length; i++) {
      final data = blobData[i];
      final color = colors[i];
      
      // Вычисляем позицию блоба с использованием синусоид
      // Используем sin для обеих осей чтобы движение было циклическим и плавным
      final t = animation * 2 * math.pi;
      final x = size.width * (0.5 + data.offsetX + 0.15 * math.sin(t * data.speedX + data.phaseX));
      final y = size.height * (0.5 + data.offsetY + 0.15 * math.sin(t * data.speedY + data.phaseY));
      final radius = size.width * data.radiusMultiplier;

      // Создаём блоб с сильным размытием
      final paint = Paint()
        ..color = color.withOpacity(0.6)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.8);

      canvas.drawCircle(
        Offset(x, y),
        radius,
        paint,
      );
    }
    
    // Дополнительный слой с blend mode для усиления эффекта
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..blendMode = BlendMode.screen,
    );
    
    // Рисуем блобы еще раз с меньшей непрозрачностью для blend эффекта
    for (int i = 0; i < blobData.length && i < colors.length; i++) {
      final data = blobData[i];
      final color = colors[i];
      
      final t = animation * 2 * math.pi;
      final x = size.width * (0.5 + data.offsetX + 0.15 * math.sin(t * data.speedX + data.phaseX));
      final y = size.height * (0.5 + data.offsetY + 0.15 * math.sin(t * data.speedY + data.phaseY));
      final radius = size.width * data.radiusMultiplier;

      final paint = Paint()
        ..color = color.withOpacity(0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.6);

      canvas.drawCircle(
        Offset(x, y),
        radius * 0.8,
        paint,
      );
    }
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MeshGradientPainter oldDelegate) {
    return oldDelegate.animation != animation || oldDelegate.colors != colors;
  }
}

/// Данные для одного блоба
class _BlobData {
  final double radiusMultiplier;
  final double speedX;
  final double speedY;
  final double offsetX;
  final double offsetY;
  final double phaseX;
  final double phaseY;

  _BlobData({
    required this.radiusMultiplier,
    required this.speedX,
    required this.speedY,
    required this.offsetX,
    required this.offsetY,
    required this.phaseX,
    required this.phaseY,
  });
}

/// Виджет аватара с пульсацией для экрана звонка
class PulsingAvatar extends StatefulWidget {
  final String? imageUrl;
  final String name;
  final double radius;
  
  const PulsingAvatar({
    super.key,
    this.imageUrl,
    required this.name,
    this.radius = 60,
  });

  @override
  State<PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<PulsingAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _pulseAnimation,
      child: CircleAvatar(
        radius: widget.radius,
        backgroundImage: widget.imageUrl != null
            ? NetworkImage(widget.imageUrl!)
            : null,
        child: widget.imageUrl == null
            ? Text(
                widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: widget.radius * 0.8,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              )
            : null,
      ),
    );
  }
}
