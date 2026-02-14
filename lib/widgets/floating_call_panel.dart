import 'package:flutter/material.dart';
import 'dart:async';

/// Floating panel для минимизированного звонка (показывается внизу экрана)
class FloatingCallPanel extends StatefulWidget {
  final String callerName;
  final String? callerAvatarUrl;
  final VoidCallback onTap;
  final VoidCallback onHangup;
  final DateTime callStartTime;

  const FloatingCallPanel({
    Key? key,
    required this.callerName,
    this.callerAvatarUrl,
    required this.onTap,
    required this.onHangup,
    required this.callStartTime,
  }) : super(key: key);

  @override
  State<FloatingCallPanel> createState() => _FloatingCallPanelState();
}

class _FloatingCallPanelState extends State<FloatingCallPanel> {
  Timer? _timer;
  String _callDuration = '00:00';

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

    return Material(
      elevation: 8,
      color: colors.primaryContainer,
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 24,
                backgroundColor: colors.primary,
                backgroundImage: widget.callerAvatarUrl != null
                    ? NetworkImage(widget.callerAvatarUrl!)
                    : null,
                child: widget.callerAvatarUrl == null
                    ? Icon(Icons.person, color: colors.onPrimary)
                    : null,
              ),
              const SizedBox(width: 12),
              
              // Name and duration
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.callerName,
                      style: TextStyle(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _callDuration,
                      style: TextStyle(
                        color: colors.onPrimaryContainer.withValues(alpha: 0.8),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Hangup button
              IconButton(
                icon: Icon(Icons.call_end, color: Colors.red[400]),
                onPressed: widget.onHangup,
                // tooltip убран - требует Overlay
              ),
            ],
          ),
        ),
      ),
    );
  }
}
