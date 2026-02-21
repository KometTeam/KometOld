import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:gwid/screens/cache_management_screen.dart';
import 'package:provider/provider.dart';
import 'package:gwid/utils/theme_provider.dart';
import 'package:gwid/api/api_service.dart';
import 'package:gwid/screens/phone_entry_screen.dart';
import 'package:gwid/screens/custom_request_screen.dart';
import 'dart:async';
import 'package:maxcalls_dart/maxcalls_dart.dart';

class DebugScreen extends StatelessWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = context.watch<ThemeProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Settings'),
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _OutlinedSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    "Performance Debug",
                    style: TextStyle(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.speed),
                  title: const Text("Показать FPS overlay"),
                  subtitle: const Text("Отображение FPS и производительности"),
                  trailing: Switch(
                    value: theme.debugShowPerformanceOverlay,
                    onChanged: (value) =>
                        theme.setDebugShowPerformanceOverlay(value),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.refresh),
                  title: const Text("Показать панель обновления чатов"),
                  subtitle: const Text(
                    "Debug панель для обновления списка чатов",
                  ),
                  trailing: Switch(
                    value: theme.debugShowChatsRefreshPanel,
                    onChanged: (value) =>
                        theme.setDebugShowChatsRefreshPanel(value),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.message),
                  title: const Text("Показать счётчик сообщений"),
                  subtitle: const Text("Отладочная информация о сообщениях"),
                  trailing: Switch(
                    value: theme.debugShowMessageCount,
                    onChanged: (value) => theme.setDebugShowMessageCount(value),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          _OutlinedSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    "Инструменты разработчика",
                    style: TextStyle(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.code),
                  title: const Text("Custom API Request"),
                  subtitle: const Text("Отправить сырой запрос на сервер"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const CustomRequestScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          _OutlinedSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    "Тестирование звонков",
                    style: TextStyle(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.phone_in_talk),
                  title: const Text("Тест звонков (nullcalls)"),
                  subtitle: const Text("Тестирование библиотеки звонков MAX"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showCallsTestScreen(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          _OutlinedSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    "Data Management",
                    style: TextStyle(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_forever),
                  title: const Text("Очистить все данные"),
                  subtitle: const Text("Полная очистка кэшей и данных"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showClearAllDataDialog(context),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.phone),
                  title: const Text("Показать ввод номера"),
                  subtitle: const Text("Открыть экран ввода номера без выхода"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showPhoneEntryScreen(context),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.traffic),
                  title: const Text("Статистика трафика"),
                  subtitle: const Text("Просмотр использованного трафика"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showTrafficStats(context),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.storage),
                  title: const Text("Использование памяти"),
                  subtitle: const Text("Просмотр статистики памяти"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showMemoryUsage(context),
                ),
                const SizedBox(height: 8),

                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cached),
                  title: const Text("Управление кэшем"),
                  subtitle: const Text("Настройки кэширования и статистика"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const CacheManagementScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showClearAllDataDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить все данные'),
        content: const Text(
          'Это действие удалит ВСЕ данные приложения:\n\n'
          '• Все кэши и сообщения\n'
          '• Настройки и профиль\n'
          '• Токен авторизации\n'
          '• История чатов\n\n'
          'После очистки приложение будет закрыто.\n'
          'Вы уверены?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _performFullDataClear(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Очистить и закрыть'),
          ),
        ],
      ),
    );
  }

  Future<void> _performFullDataClear(BuildContext context) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Очистка данных...'),
            ],
          ),
        ),
      );

      await ApiService.instance.clearAllData();

      if (context.mounted) {
        Navigator.of(context).pop();
      }

      await Future.delayed(const Duration(seconds: 2));

      if (context.mounted) {
        SystemNavigator.pop();
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при очистке данных: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showPhoneEntryScreen(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const PhoneEntryScreen()));
  }

  void _showTrafficStats(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Статистика трафика'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📊 Статистика использования данных:'),
            SizedBox(height: 16),
            Text('• Отправлено сообщений: 1,247'),
            Text('• Получено сообщений: 3,891'),
            Text('• Загружено фото: 156 MB'),
            Text('• Загружено видео: 89 MB'),
            Text('• Общий трафик: 2.1 GB'),
            SizedBox(height: 16),
            Text('📅 За последние 30 дней'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  void _showMemoryUsage(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Использование памяти'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('💾 Использование памяти:'),
            SizedBox(height: 16),
            Text('• Кэш сообщений: 45.2 MB'),
            Text('• Кэш контактов: 12.8 MB'),
            Text('• Кэш чатов: 8.3 MB'),
            Text('• Медиа файлы: 156.7 MB'),
            Text('• Общее использование: 223.0 MB'),
            SizedBox(height: 16),
            Text('📱 Доступно памяти: 2.1 GB'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Очистить кэш'),
          ),
        ],
      ),
    );
  }

  void _showCallsTestScreen(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const CallsTestScreen()));
  }
}

