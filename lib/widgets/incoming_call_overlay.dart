import 'package:flutter/material.dart';
import 'package:gwid/services/calls_service.dart';
import 'package:gwid/services/call_overlay_service.dart';
import 'package:gwid/services/floating_call_manager.dart';
import 'package:gwid/widgets/contact_avatar_widget.dart';

/// Overlay виджет для отображения входящих звонков
class IncomingCallOverlay extends StatelessWidget {
  const IncomingCallOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CallsService.instance,
      builder: (context, _) {
        final currentCall = CallsService.instance.currentIncomingCall;
        
        if (currentCall == null) {
          return const SizedBox.shrink();
        }

        return _IncomingCallDialog(call: currentCall);
      },
    );
  }
}

/// Диалог входящего звонка
class _IncomingCallDialog extends StatefulWidget {
  final IncomingCallData call;
  
  const _IncomingCallDialog({required this.call});

  @override
  State<_IncomingCallDialog> createState() => _IncomingCallDialogState();
}

class _IncomingCallDialogState extends State<_IncomingCallDialog> with TickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _pulseAnimation;
  bool _enableDataChannel = false;
  
  @override
  void initState() {
    super.initState();
    
    // Контроллер для scale анимации (появление диалога)
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    
    // Scale анимация - легкий bounce
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOutBack,
    );
    
    // Контроллер для пульсации аватарки
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    
    // Pulse анимация - легкая пульсация
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    // Запускаем анимацию появления
    _scaleController.forward();
  }
  
  @override
  void dispose() {
    _scaleController.dispose();
    _pulseController.dispose();
    super.dispose();
  }
  
  void _acceptCall() async {
    final call = widget.call;

    try {
      CallsService.instance.markCallAsAccepted(call.conversationId);
      final response = await CallsService.instance.acceptCall(
        call.conversationId,
        call.callerId,
      );
      
      CallsService.instance.clearIncomingCall();
      
      CallOverlayService.instance.showCall(
        null,
        callData: response,
        contactName: call.callerName,
        contactId: call.callerId,
        contactAvatarUrl: call.callerAvatarUrl,
        isOutgoing: false,
        isVideo: call.isVideo,
        enableDataChannel: _enableDataChannel, // Передаем флаг
      );
    } catch (e, stackTrace) {
      print('❌ Error accepting call: $e');
      print('❌ Stack trace: $stackTrace');
      
      CallsService.instance.clearIncomingCall();
      FloatingCallManager.instance.endCall();
      
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept call: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _rejectCall() async {
    final call = widget.call;
    
    try {
      // Сначала очищаем входящий звонок из сервиса
      CallsService.instance.clearIncomingCall();
      
      await CallsService.instance.rejectCall(
        call.conversationId,
        call.callerId,
      );
    } catch (e) {
      print('Error rejecting call: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    // Positioned.fill чтобы занять весь экран внутри Stack
    return Positioned.fill(
      child: Material(
        color: Colors.black54,
        child: SafeArea(
          child: Center(
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Аватарка с пульсацией и ripple эффектом
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        // Ripple эффект (пульсирующие круги)
                        ScaleTransition(
                          scale: _pulseAnimation,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.green.withValues(alpha: 0.3),
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                        
                        // Аватарка
                        ScaleTransition(
                          scale: _pulseAnimation,
                          child: ContactAvatarWidget(
                            contactId: widget.call.callerId,
                            originalAvatarUrl: widget.call.callerAvatarUrl,
                            radius: 45,
                            fallbackText: widget.call.callerName.isNotEmpty
                                ? widget.call.callerName[0].toUpperCase()
                                : '?',
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Имя звонящего
                    Text(
                      widget.call.callerName,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 8),

                    // Тип звонка
                    Text(
                      widget.call.isVideo ? 'Видеозвонок' : 'Аудиозвонок',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Опция DATA_CHANNEL
                    CheckboxListTile(
                      value: _enableDataChannel,
                      onChanged: (value) => setState(() => _enableDataChannel = value ?? false),
                      title: const Text('Enable DATA_CHANNEL'),
                      subtitle: const Text('Для temporary chat'),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),

                    const SizedBox(height: 16),

                    // Кнопки
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Отклонить
                        _IncomingCallButton(
                          icon: Icons.call_end,
                          label: 'Отклонить',
                          backgroundColor: colors.error,
                          foregroundColor: colors.onError,
                          onPressed: _rejectCall,
                        ),

                        // Принять
                        _IncomingCallButton(
                          icon: Icons.call,
                          label: 'Принять',
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          onPressed: _acceptCall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Кнопка для входящего звонка
class _IncomingCallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onPressed;

  const _IncomingCallButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: backgroundColor,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 28,
                color: foregroundColor,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
