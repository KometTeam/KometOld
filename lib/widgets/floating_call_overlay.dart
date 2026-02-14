import 'package:flutter/material.dart';
import 'package:gwid/services/floating_call_manager.dart';
import 'package:gwid/services/call_overlay_service.dart';
import 'package:gwid/widgets/floating_call_panel.dart';
import 'package:gwid/widgets/floating_call_button.dart';

/// Overlay для отображения минимизированного звонка
class FloatingCallOverlay extends StatelessWidget {
  final Widget child;

  const FloatingCallOverlay({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FloatingCallManager.instance,
      builder: (context, _) {
        final manager = FloatingCallManager.instance;

        if (!manager.hasActiveCall || !manager.isMinimized) {
          return child;
        }

        return Stack(
          children: [
            child,
            
            // Показываем панель внизу или кружок
            if (manager.shouldShowAsPanel)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: FloatingCallPanel(
                  callerName: manager.callerName!,
                  callerAvatarUrl: manager.callerAvatarUrl,
                  callStartTime: manager.callStartTime!,
                  onTap: () => _maximizeCall(context),
                  onHangup: () => _hangupCall(context),
                ),
              ),
            
            if (manager.shouldShowAsButton)
              FloatingCallButton(
                callerName: manager.callerName!,
                callerAvatarUrl: manager.callerAvatarUrl,
                callStartTime: manager.callStartTime!,
                onTap: () => _maximizeCall(context),
                onHangup: () => _hangupCall(context),
              ),
          ],
        );
      },
    );
  }

  void _maximizeCall(BuildContext context) {
    CallOverlayService.instance.maximizeCall();
  }

  void _hangupCall(BuildContext context) {
    final endCallCallback = FloatingCallManager.instance.onEndCall;
    if (endCallCallback != null) {
      endCallCallback();
    } else {
      CallOverlayService.instance.closeCall();
    }
  }
}
