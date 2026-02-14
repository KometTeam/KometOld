import 'package:flutter/material.dart';
import 'dart:async';

/// Floating draggable button для минимизированного звонка (показывается в чатах)
class FloatingCallButton extends StatefulWidget {
  final String callerName;
  final String? callerAvatarUrl;
  final VoidCallback onTap;
  final VoidCallback onHangup;
  final DateTime callStartTime;

  const FloatingCallButton({
    Key? key,
    required this.callerName,
    this.callerAvatarUrl,
    required this.onTap,
    required this.onHangup,
    required this.callStartTime,
  }) : super(key: key);

  @override
  State<FloatingCallButton> createState() => _FloatingCallButtonState();
}

class _FloatingCallButtonState extends State<FloatingCallButton> {
  Timer? _timer;
  String _callDuration = '00:00';
  Offset _position = const Offset(20, 100);
  
  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _updateDuration();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _updateDuration();
      }
    });
  }

  void _updateDuration() {
    final duration = DateTime.now().difference(widget.callStartTime);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    setState(() {
      _callDuration = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final screenSize = MediaQuery.of(context).size;

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position = Offset(
              (_position.dx + details.delta.dx).clamp(0.0, screenSize.width - 80),
              (_position.dy + details.delta.dy).clamp(0.0, screenSize.height - 120),
            );
          });
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: Stack(
            children: [
              // Avatar - только аватарка без обводки
              CircleAvatar(
                radius: 40,
                backgroundImage: widget.callerAvatarUrl != null
                    ? NetworkImage(widget.callerAvatarUrl!)
                    : null,
                child: widget.callerAvatarUrl == null
                    ? Icon(Icons.person, color: colors.onPrimary, size: 40)
                    : null,
              ),
              
              // Duration badge - время звонка внизу
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _callDuration,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
