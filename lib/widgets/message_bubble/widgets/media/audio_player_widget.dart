import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:gwid/services/cache_service.dart';

class AudioPlayerWidget extends StatefulWidget {
  final String url;
  final int duration;
  final String durationText;
  final String? wave;
  final Uint8List? waveBytes;
  final int? audioId;
  final Color textColor;
  final BorderRadius borderRadius;
  final double messageTextOpacity;

  const AudioPlayerWidget({
    super.key,
    required this.url,
    required this.duration,
    required this.durationText,
    this.wave,
    this.waveBytes,
    this.audioId,
    required this.textColor,
    required this.borderRadius,
    required this.messageTextOpacity,
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _isCompleted = false;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;
  List<int>? _waveformData;
  bool _isDragging = false;
  double _dragProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _totalDuration = Duration(milliseconds: widget.duration);

    if (widget.waveBytes != null && widget.waveBytes!.isNotEmpty) {
      _waveformData = widget.waveBytes!.toList();
    } else if (widget.wave != null && widget.wave!.isNotEmpty) {
      _decodeWaveform(widget.wave!);
    } else {
      _generateFallbackWaveform();
    }

    if (widget.url.isNotEmpty) {
      _preCacheAudio();
    }

    _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing;
        _isLoading =
            state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering;
      });

