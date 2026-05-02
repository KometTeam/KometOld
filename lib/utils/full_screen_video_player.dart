import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'dart:async';

class FullScreenVideoPlayer extends StatefulWidget {
  final String videoUrl;

  const FullScreenVideoPlayer({super.key, required this.videoUrl});

  @override
  State<FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<FullScreenVideoPlayer>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _videoPlayerController;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isPlaying = false;
  bool _showControls = true;
  bool _isBuffering = false;
  double _playbackSpeed = 1.0;
  bool _isLooping = false;
  final TransformationController _transformationController = TransformationController();
  Timer? _hideControlsTimer;
  Timer? _positionTimer;
  late AnimationController _controlsAnimationController;
  late Animation<double> _controlsAnimation;
  bool _isDragging = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  List<DurationRange> _bufferedRanges = [];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);

    _controlsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _controlsAnimation = CurvedAnimation(
      parent: _controlsAnimationController,
      curve: Curves.easeInOut,
    );

    _controlsAnimationController.forward();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
        httpHeaders: const {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      );

      _videoPlayerController!.addListener(_videoListener);
      await _videoPlayerController!.initialize();
      _videoPlayerController!.play();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isPlaying = true;
          _totalDuration = _videoPlayerController!.value.duration;
          _currentPosition = _videoPlayerController!.value.position;
        });
        _startHideControlsTimer();
        _startPositionTimer();
      }
    } catch (e) {
      print('❌ [FullScreenVideoPlayer] Error initializing player: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  void _videoListener() {
    if (!mounted) return;

    final controller = _videoPlayerController!;
    setState(() {
      _isPlaying = controller.value.isPlaying;
      _isBuffering = controller.value.isBuffering;
      _totalDuration = controller.value.duration;
      _bufferedRanges = controller.value.buffered;
      if (!_isDragging) {
        _currentPosition = controller.value.position;
      }
    });
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (_isPlaying && !_isDragging) {
        _hideControlsUI();
      }
    });
  }

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || _isDragging) return;
      if (_videoPlayerController != null &&
          _videoPlayerController!.value.isInitialized) {
        setState(() {
          _currentPosition = _videoPlayerController!.value.position;
        });
      }
    });
  }

  void _showControlsUI() {
    if (_showControls) return;
    setState(() {
      _showControls = true;
    });
    _controlsAnimationController.forward();
    _startHideControlsTimer();
  }

  void _hideControlsUI() {
    if (!_showControls) return;
    setState(() {
      _showControls = false;
    });
    _controlsAnimationController.reverse();
  }

  void _togglePlayPause() {
    setState(() {
      if (_isPlaying) {
        _videoPlayerController!.pause();
        _showControlsUI();
      } else {
        _videoPlayerController!.play();
        _startHideControlsTimer();
      }
    });
  }

  Duration _clampDuration(Duration value, Duration min, Duration max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  void _seekTo(Duration position) {
    _videoPlayerController!.seekTo(position);
    setState(() {
      _currentPosition = position;
      _isDragging = false;
    });
    _startHideControlsTimer();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  void _showSpeedMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) => _SpeedSliderSheet(
        currentSpeed: _playbackSpeed,
        onSpeedChanged: (speed) {
          setState(() {
            _playbackSpeed = speed;
            _videoPlayerController!.setPlaybackSpeed(speed);
          });
        },
        onClose: () => Navigator.pop(context),
      ),
    );
  }

  void _toggleLoop() {
    setState(() => _isLooping = !_isLooping);
    _videoPlayerController!.setLooping(_isLooping);
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _positionTimer?.cancel();
    _videoPlayerController?.removeListener(_videoListener);
    _videoPlayerController?.dispose();
    _controlsAnimationController.dispose();
    _transformationController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (_showControls) {
                _hideControlsUI();
              } else {
                _showControlsUI();
              }
            },
            onDoubleTapDown: (details) {
              final screenWidth = MediaQuery.of(context).size.width;
              if (details.globalPosition.dx < screenWidth / 2) {
                final newPosition = _clampDuration(
                  _currentPosition - const Duration(seconds: 10),
                  Duration.zero,
                  _totalDuration,
                );
                _seekTo(newPosition);
                _showControlsUI();
              } else {
                final newPosition = _clampDuration(
                  _currentPosition + const Duration(seconds: 10),
                  Duration.zero,
                  _totalDuration,
                );
                _seekTo(newPosition);
                _showControlsUI();
              }
            },
            child: Stack(
              children: [
                _isLoading
                    ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
                    : _hasError
                    ? Center(child: _ErrorWidget(colorScheme: colorScheme))
                    : _videoPlayerController != null &&
                          _videoPlayerController!.value.isInitialized
                    ? InteractiveViewer(
                        transformationController: _transformationController,
                        minScale: 1.0,
                        maxScale: 4.0,
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: _videoPlayerController!.value.aspectRatio,
                            child: VideoPlayer(_videoPlayerController!),
                          ),
                        ),
                      )
                    : const SizedBox(),

                if (_isBuffering)
                  Positioned(
                    top: 60,
                    right: 16,
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: colorScheme.primary,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_showControls)
            GestureDetector(
              onDoubleTapDown: (details) {
                final screenWidth = MediaQuery.of(context).size.width;
                if (details.globalPosition.dx < screenWidth / 2) {
                  final newPosition = _clampDuration(
                    _currentPosition - const Duration(seconds: 10),
                    Duration.zero,
                    _totalDuration,
                  );
                  _seekTo(newPosition);
                  _showControlsUI();
                } else {
                  final newPosition = _clampDuration(
                    _currentPosition + const Duration(seconds: 10),
                    Duration.zero,
                    _totalDuration,
                  );
                  _seekTo(newPosition);
                  _showControlsUI();
                }
              },
              behavior: HitTestBehavior.translucent,
              child: AnimatedBuilder(
                animation: _controlsAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _controlsAnimation.value,
                    child: child,
                  );
                },
                child: _VideoControls(
                  colorScheme: colorScheme,
                  isPlaying: _isPlaying,
                  currentPosition: _currentPosition,
                  totalDuration: _totalDuration,
                  bufferedRanges: _bufferedRanges,
                  playbackSpeed: _playbackSpeed,
                  isLooping: _isLooping,
                  onPlayPause: _togglePlayPause,
                  onSeek: (position) {
                    setState(() {
                      _isDragging = true;
                      _currentPosition = position;
                    });
                  },
                  onSeekEnd: (position) {
                    _seekTo(position);
                  },
                  onBack: () => Navigator.pop(context),
                  onSpeedTap: () {
                    _showSpeedMenu();
                  },
                  onLoopTap: _toggleLoop,
                  onRewind: () {
                    final newPosition = _clampDuration(
                      _currentPosition - const Duration(seconds: 10),
                      Duration.zero,
                      _totalDuration,
                    );
                    _seekTo(newPosition);
                    _showControlsUI();
                  },
                  onForward: () {
                    final newPosition = _clampDuration(
                      _currentPosition + const Duration(seconds: 10),
                      Duration.zero,
                      _totalDuration,
                    );
                    _seekTo(newPosition);
                    _showControlsUI();
                  },
                  formatDuration: _formatDuration,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VideoControls extends StatelessWidget {
  final ColorScheme colorScheme;
  final bool isPlaying;
  final Duration currentPosition;
  final Duration totalDuration;
  final List<DurationRange> bufferedRanges;
  final double playbackSpeed;
  final bool isLooping;
  final VoidCallback onPlayPause;
  final Function(Duration) onSeek;
  final Function(Duration) onSeekEnd;
  final VoidCallback onBack;
  final VoidCallback onSpeedTap;
  final VoidCallback onLoopTap;
  final VoidCallback onRewind;
  final VoidCallback onForward;
  final String Function(Duration) formatDuration;

  const _VideoControls({
    required this.colorScheme,
    required this.isPlaying,
    required this.currentPosition,
    required this.totalDuration,
    required this.bufferedRanges,
    required this.playbackSpeed,
    required this.isLooping,
    required this.onPlayPause,
    required this.onSeek,
    required this.onSeekEnd,
    required this.onBack,
    required this.onSpeedTap,
    required this.onLoopTap,
    required this.onRewind,
    required this.onForward,
    required this.formatDuration,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalDuration.inMilliseconds > 0
        ? currentPosition.inMilliseconds / totalDuration.inMilliseconds
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.5),
                      foregroundColor: Colors.white,
                      shape: const CircleBorder(),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onLoopTap,
                    icon: Icon(
                      isLooping ? Icons.repeat_one : Icons.repeat,
                      color: isLooping ? colorScheme.primary : Colors.white,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.5),
                      shape: const CircleBorder(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: onSpeedTap,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.speed, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          '${playbackSpeed}x',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _CustomProgressBar(
                    progress: progress,
                    currentPosition: currentPosition,
                    totalDuration: totalDuration,
                    bufferedRanges: bufferedRanges,
                    onSeek: onSeek,
                    onSeekEnd: onSeekEnd,
                    colorScheme: colorScheme,
                    formatDuration: formatDuration,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        formatDuration(currentPosition),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Text(
                        ' / ',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      Text(
                        formatDuration(totalDuration),
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _MaterialYouControlButton(
                        icon: Icons.replay_10,
                        onTap: onRewind,
                        colorScheme: colorScheme,
                        label: '-10',
                      ),
                      const SizedBox(width: 12),
                      _MaterialYouControlButton(
                        icon: isPlaying ? Icons.pause : Icons.play_arrow,
                        onTap: onPlayPause,
                        colorScheme: colorScheme,
                        isPrimary: true,
                      ),
                      const SizedBox(width: 12),

                      _MaterialYouControlButton(
                        icon: Icons.forward_10,
                        onTap: onForward,
                        colorScheme: colorScheme,
                        label: '+10',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaterialYouControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final ColorScheme colorScheme;
  final String? label;
  final bool isPrimary;

  const _MaterialYouControlButton({
    required this.icon,
    required this.onTap,
    required this.colorScheme,
    this.label,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isPrimary) {
      return FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.all(20),
          shape: const CircleBorder(),
          minimumSize: const Size(72, 72),
          elevation: 3,
        ),
        child: Icon(icon, size: 36),
      );
    } else {
      return FilledButton.tonal(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.16),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.all(14),
          shape: const CircleBorder(),
          minimumSize: const Size(60, 60),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26),
            if (label != null) ...[
              const SizedBox(height: 2),
              Text(
                label!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                ),
              ),
            ],
          ],
        ),
      );
    }
  }
}