class _OutlinedSection extends StatelessWidget {
  final Widget child;

  const _OutlinedSection({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outline.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class Session {
  final String client;
  final String location;
  final bool current;
  final int time;
  final String info;

  Session({
    required this.client,
    required this.location,
    required this.current,
    required this.time,
    required this.info,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      client: json['client'] ?? '',
      location: json['location'] ?? '',
      current: json['current'] ?? false,
      time: json['time'] ?? 0,
      info: json['info'] ?? '',
    );
  }
}

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  List<Session> _sessions = [];
  bool _isLoading = true;
  bool _isInitialLoad = true;
  StreamSubscription? _apiSubscription;

  @override
  void initState() {
    super.initState();
    _listenToApi();
  }

  void _loadSessions() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isLoading = true;
        });
      }
    });
    ApiService.instance.requestSessions();
  }

  void _terminateAllSessions() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сбросить все сессии?'),
        content: const Text(
          'Все остальные сессии будут завершены. '
          'Текущая сессия останется активной.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isLoading = true;
          });
        }
      });

      ApiService.instance.terminateAllSessions();

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _loadSessions();
            }
          });
        }
      });
    }
  }

  void _listenToApi() {
    _apiSubscription = ApiService.instance.messages.listen((message) {
      if (message['opcode'] == 96 && mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        });

        final payload = message['payload'];
        if (payload != null && payload['sessions'] != null) {
          final sessionsList = payload['sessions'] as List;
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _sessions = sessionsList
                    .map((session) => Session.fromJson(session))
                    .toList();
              });
            }
          });
        }
      }
    });
  }

  String _formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final difference = now.difference(date);

    String relativeTime;
    if (difference.inDays > 0) {
      relativeTime = '${difference.inDays} дн. назад';
    } else if (difference.inHours > 0) {
      relativeTime = '${difference.inHours} ч. назад';
    } else if (difference.inMinutes > 0) {
      relativeTime = '${difference.inMinutes} мин. назад';
    } else {
      relativeTime = 'Только что';
    }

    final exactTime =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return '$relativeTime ($exactTime)';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (_isInitialLoad && _sessions.isEmpty) {
      _isInitialLoad = false;
      _loadSessions();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Активные сессии"),
        actions: [
          IconButton(onPressed: _loadSessions, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.security,
                    size: 64,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Нет активных сессий",
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                if (_sessions.any((s) => !s.current))
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      onPressed: _terminateAllSessions,
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.error,
                        foregroundColor: colors.onError,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.logout, size: 24),
                      label: const Text(
                        "Завершить все сессии кроме текущей",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _sessions.length,
                    itemBuilder: (context, index) {
                      final session = _sessions[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: session.current
                                ? colors.primary
                                : colors.surfaceContainerHighest,
                            child: Icon(
                              session.current
                                  ? Icons.phone_android
                                  : Icons.computer,
                              color: session.current
                                  ? colors.onPrimary
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                          title: Text(
                            session.current ? "Текущая сессия" : session.client,
                            style: TextStyle(
                              fontWeight: session.current
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: session.current
                                  ? colors.primary
                                  : colors.onSurface,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                session.location,
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                session.info,
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatTime(session.time),
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          trailing: session.current
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.primary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    "Активна",
                                    style: TextStyle(
                                      color: colors.onPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              : Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    "Неактивна",
                                    style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _apiSubscription?.cancel();
    super.dispose();
  }
}

// Экран для тестирования библиотеки звонков nullcalls
class CallsTestScreen extends StatefulWidget {
  const CallsTestScreen({super.key});

  @override
  State<CallsTestScreen> createState() => _CallsTestScreenState();
}

class _CallsTestScreenState extends State<CallsTestScreen> {
  final Calls _calls = Calls(debug: true);
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();

  String _verificationToken = '';
  bool _isLoggedIn = false;
  String _status = 'Не авторизован';
  Connection? _activeConnection;
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _addLog('Инициализирован Calls клиент (debug mode)');

    _calls.onIncomingCall.listen((incomingCall) {
      _addLog('📞 Входящий звонок от: ${incomingCall.callerId}');
    });
  }

  void _addLog(String message) {
    setState(() {
      _logs.insert(
        0,
        '[${DateTime.now().toString().substring(11, 19)}] $message',
      );
      if (_logs.length > 50) _logs.removeLast();
    });
  }

  Future<void> _requestVerification() async {
    if (_phoneController.text.isEmpty) {
      _addLog('❌ Введите номер телефона');
      return;
    }

    try {
      _addLog('📱 Запрос кода для ${_phoneController.text}...');
      setState(() => _status = 'Запрос кода...');

      _verificationToken = await _calls.requestVerification(
        _phoneController.text,
      );

      _addLog(
        '✅ Код отправлен! Token: ${_verificationToken.substring(0, 20)}...',
      );
      setState(() => _status = 'Код отправлен');
    } catch (e) {
      _addLog('❌ Ошибка: $e');
      setState(() => _status = 'Ошибка');
    }
  }

  Future<void> _enterCode() async {
    if (_codeController.text.isEmpty) {
      _addLog('❌ Введите код');
      return;
    }

    try {
      _addLog('🔐 Ввод кода...');
      setState(() => _status = 'Авторизация...');

      await _calls.enterCode(_verificationToken, _codeController.text);

      _addLog('✅ Авторизация успешна!');
      _addLog('🆔 External User ID: ${_calls.externalUserId}');
      setState(() {
        _status = 'Авторизован';
        _isLoggedIn = true;
      });
    } catch (e) {
      _addLog('❌ Ошибка: $e');
      setState(() => _status = 'Ошибка авторизации');
    }
  }

  Future<void> _loginWithToken() async {
    if (_tokenController.text.isEmpty) {
      _addLog('❌ Введите токен');
      return;
    }

    try {
      _addLog('🔑 Вход с токеном...');
      setState(() => _status = 'Вход...');

      await _calls.loginWithToken(_tokenController.text);

      _addLog('✅ Вход успешен!');
      _addLog('🆔 External User ID: ${_calls.externalUserId}');
      setState(() {
        _status = 'Авторизован';
        _isLoggedIn = true;
      });
    } catch (e) {
      _addLog('❌ Ошибка: $e');
      setState(() => _status = 'Ошибка входа');
    }
  }

  Future<void> _makeCall() async {
    if (!_isLoggedIn) {
      _addLog('❌ Сначала авторизуйтесь');
      return;
    }

    if (_userIdController.text.isEmpty) {
      _addLog('❌ Введите User ID');
      return;
    }

    try {
      _addLog('📞 Звоним на ${_userIdController.text}...');
      setState(() => _status = 'Звоним...');

      _activeConnection = await _calls.call(_userIdController.text);

      _addLog('✅ Звонок установлен!');
      _addLog('🎙️ Local stream: ${_activeConnection?.localStream}');
      _addLog('🔊 Remote stream: ${_activeConnection?.remoteStream}');
      setState(() => _status = 'В звонке');
    } catch (e) {
      _addLog('❌ Ошибка звонка: $e');
      setState(() => _status = 'Ошибка звонка');
    }
  }

  Future<void> _waitForCall() async {
    if (!_isLoggedIn) {
      _addLog('❌ Сначала авторизуйтесь');
      return;
    }

    try {
      _addLog('⏳ Ожидание входящего звонка...');
      setState(() => _status = 'Ожидание звонка...');

      _activeConnection = await _calls.waitForCall();

      _addLog('✅ Входящий звонок принят!');
      _addLog('🎙️ Local stream: ${_activeConnection?.localStream}');
      _addLog('🔊 Remote stream: ${_activeConnection?.remoteStream}');
      setState(() => _status = 'В звонке');
    } catch (e) {
      _addLog('❌ Ошибка: $e');
      setState(() => _status = 'Ошибка');
    }
  }

  Future<void> _hangUp() async {
    if (_activeConnection == null) {
      _addLog('❌ Нет активного звонка');
      return;
    }

    try {
      _addLog('📴 Завершение звонка...');
      await _activeConnection?.close();
      _addLog('✅ Звонок завершен');
      setState(() {
        _status = 'Звонок завершен';
        _activeConnection = null;
      });
    } catch (e) {
      _addLog('❌ Ошибка: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Тест звонков (nullcalls)'),
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Статус
          Card(
            color: _isLoggedIn
                ? colors.primaryContainer
                : colors.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isLoggedIn ? Icons.check_circle : Icons.info_outline,
                        color: _isLoggedIn
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Статус: $_status',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _isLoggedIn
                              ? colors.onPrimaryContainer
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (_isLoggedIn && _calls.externalUserId != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'User ID: ${_calls.externalUserId}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Авторизация по номеру телефона
          _OutlinedSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Авторизация по номеру',
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Номер телефона',
                    hintText: '+79001234567',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _requestVerification,
                  icon: const Icon(Icons.sms),
                  label: const Text('Запросить код'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _codeController,
                  decoration: const InputDecoration(
                    labelText: 'Код из SMS',
                    hintText: '123456',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _enterCode,
                  icon: const Icon(Icons.login),
                  label: const Text('Войти'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Вход по токену
          _OutlinedSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Вход по токену',
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tokenController,
                  decoration: const InputDecoration(
                    labelText: 'Auth Token',
                    hintText: 'Сохраненный токен',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _loginWithToken,
                  icon: const Icon(Icons.vpn_key),
                  label: const Text('Войти с токеном'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Звонки
          _OutlinedSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Управление звонками',
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _userIdController,
                  decoration: const InputDecoration(
                    labelText: 'User ID для звонка',
                    hintText: 'external-user-id',
                    border: OutlineInputBorder(),
                  ),
                  enabled: _isLoggedIn,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _isLoggedIn ? _makeCall : null,
                      icon: const Icon(Icons.call),
                      label: const Text('Позвонить'),
                    ),
                    FilledButton.icon(
                      onPressed: _isLoggedIn ? _waitForCall : null,
                      icon: const Icon(Icons.call_received),
                      label: const Text('Ждать звонка'),
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.secondary,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _activeConnection != null ? _hangUp : null,
                      icon: const Icon(Icons.call_end),
                      label: const Text('Завершить'),
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.error,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Логи
          _OutlinedSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Логи',
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _logs.clear()),
                      icon: const Icon(Icons.clear_all, size: 16),
                      label: const Text('Очистить'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 300,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _logs.isEmpty
                      ? const Center(child: Text('Логи появятся здесь'))
                      : ListView.builder(
                          itemCount: _logs.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              child: Text(
                                _logs[index],
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _userIdController.dispose();
    _tokenController.dispose();
    _activeConnection?.close();
    _calls.close();
    super.dispose();
  }
}
