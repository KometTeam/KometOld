import 'package:flutter/material.dart';
import 'package:gwid/screens/call_screen.dart';
import 'package:gwid/models/call_response.dart';
import 'package:gwid/services/floating_call_manager.dart';
import 'package:gwid/main.dart';

/// Сервис для показа CallScreen через Overlay (поверх всего)
class CallOverlayService {
  static final CallOverlayService instance = CallOverlayService._();
  CallOverlayService._();

  OverlayEntry? _callOverlayEntry;
  OverlayState? _overlayState; // Сохраняем ссылку на OverlayState
  bool _isMinimized = false;
  DateTime? _callStartTime; // Сохраняем время начала звонка

  /// Показать звонок через Overlay
  void showCall(
    BuildContext? context, {
    required CallResponse callData,
    required int contactId,
    required String contactName,
    String? contactAvatarUrl,
    bool isVideo = false,
    bool isOutgoing = true,
  }) {
    if (_callOverlayEntry != null) {
      closeCall();
    }

    if (context != null) {
      try {
        _overlayState = Overlay.of(context);
      } catch (e) {
        _overlayState = null;
      }
    }
    
    if (_overlayState == null) {
      _overlayState = navigatorKey.currentState?.overlay;
    }
    
    if (_overlayState == null) return;
    
    _isMinimized = false;
    _callStartTime = DateTime.now();
    
    // НЕ вызываем startCall() здесь - это будет сделано при подключении звонка в CallScreen
    // FloatingCallManager.instance.startCall() вызывается в onTrack и onConnectionState

    _callOverlayEntry = OverlayEntry(
      builder: (context) => _CallOverlayWidget(
        callData: callData,
        contactId: contactId,
        contactName: contactName,
        contactAvatarUrl: contactAvatarUrl,
        isVideo: isVideo,
        isOutgoing: isOutgoing,
        callStartTime: _callStartTime,
        onMinimize: () => _minimizeCall(contactName, contactAvatarUrl, contactId, callData, isVideo),
        onClose: closeCall,
      ),
    );

    _overlayState!.insert(_callOverlayEntry!);
  }

  /// Минимизировать звонок (скрыть UI, но оставить WebRTC)
  void _minimizeCall(String name, String? avatar, int id, CallResponse data, bool video) {
    _isMinimized = true;
    
    FloatingCallManager.instance.minimizeCall(
      callerName: name,
      callerAvatarUrl: avatar,
      callerId: id,
      callResponse: data,
      callStartTime: _callStartTime ?? DateTime.now(),
      isVideo: video,
    );
    
    _callOverlayEntry?.markNeedsBuild();
  }

  /// Развернуть звонок обратно
  void maximizeCall() {
    if (_callOverlayEntry == null) return;
    
    _isMinimized = false;
    FloatingCallManager.instance.maximizeCall();
    _callOverlayEntry?.markNeedsBuild();
  }

  /// Закрыть звонок полностью
  void closeCall() {
    _callOverlayEntry?.remove();
    _callOverlayEntry = null;
    _overlayState = null;
    _isMinimized = false;
    _callStartTime = null;
    
    FloatingCallManager.instance.endCall();
  }

  bool get isMinimized => _isMinimized;
  bool get hasActiveCall => _callOverlayEntry != null;
}

/// Виджет CallScreen в Overlay
class _CallOverlayWidget extends StatefulWidget {
  final CallResponse callData;
  final int contactId;
  final String contactName;
  final String? contactAvatarUrl;
  final bool isVideo;
  final bool isOutgoing;
  final DateTime? callStartTime;
  final VoidCallback onMinimize;
  final VoidCallback onClose;

  const _CallOverlayWidget({
    required this.callData,
    required this.contactId,
    required this.contactName,
    this.contactAvatarUrl,
    required this.isVideo,
    required this.isOutgoing,
    this.callStartTime,
    required this.onMinimize,
    required this.onClose,
  });

  @override
  State<_CallOverlayWidget> createState() => _CallOverlayWidgetState();
}

class _CallOverlayWidgetState extends State<_CallOverlayWidget> with SingleTickerProviderStateMixin {
  late final GlobalKey _callScreenKey;
  late final AnimationController _animationController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  
  @override
  void initState() {
    super.initState();
    
    _callScreenKey = GlobalKey();
    
    // Контроллер анимации (300ms)
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    
    // Slide анимация (сверху вниз)
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, 1),
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    // Fade анимация
    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    FloatingCallManager.instance.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _animationController.dispose();
    FloatingCallManager.instance.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) {
      final isMinimized = CallOverlayService.instance.isMinimized;
      
      if (isMinimized) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
      
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMinimized = CallOverlayService.instance.isMinimized;
    
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: IgnorePointer(
          ignoring: isMinimized,
          child: Material(
            child: CallScreen(
              key: _callScreenKey,
              callData: widget.callData,
              contactId: widget.contactId,
              contactName: widget.contactName,
              contactAvatarUrl: widget.contactAvatarUrl,
              isVideo: widget.isVideo,
              isOutgoing: widget.isOutgoing,
              callStartTime: widget.callStartTime,
              onMinimize: widget.onMinimize,
            ),
          ),
        ),
      ),
    );
  }
}
