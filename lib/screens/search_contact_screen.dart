import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gwid/api/api_service.dart';
import 'package:gwid/models/contact.dart';
import 'package:gwid/screens/chat_screen.dart';

class SearchContactScreen extends StatefulWidget {
  const SearchContactScreen({super.key});

  @override
  State<SearchContactScreen> createState() => _SearchContactScreenState();
}

class _SearchContactScreenState extends State<SearchContactScreen> {
  final TextEditingController _phoneController = TextEditingController();
  StreamSubscription? _apiSubscription;
  bool _isLoading = false;
  Contact? _foundContact;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _listenToApiMessages();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _apiSubscription?.cancel();
    super.dispose();
  }

  void _listenToApiMessages() {
    _apiSubscription = ApiService.instance.messages.listen((message) {
      if (!mounted) return;

      if (message['type'] == 'contact_found') {
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });

        final payload = message['payload'];
        final contactData = payload['contact'];

        if (contactData != null) {
          _foundContact = Contact.fromJson(contactData);

          _openChatWithContact(_foundContact!);
        } else {}
      }

      if (message['type'] == 'contact_not_found') {
        setState(() {
          _isLoading = false;
          _foundContact = null;
        });

        final payload = message['payload'];
        String errorMessage = 'Контакт не найден';

        if (payload != null) {
          if (payload['localizedMessage'] != null) {
            errorMessage = payload['localizedMessage'];
          } else if (payload['message'] != null) {
            errorMessage = payload['message'];
          }
        }

        setState(() {
          _errorMessage = errorMessage;
        });
      }
    });
  }

  void _searchContact() async {
    final phone = _phoneController.text.trim();

    if (phone.isEmpty) {
      return;
    }

    if (!phone.startsWith('+') || phone.length < 10) {
      return;
    }

    setState(() {
      _isLoading = true;
      _foundContact = null;
      _errorMessage = null;
    });

    try {
      await ApiService.instance.searchContactByPhone(phone);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка поиска контакта: ${e.toString()}'),
          backgroundColor: Theme.of(context).colorScheme.error,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(10),
        ),
      );
    }
  }

  Future<void> _openChatWithContact(Contact contact) async {
    try {
      print(
        '🔍 Открываем чат с контактом: ${contact.name} (ID: ${contact.id})',
      );

      final chatId = await ApiService.instance.getChatIdByUserId(contact.id);

      if (chatId == null) {
        print('⚠️ Чат не найден для контакта ${contact.id}');
        return;
      }

      print('✅ Найден chatId: $chatId');

      await ApiService.instance.subscribeToChat(chatId, true);
      print('✅ Подписались на чат $chatId');

      final profileData = ApiService.instance.lastChatsPayload?['profile'];
      final contactProfile = profileData?['contact'] as Map<String, dynamic>?;
      final myId = contactProfile?['id'] as int? ?? 0;

      if (myId == 0) {
        print('⚠️ Не удалось получить myId, используем 0');
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              chatId: chatId,
              contact: contact,
              myId: myId,
              pinnedMessage: null,
              isGroupChat: false,
              isChannel: false,
              onChatUpdated: () {
                print('Chat updated');
              },
            ),
          ),
        );
      }
    } catch (e) {
      print('❌ Ошибка при открытии чата: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при открытии чата: ${e.toString()}'),
            backgroundColor: Colors.red,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(10),
          ),
        );
      }
    }
  }

  void _startChat() {
    if (_foundContact != null) {
      _openChatWithContact(_foundContact!);
    }
  }

  Future<void> _startChatAlternative() async {
    if (_foundContact == null) return;

    try {
      setState(() {
        _isLoading = true;
      });

      print('🔄 Альтернативный способ: добавляем контакт ${_foundContact!.id}');

      await ApiService.instance.addContact(_foundContact!.id);
      print('✅ Отправлен opcode=34 с action=ADD');

      await ApiService.instance.requestContactsByIds([_foundContact!.id]);
      print('✅ Отправлен opcode=35 с contactIds=[${_foundContact!.id}]');

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Перезайти в приложение'),
            content: const Text(
              'Для завершения добавления контакта необходимо перезайти в приложение.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Понятно'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print('❌ Ошибка при альтернативном способе: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: ${e.toString()}'),
            backgroundColor: Colors.red,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(10),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Найти контакт'),
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.person_search, color: colors.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Поиск контакта',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Введите номер телефона для поиска контакта. '
                        'Пользователь должен быть зарегистрирован в системе '
                        'и разрешить поиск по номеру телефона.',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  'Номер телефона',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Номер телефона',
                    hintText: '+7XXXXXXXXXX',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.phone),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: colors.outline.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Формат номера:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: colors.primary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '• Номер должен начинаться с "+"\n'
                        '• Пример: +79999999990\n'
                        '• Минимум 10 цифр после "+"',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _searchContact,
                    icon: _isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colors.onPrimary,
                              ),
                            ),
                          )
                        : const Icon(Icons.search),
                    label: Text(_isLoading ? 'Поиск...' : 'Найти контакт'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                if (_foundContact != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green),
                            SizedBox(width: 8),
                            Text(
                              'Контакт найден',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundImage:
                                  _foundContact!.photoBaseUrl != null
                                  ? NetworkImage(_foundContact!.photoBaseUrl!)
                                  : null,
                              child: _foundContact!.photoBaseUrl == null
                                  ? Text(
                                      _foundContact!.name.isNotEmpty
                                          ? _foundContact!.name[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: colors.onSurface,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _foundContact!.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  if (_foundContact!.description?.isNotEmpty ==
                                      true)
                                    Text(
                                      _foundContact!.description!,
                                      style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                        fontSize: 14,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_foundContact!.id >= 0) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _startChat,
                              icon: const Icon(Icons.chat),
                              label: const Text('Написать сообщение'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _startChatAlternative,
                              icon: const Icon(Icons.alternate_email),
                              label: const Text(
                                'Начать чат альтернативным способом',
                              ),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                if (_errorMessage != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