class _CustomProgressBar extends StatefulWidget {
  final double progress;
  final Duration currentPosition;
  final Duration totalDuration;
  final List<DurationRange> bufferedRanges;
  final Function(Duration) onSeek;
  final Function(Duration) onSeekEnd;
  final ColorScheme colorScheme;
  final String Function(Duration) formatDuration;

  const _CustomProgressBar({
    required this.progress,
    required this.currentPosition,
    required this.totalDuration,
    required this.bufferedRanges,
    required this.onSeek,
    required this.onSeekEnd,
    required this.colorScheme,
    required this.formatDuration,
  });

  @override
  State<_CustomProgressBar> createState() => _CustomProgressBarState();
}

class _CustomProgressBarState extends State<_CustomProgressBar> {
  bool _isDragging = false;
  double _dragProgress = 0.0;

  Duration _getPositionFromLocalPosition(Offset localPosition, Size size) {
    final progress = (localPosition.dx / size.width).clamp(0.0, 1.0);
    return Duration(
      milliseconds: (progress * widget.totalDuration.inMilliseconds).round(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = _isDragging ? _dragProgress : widget.progress;
    final currentPos = Duration(
      milliseconds: (progress * widget.totalDuration.inMilliseconds).round(),
    );

    return GestureDetector(
      onPanStart: (details) {
        setState(() {
          _isDragging = true;
        });
        final box = context.findRenderObject() as RenderBox;
        final localPosition = box.globalToLocal(details.globalPosition);
        _dragProgress = (localPosition.dx / box.size.width).clamp(0.0, 1.0);
        final position = _getPositionFromLocalPosition(localPosition, box.size);
        widget.onSeek(position);
      },
      onPanUpdate: (details) {
        final box = context.findRenderObject() as RenderBox;
        final localPosition = box.globalToLocal(details.globalPosition);
        setState(() {
          _dragProgress = (localPosition.dx / box.size.width).clamp(0.0, 1.0);
        });
        final position = _getPositionFromLocalPosition(localPosition, box.size);
        widget.onSeek(position);
      },
      onPanEnd: (details) {
        setState(() {
          _isDragging = false;
        });
        widget.onSeekEnd(currentPos);
      },
      onTapDown: (details) {
        if (_isDragging) return;
        final box = context.findRenderObject() as RenderBox;
        final localPosition = box.globalToLocal(details.globalPosition);
        final position = _getPositionFromLocalPosition(localPosition, box.size);
        widget.onSeekEnd(position);
      },
      child: SizedBox(
        height: 48,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final containerWidth = constraints.maxWidth;

            return Stack(
              children: [
                Center(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (widget.totalDuration.inMilliseconds > 0)
                  ...widget.bufferedRanges.map((range) {
                    final startProgress =
                        (range.start.inMilliseconds /
                                widget.totalDuration.inMilliseconds)
                            .clamp(0.0, 1.0);
                    final endProgress =
                        (range.end.inMilliseconds /
                                widget.totalDuration.inMilliseconds)
                            .clamp(0.0, 1.0);
                    final bufferedWidth = (endProgress - startProgress).clamp(
                      0.0,
                      1.0,
                    );

                    if (bufferedWidth <= 0) return const SizedBox.shrink();

                    final leftOffset = startProgress * containerWidth;
                    final bufferedWidthPx = bufferedWidth * containerWidth;

                    return Positioned(
                      left: leftOffset,
                      top: 22,
                      child: Container(
                        width: bufferedWidthPx,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                Center(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: progress,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: widget.colorScheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),

                Center(
                  child: Align(
                    alignment: Alignment(progress * 2 - 1, 0),
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: widget.colorScheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SpeedSliderSheet extends StatefulWidget {
  final double currentSpeed;
  final Function(double) onSpeedChanged;
  final VoidCallback onClose;

  const _SpeedSliderSheet({
    required this.currentSpeed,
    required this.onSpeedChanged,
    required this.onClose,
  });

  @override
  State<_SpeedSliderSheet> createState() => _SpeedSliderSheetState();
}

class _SpeedSliderSheetState extends State<_SpeedSliderSheet> {
  late double _speed;

  @override
  void initState() {
    super.initState();
    _speed = widget.currentSpeed;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: theme.dialogBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              Text(
                'Скорость воспроизведения',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_speed.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '')}x',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('0.25x', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
              Expanded(
                child: Slider(
                  value: _speed,
                  min: 0.25,
                  max: 2.0,
                  divisions: 7,
                  onChanged: (value) {
                    // Снапаем к значениям: 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0
                    final snapped = (value * 4).round() / 4;
                    setState(() => _speed = snapped);
                    widget.onSpeedChanged(snapped);
                  },
                ),
              ),
              Text('2x', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0].map((s) {
              return GestureDetector(
                onTap: () {
                  setState(() => _speed = s);
                  widget.onSpeedChanged(s);
                },
                child: Text(
                  '${s}x',
                  style: TextStyle(
                    color: _speed == s ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: _speed == s ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: widget.onClose,
            child: const Text('Готово'),
          ),
        ],
      ),
    );
  }
}

class _ErrorWidget extends StatelessWidget {
  final ColorScheme colorScheme;

  const _ErrorWidget({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                color: colorScheme.onErrorContainer,
                size: 48,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Не удалось загрузить видео',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Проверьте подключение к интернету\nили попробуйте позже',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
