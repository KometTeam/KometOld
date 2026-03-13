import 'package:flutter/material.dart';
import 'package:gwid/api/api_service.dart';
import 'package:gwid/widgets/contact_avatar_widget.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  List<Map<String, dynamic>> _callMessages = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCallHistory();
  }

  Future<void> _loadCallHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final apiService = ApiService.instance;

      // Отправляем запрос истории звонков (opcode 79) и ждём ответ
      final response = await apiService.sendRequest(79, {'forward': false, 'count': 100});

      final payload = response['payload'] as Map<String, dynamic>?;
      final history = payload?['history'] as List? ?? [];
      final callMessages = history
          .where((item) {
            final msg = (item as Map)['message'] as Map?;
            if (msg == null) return false;
            final attaches = msg['attaches'] as List? ?? [];
            return attaches.any((a) => a is Map && a['_type'] == 'CALL');
          })
          .map((item) {
            final itemMap = item as Map;
            final msg = Map<String, dynamic>.from(itemMap['message'] as Map);
            // Сохраняем chatId в самом сообщении для удаления
            msg['_chatId'] = itemMap['chatId'];
            return msg;
          })
          .toList();

      // Собираем все уникальные contactId которых нет в кэше
      final unknownIds = <int>{};
      final myId = ApiService.instance.myUserId ?? 0;
      for (final msg in callMessages) {
        final sender = msg['sender'] as int?;
        final attaches = msg['attaches'] as List? ?? [];
        for (final attach in attaches) {
          if (attach is Map && attach['_type'] == 'CALL') {
            final contactIds = attach['contactIds'] as List? ?? [];
            for (final id in contactIds) {
              if (id is int && id != myId && ApiService.instance.getCachedContact(id) == null) {
                unknownIds.add(id);
              }
            }
          }
        }
        if (sender != null && sender != myId && ApiService.instance.getCachedContact(sender) == null) {
          unknownIds.add(sender);
        }
      }

      // Загружаем незнакомых контактов пачками по 10
      if (unknownIds.isNotEmpty) {
        final idList = unknownIds.toList();
        for (var i = 0; i < idList.length; i += 10) {
          final batch = idList.sublist(i, i + 10 > idList.length ? idList.length : i + 10);
          try {
            final contactResp = await ApiService.instance.sendRequest(32, {'contactIds': batch});
            final contacts = (contactResp['payload']?['contacts'] as List?) ?? [];
            for (final c in contacts) {
              if (c is Map) {
                ApiService.instance.cacheContact(Map<String, dynamic>.from(c));
              }
            }
          } catch (_) {}
        }
      }

      if (mounted) {
        setState(() {
          _callMessages = callMessages;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Ошибка загрузки истории: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Звонки'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _callMessages.isEmpty ? null : _clearAllCalls,
            tooltip: 'Очистить историю',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCallHistory,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _buildBody(theme, colors),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme colors) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: colors.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadCallHistory,
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    if (_callMessages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.phone_disabled,
              size: 64,
              color: colors.onSurface.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'История звонков пуста',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCallHistory,
      child: ListView.builder(
        itemCount: _callMessages.length,
        itemBuilder: (context, index) {
          final message = _callMessages[index];
          return _buildCallItem(message, theme, colors);
        },
      ),
    );
  }

  Future<void> _clearAllCalls() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить историю звонков?'),
        content: const Text('Все звонки будут удалены. Это действие нельзя отменить.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;

    final toDelete = List<Map<String, dynamic>>.from(_callMessages);
    for (final message in toDelete) {
      await _deleteCall(message);
    }
  }

  Future<void> _deleteCall(Map<String, dynamic> message) async {
    final chatId = message['_chatId'] as int?;
    final messageId = message['id'];
    if (chatId == null || messageId == null) return;

    try {
      await ApiService.instance.sendRequest(66, {
        'chatId': chatId,
        'messageIds': [messageId is String ? int.tryParse(messageId) ?? messageId : messageId],
        'forMe': true,
      });
      if (mounted) {
        setState(() {
          _callMessages.removeWhere((m) => m['id'] == messageId);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка удаления: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Widget _buildCallItem(
    Map<String, dynamic> message,
    ThemeData theme,
    ColorScheme colors,
  ) {
    final apiService = ApiService.instance;
    final myId = apiService.myUserId ?? 0;
    final senderId = message['sender'] as int? ?? 0;
    final isIncoming = senderId != myId;

    // Получаем attach звонка
    final attaches = message['attaches'] as List? ?? [];
    final callAttach =
        attaches.firstWhere(
              (a) => a is Map && a['_type'] == 'CALL',
              orElse: () => <String, dynamic>{},
            )
            as Map<String, dynamic>;

    if (callAttach.isEmpty) {
      return const SizedBox.shrink();
    }
    final hangupType = (callAttach['hangupType'] as String? ?? 'unknown')
        .toLowerCase();
    final duration = callAttach['duration'] as int? ?? 0;
    final callType = (callAttach['callType'] as String? ?? 'audio')
        .toLowerCase();

    // DEBUG: Проверим что приходит
    if (hangupType == 'rejected' || hangupType == 'canceled') {
      print(
        '🔍 [CallsScreen] hangupType=$hangupType, duration=$duration, callAttach=$callAttach',
      );
    }
    final contactIds = callAttach['contactIds'] as List? ?? [];
    final time = message['time'] as int? ?? 0;

    // Определяем иконку и цвет
    IconData icon;
    Color iconColor;

    if (hangupType == 'missed') {
      icon = Icons.call_missed;
      iconColor = Colors.red;
    } else if (isIncoming) {
      icon = Icons.call_received;
      iconColor = Colors.green;
    } else {
      icon = Icons.call_made;
      iconColor = Colors.blue;
    }

    // Статус звонка
    String statusText;
    if (hangupType == 'missed') {
      statusText = 'Пропущенный';
    } else if (duration > 0) {
      // Если есть длительность - показываем её (даже для REJECTED/CANCELED)
      statusText = _formatDuration(duration);
    } else if (hangupType == 'rejected') {
      statusText = 'Отклонен';
    } else if (hangupType == 'canceled') {
      statusText = 'Отменен';
    } else {
      statusText = 'Звонок';
    }

    // Имя контакта - используем senderId если входящий, иначе contactIds
    final contactId = isIncoming
        ? senderId
        : (contactIds.isNotEmpty ? contactIds.first as int? : null);
    final cachedContact = contactId != null ? ApiService.instance.getCachedContact(contactId) : null;
    final contactName = cachedContact?.name ?? (contactId != null ? '$contactId' : 'Неизвестно');
    final avatarUrl = cachedContact?.photoBaseUrl;

    // Время
    final timeStr = _formatTime(DateTime.fromMillisecondsSinceEpoch(time));

    return ListTile(
      leading: Stack(
        children: [
          ContactAvatarWidget(
            contactId: contactId ?? 0,
            originalAvatarUrl: avatarUrl,
            radius: 22,
            fallbackText: contactName,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: CircleAvatar(
              radius: 8,
              backgroundColor: colors.surface,
              child: Icon(icon, color: iconColor, size: 10),
            ),
          ),
        ],
      ),
      title: Text(
        contactName,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: hangupType == 'missed' && isIncoming
              ? FontWeight.bold
              : FontWeight.normal,
        ),
      ),
      subtitle: Row(
        children: [
          if (callType == 'video')
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                Icons.videocam,
                size: 14,
                color: colors.onSurface.withOpacity(0.6),
              ),
            ),
          Text(statusText),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            timeStr,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => _deleteCall(message),
            child: Icon(
              Icons.delete_outline,
              size: 16,
              color: colors.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      ),
      onTap: () => _showCallDetails(message, contactName),
    );
  }

  String _formatDuration(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    if (seconds < 60) {
      return '$seconds сек';
    }
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inDays == 0) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Вчера';
    } else if (diff.inDays < 7) {
      const days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
      return days[time.weekday - 1];
    } else {
      return '${time.day.toString().padLeft(2, '0')}.${time.month.toString().padLeft(2, '0')}';
    }
  }

  void _showCallDetails(Map<String, dynamic> message, String contactName) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(contactName, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.phone),
              title: const Text('Позвонить'),
              onTap: () {
                Navigator.pop(context);
                _makeCall(message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Видеозвонок'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Видеозвонок
              },
            ),
          ],
        ),
      ),
    );
  }

  void _makeCall(Map<String, dynamic> message) {
    final attaches = message['attaches'] as List? ?? [];
    final callAttach =
        attaches.firstWhere(
              (a) => a is Map && a['_type'] == 'CALL',
              orElse: () => <String, dynamic>{},
            )
            as Map<String, dynamic>;

    final contactIds = callAttach['contactIds'] as List? ?? [];
    final contactId = contactIds.isNotEmpty ? contactIds.first : null;

    // TODO: Интеграция с CallsService для реального звонка
  }
}
