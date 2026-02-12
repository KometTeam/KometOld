import 'package:flutter/material.dart';
import 'package:gwid/services/calls_service.dart';
import 'package:gwid/screens/call_screen.dart';
import 'package:gwid/widgets/contact_avatar_widget.dart';

/// Overlay виджет для отображения входящих звонков
class IncomingCallOverlay extends StatefulWidget {
  const IncomingCallOverlay({super.key});

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay> {
  IncomingCallData? _currentCall;

  @override
  void initState() {
    super.initState();
    
    // Слушаем входящие звонки
    CallsService.instance.incomingCalls.listen((call) {
      if (mounted) {
        setState(() {
          _currentCall = call;
        });
      }
    });
  }

  void _acceptCall() async {
    if (_currentCall == null) return;

    final currentCall = _currentCall!; // Сохраняем до изменения state

    try {
      // Скрываем overlay сразу
      setState(() {
        _currentCall = null;
      });

      // Принимаем звонок
      final response = await CallsService.instance.acceptCall(
        currentCall.conversationId,
        currentCall.callerId,
      );
      
      if (!mounted) return;

      // Открываем экран звонка
      // Используем navigator key для надежной навигации
      final navigator = Navigator.of(context, rootNavigator: true);
      navigator.push(
        MaterialPageRoute(
          builder: (context) => CallScreen(
            callData: response,
            contactName: currentCall.callerName,
            contactId: currentCall.callerId,
            contactAvatarUrl: currentCall.callerAvatarUrl,
            isOutgoing: false,
            isVideo: currentCall.isVideo,
          ),
        ),
      );
    } catch (e) {
      print('❌ Ошибка принятия звонка: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось принять звонок: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _rejectCall() async {
    if (_currentCall == null) return;

    try {
      await CallsService.instance.rejectCall(_currentCall!.conversationId);
    } catch (e) {
      print('❌ Ошибка отклонения звонка: $e');
    } finally {
      if (mounted) {
        setState(() {
          _currentCall = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentCall == null) {
      return const SizedBox.shrink();
    }

    final colors = Theme.of(context).colorScheme;

    return Material(
      color: Colors.black54,
      child: SafeArea(
        child: Center(
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
                // Аватарка звонящего
                ContactAvatarWidget(
                  contactId: _currentCall!.callerId,
                  originalAvatarUrl: _currentCall!.callerAvatarUrl,
                  radius: 40,
                  fallbackText: _currentCall!.callerName.isNotEmpty
                      ? _currentCall!.callerName[0].toUpperCase()
                      : '?',
                ),

                const SizedBox(height: 24),

                // Имя звонящего
                Text(
                  _currentCall!.callerName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 8),

                // Тип звонка
                Text(
                  _currentCall!.isVideo ? 'Видеозвонок' : 'Аудиозвонок',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 32),

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