      if (state.processingState == ProcessingState.completed) {
        _audioPlayer.seek(Duration.zero);
        _audioPlayer.pause();
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _isCompleted = true;
            _position = Duration.zero;
          });
        }
      }
    });

    _audioPlayer.positionStream.listen((position) {
      if (!mounted || _isDragging) return;
      setState(() => _position = position);
    });

    _audioPlayer.durationStream.listen((duration) {
      if (mounted && duration != null && duration.inMilliseconds > 0) {
        setState(() => _totalDuration = duration);
      }
    });
  }

  void _decodeWaveform(String waveBase64) {
    try {
      String base64Data = waveBase64;
      if (waveBase64.contains(',')) {
        base64Data = waveBase64.split(',')[1];
      }
      final bytes = base64Decode(base64Data);
      _decodeWaveformFromImage(bytes);
    } catch (e) {
      _generateFallbackWaveform();
    }
  }

  Future<void> _decodeWaveformFromImage(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        _generateFallbackWaveform();
        return;
      }

      final w = image.width;
      final h = image.height;
      final pixels = byteData.buffer.asUint8List();
      final result = <int>[];

      for (int x = 0; x < w; x++) {
        // Ищем самый нижний непрозрачный/тёмный пиксель в колонке снизу вверх
        int filledRows = 0;
        for (int y = h - 1; y >= 0; y--) {
          final idx = (y * w + x) * 4;
          final r = pixels[idx];
          final g = pixels[idx + 1];
          final b = pixels[idx + 2];
          final a = pixels[idx + 3];
          // Пиксель считается заполненным если он непрозрачный и достаточно тёмный/цветной
          if (a > 30 && (r < 200 || g < 200 || b < 200)) {
            filledRows = h - y;
            break;
          }
        }
        // Нормализуем в 0-255
        final amplitude = ((filledRows / h) * 255).round().clamp(0, 255);
        result.add(amplitude);
      }

      if (mounted) {
        setState(() {
          _waveformData = result.isEmpty ? null : result;
        });
      }
      if (result.isEmpty) _generateFallbackWaveform();
    } catch (e) {
      _generateFallbackWaveform();
    }
  }

  void _generateFallbackWaveform() {
    final rng = Random(widget.duration);
    _waveformData = List.generate(40, (i) {
      final v = (sin(i * 0.4) * 0.3 + rng.nextDouble() * 0.7);
      return (v * 200 + 55).toInt().clamp(55, 255);
    });
  }

  Future<void> _preCacheAudio() async {
    try {
      final cacheService = CacheService();
      final hasCached = await cacheService.hasCachedAudioFile(
        widget.url,
        customKey: widget.audioId?.toString(),
      );
      if (!hasCached) {
        await cacheService.cacheAudioFile(
          widget.url,
          customKey: widget.audioId?.toString(),
        );
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> _togglePlayPause() async {
    if (_isLoading) return;

    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        if (_isCompleted) {
          await _audioPlayer.seek(Duration.zero);
          setState(() {
            _isCompleted = false;
            _position = Duration.zero;
          });
        }

        if (_audioPlayer.processingState == ProcessingState.idle) {
          setState(() => _isLoading = true);
          final cacheService = CacheService();
          var cachedFile = await cacheService.getCachedAudioFile(
            widget.url,
            customKey: widget.audioId?.toString(),
          );

          try {
            if (cachedFile != null && await cachedFile.exists()) {
              await _audioPlayer.setFilePath(cachedFile.path);
            } else {
              await _audioPlayer.setUrl(widget.url);
            }
          } catch (loadError) {
            debugPrint('Audio load error: $loadError');
            // Try direct URL as fallback
            try {
              await _audioPlayer.setUrl(widget.url);
            } catch (e) {
              debugPrint('Audio fallback error: $e');
              if (mounted) setState(() => _isLoading = false);
              return;
            }
          }
        }

        await _audioPlayer.play();
      }
    } catch (e) {
      debugPrint('Audio error: $e');
    }
  }

  Future<void> _seek(Duration position) async {
    try {
      await _audioPlayer.seek(position);
      setState(() => _position = position);
    } catch (e) {
      // ignore
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _totalDuration.inMilliseconds > 0
        ? (_isDragging
            ? _dragProgress
            : (_position.inMilliseconds / _totalDuration.inMilliseconds).clamp(0.0, 1.0))
        : 0.0;

    final displayDuration = _isPlaying || _position > Duration.zero
        ? _formatDuration(_position)
        : _formatDuration(_totalDuration);

    final playColor = widget.textColor.withValues(alpha: widget.messageTextOpacity);
    final waveColor = widget.textColor.withValues(alpha: 0.3 * widget.messageTextOpacity);
    final waveProgressColor = widget.textColor.withValues(alpha: 0.9 * widget.messageTextOpacity);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Кнопка play/pause
          GestureDetector(
            onTap: _togglePlayPause,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: playColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: _isLoading
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: playColor,
                      ),
                    )
                  : Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: playColor,
                      size: 24,
                    ),
            ),
          ),
          const SizedBox(width: 10),

          // Waveform + время
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Waveform с жестом перетаскивания
                LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      onHorizontalDragStart: (details) {
                        setState(() {
                          _isDragging = true;
                          _dragProgress = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                        });
                      },
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          _dragProgress = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                        });
                      },
                      onHorizontalDragEnd: (details) {
                        final newPos = Duration(
                          milliseconds: (_totalDuration.inMilliseconds * _dragProgress).round(),
                        );
                        setState(() => _isDragging = false);
                        _seek(newPos);
                      },
                      onTapUp: (details) {
                        final p = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                        final newPos = Duration(
                          milliseconds: (_totalDuration.inMilliseconds * p).round(),
                        );
                        _seek(newPos);
                      },
                      child: SizedBox(
                        height: 32,
                        width: constraints.maxWidth,
                        child: CustomPaint(
                          painter: WaveformPainter(
                            waveform: _waveformData ?? [],
                            progress: progress,
                            color: waveColor,
                            progressColor: waveProgressColor,
                            isDragging: _isDragging,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 2),
                // Время
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      displayDuration,
                      style: TextStyle(
                        color: widget.textColor.withValues(alpha: 0.6 * widget.messageTextOpacity),
                        fontSize: 11,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      widget.durationText,
                      style: TextStyle(
                        color: widget.textColor.withValues(alpha: 0.4 * widget.messageTextOpacity),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WaveformPainter extends CustomPainter {
  final List<int> waveform;
  final double progress;
  final Color color;
  final Color progressColor;
  final bool isDragging;

  WaveformPainter({
    required this.waveform,
    required this.progress,
    required this.color,
    required this.progressColor,
    this.isDragging = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final count = waveform.length;
    final totalWidth = size.width;
    final barWidth = (totalWidth / count * 0.6).clamp(2.0, 6.0);
    final gap = totalWidth / count;
    final progressX = totalWidth * progress;

    for (int i = 0; i < count; i++) {
      final x = i * gap + gap / 2 - barWidth / 2;
      final normalizedHeight = (waveform[i] / 255.0).clamp(0.08, 1.0);
      final barHeight = (size.height * normalizedHeight).clamp(3.0, size.height);

      final isPlayed = x < progressX;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          x,
          (size.height - barHeight) / 2,
          barWidth,
          barHeight,
        ),
        const Radius.circular(3),
      );

      paint.color = isPlayed ? progressColor : color;
      canvas.drawRRect(rect, paint);
    }

    final thumbPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(progressX.clamp(4.0, size.width - 4.0), size.height / 2),
      isDragging ? 6.0 : 4.0,
      thumbPaint,
    );
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.waveform != waveform ||
        oldDelegate.isDragging != isDragging;
  }
}
