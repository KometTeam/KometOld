import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import 'package:gwid/api/api_service.dart';
import 'package:gwid/screens/chat_screen.dart';
import 'package:gwid/screens/manage_account_screen.dart';
import 'package:gwid/screens/settings/settings_screen.dart';
import 'package:gwid/screens/phone_entry_screen.dart';
import 'package:gwid/models/chat.dart';
import 'package:gwid/models/contact.dart';
import 'package:gwid/models/message.dart';
import 'package:gwid/models/profile.dart';
import 'package:gwid/models/chat_folder.dart';
import 'package:gwid/utils/theme_provider.dart';
import 'package:gwid/theme/theme.dart'
    show
        DrawerBackgroundType,
        FolderTabsBackgroundType,
        AppBarBackgroundType,
        ChatPreviewMode;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gwid/screens/join_group_screen.dart';
import 'package:gwid/screens/search_contact_screen.dart';
import 'package:gwid/screens/downloads_screen.dart';
import 'package:gwid/utils/user_id_lookup_screen.dart';
import 'package:gwid/screens/music_library_screen.dart';
import 'package:gwid/widgets/message_preview_dialog.dart';
import 'package:gwid/services/chat_read_settings_service.dart';
import 'package:gwid/services/local_profile_manager.dart';
import 'package:gwid/widgets/contact_name_widget.dart';
import 'package:gwid/widgets/contact_avatar_widget.dart';
import 'package:gwid/services/account_manager.dart';
import 'package:gwid/services/chat_cache_service.dart';
import 'package:gwid/models/account.dart';
import 'package:gwid/services/message_queue_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:gwid/services/contact_local_names_service.dart';
import 'package:gwid/services/message_read_status_service.dart';

import 'package:gwid/screens/chat/models/search_result.dart';
import 'package:gwid/screens/chat/widgets/typing_dots.dart';
import 'package:gwid/screens/chat/widgets/presence_dot.dart';
import 'package:gwid/screens/chat/widgets/chats_screen_scaffold.dart';
import 'package:gwid/screens/chat/widgets/chats_list_page.dart';
import 'package:gwid/screens/chat/dialogs/add_chats_to_folder_dialog.dart';
import 'package:gwid/screens/chat/dialogs/read_settings_dialog.dart';
import 'package:gwid/screens/settings/chat_notification_settings_dialog.dart';
import 'package:gwid/screens/chat/screens/calls_screen.dart';
import 'package:gwid/screens/chat/screens/sferum_webview_panel.dart';
import 'package:gwid/screens/chat/handlers/message_handler.dart';
import 'package:gwid/widgets/optimized/optimized_widgets.dart';
import 'package:gwid/widgets/shatter_animation.dart';

class ChatsScreen extends StatefulWidget {
  final void Function(
    Chat chat,
    Contact contact,
    bool isGroup,
    bool isChannel,
    int? participantCount,
  )?
  onChatSelected;
  final bool hasScaffold;
  final bool isForwardMode;
  final void Function(Chat chat)? onForwardChatSelected;

  const ChatsScreen({
    super.key,
    this.onChatSelected,
    this.hasScaffold = true,
    this.isForwardMode = false,
    this.onForwardChatSelected,
  });

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen>
    with
        TickerProviderStateMixin,
        AutomaticKeepAliveClientMixin,
        OptimizedStateMixin<ChatsScreen> {
  late Future<Map<String, dynamic>> _chatsFuture;
  StreamSubscription? _apiSubscription;
  List<Chat> _allChats = [];
  bool _chatsLoaded = false;
  bool _chatOrderLoaded =
      false; // Флаг для предотвращения повторной загрузки порядка
  MessageHandler? _messageHandler;
  List<Chat> _filteredChats = [];
  Map<int, Contact> _contacts = {};
  bool _isSearchExpanded = false;
  String _searchQuery = '';
  // Используем Debouncer из OptimizedStateMixin вместо Timer
  List<SearchResult> _searchResults = [];
  String _searchFilter = 'all';

  Timer? _globalSearchDebounce;
  int _globalSearchToken = 0;
  bool _isGlobalSearchLoading = false;
  String? _globalSearchError;
  List<Map<String, dynamic>> _globalSearchResults = [];
  String? _globalSearchMarker;
  bool _globalSearchHasMore = false;
  bool _hasRequestedBlockedContacts = false;
  final Set<int> _loadingContactIds = {};
  bool _isSwitchingAccounts = false;

  List<ChatFolder> _folders = [];
  String? _selectedFolderId;
  late TabController _folderTabController;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late AnimationController _searchAnimationController;
  Profile? _myProfile;
  bool _isProfileLoading = true;
  String _connectionStatus = 'connecting';
  StreamSubscription<void>? _connectionStatusSubscription;
  StreamSubscription<String>? _connectionStateSubscription;
  StreamSubscription<int>? _contactNamesSubscription;
  StreamSubscription<MessageReadUpdate>? _readStatusSubscription;
  bool _isAccountsExpanded = false;
  bool _isReconnecting = false;

  SharedPreferences? _prefs;
  Set<int> _GETOUT = {};
  int _getoutPressCount = 0;
  final Set<int> _dismissingChats = {};
  bool _prefsLoaded = false;
  Map<int, Map<String, dynamic>> _chatDrafts = {};

  Set<int> _archivedChats = {};
  bool _isInArchive = false;

  int get _myId =>
      _myProfile?.id ?? int.tryParse(ApiService.instance.userId ?? '0') ?? 0;

  final Map<int, Chat> _dismissingChatObjects = {};

  List<Chat> get _visibleChats {
    if (!_prefsLoaded) return _allChats;
    final visible = _allChats.where((chat) {
      if (_GETOUT.contains(chat.id)) return false;
      // В архивном режиме — только архивные, иначе — только не архивные
      if (_isInArchive) return _archivedChats.contains(chat.id);
      return !_archivedChats.contains(chat.id);
    }).toList();
    for (final chat in _dismissingChatObjects.values) {
      if (!visible.any((c) => c.id == chat.id)) {
        visible.add(chat);
      }
    }
    return visible;
  }

  List<Chat> get _archivedChatsList =>
      _allChats.where((c) => _archivedChats.contains(c.id) && !_GETOUT.contains(c.id)).toList();

  String _getoutKey() {
    final uid = _myId != 0 ? _myId : int.tryParse(ApiService.instance.userId ?? '0') ?? 0;
    return 'gotupandcameoutofhere_$uid';
  }

  Set<int> _loadGetoutFromPrefs(SharedPreferences p) {
    final key = _getoutKey();
    final hiddenIds = p.getStringList(key) ?? [];
    return hiddenIds.map((e) => int.tryParse(e) ?? -1).where((id) => id != -1).toSet();
  }

  Future<void> _saveGetoutToPrefs() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setStringList(
      _getoutKey(),
      _GETOUT.map((id) => id.toString()).toList(),
    );
  }

  String _archiveKey() {
    final uid = _myId != 0 ? _myId : int.tryParse(ApiService.instance.userId ?? '0') ?? 0;
    return 'archived_chats_$uid';
  }

  Set<int> _loadArchiveFromPrefs(SharedPreferences p) {
    final ids = p.getStringList(_archiveKey()) ?? [];
    return ids.map((e) => int.tryParse(e) ?? -1).where((id) => id != -1).toSet();
  }

  Future<void> _saveArchiveToPrefs() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setStringList(
      _archiveKey(),
      _archivedChats.map((id) => id.toString()).toList(),
    );
  }

  Future<void> _toggleArchive(Chat chat) async {
    setState(() {
      if (_archivedChats.contains(chat.id)) {
        _archivedChats.remove(chat.id);
      } else {
        _archivedChats.add(chat.id);
      }
    });
    await _saveArchiveToPrefs();
    _filterChats();
    setState(() {});
  }

  // Вызывается когда профиль наконец загружен — перечитываем GETOUT с правильным ключом
  void _reloadGetoutIfNeeded() {
    if (_prefs == null || !_prefsLoaded) return;
    final newGetout = _loadGetoutFromPrefs(_prefs!);
    final newArchive = _loadArchiveFromPrefs(_prefs!);
    setState(() {
      _GETOUT = newGetout;
      _archivedChats = newArchive;
    });
    _filterChats();
  }

  Future<void> _initializePrefs() async {
    final p = await SharedPreferences.getInstance();
    _prefs = p;
    final uid = _myId != 0
        ? _myId
        : int.tryParse(ApiService.instance.userId ?? '0') ?? 0;
    if (uid != 0) {
      _GETOUT = _loadGetoutFromPrefs(p);
      _archivedChats = _loadArchiveFromPrefs(p);
    } else {
      _GETOUT = {};
      _archivedChats = {};
    }
    _prefsLoaded = true;
    print('✅ [GETOUT] Загружено из prefs: $_GETOUT');
    if (mounted) {
      setState(() {});
      _filterChats();
    }
  }

  @override
  void initState() {
    super.initState();
    _initializePrefs();
    _loadMyProfile();

    // Проверяем, есть ли уже данные в кэше (например, после авторизации)
    // Если данные есть и сессия готова, используем их сразу без повторной загрузки
    final cachedData = ApiService.instance.lastChatsPayload;
    if (cachedData != null &&
        cachedData['chats'] != null &&
        ApiService.instance.isOnline &&
        ApiService.instance.isSessionReady) {
      print('ChatsScreen: используем кэшированные данные из lastChatsPayload');
      _chatsFuture = Future.value(cachedData);
      _chatsLoaded =
          false; // Сбрасываем флаг, чтобы данные обработались в build
    } else {
      // Данных нет или сессия не готова - загружаем с таймаутом
      _chatsFuture = _loadChatsWithTimeout();
    }

    _searchAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _folderTabController = TabController(length: 1, vsync: this);
    _folderTabController.addListener(_onFolderTabChanged);

    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onSearchFocusChanged);

    unawaited(_listenForUpdates());

    _connectionStateSubscription = ApiService.instance.connectionStatus.listen((
      status,
    ) {
      if (mounted) {
        setState(() {
          _connectionStatus = status;
        });
      }
    });

    _connectionStatusSubscription = ApiService.instance.reconnectionComplete
        .listen((_) {
          if (mounted) {
            print("🔄 ChatsScreen: Получено уведомление о переподключении");
            _loadChatsAndContacts();
            print("🔄 ChatsScreen: Обновление чатов запущено");
          }
        });

    _contactNamesSubscription = ContactLocalNamesService().changes.listen((_) {
      if (mounted) setState(() {});
    });

    // Подписываемся на обновления статусов прочитанности
    _readStatusSubscription = MessageReadStatusService().statusUpdates.listen((
      update,
    ) {
      print(
        '🔔 [ChatsScreen] Получено обновление статуса прочитанности для чата ${update.chatId}',
      );
      if (mounted) {
        setState(() {
          // setState триггерит перерисовку списка чатов
        });
      }
    });
  }

  /// Загружает чаты с таймаутом и обработкой ошибок
  Future<Map<String, dynamic>> _loadChatsWithTimeout() async {
    try {
      // Ждем подключения с таймаутом 15 секунд
      await ApiService.instance.waitUntilOnline().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          print('ChatsScreen: таймаут ожидания подключения');
          throw TimeoutException('Таймаут подключения к серверу');
        },
      );

      // Загружаем чаты с таймаутом 20 секунд
      final result = await ApiService.instance.getChatsAndContacts().timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          print('ChatsScreen: таймаут загрузки чатов');
          throw TimeoutException('Таймаут загрузки чатов');
        },
      );

      // Предзагружаем сообщения из топ-чатов для быстрого открытия
      final chats = result['chats'] as List<dynamic>? ?? [];
      if (chats.isNotEmpty) {
        final topChatIds = chats
            .take(5) // Первые 5 чатов
            .where((c) => c is Map<String, dynamic>)
            .map((c) => c['id'] as int?)
            .where((id) => id != null)
            .cast<int>()
            .toList();

        if (topChatIds.isNotEmpty) {
          // Запускаем предзагрузку в фоне без ожидания
          unawaited(
            ApiService.instance.preloadChatMessages(
              topChatIds,
              messageCount: 7,
            ),
          );
        }
      }

      return result;
    } catch (e) {
      print('ChatsScreen: Ошибка загрузки чатов: $e');
      if (e.toString().contains('Auth token not found') ||
          e.toString().contains('FAIL_WRONG_PASSWORD')) {
        _showTokenExpiredDialog(
          'Токен авторизации недействителен. Требуется повторная авторизация.',
        );
      }
      rethrow;
    }
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _loadMyProfile() async {
    if (!mounted) return;
    setState(() {
      _isProfileLoading = true;
    });

    Profile? serverProfile;

    try {
      final accountManager = AccountManager();
      await accountManager.initialize();
      final currentAccount = accountManager.currentAccount;
      if (currentAccount?.profile != null) {
        serverProfile = currentAccount!.profile;
      }
    } catch (e) {
      print('Ошибка загрузки профиля из AccountManager: $e');
    }

    if (serverProfile == null) {
      final cachedProfileData =
          ApiService.instance.lastChatsPayload?['profile'];
      if (cachedProfileData != null) {
        serverProfile = Profile.fromJson(cachedProfileData);
      }
    }

    try {
      final profileManager = LocalProfileManager();
      await profileManager.initialize();
      final actualProfile = await profileManager.getActualProfile(
        serverProfile,
      );

      if (mounted && actualProfile != null) {
        setState(() {
          _myProfile = actualProfile;
          _isProfileLoading = false;
        });
        _reloadGetoutIfNeeded();
        return;
      }
    } catch (e) {
      print('Ошибка загрузки локального профиля: $e');
    }

    if (mounted && serverProfile != null) {
      setState(() {
        _myProfile = serverProfile;
        _isProfileLoading = false;
      });
      _reloadGetoutIfNeeded();
      return;
    }

    try {
      if (!ApiService.instance.isOnline) {
        await ApiService.instance.waitUntilOnline().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            print("Таймаут ожидания подключения для загрузки профиля");
            throw TimeoutException("Таймаут подключения");
          },
        );
      }

      final result = await ApiService.instance
          .getChatsAndContacts(force: true)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              print("Таймаут загрузки чатов и профиля");
              throw TimeoutException("Таймаут загрузки");
            },
          );

      if (mounted) {
        final profileJson = result['profile'];
        if (profileJson != null) {
          setState(() {
            _myProfile = Profile.fromJson(profileJson);
            _isProfileLoading = false;
          });
        } else {
          setState(() {
            _isProfileLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProfileLoading = false;
        });
        print("Ошибка загрузки профиля в ChatsScreen: $e");
      }
    }
  }

  void _updateChatLastMessage(int chatId, Message? newLastMessage) {
    final chatIndex = _allChats.indexWhere((chat) => chat.id == chatId);
    if (chatIndex != -1) {
      final updatedChat = _allChats[chatIndex].copyWith(
        lastMessage: newLastMessage,
      );
      _allChats[chatIndex] = updatedChat;
      _filterChats();
      setState(() {});
    }
  }

  void _updateChatDraft(int chatId, Map<String, dynamic>? draft) {
    setState(() {
      if (draft != null) {
        _chatDrafts[chatId] = draft;
      } else {
        _chatDrafts.remove(chatId);
      }
    });
  }

  Future<void> _loadChatDrafts() async {
    try {
      final chatCacheService = ChatCacheService();
      await chatCacheService.initialize();

      final drafts = <int, Map<String, dynamic>>{};
      for (final chat in _allChats) {
        final draft = await chatCacheService.getChatInputState(chat.id);
        if (draft != null &&
            draft['text']?.toString().trim().isNotEmpty == true) {
          drafts[chat.id] = draft;
        }
      }

      if (mounted) {
        setState(() {
          _chatDrafts = drafts;
        });
      }
    } catch (e) {
      print('Ошибка загрузки черновиков: $e');
    }
  }

  void _navigateToLogin() {
    print('Перенаправляем на экран входа из-за недействительного токена');
  }

  void _showTokenExpiredDialog(String message) {
    if (_isSwitchingAccounts) {
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Ошибка авторизации'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _navigateToLogin();
              },
              child: const Text('Войти заново'),
            ),
          ],
        );
      },
    );
  }

  void _showCreateChannelDialog() {
    final TextEditingController titleController = TextEditingController();
    final List<int> selectedContacts = [];

    final int? myId = _myProfile?.id;

    final List<Contact> availableContacts = _contacts.values.where((contact) {
      final contactNameLower = contact.name.toLowerCase();
      return contactNameLower != 'max' &&
          contactNameLower != 'gigachat' &&
          (myId == null || contact.id != myId);
    }).toList();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Создать канал'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Название канала',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Выберите первых подписчиков:'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  width: 300,
                  child: ListView.builder(
                    itemCount: availableContacts.length,
                    itemBuilder: (context, index) {
                      final contact = availableContacts[index];
                      final isSelected = selectedContacts.contains(contact.id);

                      return CheckboxListTile(
                        title: Text(
                          getContactDisplayName(
                            contactId: contact.id,
                            originalName: contact.name,
                            originalFirstName: contact.firstName,
                            originalLastName: contact.lastName,
                          ),
                        ),
                        subtitle: Text(
                          contact.firstName.isNotEmpty &&
                                  contact.lastName.isNotEmpty
                              ? '${contact.firstName} ${contact.lastName}'
                              : '',
                        ),
                        value: isSelected,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              selectedContacts.add(contact.id);
                            } else {
                              selectedContacts.remove(contact.id);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                if (titleController.text.trim().isNotEmpty) {
                  ApiService.instance.createChannelWithMessage(
                    titleController.text.trim(),
                    selectedContacts,
                  );
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _listenForUpdates() async {
    // КРИТИЧНО: отменяем старую подписку перед созданием новой
    await _apiSubscription?.cancel();
    _apiSubscription = null;

    final handler = MessageHandler(
      setState: setState,
      getContext: () => context,
      getMounted: () => mounted,
      allChats: _allChats,
      contacts: _contacts,
      folders: _folders,
      onlineChats: _onlineChats,
      typingChats: _typingChats,
      typingDecayTimers: _typingDecayTimers,
      setTypingForChat: _setTypingForChat,
      filterChats: _filterChats,
      refreshChats: _refreshChats,
      sortFoldersByOrder: _sortFoldersByOrder,
      updateFolderTabController: _updateFolderTabController,
      folderTabController: _folderTabController,
      setMyProfile: (profile) {
        setState(() {
          _myProfile = profile;
          _isProfileLoading = false;
        });
        _reloadGetoutIfNeeded();
      },
      showTokenExpiredDialog: _showTokenExpiredDialog,
      isSavedMessages: _isSavedMessages,
    );

    _messageHandler = handler;
    _apiSubscription = handler.listen();
  }

  void _removeChatLocally(int chatId) {
    if (!mounted) return;
    _typingDecayTimers[chatId]?.cancel();
    _typingDecayTimers.remove(chatId);
    _typingChats.remove(chatId);
    _onlineChats.remove(chatId);
    setState(() {
      _allChats.removeWhere((c) => c.id == chatId);
      _filteredChats.removeWhere((c) => c.id == chatId);
    });
    // Чистим disk cache чтобы чат не воскрес после перезапуска
    ChatCacheService().removeChatFromCachedList(chatId);
    ChatCacheService().clearChatCache(chatId);
    // Убираем чат из кэшированного payload API
    ApiService.instance.removeChatFromLastPayload(chatId);
  }

  final Map<int, Timer> _typingDecayTimers = {};
  final Set<int> _typingChats = {};
  final Set<int> _onlineChats = {};

  bool _isFilteringInProgress = false;
  void _setTypingForChat(int chatId) {
    _typingChats.add(chatId);
    _typingDecayTimers[chatId]?.cancel();
    _typingDecayTimers[chatId] = Timer(const Duration(seconds: 11), () {
      _typingChats.remove(chatId);
      if (mounted) setState(() {});
    });
    if (mounted) setState(() {});
  }

  void _refreshChats() {
    _chatsFuture = (() async {
      final result = await ApiService.instance.getChatsAndContacts(force: true);

      // Предзагружаем сообщения из топ-чатов для быстрого открытия
      final chats = result['chats'] as List<dynamic>? ?? [];
      if (chats.isNotEmpty) {
        final topChatIds = chats
            .take(5) // Первые 5 чатов
            .where((c) => c is Map<String, dynamic>)
            .map((c) => c['id'] as int?)
            .where((id) => id != null)
            .cast<int>()
            .toList();

        if (topChatIds.isNotEmpty) {
          // Запускаем предзагрузку в фоне без ожидания
          unawaited(
            ApiService.instance.preloadChatMessages(
              topChatIds,
              messageCount: 7,
            ),
          );
        }
      }

      return result;
    })();

    _chatsFuture
        .then((data) {
          if (mounted) {
            final chats = data['chats'] as List<dynamic>;
            final contacts = data['contacts'] as List<dynamic>;
            final profileData = data['profile'];

            _allChats = chats
                .where((json) => json != null)
                .map(
                  (json) =>
                      Chat.tryFromJson((json as Map).cast<String, dynamic>()),
                )
                .whereType<Chat>()
                .toList();
            _contacts.clear();
            for (final contactJson in contacts) {
              _loadChatDrafts();
              final contact = Contact.fromJson(
                (contactJson as Map).cast<String, dynamic>(),
              );
              _contacts[contact.id] = contact;
            }

            if (profileData != null) {
              _myProfile = Profile.fromJson(profileData);
              _isProfileLoading = false;
            }
            _filterChats();
            setState(() {});
          }
        })
        .catchError((error) {
          print('Ошибка в _refreshChats: $error');
          // При ошибке ничего не делаем, просто логируем
        });
  }

  void _showAddMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Создать',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),

                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    child: Icon(
                      Icons.group_add,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  title: const Text('Создать группу'),
                  subtitle: const Text('Создать чат с несколькими участниками'),
                  onTap: () {
                    Navigator.pop(context);
                    _showCreateGroupDialog();
                  },
                ),

                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    child: Icon(
                      Icons.campaign,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  title: const Text('Создать канал'),
                  subtitle: const Text('Публичные посты для подписчиков'),
                  onTap: () {
                    Navigator.pop(context);
                    _showCreateChannelDialog();
                  },
                ),

                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    child: Icon(
                      Icons.person_search,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  title: const Text('Найти контакт'),
                  subtitle: const Text('Поиск по номеру телефона'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const SearchContactScreen(),
                      ),
                    );
                  },
                ),

                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer,
                    child: Icon(
                      Icons.link,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                  title: const Text('Присоединиться по ссылке'),
                  subtitle: const Text('По ссылке-приглашению'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const JoinGroupScreen(),
                      ),
                    );
                  },
                ),

                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    child: const Icon(Icons.download, color: Colors.white),
                  ),
                  title: const Text('Загрузки'),
                  subtitle: const Text('Скачанные файлы'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const DownloadsScreen(),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCreateGroupDialog() {
    final TextEditingController nameController = TextEditingController();
    final List<int> selectedContacts = [];

    final int? myId = _myProfile?.id;

    final List<Contact> availableContacts = _contacts.values.where((contact) {
      final contactNameLower = contact.name.toLowerCase();
      return contactNameLower != 'max' &&
          contactNameLower != 'gigachat' &&
          (myId == null || contact.id != myId);
    }).toList();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Создать группу'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Название группы',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Выберите участников:'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  width: 300,

                  child: ListView.builder(
                    itemCount: availableContacts.length,
                    itemBuilder: (context, index) {
                      final contact = availableContacts[index];
                      final isSelected = selectedContacts.contains(contact.id);

                      return CheckboxListTile(
                        title: Text(
                          getContactDisplayName(
                            contactId: contact.id,
                            originalName: contact.name,
                            originalFirstName: contact.firstName,
                            originalLastName: contact.lastName,
                          ),
                        ),
                        subtitle: Text(
                          contact.firstName.isNotEmpty &&
                                  contact.lastName.isNotEmpty
                              ? '${contact.firstName} ${contact.lastName}'
                              : '',
                        ),
                        value: isSelected,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              selectedContacts.add(contact.id);
                            } else {
                              selectedContacts.remove(contact.id);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  ApiService.instance.createGroupWithMessage(
                    nameController.text.trim(),
                    selectedContacts,
                  );
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSavedMessages(Chat chat) {
    return chat.id == 0;
  }

  bool _isGroupChat(Chat chat) {
    return chat.type == 'CHAT' || chat.participantIds.length > 2;
  }

  void _updateFolderTabController() {
    final oldIndex = _folderTabController.index;
    final newLength = 1 + _folders.length;
    if (_folderTabController.length != newLength) {
      _folderTabController.removeListener(_onFolderTabChanged);
      _folderTabController.dispose();
      _folderTabController = TabController(
        length: newLength,
        vsync: this,
        initialIndex: oldIndex < newLength ? oldIndex : 0,
      );
      _folderTabController.addListener(_onFolderTabChanged);
    }
  }

  void _sortFoldersByOrder(List<dynamic>? foldersOrder) {
    if (foldersOrder == null || foldersOrder.isEmpty) return;

    final orderedIds = foldersOrder.map((id) => id.toString()).toList();
    _folders.sort((a, b) {
      final aIndex = orderedIds.indexOf(a.id);
      final bIndex = orderedIds.indexOf(b.id);
      if (aIndex == -1 && bIndex == -1) return 0;
      if (aIndex == -1) return 1;
      if (bIndex == -1) return -1;
      return aIndex.compareTo(bIndex);
    });
  }

  void _loadFolders(Map<String, dynamic> data) {
    try {
      final config = data['config'] as Map<String, dynamic>?;
      if (config == null) return;

      final chatFolders = config['chatFolders'] as Map<String, dynamic>?;
      if (chatFolders == null) return;

      final foldersJson = chatFolders['FOLDERS'] as List<dynamic>?;
      if (foldersJson == null) return;

      final folders = foldersJson
          .map((json) => ChatFolder.fromJson(json as Map<String, dynamic>))
          .toList();

      setState(() {
        _folders = folders;

        final foldersOrder = chatFolders['foldersOrder'] as List<dynamic>?;
        _sortFoldersByOrder(foldersOrder);

        _updateFolderTabController();

        if (_selectedFolderId == null) {
          if (_folderTabController.index != 0) {
            _folderTabController.animateTo(0);
          }
        } else {
          final folderIndex = _folders.indexWhere(
            (f) => f.id == _selectedFolderId,
          );
          if (folderIndex != -1) {
            final targetIndex = folderIndex + 1;
            if (_folderTabController.index != targetIndex) {
              _folderTabController.animateTo(targetIndex);
            }
          }
        }
      });
    } catch (e) {
      print('Ошибка загрузки папок: $e');
    }
  }

  bool _chatBelongsToFolder(Chat chat, ChatFolder? folder) {
    if (folder == null) return true;

    if (folder.include != null && folder.include!.isNotEmpty) {
      return folder.include!.contains(chat.id);
    }

    if (folder.filters.isNotEmpty) {
      final hasContact = folder.filters.any(
        (f) => f == 9 || f == '9' || f == 'CONTACT',
      );
      final hasNotContact = folder.filters.any(
        (f) => f == 8 || f == '8' || f == 'NOT_CONTACT',
      );

      if (hasContact && hasNotContact) {
        if (chat.type != 'DIALOG' ||
            chat.participantIds.length > 2 ||
            _isGroupChat(chat)) {
          return false;
        }

        final otherParticipantId = chat.participantIds.firstWhere(
          (id) => id != _myId,
          orElse: () => 0,
        );
        if (otherParticipantId != 0) {
          final contact = _contacts[otherParticipantId];
          if (contact != null && contact.isBot) {
            return false;
          }
        }

        return true;
      }

      for (final filter in folder.filters) {
        bool matchesThisFilter = false;
        if (filter == 0 || filter == '0' || filter == 'UNREAD') {
          matchesThisFilter = chat.newMessages > 0;
        } else if (filter == 9 || filter == '9' || filter == 'CONTACT') {
          if (chat.type != 'DIALOG' ||
              chat.participantIds.length > 2 ||
              _isGroupChat(chat)) {
            matchesThisFilter = false;
          } else {
            final otherParticipantId = chat.participantIds.firstWhere(
              (id) => id != _myId,
              orElse: () => 0,
            );
            if (otherParticipantId != 0) {
              final contact = _contacts[otherParticipantId];
              matchesThisFilter = contact == null || !contact.isBot;
            } else {
              matchesThisFilter = true;
            }
          }
        } else if (filter == 8 || filter == '8' || filter == 'NOT_CONTACT') {
          matchesThisFilter =
              chat.type == 'CHAT' ||
              chat.type == 'CHANNEL' ||
              _isGroupChat(chat);
        } else {
          matchesThisFilter = false;
        }

        if (matchesThisFilter) {
          return true;
        }
      }
      return false;
    }

    return false;
  }

  void _filterChats() {
    // КРИТИЧНО: Блокируем реентрантные вызовы
    if (_isFilteringInProgress) {
      print('⚠️ [filterChats] УЖЕ ВЫПОЛНЯЕТСЯ, пропускаем');
      return;
    }

    _isFilteringInProgress = true;

    try {
      // DEBUG: Выводим откуда вызван
      print(
        '🔍 [filterChats] Начало фильтрации, _allChats.length=${_allChats.length}',
      );
      print('📍 [filterChats] Вызван из:\n${StackTrace.current}');
      final query = _searchController.text.toLowerCase();
      print('🚫 [GETOUT] _GETOUT=$_GETOUT, _prefsLoaded=$_prefsLoaded');
      if (!_prefsLoaded) {
        // Prefs ещё не загружены — подождём, _initializePrefs сам вызовет _filterChats
        print('⏳ [GETOUT] Prefs ещё не загружены, пропускаем фильтрацию');
        return;
      }
      List<Chat> chatsToFilter = _allChats.where((chat) {
        if (_GETOUT.contains(chat.id)) {
          print('🚫 [GETOUT] Фильтруем чат ${chat.id} (${chat.title})');
          return false;
        }
        final msg = chat.lastMessage;
        if (msg.text.isNotEmpty) return true;
        return msg.attaches.any((a) {
          final type = (a['_type'] ?? a['type'])?.toString() ?? '';
          return type.isNotEmpty;
        });
      }).toList();

      if (_selectedFolderId != null) {
        print('🔍 [filterChats] Фильтруем по папке $_selectedFolderId');
        final selectedFolder = _folders.firstWhere(
          (f) => f.id == _selectedFolderId,
          orElse: () => _folders.first,
        );
        chatsToFilter = chatsToFilter
            .where((chat) => _chatBelongsToFolder(chat, selectedFolder))
            .toList();
        print(
          '🔍 [filterChats] После фильтрации по папке: ${chatsToFilter.length}',
        );
      }

      if (query.isEmpty && !_searchFocusNode.hasFocus) {
        print('🔍 [filterChats] Копируем все чаты');
        _filteredChats = List.from(chatsToFilter);

        print('🔍 [filterChats] Сортируем ${_filteredChats.length} чатов...');
        _filteredChats.sort((a, b) {
          final aPinned = a.favIndex > 0;
          final bPinned = b.favIndex > 0;
          if (aPinned && bPinned) return a.favIndex.compareTo(b.favIndex);
          if (aPinned) return -1;
          if (bPinned) return 1;
          return b.lastMessage.time.compareTo(a.lastMessage.time);
        });
        print('🔍 [filterChats] Сортировка завершена');
      } else if (_searchFocusNode.hasFocus && query.isEmpty) {
        _filteredChats = [];
      } else if (query.isNotEmpty) {
        _filteredChats = chatsToFilter.where((chat) {
          final isSavedMessages = _isSavedMessages(chat);
          if (isSavedMessages) {
            return "избранное".contains(query);
          }
          final otherParticipantId = chat.participantIds.firstWhere(
            (id) => id != _myId,
            orElse: () => 0,
          );
          final contactName =
              _contacts[otherParticipantId]?.name.toLowerCase() ?? '';
          return contactName.contains(query);
        }).toList();

        _filteredChats.sort((a, b) {
          final aPinned = a.favIndex > 0;
          final bPinned = b.favIndex > 0;
          if (aPinned && bPinned) return a.favIndex.compareTo(b.favIndex);
          if (aPinned) return -1;
          if (bPinned) return 1;
          return b.lastMessage.time.compareTo(a.lastMessage.time);
        });
      } else {
        _filteredChats = [];
      }
      print(
        '✅ [filterChats] Завершено, _filteredChats.length=${_filteredChats.length}',
      );
    } finally {
      _isFilteringInProgress = false;
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    _searchQuery = query;

    // Используем debouncedSetState для оптимизации
    debouncedSetState('search', delay: const Duration(milliseconds: 300));
    _performSearch();
    _scheduleGlobalSearch();
  }

  void _scheduleGlobalSearch() {
    _globalSearchDebounce?.cancel();

    final q = _searchQuery.trim();
    if (q.isEmpty) {
      setState(() {
        _isGlobalSearchLoading = false;
        _globalSearchError = null;
        _globalSearchResults = [];
        _globalSearchMarker = null;
        _globalSearchHasMore = false;
      });
      return;
    }

    _globalSearchDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_performGlobalSearch(reset: true));
    });
  }

  Future<void> _performGlobalSearch({required bool reset}) async {
    final q = _searchQuery.trim();
    if (q.isEmpty) return;

    final int token = ++_globalSearchToken;

    if (reset) {
      setState(() {
        _isGlobalSearchLoading = true;
        _globalSearchError = null;
        _globalSearchResults = [];
        _globalSearchMarker = null;
        _globalSearchHasMore = false;
      });
    } else {
      setState(() {
        _isGlobalSearchLoading = true;
        _globalSearchError = null;
      });
    }

    try {
      final payload = await ApiService.instance.globalSearch(
        q,
        count: 30,
        marker: reset ? null : _globalSearchMarker,
        useTypeAll: false,
      );

      if (!mounted || token != _globalSearchToken) return;

      final result = payload['result'];
      final List<Map<String, dynamic>> items = [];
      if (result is List) {
        for (final item in result) {
          if (item is! Map) continue;
          final map = item.cast<String, dynamic>();
          final section = map['section']?.toString();
          if (section == 'MESSAGES') continue;
          items.add(map);
        }
      }

      final marker = payload['marker']?.toString();
      final hasMore = marker != null && marker.isNotEmpty;

      setState(() {
        _globalSearchMarker = marker;
        _globalSearchHasMore = hasMore;
        if (reset) {
          _globalSearchResults = items;
        } else {
          _globalSearchResults = [..._globalSearchResults, ...items];
        }
      });
    } catch (e) {
      if (!mounted || token != _globalSearchToken) return;
      setState(() {
        _globalSearchError = e.toString();
      });
    } finally {
      if (!mounted || token != _globalSearchToken) return;
      setState(() {
        _isGlobalSearchLoading = false;
      });
    }
  }

  void _onSearchFocusChanged() {
    if (_searchFocusNode.hasFocus) {
      _isSearchExpanded = true;
      _searchAnimationController.forward();
    } else if (_searchController.text.isEmpty) {
      _isSearchExpanded = false;
      _searchAnimationController.reverse();
    }
  }

  void _performSearch() async {
    if (_searchQuery.isEmpty) {
      setState(() {
        _searchResults.clear();
      });
      return;
    }

    setState(() {});

    final results = <SearchResult>[];
    final query = _searchQuery.toLowerCase();

    for (final chat in _allChats) {
      final isSavedMessages = _isSavedMessages(chat);

      if (isSavedMessages) {
        if ("избранное".contains(query)) {
          results.add(
            SearchResult(
              chat: chat,
              contact: _contacts[chat.ownerId],
              matchedText: "Избранное",
              matchType: 'name',
            ),
          );
        }
        continue;
      }

      if (chat.type == 'CHANNEL') {
        final channelTitle = chat.title ?? '';
        final channelDescription = chat.description ?? '';

        if (channelTitle.toLowerCase().contains(query) ||
            channelDescription.toLowerCase().contains(query) ||
            'канал'.contains(query)) {
          results.add(
            SearchResult(
              chat: chat,
              contact: null,
              matchedText: channelTitle.isNotEmpty ? channelTitle : 'Канал',
              matchType: channelTitle.toLowerCase().contains(query)
                  ? 'name'
                  : 'description',
            ),
          );
        }
        continue;
      }

      if (_isGroupChat(chat)) {
        final groupTitle = chat.title ?? '';
        final groupDescription = chat.description ?? '';

        if (groupTitle.toLowerCase().contains(query) ||
            groupDescription.toLowerCase().contains(query) ||
            'группа'.contains(query)) {
          results.add(
            SearchResult(
              chat: chat,
              contact: null,
              matchedText: groupTitle.isNotEmpty ? groupTitle : 'Группа',
              matchType: groupTitle.toLowerCase().contains(query)
                  ? 'name'
                  : 'description',
            ),
          );
        }
        continue;
      }

      final otherParticipantId = chat.participantIds.firstWhere(
        (id) => id != _myId,
        orElse: () => 0,
      );
      final contact = _contacts[otherParticipantId];

      if (contact == null) continue;

      final displayName = getContactDisplayName(
        contactId: contact.id,
        originalName: contact.name,
        originalFirstName: contact.firstName,
        originalLastName: contact.lastName,
      );

      if (displayName.toLowerCase().contains(query) ||
          contact.name.toLowerCase().contains(query)) {
        results.add(
          SearchResult(
            chat: chat,
            contact: contact,
            matchedText: displayName,
            matchType: 'name',
          ),
        );
        continue;
      }

      if (contact.description != null &&
          contact.description?.toLowerCase().contains(query) == true) {
        results.add(
          SearchResult(
            chat: chat,
            contact: contact,
            matchedText: contact.description ?? '',
            matchType: 'description',
          ),
        );
        continue;
      }

      if (chat.lastMessage.text.toLowerCase().contains(query) ||
          (chat.lastMessage.text.contains("welcome.saved.dialog.message") &&
              'привет избранные майор'.contains(query.toLowerCase()))) {
        results.add(
          SearchResult(
            chat: chat,
            contact: contact,
            matchedText:
                chat.lastMessage.text.contains("welcome.saved.dialog.message")
                ? 'Привет! Это твои избранные...'
                : chat.lastMessage.text,
            matchType: 'message',
          ),
        );
      }
    }

    List<SearchResult> filteredResults = results;
    if (_searchFilter == 'recent') {
      final weekAgo = DateTime.now().subtract(const Duration(days: 7));
      filteredResults = results.where((result) {
        final lastMessageTime = DateTime.fromMillisecondsSinceEpoch(
          result.chat.lastMessage.time,
        );
        return lastMessageTime.isAfter(weekAgo);
      }).toList();
    }

    setState(() {
      _searchResults = filteredResults;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    _globalSearchDebounce?.cancel();
    setState(() {
      _searchQuery = '';
      _searchResults.clear();
      _isSearchExpanded = false;
      _isGlobalSearchLoading = false;
      _globalSearchError = null;
      _globalSearchResults = [];
      _globalSearchMarker = null;
      _globalSearchHasMore = false;
    });
    _searchAnimationController.reverse();
  }

  void _loadChatsAndContacts() {
    print('🔄 Принудительная загрузка чатов после переподключения...');
    final future = ApiService.instance.getChatsAndContacts(force: true);

    setState(() {
      _chatsFuture = future;
    });

    future
        .then((data) {
          if (!mounted) return;

          final chats = (data['chats'] as List?) ?? const [];
          final contacts = (data['contacts'] as List?) ?? const [];
          final profileData = data['profile'];

          setState(() {
            final newChats = chats
                .where((json) => json != null)
                .map(
                  (json) =>
                      Chat.tryFromJson((json as Map).cast<String, dynamic>()),
                )
                .whereType<Chat>()
                .toList();

            final newChatIds = newChats.map((c) => c.id).toSet();

            for (final newChat in newChats) {
              final existingIndex = _allChats.indexWhere(
                (c) => c.id == newChat.id,
              );
              if (existingIndex != -1) {
                _allChats[existingIndex] = newChat;
              } else {
                _allChats.add(newChat);
              }
            }

            _allChats.removeWhere(
              (chat) => !newChatIds.contains(chat.id),
            );

            for (final contactJson in contacts) {
              final contact = Contact.fromJson(
                (contactJson as Map).cast<String, dynamic>(),
              );
              _contacts[contact.id] = contact;
            }

            if (profileData != null) {
              _myProfile = Profile.fromJson(profileData);
              _isProfileLoading = false;
            }
          });

          _filterChats();
          if (mounted) setState(() {});

          _loadChatDrafts();
        })
        .catchError((error) {
          print('Ошибка в _loadChatsAndContacts: $error');
          if (!mounted) return;

          // Даже при ошибке убедимся, что _chatsLoaded установлен в true
          // чтобы не показывать вечный индикатор загрузки
          setState(() {
            _chatsLoaded = true;
          });
        });
  }

  Future<void> _loadChatOrder() async {
    _allChats.sort((a, b) => b.lastMessage.time.compareTo(a.lastMessage.time));
    if (_prefs == null) {
      _prefs = await SharedPreferences.getInstance();
      _GETOUT = _loadGetoutFromPrefs(_prefs!);
    }
    _filterChats();
  }

  Future<void> _loadMissingContact(int contactId) async {
    if (_loadingContactIds.contains(contactId)) return;

    final existing = _contacts[contactId];
    if (existing != null) {
      final isNumericName = RegExp(r'^\d+$').hasMatch(existing.name);
      if (!isNumericName && existing.name != contactId.toString()) {
        return;
      }
    }

    _loadingContactIds.add(contactId);

    try {
      final contacts = await ApiService.instance.fetchContactsByIds([
        contactId,
      ]);
      if (contacts.isNotEmpty && mounted) {
        setState(() {
          _contacts[contactId] = contacts.first;
        });
      }
    } catch (e) {
      print('Ошибка загрузки контакта $contactId: $e');
    } finally {
      _loadingContactIds.remove(contactId);
    }
  }

  String _formatTimestamp(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    if (now.day == dt.day && now.month == dt.month && now.year == dt.year) {
      return DateFormat('HH:mm', 'ru').format(dt);
    } else {
      final yesterday = now.subtract(const Duration(days: 1));
      if (dt.day == yesterday.day &&
          dt.month == yesterday.month &&
          dt.year == yesterday.year) {
        return 'Вчера';
      } else {
        return DateFormat('d MMM', 'ru').format(dt);
      }
    }
  }

  Future<void> _openSferum() async {
    try {
      await ApiService.instance.waitUntilOnline();
      final seq32 = await ApiService.instance.sendAndTrackFullJsonRequest(
        jsonEncode({
          "ver": 11,
          "cmd": 0,
          "seq": 0,
          "opcode": 32,
          "payload": {
            "contactIds": [2340831],
          },
        }),
      );

      final resp32 = await ApiService.instance.messages
          .firstWhere((m) => m['seq'] == seq32)
          .timeout(const Duration(seconds: 10));

      final contacts = resp32['payload']['contacts'] as List;
      if (contacts.isEmpty) {
        throw Exception('Не удалось получить информацию о боте');
      }
      final webAppUrl = contacts[0]['webApp'] as String?;
      if (webAppUrl == null) {
        throw Exception('Бот не имеет веб-приложения');
      }

      int? chatId;
      for (var chat in _allChats) {
        if (chat.participantIds.contains(2340831)) {
          chatId = chat.id;
          break;
        }
      }

      print('🔍 Найден chatId для бота Сферума: ${chatId ?? "не найден"}');

      final seq160 = await ApiService.instance.sendAndTrackFullJsonRequest(
        jsonEncode({
          "ver": 11,
          "cmd": 0,
          "seq": 0,
          "opcode": 160,
          "payload": {"botId": 2340831, "chatId": chatId ?? 0},
        }),
      );

      print('📤 Отправлен opcode 160 с seq: $seq160');

      final resp160 = await ApiService.instance.messages
          .firstWhere((m) => m['seq'] == seq160)
          .timeout(const Duration(seconds: 10));

      print('📥 Получен ответ на opcode 160: ${resp160.toString()}');

      final webUrl = resp160['payload']['url'] as String?;
      if (webUrl == null) {
        throw Exception('Не удалось получить URL веб-приложения');
      }

      print('🌐 URL веб-приложения: $webUrl');

      if (!mounted) return;

      if (mounted) {
        _showSferumWebView(context, webUrl);
      }
    } catch (e, stackTrace) {
      print('❌ Ошибка открытия Сферума: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка открытия Сферума: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showSferumWebView(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SferumWebViewPanel(url: url),
        fullscreenDialog: true,
      ),
    );
  }

  Widget _buildConnectionScreen() {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
            ),
            const SizedBox(height: 24),

            Text(
              'Подключение',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 8),

            Text(
              'Устанавливаем соединение с сервером...',
              style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final Widget bodyContent = Stack(
      children: [
        FutureBuilder<Map<String, dynamic>>(
          future: _chatsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildConnectionScreen();
            }
            if (snapshot.hasError) {
              return Center(
                child: Text('Ошибка загрузки чатов: ${snapshot.error}'),
              );
            }
            if (snapshot.hasData) {
              if (!_chatsLoaded) {
                final chatListJson = snapshot.data!['chats'] as List;
                final contactListJson = snapshot.data!['contacts'] as List;
                _allChats = chatListJson
                    .map(
                      (json) => Chat.tryFromJson((json as Map<String, dynamic>)),
                    )
                    .whereType<Chat>()
                    .toList();
                _chatsLoaded = true;
                unawaited(_listenForUpdates());

                _loadChatDrafts();
                final contacts = contactListJson.map(
                  (json) => Contact.fromJson(json as Map<String, dynamic>),
                );
                _contacts = {for (var c in contacts) c.id: c};

                final presence =
                    snapshot.data!['presence'] as Map<String, dynamic>?;
                if (presence != null) {
                  print('Получен presence: $presence');
                }

                if (!_hasRequestedBlockedContacts) {
                  _hasRequestedBlockedContacts = true;
                  ApiService.instance.getBlockedContacts();
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _loadFolders(snapshot.data!);
                });

                // ИСПРАВЛЕНИЕ: Вызываем _loadChatOrder только ОДИН раз
                if (!_chatOrderLoaded) {
                  _chatOrderLoaded = true;
                  _loadChatOrder()
                      .then((_) {
                        if (!mounted) return;
                        _filterChats();
                      })
                      .catchError((error) {
                        print('Ошибка в _loadChatOrder: $error');
                        if (!mounted) return;
                        _filterChats();
                      });
                }
              }

              // ИСПРАВЛЕНИЕ: Проверяем флаг перед изменением состояния в build()
              if (_filteredChats.isEmpty &&
                  _allChats.isNotEmpty &&
                  _chatOrderLoaded) {
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  if (!mounted) return;
                  if (_prefs == null) {
                    _prefs = await SharedPreferences.getInstance();
                    _GETOUT = _loadGetoutFromPrefs(_prefs!);
                  }
                  if (mounted && _filteredChats.isEmpty) {
                    _filterChats();
                  }
                });
              }
              if (_filteredChats.isEmpty && _allChats.isEmpty) {
                // Если чаты еще не загружены - показываем индикатор загрузки
                if (!_chatsLoaded) {
                  return const Center(child: CircularProgressIndicator());
                }
                // Если чаты загружены но их нет - показываем сообщение
                return const Center(
                  child: Text(
                    'Нет чатов',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                );
              }

              if (_isSearchExpanded) {
                return _buildSearchResults();
              } else {
                final isAllChatsTab = _folderTabController.index == 0;
                final showArchiveBanner = isAllChatsTab && _archivedChatsList.isNotEmpty;
                return Column(
                  children: [
                    _buildFolderTabs(),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: showArchiveBanner
                          ? _buildArchiveBanner()
                          : const SizedBox.shrink(),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _folderTabController,
                        children: _buildFolderPages(),
                      ),
                    ),
                  ],
                );
              }
            }
            return const Center(child: Text('Нет данных'));
          },
        ),

        if (!_isSearchExpanded) _buildDebugRefreshPanel(context),
      ],
    );

    final content = widget.hasScaffold
        ? ChatsScreenScaffold(
            bodyContent: bodyContent,
            buildAppBar: _buildAppBar,
            buildAppDrawer: _buildAppDrawer,
            onAddPressed: widget.isForwardMode
                ? null
                : () => _showAddMenu(context),
          )
        : bodyContent;

    return PopScope(
      canPop: !_isSearchExpanded,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isSearchExpanded) {
          _clearSearch();
        }
      },
      child: content,
    );
  }

  Widget _buildAppDrawer(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final themeProvider = context.watch<ThemeProvider>();
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;

    return Drawer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FutureBuilder<List<Account>>(
            future: _loadAccounts(),
            builder: (context, accountsSnapshot) {
              final accounts = accountsSnapshot.data ?? [];
              final accountManager = AccountManager();
              final currentAccount = accountManager.currentAccount;
              final hasMultipleAccounts = accounts.length > 1;

              return Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 16.0,
                      left: 16.0,
                      right: 16.0,
                      bottom: 16.0,
                    ),
                    decoration: () {
                      if (themeProvider.drawerBackgroundType ==
                          DrawerBackgroundType.gradient) {
                        return BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              themeProvider.drawerGradientColor1,
                              themeProvider.drawerGradientColor2,
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        );
                      } else if (themeProvider.drawerBackgroundType ==
                              DrawerBackgroundType.image &&
                          themeProvider.drawerImagePath != null &&
                          themeProvider.drawerImagePath!.isNotEmpty) {
                        return BoxDecoration(
                          image: DecorationImage(
                            image: FileImage(
                              File(themeProvider.drawerImagePath!),
                            ),
                            fit: BoxFit.cover,
                          ),
                        );
                      }
                      return BoxDecoration(color: colors.primaryContainer);
                    }(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: colors.primary,
                              backgroundImage:
                                  _isProfileLoading ||
                                      _myProfile?.photoBaseUrl == null
                                  ? null
                                  : CachedNetworkImageProvider(
                                      _myProfile!.photoBaseUrl!,
                                    ),
                              child: _isProfileLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : (_myProfile?.photoBaseUrl == null
                                        ? Text(
                                            _myProfile
                                                        ?.displayName
                                                        .isNotEmpty ==
                                                    true
                                                ? _myProfile!.displayName[0]
                                                      .toUpperCase()
                                                : '?',
                                            style: TextStyle(
                                              color: colors.onPrimary,
                                              fontSize: 28,
                                            ),
                                          )
                                        : null),
                            ),
                            IconButton(
                              icon: Icon(
                                isDarkMode
                                    ? Icons.brightness_7
                                    : Icons.brightness_4,
                                color: colors.onPrimaryContainer,
                                size: 26,
                              ),
                              onPressed: () {
                                themeProvider.toggleTheme();
                              },
                              tooltip: isDarkMode
                                  ? 'Светлая тема'
                                  : 'Темная тема',
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        Text(
                          _myProfile?.displayName ?? 'Загрузка...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 4),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _myProfile?.formattedPhone ?? '',
                                style: TextStyle(
                                  color: colors.onPrimaryContainer.withValues(
                                    alpha: 0.8,
                                  ),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _isAccountsExpanded = !_isAccountsExpanded;
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: Icon(
                                  _isAccountsExpanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  color: colors.onPrimaryContainer,
                                  size: 24,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  ClipRect(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOutCubic,
                      child: _isAccountsExpanded
                          ? Column(
                              children: [
                                if (hasMultipleAccounts)
                                  ...accounts.map((account) {
                                    final isCurrent =
                                        account.id == currentAccount?.id;
                                    return ListTile(
                                      leading: CircleAvatar(
                                        radius: 20,
                                        backgroundColor: isCurrent
                                            ? colors.primary
                                            : colors.surfaceContainerHighest,
                                        backgroundImage:
                                            account.avatarUrl != null
                                            ? CachedNetworkImageProvider(
                                                account.avatarUrl!,
                                              )
                                            : null,
                                        child: account.avatarUrl == null
                                            ? Text(
                                                account.displayName.isNotEmpty
                                                    ? account.displayName[0]
                                                          .toUpperCase()
                                                    : '?',
                                                style: TextStyle(
                                                  color: isCurrent
                                                      ? colors.onPrimary
                                                      : colors.onSurfaceVariant,
                                                  fontSize: 16,
                                                ),
                                              )
                                            : null,
                                      ),
                                      title: Text(
                                        account.displayName,
                                        style: TextStyle(
                                          fontWeight: isCurrent
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                      subtitle: account.displayPhone.isNotEmpty
                                          ? Text(account.displayPhone)
                                          : null,
                                      trailing: isCurrent
                                          ? Icon(
                                              Icons.check_circle,
                                              color: colors.primary,
                                              size: 20,
                                            )
                                          : IconButton(
                                              icon: Icon(
                                                Icons.close,
                                                size: 20,
                                                color: colors.onSurfaceVariant,
                                              ),
                                              onPressed: () {
                                                _showDeleteAccountDialog(
                                                  context,
                                                  account,
                                                  accountManager,
                                                  () {
                                                    setState(() {});
                                                  },
                                                );
                                              },
                                            ),
                                      onTap: isCurrent
                                          ? null
                                          : () async {
                                              Navigator.pop(context);
                                              setState(() {
                                                _isSwitchingAccounts = true;
                                              });
                                              try {
                                                await ApiService.instance
                                                    .switchAccount(account.id);
                                                if (mounted) {
                                                  setState(() {
                                                    _isAccountsExpanded = false;

                                                    _allChats.clear();
                                                    _filteredChats.clear();
                                                    _contacts.clear();
                                                    _folders.clear();
                                                    _chatDrafts.clear();
                                                    _searchResults.clear();
                                                    _myProfile = null;
                                                    _isProfileLoading = true;
                                                    _chatsLoaded = false;

                                                    _loadMyProfile();
                                                    _chatsFuture = (() async {
                                                      try {
                                                        await ApiService
                                                            .instance
                                                            .waitUntilOnline();
                                                        return ApiService
                                                            .instance
                                                            .getChatsAndContacts();
                                                      } catch (e) {
                                                        print(
                                                          'Ошибка получения чатов: $e',
                                                        );
                                                        rethrow;
                                                      }
                                                    })();
                                                  });
                                                }
                                              } catch (e) {
                                                if (mounted) {
                                                  final errorMessage = e
                                                      .toString();

                                                  const invalidTokenKeywords = [
                                                    'invalid_token',
                                                    'FAIL_WRONG_PASSWORD',
                                                  ];
                                                  final isInvalidToken =
                                                      invalidTokenKeywords.any(
                                                        (keyword) =>
                                                            errorMessage
                                                                .contains(
                                                                  keyword,
                                                                ),
                                                      ) ||
                                                      errorMessage.contains(
                                                        'недействительн',
                                                      );

                                                  if (isInvalidToken) {
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        content: const Text(
                                                          'Аккаунт недействителен. Требуется повторная авторизация.',
                                                        ),
                                                        backgroundColor:
                                                            colors.error,
                                                        duration:
                                                            const Duration(
                                                              seconds: 4,
                                                            ),
                                                      ),
                                                    );
                                                  } else {
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          'Ошибка переключения аккаунта: $e',
                                                        ),
                                                        backgroundColor:
                                                            colors.error,
                                                      ),
                                                    );
                                                  }
                                                }
                                              } finally {
                                                if (mounted) {
                                                  setState(() {
                                                    _isSwitchingAccounts =
                                                        false;
                                                  });
                                                }
                                              }
                                            },
                                    );
                                  }),

                                Container(
                                  decoration:
                                      themeProvider
                                          .useGradientForAddAccountButton
                                      ? BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              themeProvider
                                                  .addAccountButtonGradientColor1,
                                              themeProvider
                                                  .addAccountButtonGradientColor2,
                                            ],
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                          ),
                                        )
                                      : null,
                                  child: ListTile(
                                    leading: const Icon(
                                      Icons.add_circle_outline,
                                    ),
                                    title: const Text('Добавить аккаунт'),
                                    onTap: () {
                                      Navigator.pop(context);
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const PhoneEntryScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              );
            },
          ),
          Expanded(
            child: () {
              final menuColumn = Column(
                children: [
                  _buildAccountsSection(context, colors),
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const Text('Мой профиль'),
                    onTap: () {
                      Navigator.pop(context);
                      _navigateToProfileEdit();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.call_outlined),
                    title: const Text('Звонки'),
                    onTap: () {
                      final apiService = context.read<ApiService>();
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => Provider<ApiService>.value(
                            value: apiService,
                            child: const CallsScreen(),
                          ),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.music_note),
                    title: const Text('Музыка'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const MusicLibraryScreen(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: _isReconnecting
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colors.primary,
                              ),
                            ),
                          )
                        : const Icon(Icons.refresh),
                    title: const Text('Переподключиться'),
                    enabled: !_isReconnecting,
                    onTap: () async {
                      if (_isReconnecting) return;

                      setState(() {
                        _isReconnecting = true;
                      });

                      try {
                        await ApiService.instance.performFullReconnection();
                        if (mounted) {
                          Navigator.pop(context);
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Ошибка переподключения: $e'),
                              backgroundColor: colors.error,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() {
                            _isReconnecting = false;
                          });
                        }
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('Настройки'),
                    onTap: () {
                      Navigator.pop(context);

                      final screenSize = MediaQuery.of(context).size;
                      final screenWidth = screenSize.width;
                      final screenHeight = screenSize.height;
                      final isDesktopOrTablet =
                          screenWidth >= 600 && screenHeight >= 800;

                      print(
                        'Screen size: ${screenWidth}x$screenHeight, isDesktopOrTablet: $isDesktopOrTablet',
                      );

                      if (isDesktopOrTablet) {
                        showDialog(
                          context: context,
                          barrierDismissible: true,
                          builder: (context) => SettingsScreen(
                            showBackToChats: true,
                            onBackToChats: () => Navigator.of(context).pop(),
                            myProfile: _myProfile,
                            isModal: true,
                          ),
                        );
                      } else {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => SettingsScreen(
                              showBackToChats: true,
                              onBackToChats: () => Navigator.of(context).pop(),
                              myProfile: _myProfile,
                              isModal: false,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  const Spacer(),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: Icon(Icons.logout, color: colors.error),
                    title: Text('Выйти', style: TextStyle(color: colors.error)),
                    onTap: () {
                      Navigator.pop(context);
                      _showLogoutDialog();
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              );

              if (themeProvider.drawerBackgroundType ==
                  DrawerBackgroundType.gradient) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        themeProvider.drawerGradientColor2,
                        themeProvider.drawerGradientColor1,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: menuColumn,
                );
              } else if (themeProvider.drawerBackgroundType ==
                      DrawerBackgroundType.image &&
                  themeProvider.drawerImagePath != null &&
                  themeProvider.drawerImagePath!.isNotEmpty) {
                return Container(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: FileImage(File(themeProvider.drawerImagePath!)),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: menuColumn,
                );
              }
              return menuColumn;
            }(),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountsSection(BuildContext context, ColorScheme colors) {
    return const SizedBox.shrink();
  }

  Future<List<Account>> _loadAccounts() async {
    final accountManager = AccountManager();
    await accountManager.initialize();
    return accountManager.accounts;
  }

  Widget _buildSearchResults() {
    final colors = Theme.of(context).colorScheme;

    if (_searchQuery.isEmpty) {
      return Column(
        children: [
          _buildRecentChatsIcons(),
          const Divider(height: 1),

          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search,
                    size: 64,
                    color: colors.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Начните вводить для поиска',
                    style: TextStyle(
                      fontSize: 18,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Или выберите чат из списка выше',
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final int globalHeaderCount = 1;
    final int globalItemsCount = _globalSearchResults.length;
    final int globalMoreCount = _globalSearchHasMore ? 1 : 0;
    final int localHeaderCount = 1;
    final int localItemsCount = _searchResults.length;

    final int totalCount =
        globalHeaderCount +
        globalItemsCount +
        globalMoreCount +
        localHeaderCount +
        localItemsCount;

    if (!_isGlobalSearchLoading &&
        _globalSearchError == null &&
        _globalSearchResults.isEmpty &&
        _searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: colors.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Ничего не найдено',
              style: TextStyle(
                fontSize: 18,
                color: colors.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Попробуйте изменить поисковый запрос',
              style: TextStyle(
                fontSize: 14,
                color: colors.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: totalCount,
      itemBuilder: (context, index) {
        int i = index;

        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Глобальный поиск',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (_isGlobalSearchLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          );
        }

        i -= globalHeaderCount;

        if (i < globalItemsCount) {
          final item = _globalSearchResults[i];
          final chat = item['chat'];
          final highlights = item['highlights'];

          String title = '';
          String subtitle = '';

          if (chat is Map) {
            final chatMap = chat.cast<String, dynamic>();
            title =
                chatMap['title']?.toString() ??
                chatMap['link']?.toString() ??
                '';
            subtitle = chatMap['description']?.toString() ?? '';
          }

          if (title.isEmpty) {
            title = item['chatId']?.toString() ?? 'Результат';
          }

          if (highlights is List && highlights.isNotEmpty) {
            final h = highlights.map((e) => e.toString()).join(', ');
            subtitle = subtitle.isEmpty ? h : '$subtitle\n$h';
          }

          return ListTile(
            title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: subtitle.isEmpty
                ? null
                : Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
          );
        }

        i -= globalItemsCount;

        if (_globalSearchHasMore && i == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _isGlobalSearchLoading
                    ? null
                    : () => _performGlobalSearch(reset: false),
                child: const Text('Загрузить еще (глобально)'),
              ),
            ),
          );
        }

        i -= globalMoreCount;

        if (i == 0) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Локальные результаты',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        }

        i -= localHeaderCount;

        if (i < localItemsCount) {
          return _buildSearchResultItem(_searchResults[i]);
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildSearchResultItem(SearchResult result) {
    final colors = Theme.of(context).colorScheme;
    final chat = result.chat;
    final contact = result.contact;

    final bool isSavedMessages = _isSavedMessages(chat);
    final bool isGroupChat = _isGroupChat(chat);
    final bool isChannel = chat.type == 'CHANNEL';

    Contact? contactToUse = contact;
    if (contact == null && (isChannel || isGroupChat)) {
      contactToUse = Contact(
        id: chat.id,
        name: isChannel ? (chat.title ?? 'Канал') : (chat.title ?? 'Группа'),
        firstName: "",
        lastName: "",
        photoBaseUrl: chat.baseIconUrl,
        description: chat.description,
        isBlocked: false,
        isBlockedByMe: false,
      );
    }

    if (contactToUse == null) return const SizedBox.shrink();

    final Contact contactToUseFinal = isSavedMessages
        ? Contact(
            id: chat.id,
            name: "Избранное",
            firstName: "",
            lastName: "",
            photoBaseUrl: null,
            description: null,
            isBlocked: false,
            isBlockedByMe: false,
          )
        : contactToUse;

    return ListTile(
      onTap: () {
        final participantCount =
            chat.participantsCount ?? chat.participantIds.length;

        if (widget.isForwardMode && widget.onForwardChatSelected != null) {
          widget.onForwardChatSelected!(chat);
        } else if (widget.onChatSelected != null) {
          widget.onChatSelected!(
            chat,
            contactToUseFinal,
            isGroupChat,
            isChannel,
            participantCount,
          );
        } else {
          print('🔘 Открываем ChatScreen для чата: ${chat.id}');
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                chatId: chat.id,
                contact: contactToUseFinal,
                myId: chat.ownerId,
                pinnedMessage: chat.pinnedMessage,
                isGroupChat: isGroupChat,
                isChannel: isChannel,
                participantCount: participantCount,
                onChatRemoved: () {
                  _removeChatLocally(chat.id);
                },
              ),
            ),
          );
        }
      },
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: colors.primaryContainer,
        backgroundImage: contactToUseFinal.photoBaseUrl != null
            ? CachedNetworkImageProvider(contactToUseFinal.photoBaseUrl ?? '')
            : null,
        child: contactToUseFinal.photoBaseUrl == null
            ? Text(
                contactToUseFinal.name.isNotEmpty
                    ? contactToUseFinal.name[0].toUpperCase()
                    : '?',
                style: TextStyle(color: colors.onPrimaryContainer),
              )
            : null,
      ),
      title: _buildHighlightedText(
        getContactDisplayName(
          contactId: contactToUseFinal.id,
          originalName: contactToUseFinal.name,
          originalFirstName: contactToUseFinal.firstName,
          originalLastName: contactToUseFinal.lastName,
        ),
        result.matchedText,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (result.matchType == 'message')
            chat.lastMessage.text.contains("welcome.saved.dialog.message")
                ? _buildWelcomeMessage()
                : _buildSearchMessagePreview(chat, result.matchedText),
          if (result.matchType == 'description')
            _buildHighlightedText(
              contactToUseFinal.description ?? '',
              result.matchedText,
            ),
          const SizedBox(height: 4),
          Text(
            _formatTimestamp(chat.lastMessage.time),
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
      trailing: chat.newMessages > 0
          ? CircleAvatar(
              radius: 10,
              backgroundColor: colors.primary,
              child: Text(
                chat.newMessages.toString(),
                style: TextStyle(color: colors.onPrimary, fontSize: 12),
              ),
            )
          : null,
    );
  }

  Widget _buildHighlightedText(String text, String query) {
    if (query.isEmpty) return Text(text);

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final index = lowerText.indexOf(lowerQuery);

    if (index == -1) return Text(text);

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: text.substring(0, index),
            style: const TextStyle(color: Colors.black),
          ),
          TextSpan(
            text: text.substring(index, index + query.length),
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(
            text: text.substring(index + query.length),
            style: const TextStyle(color: Colors.black),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentChatsIcons() {
    final colors = Theme.of(context).colorScheme;

    final recentChats = _allChats.take(15).toList();

    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: recentChats.length,
        itemBuilder: (context, index) {
          final chat = recentChats[index];
          final bool isGroupChat = _isGroupChat(chat);
          final bool isSavedMessages = _isSavedMessages(chat);

          Contact? contact;
          int? otherParticipantId;
          if (isSavedMessages) {
            contact = _contacts[chat.ownerId];
          } else if (isGroupChat) {
            contact = null;
          } else {
            otherParticipantId = chat.participantIds.firstWhere(
              (id) => id != _myId,
              orElse: () => 0,
            );
            contact = _contacts[otherParticipantId];
          }

          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () {
                final bool isChannel = chat.type == 'CHANNEL';
                String title;
                if (isGroupChat) {
                  title = chat.title?.isNotEmpty == true
                      ? chat.title!
                      : "Группа";
                } else if (isSavedMessages) {
                  title = "Избранное";
                } else if (contact != null) {
                  title = getContactDisplayName(
                    contactId: contact.id,
                    originalName: contact.name,
                    originalFirstName: contact.firstName,
                    originalLastName: contact.lastName,
                  );
                } else if (chat.title?.isNotEmpty == true) {
                  title = chat.title!;
                } else {
                  title = "Данные загружаются...";
                  if (otherParticipantId != null && otherParticipantId != 0) {
                    _loadMissingContact(otherParticipantId);
                  }
                }
                final String? avatarUrl = isGroupChat
                    ? chat.baseIconUrl
                    : (isSavedMessages ? null : contact?.photoBaseUrl);
                final participantCount =
                    chat.participantsCount ?? chat.participantIds.length;

                final Contact contactFallback =
                    contact ??
                    Contact(
                      id: chat.id,
                      name: title,
                      firstName: "",
                      lastName: "",
                      photoBaseUrl: avatarUrl,
                      description: isChannel ? chat.description : null,
                      isBlocked: false,
                      isBlockedByMe: false,
                    );

                if (widget.isForwardMode &&
                    widget.onForwardChatSelected != null) {
                  widget.onForwardChatSelected!(chat);
                } else if (widget.onChatSelected != null) {
                  widget.onChatSelected!(
                    chat,
                    contactFallback,
                    isGroupChat,
                    isChannel,
                    participantCount,
                  );
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ChatScreen(
                        chatId: chat.id,
                        contact: contactFallback,
                        myId: chat.ownerId,
                        pinnedMessage: chat.pinnedMessage,
                        isGroupChat: isGroupChat,
                        isChannel: isChannel,
                        participantCount: participantCount,
                        onChatUpdated: () {
                          _loadChatsAndContacts();
                        },
                        onLastMessageChanged: (Message? newLastMessage) {
                          _updateChatLastMessage(chat.id, newLastMessage);
                        },
                        onDraftChanged:
                            (int chatId, Map<String, dynamic>? draft) {
                              _updateChatDraft(chatId, draft);
                            },
                        onChatRemoved: () {
                          _removeChatLocally(chat.id);
                        },
                      ),
                    ),
                  );
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      isSavedMessages || isGroupChat
                          ? CircleAvatar(
                              radius: 28,
                              backgroundColor: colors.primaryContainer,
                              backgroundImage:
                                  isGroupChat && chat.baseIconUrl != null
                                  ? CachedNetworkImageProvider(
                                      chat.baseIconUrl ?? '',
                                    )
                                  : null,
                              child:
                                  isSavedMessages ||
                                      (isGroupChat && chat.baseIconUrl == null)
                                  ? Icon(
                                      isSavedMessages
                                          ? Icons.bookmark
                                          : Icons.group,
                                      color: colors.onPrimaryContainer,
                                      size: 20,
                                    )
                                  : null,
                            )
                          : contact != null
                          ? ContactAvatarWidget(
                              contactId: contact.id,
                              originalAvatarUrl: contact.photoBaseUrl,
                              radius: 28,
                              fallbackText: contact.name.isNotEmpty
                                  ? contact.name[0].toUpperCase()
                                  : '?',
                              backgroundColor: colors.primaryContainer,
                            )
                          : CircleAvatar(
                              radius: 28,
                              backgroundColor: colors.primaryContainer,
                              child: const Text('?'),
                            ),

                      if (chat.newMessages > 0)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: colors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colors.surface,
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                chat.newMessages > 9
                                    ? '9+'
                                    : chat.newMessages.toString(),
                                style: TextStyle(
                                  color: colors.onPrimary,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 56,
                    child: isGroupChat
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.group,
                                size: 10,
                                color: colors.onSurface,
                              ),
                              const SizedBox(width: 2),
                              Expanded(
                                child: Text(
                                  chat.title?.isNotEmpty == true
                                      ? chat.title!
                                      : "Группа (${chat.participantIds.length})",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.onSurface,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            isSavedMessages
                                ? "Избранное"
                                : (contact?.name ??
                                      (chat.title?.isNotEmpty == true
                                          ? chat.title!
                                          : (otherParticipantId != null
                                                ? 'ID $otherParticipantId'
                                                : ''))),
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.onSurface,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _onFolderTabChanged() {
    if (!_folderTabController.indexIsChanging) {
      final index = _folderTabController.index;
      final folderId = index == 0 ? null : _folders[index - 1].id;

      if (_selectedFolderId != folderId) {
        _selectedFolderId = folderId;
        if (_isInArchive && folderId != null) {
          _isInArchive = false;
        }
        _filterChats();
        setState(() {});
      }
    }
  }

  Widget _buildArchiveBanner() {
    final colors = Theme.of(context).colorScheme;
    final count = _archivedChatsList.length;

    if (_isInArchive) {
      // Режим архива — показываем заголовок с кнопкой назад
      return Material(
        color: colors.surfaceContainerHighest,
        child: InkWell(
          onTap: () {
            setState(() => _isInArchive = false);
            _filterChats();
            setState(() {});
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.arrow_back, size: 20, color: colors.primary),
                const SizedBox(width: 12),
                Icon(Icons.archive_outlined, size: 20, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  'Архив',
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                Text(
                  '$count ${_pluralChats(count)}',
                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Обычный режим — панелька входа в архив
    return Material(
      color: colors.surfaceContainerHighest,
      child: InkWell(
        onTap: () {
          setState(() => _isInArchive = true);
          _filterChats();
          setState(() {});
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.archive_outlined, size: 20, color: colors.onSurfaceVariant),
              const SizedBox(width: 12),
              Text(
                'Архив',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: colors.onPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  String _pluralChats(int count) {
    if (count % 10 == 1 && count % 100 != 11) return 'чат';
    if (count % 10 >= 2 && count % 10 <= 4 && (count % 100 < 10 || count % 100 >= 20)) return 'чата';
    return 'чатов';
  }

  List<Widget> _buildFolderPages() {
    final List<Widget> pages = [
      ChatsListPage(
        key: ValueKey('folder_null_archive_$_isInArchive'),
        folder: null,
        allChats: _visibleChats,
        contacts: _contacts,
        myId: _myId,
        searchQuery: _searchQuery,
        buildChatListItem: _buildChatListItem,
        isSavedMessages: _isSavedMessages,
      ),
      ..._folders.map(
        (folder) => ChatsListPage(
          key: ValueKey('folder_${folder.id}'),
          folder: folder,
          allChats: _visibleChats,
          contacts: _contacts,
          myId: _myId,
          searchQuery: _searchQuery,
          buildChatListItem: _buildChatListItem,
          isSavedMessages: _isSavedMessages,
          chatBelongsToFolder: _chatBelongsToFolder,
        ),
      ),
    ];

    return pages;
  }

  Widget _buildFolderTabs() {
    if (_folderTabController.length <= 1) {
      return const SizedBox.shrink();
    }

    final colors = Theme.of(context).colorScheme;

    final List<Widget> tabs = [
      Tab(
        child: GestureDetector(
          onLongPress: () {},
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [Text('Все чаты', style: TextStyle(fontSize: 14))],
          ),
        ),
      ),
      ..._folders.map(
        (folder) => Tab(
          child: GestureDetector(
            onLongPress: () {
              _showFolderEditMenu(folder);
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (folder.emoji != null) ...[
                  Text(folder.emoji!, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                ],
                Text(folder.title, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    ];

    final themeProvider = context.watch<ThemeProvider>();

    BoxDecoration? folderTabsDecoration;
    if (themeProvider.folderTabsBackgroundType ==
        FolderTabsBackgroundType.gradient) {
      folderTabsDecoration = BoxDecoration(
        gradient: LinearGradient(
          colors: [
            themeProvider.folderTabsGradientColor1,
            themeProvider.folderTabsGradientColor2,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(
          bottom: BorderSide(
            color: colors.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      );
    } else if (themeProvider.folderTabsBackgroundType ==
            FolderTabsBackgroundType.image &&
        themeProvider.folderTabsImagePath != null &&
        themeProvider.folderTabsImagePath!.isNotEmpty) {
      folderTabsDecoration = BoxDecoration(
        image: DecorationImage(
          image: FileImage(File(themeProvider.folderTabsImagePath!)),
          fit: BoxFit.cover,
        ),
        border: Border(
          bottom: BorderSide(
            color: colors.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      );
    }

    return Container(
      height: 48,
      decoration:
          folderTabsDecoration ??
          BoxDecoration(
            color: colors.surface,
            border: Border(
              bottom: BorderSide(
                color: colors.outline.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
          ),
      child: Stack(
        children: [
          Row(
            children: [
              Expanded(
                child: _folders.length <= 3
                    ? Center(
                        child: TabBar(
                          controller: _folderTabController,
                          isScrollable: false,
                          tabAlignment: TabAlignment.center,
                          labelColor: colors.primary,
                          unselectedLabelColor: colors.onSurfaceVariant,
                          indicator: UnderlineTabIndicator(
                            borderSide: BorderSide(
                              width: 3,
                              color: colors.primary,
                            ),
                            insets: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          indicatorSize: TabBarIndicatorSize.label,
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          unselectedLabelStyle: const TextStyle(
                            fontWeight: FontWeight.normal,
                            fontSize: 14,
                          ),
                          dividerColor: Colors.transparent,
                          tabs: tabs,
                          onTap: (index) {},
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(
                          right: 48,
                        ), // Место для кнопки +
                        child: TabBar(
                          controller: _folderTabController,
                          isScrollable: true,
                          labelColor: colors.primary,
                          unselectedLabelColor: colors.onSurfaceVariant,
                          indicator: UnderlineTabIndicator(
                            borderSide: BorderSide(
                              width: 3,
                              color: colors.primary,
                            ),
                            insets: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          indicatorSize: TabBarIndicatorSize.label,
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          unselectedLabelStyle: const TextStyle(
                            fontWeight: FontWeight.normal,
                            fontSize: 14,
                          ),
                          dividerColor: Colors.transparent,
                          tabs: tabs,
                          onTap: (index) {},
                        ),
                      ),
              ),
            ],
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: IconButton(
              icon: const Icon(Icons.add, size: 20),
              onPressed: _showCreateFolderDialog,
              tooltip: 'Создать папку',
              padding: const EdgeInsets.symmetric(horizontal: 8),
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateFolderDialog() {
    final TextEditingController titleController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Создать папку'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Название папки',
            hintText: 'Введите название',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              ApiService.instance.createFolder(value.trim());
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              final title = titleController.text.trim();
              if (title.isNotEmpty) {
                ApiService.instance.createFolder(title);
                Navigator.of(context).pop();
              }
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFolderEditMenu(ChatFolder folder) async {
    final colors = Theme.of(context).colorScheme;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.4,
          minChildSize: 0.3,
          maxChildSize: 0.6,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: colors.outline.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (folder.emoji != null) ...[
                          Text(
                            folder.emoji!,
                            style: const TextStyle(fontSize: 24),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Text(
                            folder.title,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          color: colors.onSurfaceVariant,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: _buildFolderEditMenuContent(folder, context)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFolderEditMenuContent(ChatFolder folder, BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Действия',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Выбрать чаты'),
              onTap: () {
                Navigator.of(context).pop();
                _showAddChatsToFolderDialog(folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Переименовать'),
              onTap: () {
                Navigator.of(context).pop();
                _showRenameFolderDialog(folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                'Удалить папку',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _showDeleteFolderDialog(folder);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showRenameFolderDialog(ChatFolder folder) {
    final TextEditingController titleController = TextEditingController(
      text: folder.title,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Переименовать папку'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Название папки',
            hintText: 'Введите название',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              ApiService.instance.updateFolder(
                folder.id,
                title: value.trim(),
                include: folder.include,
                filters: folder.filters,
              );
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              final title = titleController.text.trim();
              if (title.isNotEmpty) {
                ApiService.instance.updateFolder(
                  folder.id,
                  title: title,
                  include: folder.include,
                  filters: folder.filters,
                );
                Navigator.of(context).pop();
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  void _showDeleteFolderDialog(ChatFolder folder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить папку'),
        content: Text(
          'Вы уверены, что хотите удалить папку "${folder.title}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ApiService.instance.deleteFolder(folder.id);
              setState(() {
                _folders.removeWhere((f) => f.id == folder.id);
              });
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMessagePreview(Chat chat, ChatFolder? currentFolder) async {
    await MessagePreviewDialog.show(
      context,
      chat,
      _contacts,
      _myProfile,
      null,
      (context) => _buildChatMenuContent(chat, currentFolder, context),
    );
  }

  Widget _buildChatMenuContent(
    Chat chat,
    ChatFolder? currentFolder,
    BuildContext context,
  ) {
    return const SizedBox.shrink();
  }

  void _showFolderSelectionMenu(Chat chat) {
    if (_folders.isEmpty) return;

    showModalBottomSheet(
      context: context,
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Выберите папку',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              const Divider(),
              ..._folders.map((folder) {
                return ListTile(
                  leading: folder.emoji != null
                      ? Text(
                          folder.emoji!,
                          style: const TextStyle(fontSize: 24),
                        )
                      : const Icon(Icons.folder),
                  title: Text(folder.title),
                  onTap: () {
                    Navigator.of(context).pop();
                    _addChatToFolder(chat, folder);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showReadSettingsDialog(Chat chat) async {
    final settingsService = ChatReadSettingsService.instance;
    final currentSettings = await settingsService.getSettings(chat.id);
    final theme = context.read<ThemeProvider>();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return ReadSettingsDialogContent(
          chat: chat,
          initialSettings: currentSettings,
          globalReadOnAction: theme.debugReadOnAction,
          globalReadOnEnter: theme.debugReadOnEnter,
        );
      },
    );
  }

  Future<void> _togglePinChat(Chat chat) async {
    final allFolder = _folders.firstWhere(
      (f) => f.id == 'all.chat.folder',
      orElse: () => ChatFolder(
        id: 'all.chat.folder',
        title: 'Все',
        favorites: [],
        include: [],
        filters: [],
        hideEmpty: false,
        widgets: [],
        options: [],
      ),
    );

    final oldFavIndex = chat.favIndex;
    final currentFavorites = List<int>.from(allFolder.favorites ?? []);

    if (chat.isPinned) {
      currentFavorites.remove(chat.id);
    } else {
      if (!currentFavorites.contains(chat.id)) {
        currentFavorites.add(chat.id);
      }
    }

    // Оптимистичное обновление UI
    setState(() {
      final idx = _allChats.indexWhere((c) => c.id == chat.id);
      if (idx != -1) {
        final newFavIndex = chat.isPinned ? 0 : currentFavorites.indexOf(chat.id) + 1;
        _allChats[idx] = _allChats[idx].copyWith(favIndex: newFavIndex);
      }
    });
    _filterChats();

    try {
      final response = await ApiService.instance.sendRequest(274, {
        'id': allFolder.id,
        'title': allFolder.title,
        'include': allFolder.include ?? [],
        'favorites': currentFavorites,
        'filters': allFolder.filters ?? [],
        'options': allFolder.options ?? [],
      });

      final cmd = response['cmd'];
      final folder = response['payload']?['folder'];
      if (cmd != 256 || folder == null) {
        // Откат при ошибке
        setState(() {
          final idx = _allChats.indexWhere((c) => c.id == chat.id);
          if (idx != -1) {
            _allChats[idx] = _allChats[idx].copyWith(favIndex: oldFavIndex);
          }
        });
        _filterChats();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось изменить закреп')),
          );
        }
      }
    } catch (e) {
      // Откат при ошибке
      setState(() {
        final idx = _allChats.indexWhere((c) => c.id == chat.id);
        if (idx != -1) {
          _allChats[idx] = _allChats[idx].copyWith(favIndex: oldFavIndex);
        }
      });
      _filterChats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  void _showGetoutDialog(Chat chat) {
    // Определяем задержку в зависимости от количества нажатий
    final delay = _getoutPressCount == 0 ? 5 : _getoutPressCount == 1 ? 3 : 0;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _GetoutDialog(
        chatTitle: chat.title ?? 'этот чат',
        delaySeconds: delay,
        onConfirm: () async {
          _getoutPressCount++;
          _GETOUT.add(chat.id);
          _archivedChats.remove(chat.id);
          await _saveGetoutToPrefs();
          await _saveArchiveToPrefs();
          if (mounted) {
            setState(() {
              _dismissingChatObjects[chat.id] = chat;
              _dismissingChats.add(chat.id);
            });
          }
          await Future.delayed(const Duration(milliseconds: 700));
          if (mounted) {
            setState(() {
              _dismissingChats.remove(chat.id);
              _dismissingChatObjects.remove(chat.id);
            });
          }
        },
      ),
    );
  }

  void _addChatToFolder(Chat chat, ChatFolder folder) {
    final currentInclude = folder.include ?? [];

    if (currentInclude.contains(chat.id)) {
      return;
    }

    final newInclude = List<int>.from(currentInclude)..add(chat.id);

    ApiService.instance.updateFolder(
      folder.id,
      title: folder.title,
      include: newInclude,
      filters: folder.filters,
    );
  }

  void _showAddChatsToFolderDialog(ChatFolder folder) {
    final currentInclude = folder.include ?? [];

    final allAvailableChats = _allChats.where((chat) {
      return chat.id != 0;
    }).toList();

    final sortedChats = List<Chat>.from(allAvailableChats);
    sortedChats.sort((a, b) {
      final aInFolder = currentInclude.contains(a.id);
      final bInFolder = currentInclude.contains(b.id);
      if (aInFolder && !bInFolder) return -1;
      if (!aInFolder && bInFolder) return 1;
      return 0;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AddChatsToFolderDialog(
          folder: folder,
          availableChats: sortedChats,
          contacts: _contacts,
          onAddChats: (selectedChats) {
            _updateFolderChats(selectedChats, folder);
          },
        );
      },
    );
  }

  void _updateFolderChats(List<Chat> selectedChats, ChatFolder folder) {
    final selectedChatIds = selectedChats.map((chat) => chat.id).toList();
    ApiService.instance.updateFolder(
      folder.id,
      title: folder.title,
      include: selectedChatIds,
      filters: folder.filters,
    );
  }

  Widget _buildDebugRefreshPanel(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    if (!theme.debugShowChatsRefreshPanel) return const SizedBox.shrink();
    final bool hasBottomBar = theme.debugShowBottomBar;
    final double bottomPadding = hasBottomBar ? 80.0 : 20.0;
    final colors = Theme.of(context).colorScheme;
    return Positioned(
      left: 12,
      right: 12,
      bottom: bottomPadding,
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Material(
              color: colors.surface.withValues(alpha: 0.95),
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  SchedulerBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _allChats.clear();
                        _filteredChats.clear();
                        _chatsFuture = ApiService.instance.getChatsAndContacts(
                          force: true,
                        );
                      });
                    }
                  });
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh),
                      SizedBox(width: 8),
                      Text('Обновить список чатов'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusRow({
    required Key key,
    required String text,
    required Widget icon,
  }) {
    return Row(
      key: key,
      children: [
        SizedBox(width: 18, height: 18, child: Center(child: icon)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentTitleWidget() {
    final colors = Theme.of(context).colorScheme;
    final onSurfaceVariant = colors.onSurfaceVariant;
    final isActuallyConnected = ApiService.instance.isActuallyConnected;

    if (_connectionStatus == 'connecting' && !isActuallyConnected) {
      return _buildStatusRow(
        key: const ValueKey('status_connecting'),
        text: 'Подключение...',
        icon: CircularProgressIndicator(
          strokeWidth: 2,
          color: onSurfaceVariant,
        ),
      );
    }

    if (_connectionStatus == 'authorizing' && !isActuallyConnected) {
      return _buildStatusRow(
        key: const ValueKey('status_authorizing'),
        text: 'Авторизация...',
        icon: CircularProgressIndicator(
          strokeWidth: 2,
          color: onSurfaceVariant,
        ),
      );
    }

    if (_connectionStatus == 'disconnected' ||
        _connectionStatus == 'Все серверы недоступны') {
      return _buildStatusRow(
        key: const ValueKey('status_error'),
        text: 'Нет сети',
        icon: Icon(Icons.cloud_off, size: 18, color: colors.error),
      );
    }

    if (_isProfileLoading) {
      return _buildStatusRow(
        key: const ValueKey('status_loading'),
        text: 'Загрузка...',
        icon: CircularProgressIndicator(
          strokeWidth: 2,
          color: onSurfaceVariant,
        ),
      );
    }

    return Text(
      _myProfile?.displayName ?? 'Komet',
      key: const ValueKey('status_username'),
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final themeProvider = context.read<ThemeProvider>();

    BoxDecoration? appBarDecoration;
    if (themeProvider.appBarBackgroundType == AppBarBackgroundType.gradient) {
      appBarDecoration = BoxDecoration(
        gradient: LinearGradient(
          colors: [
            themeProvider.appBarGradientColor1,
            themeProvider.appBarGradientColor2,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      );
    } else if (themeProvider.appBarBackgroundType ==
            AppBarBackgroundType.image &&
        themeProvider.appBarImagePath != null &&
        themeProvider.appBarImagePath!.isNotEmpty) {
      appBarDecoration = BoxDecoration(
        image: DecorationImage(
          image: FileImage(File(themeProvider.appBarImagePath!)),
          fit: BoxFit.cover,
        ),
      );
    }

    return AppBar(
      titleSpacing: 4.0,
      flexibleSpace: appBarDecoration != null
          ? Container(decoration: appBarDecoration)
          : null,

      leading: widget.isForwardMode
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            )
          : _isSearchExpanded
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _clearSearch,
            )
          : Builder(
              builder: (context) {
                return IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  tooltip: 'Меню',
                );
              },
            ),

      title: widget.isForwardMode
          ? const Text(
              'Переслать...',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            )
          : _isSearchExpanded
          ? _buildSearchField(colors)
          : Row(
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder:
                        (Widget child, Animation<double> animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.centerLeft,
                        children: [...previousChildren, ?currentChild],
                      );
                    },
                    child: _buildCurrentTitleWidget(),
                  ),
                ),
              ],
            ),
      actions: widget.isForwardMode
          ? []
          : _isSearchExpanded
          ? [
              if (_searchQuery.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(left: 4),
                  child: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                    },
                  ),
                ),
              Container(
                margin: const EdgeInsets.only(left: 4),
                child: IconButton(
                  icon: const Icon(Icons.filter_list),
                  onPressed: _showSearchFilters,
                ),
              ),
            ]
          : [
              if ((_prefs?.getBool('show_sferum_button') ?? true))
                IconButton(
                  icon: Image.asset(
                    'assets/images/spermum.png',
                    width: 28,
                    height: 28,
                  ),
                  onPressed: _openSferum,
                  tooltip: 'Сферум',
                ),
              IconButton(
                icon: const Icon(Icons.download, color: Colors.white),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const DownloadsScreen(),
                    ),
                  );
                },
                tooltip: 'Загрузки',
              ),
              InkWell(
                onTap: () {
                  setState(() {
                    _isSearchExpanded = true;
                  });
                  _searchAnimationController.forward();
                  _searchFocusNode.requestFocus();
                },

                onLongPress: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const UserIdLookupScreen(),
                    ),
                  );
                },
                customBorder: const CircleBorder(),
                child: Container(
                  padding: const EdgeInsets.all(8.0),
                  child: const Icon(Icons.search),
                ),
              ),
              const SizedBox(width: 8),
            ],
    );
  }

  Widget _buildWelcomeMessage() {
    return Text(
      'Привет! Это твои избранные. Все написанное сюда попадёт прямиком к дяде Майору.',
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 12,
        fontStyle: FontStyle.italic,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildSearchField(ColorScheme colors) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        autofocus: true,
        decoration: InputDecoration(
          contentPadding: EdgeInsets.zero,
          prefixIcon: Icon(
            Icons.search,
            color: colors.onSurfaceVariant,
            size: 18,
          ),
          hintText: 'Поиск в чатах...',
          hintStyle: TextStyle(color: colors.onSurfaceVariant),
          filled: true,
          fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.3),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
        ),
        style: const TextStyle(fontSize: 16),
      ),
    );
  }

  void _navigateToProfileEdit() async {
    if (_myProfile != null) {
      final updatedProfile = await Navigator.of(context).push<Profile?>(
        MaterialPageRoute(
          builder: (context) => ManageAccountScreen(myProfile: _myProfile!),
        ),
      );
      if (updatedProfile != null && mounted) {
        setState(() {
          _myProfile = updatedProfile;
        });
      }
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Профиль еще не загружен')));
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Выход из аккаунта'),
          content: const Text('Вы действительно хотите выйти из аккаунта?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _logout();
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Выйти'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _logout() async {
    try {
      await ApiService.instance.logout();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const PhoneEntryScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка при выходе: $e')));
      }
    }
  }

  void _showDeleteAccountDialog(
    BuildContext context,
    Account account,
    AccountManager accountManager,
    VoidCallback onDeleted,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Удаление аккаунта'),
          content: const Text('Точно хочешь удалить аккаунт?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Нет'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  await accountManager.removeAccount(account.id);
                  if (mounted) {
                    onDeleted();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Ошибка: ${e.toString()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Да'),
            ),
          ],
        );
      },
    );
  }

  void _showSearchFilters() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Фильтры поиска',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _buildFilterOption('all', 'Все чаты', Icons.chat_bubble_outline),
            _buildFilterOption('recent', 'Недавние', Icons.access_time),
            _buildFilterOption(
              'channels',
              'Каналы',
              Icons.broadcast_on_personal,
            ),
            _buildFilterOption('groups', 'Группы', Icons.group),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterOption(String value, String title, IconData icon) {
    final isSelected = _searchFilter == value;
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(title),
      trailing: isSelected ? const Icon(Icons.check) : null,
      onTap: () {
        setState(() {
          _searchFilter = value;
        });
        Navigator.pop(context);
        _performSearch();
      },
    );
  }

  Message? _extractForwardedMessage(
    Map<String, dynamic> link,
    Message fallback,
  ) {
    final forwardedMessage = link['message'] as Map<String, dynamic>?;
    if (forwardedMessage == null) return null;

    final attaches =
        (forwardedMessage['attaches'] as List?)
            ?.map((e) => (e as Map).cast<String, dynamic>())
            .toList() ??
        const [];

    final elements =
        (forwardedMessage['elements'] as List?)
            ?.map((e) => (e as Map).cast<String, dynamic>())
            .toList() ??
        const [];

    return Message(
      id: forwardedMessage['id']?.toString() ?? 'forward_preview',
      text: forwardedMessage['text'] as String? ?? '',
      time: forwardedMessage['time'] as int? ?? fallback.time,
      senderId: forwardedMessage['sender'] as int? ?? 0,
      status: forwardedMessage['status'] as String?,
      updateTime: forwardedMessage['updateTime'] as int?,
      attaches: attaches,
      cid: forwardedMessage['cid'] as int?,
      reactionInfo: forwardedMessage['reactionInfo'] as Map<String, dynamic>?,
      link: forwardedMessage['link'] as Map<String, dynamic>?,
      elements: elements,
    );
  }

  String? _getForwardedSenderName(Map<String, dynamic> link) {
    final chatName = link['chatName'] as String?;
    if (chatName != null && chatName.isNotEmpty) return chatName;

    final forwardedMessage = link['message'] as Map<String, dynamic>?;
    final originalSenderId = forwardedMessage?['sender'] as int?;
    if (originalSenderId != null) {
      final contact = _contacts[originalSenderId];
      if (contact != null) {
        return getContactDisplayName(
          contactId: contact.id,
          originalName: contact.name,
          originalFirstName: contact.firstName,
          originalLastName: contact.lastName,
        );
      }

      _loadMissingContact(originalSenderId);

      final senderName = forwardedMessage?['senderName'] as String?;
      if (senderName != null && senderName.isNotEmpty) {
        return senderName;
      }

      final firstName = forwardedMessage?['firstName'] as String?;
      final lastName = forwardedMessage?['lastName'] as String?;
      if (firstName != null && firstName.isNotEmpty) {
        if (lastName != null && lastName.isNotEmpty) {
          return '$firstName $lastName';
        }
        return firstName;
      }
    }

    return 'Отправитель загружается';
  }

  String _buildForwardedSnippet(Message forwardedMessage) {
    if (forwardedMessage.text.isNotEmpty) {
      return forwardedMessage.text.replaceAll("\n", " ");
    }

    if (forwardedMessage.attaches.isNotEmpty) {
      return _getAttachmentTypeText(forwardedMessage.attaches);
    }

    return 'Пересланное сообщение';
  }

  Widget _buildMessagePreviewContent(
    Message message,
    Chat chat,
    ColorScheme colors, {
    bool isForwarded = false,
  }) {
    if (message.attaches.isNotEmpty) {
      for (final attach in message.attaches) {
        final type = attach['_type'];
        if (type == 'CALL' || type == 'call') {
          return _buildCallPreview(attach, message, chat);
        }
      }
    }

    Widget messagePreview;
    if (message.text.isEmpty && message.attaches.isNotEmpty) {
      final hasPhoto = message.attaches.any(
        (attach) => attach['_type'] == 'PHOTO',
      );
      final hasContact = message.attaches.any(
        (attach) => attach['_type'] == 'CONTACT',
      );

      if (hasPhoto) {
        messagePreview = _buildPhotoAttachmentPreview(message);
      } else if (hasContact) {
        messagePreview = _buildContactAttachmentPreview(message);
      } else {
        final attachmentText = _getAttachmentTypeText(message.attaches);
        messagePreview = Text(
          attachmentText.replaceAll("\n", " "),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.onSurfaceVariant),
        );
      }
    } else if (message.attaches.isNotEmpty) {
      final hasPhoto = message.attaches.any(
        (attach) => attach['_type'] == 'PHOTO',
      );
      if (hasPhoto) {
        messagePreview = _buildPhotoWithCaptionPreview(message);
      } else {
        messagePreview = Text(
          message.text.replaceAll("\n", " "),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.onSurfaceVariant),
        );
      }
    } else if (message.text.isNotEmpty) {
      final text = message.text.replaceAll("\n", " ");
      if (_looksLikeKometMessage(text)) {
        final built = _tryBuildKometPreview(text, colors.onSurfaceVariant);
        messagePreview =
            built ??
            Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.onSurfaceVariant),
            );
      } else {
        messagePreview = Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.onSurfaceVariant),
        );
      }
    } else {
      messagePreview = Text(
        isForwarded ? 'Пересланное сообщение' : '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colors.onSurfaceVariant),
      );
    }

    return messagePreview;
  }

  bool _looksLikeKometMessage(String text) {
    final lower = text.toLowerCase();
    return lower.contains('komet.color_') ||
        lower.contains('komet.cosmetic.pulse#') ||
        lower.contains("komet.cosmetic.galaxy'");
  }

  Widget? _tryBuildKometPreview(String text, Color baseColor) {
    try {
      final spans = _parseKometPreviewSpans(text, baseColor);
      if (spans.isEmpty) return null;
      return RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(children: spans),
      );
    } catch (_) {
      return null;
    }
  }

  List<InlineSpan> _parseKometPreviewSpans(String text, Color baseColor) {
    final spans = <InlineSpan>[];
    int index = 0;

    while (index < text.length) {
      final nextPulse = text.indexOf('komet.cosmetic.pulse#', index);
      final nextGalaxy = text.indexOf("komet.cosmetic.galaxy'", index);
      final nextColor = text.indexOf('komet.color_', index);

      int nextMarker = text.length;
      String? markerType;

      if (nextPulse != -1 && nextPulse < nextMarker) {
        nextMarker = nextPulse;
        markerType = 'pulse';
      }
      if (nextGalaxy != -1 && nextGalaxy < nextMarker) {
        nextMarker = nextGalaxy;
        markerType = 'galaxy';
      }
      if (nextColor != -1 && nextColor < nextMarker) {
        nextMarker = nextColor;
        markerType = 'color';
      }

      if (markerType == null) {
        if (index < text.length) {
          spans.add(
            TextSpan(
              text: text.substring(index),
              style: TextStyle(color: baseColor),
            ),
          );
        }
        break;
      }

      if (nextMarker > index) {
        spans.add(
          TextSpan(
            text: text.substring(index, nextMarker),
            style: TextStyle(color: baseColor),
          ),
        );
      }

      if (markerType == 'pulse') {
        const prefix = 'komet.cosmetic.pulse#';
        final afterHash = text.substring(nextMarker + prefix.length);
        final quoteIndex = afterHash.indexOf("'");
        if (quoteIndex == -1) throw StateError('invalid pulse syntax');
        final hexStr = afterHash.substring(0, quoteIndex).trim();
        final color = _parseKometHexColor(hexStr);

        final textStart = quoteIndex + 1;
        final secondQuote = afterHash.indexOf("'", textStart);
        if (secondQuote == -1) throw StateError('invalid pulse text');
        final segmentText = afterHash.substring(textStart, secondQuote);

        spans.add(
          TextSpan(
            text: segmentText,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        );

        index = nextMarker + prefix.length + secondQuote + 2;
        continue;
      }

      if (markerType == 'galaxy') {
        const prefix = "komet.cosmetic.galaxy''";
        final textStart = nextMarker + prefix.length;
        final quoteIndex = text.indexOf("''", textStart);
        if (quoteIndex == -1) {
          index = nextMarker + 1;
          continue;
        }
        final segmentText = text.substring(textStart, quoteIndex);
        spans.add(
          TextSpan(
            text: segmentText,
            style: TextStyle(color: baseColor, fontWeight: FontWeight.w600),
          ),
        );
        index = quoteIndex + 2;
        continue;
      }

      if (markerType == 'color') {
        const marker = 'komet.color_';
        final colorStart = nextMarker + marker.length;
        final firstQuote = text.indexOf("''", colorStart);
        if (firstQuote == -1) {
          index = nextMarker + 1;
          continue;
        }
        final colorStr = text.substring(colorStart, firstQuote).trim();
        final color = _parseKometHexColor(colorStr);

        final textStart = firstQuote + 2;
        final secondQuote = text.indexOf("''", textStart);
        if (secondQuote == -1) {
          index = nextMarker + 1;
          continue;
        }
        final segmentText = text.substring(textStart, secondQuote);

        spans.add(
          TextSpan(
            text: segmentText,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        );
        index = secondQuote + 2;
        continue;
      }
    }

    return spans;
  }

  Color _parseKometHexColor(String raw) {
    var hex = raw.trim();
    if (hex.startsWith('#')) {
      hex = hex.substring(1);
    }
    if (hex.isEmpty) throw StateError('empty hex');

    if (hex.length == 3) {
      hex = '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}';
    } else if (hex.length == 4) {
      hex =
          '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}${hex[3]}${hex[3]}';
    } else if (hex.length == 5) {
      hex = '0$hex';
    } else if (hex.length < 6) {
      hex = hex.padRight(6, '0');
    } else if (hex.length > 6) {
      hex = hex.substring(0, 6);
    }

    return Color(int.parse('FF$hex', radix: 16));
  }

  Widget _buildLastMessagePreview(Chat chat) {
    final message = chat.lastMessage;
    final colors = Theme.of(context).colorScheme;

    final draftState = _chatDrafts[chat.id];
    if (draftState != null) {
      final draftText = draftState['text']?.toString().trim();
      if (draftText != null && draftText.isNotEmpty) {
        return RichText(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            children: [
              const TextSpan(
                text: 'Черновик:',
                style: TextStyle(
                  color: Colors.white,
                  fontStyle: FontStyle.italic,
                ),
              ),
              TextSpan(
                text: draftText,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        );
      }
    }

    final isMyMessage =
        _myProfile != null && message.senderId == _myProfile!.id;

    Widget messagePreview;
    if (message.isForwarded && message.link is Map<String, dynamic>) {
      final link = message.link as Map<String, dynamic>;
      final forwardedMessage = _extractForwardedMessage(link, message);
      if (forwardedMessage != null) {
        final forwardedFrom = _getForwardedSenderName(link);
        final snippet = _buildForwardedSnippet(forwardedMessage);
        final prefix = forwardedFrom?.isNotEmpty == true
            ? forwardedFrom!
            : 'Переслано';

        messagePreview = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forward, size: 14, color: colors.onSurfaceVariant),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '$prefix: $snippet',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      } else {
        messagePreview = _buildMessagePreviewContent(message, chat, colors);
      }
    } else {
      messagePreview = _buildMessagePreviewContent(message, chat, colors);
    }

    if (isMyMessage) {
      final queueItem = MessageQueueService().findByCid(message.cid ?? 0);
      final bool isPending =
          queueItem != null || message.id.startsWith('local_');

      return Row(
        children: [
          if (isPending)
            Icon(Icons.access_time, size: 14, color: colors.onSurfaceVariant)
          else
            Icon(Icons.done, size: 14, color: colors.onSurfaceVariant),
          const SizedBox(width: 4),
          Expanded(child: messagePreview),
        ],
      );
    }

    return messagePreview;
  }

  Widget _buildPhotoAttachmentPreview(Message message) {
    final photoUrl = _extractFirstPhotoUrl(message.attaches);
    if (photoUrl == null) {
      return const Text(
        'Вложение',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CachedNetworkImage(
              imageUrl: photoUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.photo,
                  size: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.photo,
                  size: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Вложение',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContactAttachmentPreview(Message message) {
    final contactData = _extractFirstContactData(message.attaches);
    if (contactData == null) {
      return const Text(
        'Контакт',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final name = contactData['name']!;
    final photoUrl = contactData['photoUrl'];

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 20,
            height: 20,
            child: photoUrl != null
                ? CachedNetworkImage(
                    imageUrl: photoUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.person,
                        size: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.person,
                        size: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Container(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.person,
                      size: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoWithCaptionPreview(Message message) {
    final photoUrl = _extractFirstPhotoUrl(message.attaches);
    if (photoUrl == null) {
      return Text(message.text, maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CachedNetworkImage(
              imageUrl: photoUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.photo,
                  size: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.photo,
                  size: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  String? _extractFirstPhotoUrl(List<Map<String, dynamic>> attaches) {
    for (final attach in attaches) {
      if (attach['_type'] == 'PHOTO') {
        final dynamic url = attach['url'] ?? attach['baseUrl'];
        if (url is String && url.isNotEmpty) {
          return url;
        }
      }
    }
    return null;
  }

  Map<String, String?>? _extractFirstContactData(
    List<Map<String, dynamic>> attaches,
  ) {
    for (final attach in attaches) {
      if (attach['_type'] == 'CONTACT') {
        final name = attach['name'] as String?;
        final firstName = attach['firstName'] as String?;
        final lastName = attach['lastName'] as String?;
        final photoUrl =
            attach['photoUrl'] as String? ?? attach['baseUrl'] as String?;

        String displayName;
        if (name != null && name.isNotEmpty) {
          displayName = name;
        } else if (firstName != null && lastName != null) {
          displayName = '$firstName $lastName';
        } else if (firstName != null) {
          displayName = firstName;
        } else {
          displayName = 'Контакт';
        }

        return {'name': displayName, 'photoUrl': photoUrl};
      }
    }
    return null;
  }

  String _getAttachmentTypeText(List<Map<String, dynamic>> attaches) {
    if (attaches.any((attach) => attach['_type'] == 'VIDEO')) {
      return 'Видео';
    }
    if (attaches.any((attach) => attach['_type'] == 'AUDIO')) {
      return 'Аудио';
    }
    if (attaches.any((attach) => attach['_type'] == 'MUSIC')) {
      return 'Музыка';
    }
    if (attaches.any((attach) => attach['_type'] == 'STICKER')) {
      return 'Стикер';
    }
    if (attaches.any((attach) => attach['_type'] == 'CONTACT')) {
      return 'Контакт';
    }
    if (attaches.any((attach) => attach['_type'] == 'FILE')) {
      return 'Файл';
    }
    if (attaches.any((attach) => attach['_type'] == 'INLINE_KEYBOARD')) {
      return 'Кнопки';
    }

    return 'Вложение';
  }

  String _getSenderDisplayName(Chat chat, Message message) {
    final isGroupChat = _isGroupChat(chat);
    final isChannel = chat.type == 'CHANNEL';

    if (!isGroupChat && !isChannel) {
      return '';
    }

    if (isChannel) {
      return '';
    }

    final contact = _contacts[message.senderId];
    if (contact != null) {
      return getContactDisplayName(
        contactId: contact.id,
        originalName: contact.name,
        originalFirstName: contact.firstName,
        originalLastName: contact.lastName,
      );
    }

    _loadMissingContact(message.senderId);
    return '';
  }

  Widget _buildChatSubtitle(Chat chat) {
    final theme = context.watch<ThemeProvider>();
    final colors = Theme.of(context).colorScheme;

    if (chat.lastMessage.text.contains("welcome.saved.dialog.message")) {
      return _buildWelcomeMessage();
    }

    final message = chat.lastMessage;
    final senderName = _getSenderDisplayName(chat, message);

    final mode = theme.chatPreviewMode;

    switch (mode) {
      case ChatPreviewMode.twoLine:
        // Двустрочно: имя отправителя + сообщение (если есть имя)
        if (senderName.isNotEmpty) {
          final messagePreview = _buildLastMessagePreview(chat);
          if (messagePreview is Text) {
            return RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$senderName: ',
                    style: TextStyle(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  TextSpan(
                    text: messagePreview.data ?? '',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            );
          }
        }
        // Если нет имени отправителя, показываем обычное превью
        return _buildLastMessagePreview(chat);
      case ChatPreviewMode.threeLine:
        // Трехстрочно: имя чата + имя отправителя + сообщение
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (senderName.isNotEmpty)
              Text(
                senderName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            _buildLastMessagePreview(chat),
          ],
        );
      case ChatPreviewMode.noNicknames:
        // Без имен: только сообщение
        return _buildLastMessagePreview(chat);
    }
  }

  Widget _buildSearchMessagePreview(Chat chat, String matchedText) {
    final message = chat.lastMessage;

    if (message.attaches.isNotEmpty) {
      final callAttachments = message.attaches.where((attach) {
        final type = attach['_type'];
        return type == 'CALL' || type == 'call';
      }).toList();

      if (callAttachments.isNotEmpty) {
        return _buildCallPreview(callAttachments.first, message, chat);
      }
    }

    if (message.text.isEmpty && message.attaches.isNotEmpty) {
      // Проверяем, есть ли фото или контакты среди вложений
      final hasPhoto = message.attaches.any(
        (attach) => attach['_type'] == 'PHOTO',
      );

      final hasContact = message.attaches.any(
        (attach) => attach['_type'] == 'CONTACT',
      );

      if (hasPhoto) {
        return _buildPhotoAttachmentPreview(message);
      } else if (hasContact) {
        return _buildContactAttachmentPreview(message);
      } else {
        final attachmentText = _getAttachmentTypeText(message.attaches);

        return Text(
          attachmentText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      }
    }

    // Для поиска выделяем найденный текст
    return _buildHighlightedText(message.text, matchedText);
  }

  Widget _buildCallPreview(
    Map<String, dynamic> callAttach,
    Message message,
    Chat chat,
  ) {
    final colors = Theme.of(context).colorScheme;
    final hangupType = callAttach['hangupType'] as String? ?? '';
    final callType = callAttach['callType'] as String? ?? 'AUDIO';
    final duration = callAttach['duration'] as int? ?? 0;

    String callText;
    IconData callIcon;
    Color? callColor;

    switch (hangupType) {
      case 'HUNGUP':
        final minutes = duration ~/ 60000;
        final seconds = (duration % 60000) ~/ 1000;
        final durationText = minutes > 0
            ? '$minutes:${seconds.toString().padLeft(2, '0')}'
            : '$seconds сек';

        final callTypeText = callType == 'VIDEO' ? 'Видеозвонок' : 'Звонок';
        callText = '$callTypeText, $durationText';
        callIcon = callType == 'VIDEO' ? Icons.videocam : Icons.call;
        callColor = colors.primary;
        break;

      case 'MISSED':
        final callTypeText = callType == 'VIDEO'
            ? 'Пропущенный видеозвонок'
            : 'Пропущенный звонок';
        callText = callTypeText;
        callIcon = callType == 'VIDEO' ? Icons.videocam_off : Icons.call_missed;
        callColor = colors.error;
        break;

      case 'CANCELED':
        if (duration > 0) {
          final minutes = duration ~/ 60000;
          final seconds = (duration % 60000) ~/ 1000;
          final durationText = minutes > 0
              ? '$minutes:${seconds.toString().padLeft(2, '0')}'
              : '$seconds сек';
          final callTypeText = callType == 'VIDEO' ? 'Видеозвонок' : 'Звонок';
          callText = '$callTypeText, $durationText';
        } else {
          final callTypeText = callType == 'VIDEO'
              ? 'Видеозвонок отменен'
              : 'Звонок отменен';
          callText = callTypeText;
        }
        callIcon = callType == 'VIDEO' ? Icons.videocam_off : Icons.call_end;
        callColor = colors.onSurfaceVariant;
        break;

      case 'REJECTED':
        if (duration > 0) {
          final minutes = duration ~/ 60000;
          final seconds = (duration % 60000) ~/ 1000;
          final durationText = minutes > 0
              ? '$minutes:${seconds.toString().padLeft(2, '0')}'
              : '$seconds сек';
          final callTypeText = callType == 'VIDEO' ? 'Видеозвонок' : 'Звонок';
          callText = '$callTypeText, $durationText';
        } else {
          final callTypeText = callType == 'VIDEO'
              ? 'Видеозвонок отклонен'
              : 'Звонок отклонен';
          callText = callTypeText;
        }
        callIcon = callType == 'VIDEO' ? Icons.videocam_off : Icons.call_end;
        callColor = colors.onSurfaceVariant;
        break;

      default:
        callText = callType == 'VIDEO' ? 'Видеозвонок' : 'Звонок';
        callIcon = callType == 'VIDEO' ? Icons.videocam : Icons.call;
        callColor = colors.onSurfaceVariant;
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(callIcon, size: 16, color: callColor),
        const SizedBox(width: 4),
        Text(
          callText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: callColor),
        ),
      ],
    );
  }

  Widget _buildChatListItem(Chat chat, int index, ChatFolder? currentFolder) {
    final isDismissing = _dismissingChats.contains(chat.id);
    final child = _buildChatListItemContent(chat, index, currentFolder);
    return ShatterAnimation(
      key: ValueKey('shatter_${chat.id}'),
      shatter: isDismissing,
      duration: const Duration(milliseconds: 700),
      onComplete: () {},
      child: child,
    );
  }

  Widget _buildChatListItemContent(Chat chat, int index, ChatFolder? currentFolder) {
    final colors = Theme.of(context).colorScheme;

    final bool isSavedMessages = _isSavedMessages(chat);
    final bool isGroupChat = _isGroupChat(chat);
    final bool isChannel = chat.type == 'CHANNEL';

    Contact? contact;
    String title;
    final String? avatarUrl;
    IconData leadingIcon;

    if (isSavedMessages) {
      contact = _contacts[chat.ownerId];
      title = "Избранное";
      leadingIcon = Icons.bookmark;
      avatarUrl = null;
    } else if (isChannel) {
      contact = null;
      title = chat.title ?? "Канал";
      leadingIcon = Icons.campaign;
      avatarUrl = chat.baseIconUrl;
    } else if (isGroupChat) {
      contact = null;
      title = chat.title?.isNotEmpty == true
          ? chat.title!
          : "Группа (${chat.participantIds.length} участников)";
      leadingIcon = Icons.group;
      avatarUrl = chat.baseIconUrl;
    } else {
      final otherParticipantId = chat.participantIds.firstWhere(
        (id) => id != _myId,
        orElse: () => _myId,
      );
      contact = _contacts[otherParticipantId];

      if (contact != null) {
        title = getContactDisplayName(
          contactId: contact.id,
          originalName: contact.name,
          originalFirstName: contact.firstName,
          originalLastName: contact.lastName,
        );
      } else if (chat.title?.isNotEmpty == true) {
        title = chat.title!;
      } else {
        title = "Данные загружаются...";
        _loadMissingContact(otherParticipantId);
      }
      avatarUrl = contact?.photoBaseUrl;
      leadingIcon = Icons.person;
    }

    return GestureDetector(
      onLongPress: () => _showChatContextMenu(chat, currentFolder),
      child: ListTile(
      key: ValueKey(chat.id),
      onTap: () {
        print('🔘 onTap вызван для чата: ${chat.id}');
        final chatIndex = _allChats.indexWhere((c) => c.id == chat.id);
        if (chatIndex != -1) {
          final oldChat = _allChats[chatIndex];
          if (oldChat.newMessages > 0) {
            final updatedChat = oldChat.copyWith(newMessages: 0);
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _allChats[chatIndex] = updatedChat;
                _filterChats();
                setState(() {});
              }
            });
          }
        }

        final Contact contactFallback = isSavedMessages
            ? Contact(
                id: chat.id,
                name: "Избранное",
                firstName: "",
                lastName: "",
                photoBaseUrl: null,
                description: null,
                isBlocked: false,
                isBlockedByMe: false,
              )
            : contact ??
                  Contact(
                    id: chat.id,
                    name: title,
                    firstName: "",
                    lastName: "",
                    photoBaseUrl: avatarUrl,
                    description: isChannel ? chat.description : null,
                    isBlocked: false,
                    isBlockedByMe: false,
                  );

        final participantCount =
            chat.participantsCount ?? chat.participantIds.length;

        if (widget.isForwardMode && widget.onForwardChatSelected != null) {
          widget.onForwardChatSelected!(chat);
        } else if (widget.onChatSelected != null) {
          widget.onChatSelected!(
            chat,
            contactFallback,
            isGroupChat,
            isChannel,
            participantCount,
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                chatId: chat.id,
                contact: contactFallback,
                // Используем ID из профиля или запасной вариант через API сервис
                myId:
                    _myProfile?.id ??
                    int.tryParse(ApiService.instance.userId ?? '0') ??
                    0,
                pinnedMessage: chat.pinnedMessage,
                isGroupChat: isGroupChat,
                isChannel: isChannel,
                participantCount: participantCount,
                onLastMessageChanged: (Message? newLastMessage) {
                  _updateChatLastMessage(chat.id, newLastMessage);
                },
                onDraftChanged: (int chatId, Map<String, dynamic>? draft) {
                  _updateChatDraft(chatId, draft);
                },
                onChatRemoved: () {
                  _removeChatLocally(chat.id);
                },
              ),
            ),
          );
        }
      },
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onLongPress: () => _showMessagePreview(chat, currentFolder),
            child: (isSavedMessages || isGroupChat || isChannel)
                ? CircleAvatar(
                    radius: 24,
                    backgroundColor: colors.primaryContainer,
                    backgroundImage: avatarUrl != null
                        ? CachedNetworkImageProvider(avatarUrl)
                        : null,
                    child: avatarUrl == null
                        ? Icon(leadingIcon, color: colors.onPrimaryContainer)
                        : null,
                  )
                : contact != null
                ? ContactAvatarWidget(
                    contactId: contact.id,
                    originalAvatarUrl: contact.photoBaseUrl,
                    radius: 24,
                    fallbackText: title.isNotEmpty ? title[0].toUpperCase() : '?',
                    backgroundColor: colors.primaryContainer,
                  )
                : ContactAvatarWidget(
                    contactId: chat.id,
                    originalAvatarUrl: avatarUrl,
                    radius: 24,
                    fallbackText: title.isNotEmpty ? title[0].toUpperCase() : '?',
                    backgroundColor: colors.primaryContainer,
                  ),
          ),
          Positioned(
            right: -4,
            bottom: -2,
            child: _typingChats.contains(chat.id)
                ? TypingDots(color: colors.primary, size: 20)
                : (_onlineChats.contains(chat.id)
                      ? const PresenceDot(isOnline: true, size: 12)
                      : const SizedBox.shrink()),
          ),
        ],
      ),
      title: Row(
        children: [
          if (isGroupChat) ...[
            Icon(Icons.group, size: 16, color: colors.onSurfaceVariant),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: _buildChatSubtitle(chat),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatTimestamp(chat.lastMessage.time),
            style: TextStyle(
              color: chat.newMessages > 0
                  ? colors.primary
                  : colors.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          if (chat.newMessages > 0 && !isSavedMessages) ...[
            const SizedBox(height: 4),
            CircleAvatar(
              radius: 10,
              backgroundColor: colors.primary,
              child: Text(
                chat.newMessages.toString(),
                style: TextStyle(color: colors.onPrimary, fontSize: 12),
              ),
            ),
          ] else if (chat.isPinned && chat.newMessages == 0) ...[
            const SizedBox(height: 4),
            Icon(
              Icons.push_pin,
              size: 14,
              color: colors.onSurfaceVariant,
            ),
          ],
        ],
      ),
    ),
    );
  }

  void _showChatContextMenu(Chat chat, ChatFolder? currentFolder) {
    final bool isGroupChat = _isGroupChat(chat);
    final bool isChannel = chat.type == 'CHANNEL';
    final bool isSavedMessages = _isSavedMessages(chat);

    // Получаем контакт для личных чатов (нужен для блокировки)
    Contact? contact;
    if (!isGroupChat && !isChannel && !isSavedMessages) {
      final otherParticipantId = chat.participantIds.firstWhere(
        (id) => id != _myId,
        orElse: () => 0,
      );
      contact = _contacts[otherParticipantId];
    }

    final String chatTitle = isSavedMessages
        ? 'Избранное'
        : isChannel
        ? (chat.title ?? 'Канал')
        : isGroupChat
        ? (chat.title ?? 'Группа')
        : contact?.name ?? chat.title ?? 'Чат';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colors = Theme.of(ctx).colorScheme;
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).padding.bottom + 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                    // Удалить чат / Покинуть канал / Удалить канал
                    if (isChannel)
                      ListTile(
                        leading: Icon(Icons.delete_outline, color: colors.error),
                        title: Text(
                          chat.ownerId == _myId ? 'Удалить канал' : 'Покинуть канал',
                          style: TextStyle(color: colors.error),
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          if (chat.ownerId == _myId) {
                            _confirmDeleteChannel(chat, chatTitle);
                          } else {
                            _confirmLeaveChannel(chat, chatTitle);
                          }
                        },
                      )
                    else
                      ListTile(
                        leading: Icon(Icons.delete_outline, color: colors.error),
                        title: Text('Удалить чат', style: TextStyle(color: colors.error)),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _confirmDeleteChat(chat, chatTitle);
                        },
                      ),
                    ListTile(
                      leading: Icon(
                        _archivedChats.contains(chat.id)
                            ? Icons.unarchive_outlined
                            : Icons.archive_outlined,
                        color: colors.onSurface,
                      ),
                      title: Text(
                        _archivedChats.contains(chat.id) ? 'Разархивировать' : 'В архив',
                        style: TextStyle(color: colors.onSurface),
                      ),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _toggleArchive(chat);
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.visibility_off_outlined, color: colors.error),
                      title: Text('Не показывать этот чат больше', style: TextStyle(color: colors.error)),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _showGetoutDialog(chat);
                      },
                    ),
                    // Заблокировать — только для личных чатов
                    if (!isGroupChat && !isChannel && !isSavedMessages && contact != null)
                      ListTile(
                        leading: Icon(Icons.block, color: colors.error),
                        title: Text(
                          contact.isBlockedByMe ? 'Разблокировать' : 'Заблокировать',
                          style: TextStyle(color: colors.error),
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _confirmBlockContact(contact!, chatTitle);
                        },
                      ),
                    const Divider(height: 1),
                    // Очистить историю
                    if (!isChannel)
                      ListTile(
                        leading: Icon(Icons.cleaning_services_outlined, color: colors.onSurface),
                        title: Text('Очистить историю', style: TextStyle(color: colors.onSurface)),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _confirmClearHistory(chat, chatTitle);
                        },
                      ),
                    ListTile(
                      leading: chat.isPinned
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: Stack(
                                children: [
                                  Icon(Icons.push_pin, size: 24, color: colors.onSurface),
                                  CustomPaint(
                                    size: const Size(24, 24),
                                    painter: _StrikethroughPainter(color: colors.onSurface),
                                  ),
                                ],
                              ),
                            )
                          : Icon(Icons.push_pin_outlined, color: colors.onSurface),
                      title: Text(
                        chat.isPinned ? 'Открепить' : 'Закрепить',
                        style: TextStyle(color: colors.onSurface),
                      ),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _togglePinChat(chat);
                      },
                    ),
                    // Уведомления
                    ListTile(
                      leading: Icon(Icons.notifications_outlined, color: colors.onSurface),
                      title: Text('Уведомления', style: TextStyle(color: colors.onSurface)),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        showChatNotificationSettings(
                          context: context,
                          chatId: chat.id,
                          chatName: chatTitle,
                          isGroupChat: isGroupChat,
                          isChannel: isChannel,
                        );
                      },
                    ),
                    const Divider(height: 1),
                    // Добавить в папку
                    if (currentFolder == null && _folders.isNotEmpty)
                      ListTile(
                        leading: Icon(Icons.folder_outlined, color: colors.onSurface),
                        title: Text('Добавить в папку', style: TextStyle(color: colors.onSurface)),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showFolderSelectionMenu(chat);
                        },
                      ),
                    // Настройки чтения
                    ListTile(
                      leading: Icon(Icons.mark_chat_read_outlined, color: colors.onSurface),
                      title: Text('Настройки чтения', style: TextStyle(color: colors.onSurface)),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _showReadSettingsDialog(chat);
                      },
                    ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDeleteChat(Chat chat, String chatTitle) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить чат?'),
        content: Text(
          'Вы уверены, что хотите удалить чат "$chatTitle"? '
          'История сообщений будет удалена без возможности восстановления.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await ApiService.instance.clearChatHistory(chat.id);
                _removeChatLocally(chat.id);
              } catch (e) {
                if (mounted) {
                  final msg = e.toString().replaceFirst('Exception: ', '');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(msg)),
                  );
                }
              }
            },
            child: Text('Удалить', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  void _confirmClearHistory(Chat chat, String chatTitle) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить историю?'),
        content: Text(
          'Вы уверены, что хотите очистить историю чата "$chatTitle"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ApiService.instance
                  .clearChatHistory(chat.id)
                  .catchError((e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ошибка очистки истории')),
                      );
                    }
                  });
            },
            child: Text('Очистить', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  void _confirmBlockContact(Contact contact, String chatTitle) {
    final isBlocked = contact.isBlockedByMe;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isBlocked ? 'Разблокировать?' : 'Заблокировать?'),
        content: Text(
          isBlocked
              ? 'Разблокировать пользователя "$chatTitle"?'
              : 'Заблокировать пользователя "$chatTitle"? Он не сможет отправлять вам сообщения.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final future = isBlocked
                  ? ApiService.instance.unblockContact(contact.id)
                  : ApiService.instance.blockContact(contact.id);
              future.catchError((e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isBlocked ? 'Ошибка разблокировки' : 'Ошибка блокировки',
                      ),
                    ),
                  );
                }
              });
            },
            child: Text(
              isBlocked ? 'Разблокировать' : 'Заблокировать',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  /// Диалог удаления канала — только для владельца
  void _confirmDeleteChannel(Chat chat, String chatTitle) {
    final otherParticipants = chat.participantIds
        .where((id) => id != _myId)
        .toList();
    final hasParticipants = otherParticipants.isNotEmpty;

    showDialog(
      context: context,
      builder: (ctx) => _DeleteChannelDialog(
        chatTitle: chatTitle,
        hasParticipants: hasParticipants,
        onTransfer: () {
          Navigator.of(ctx).pop();
          _showTransferOwnershipPicker(chat, chatTitle);
        },
        onDelete: () {
          Navigator.of(ctx).pop();
          _doDeleteChannel(chat);
        },
        onCancel: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  /// Выполнить удаление канала (opcode 52)
  void _doDeleteChannel(Chat chat) {
    ApiService.instance.deleteChannel(chat.id).then((_) {
      _removeChatLocally(chat.id);
    }).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    });
  }

  /// Показать пикер выбора нового владельца
  void _showTransferOwnershipPicker(Chat chat, String chatTitle) {
    // Получаем участников канала кроме себя
    final otherParticipants = chat.participantIds
        .where((id) => id != _myId)
        .toList();

    if (otherParticipants.isEmpty) {
      // Нет других участников — просто удаляем
      _doDeleteChannel(chat);
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Передать права владельца'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: otherParticipants.length,
            itemBuilder: (context, index) {
              final participantId = otherParticipants[index];
              final contact = _contacts[participantId];
              final name = contact?.name ?? participantId.toString();
              return ListTile(
                title: Text(name),
                onTap: () {
                  Navigator.of(ctx).pop();
                  ApiService.instance
                      .transferChannelOwnership(chat.id, participantId)
                      .then((_) {
                        ApiService.instance.leaveChat(chat.id).then((_) {
                          _removeChatLocally(chat.id);
                        });
                      })
                      .catchError((e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                e.toString().replaceFirst('Exception: ', ''),
                              ),
                            ),
                          );
                        }
                      });
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
  }

  /// Диалог выхода из канала (не владелец)
  void _confirmLeaveChannel(Chat chat, String chatTitle) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Покинуть канал?'),
        content: Text('Вы хотите покинуть канал "$chatTitle"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ApiService.instance.leaveChat(chat.id).then((_) {
                _removeChatLocally(chat.id);
              }).catchError((e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        e.toString().replaceFirst('Exception: ', ''),
                      ),
                    ),
                  );
                }
              });
            },
            child: Text(
              'Покинуть',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final timer in _typingDecayTimers.values) {
      timer.cancel();
    }
    _typingDecayTimers.clear();
    _typingChats.clear();
    _onlineChats.clear();
    _apiSubscription?.cancel();
    _connectionStatusSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _messageHandler?.listen()?.cancel();
    _messageHandler
        ?.dispose(); // Освобождаем ресурсы MessageHandler (debouncer)
    _searchController.dispose();
    _searchFocusNode.dispose();
    // Debouncer очищается автоматически в dispose миксина
    _searchAnimationController.dispose();
    _folderTabController.dispose();
    _contactNamesSubscription?.cancel();
    _readStatusSubscription?.cancel();
    super.dispose();
  }
}

/// Диалог удаления канала с анимацией треска на кнопке "Передать права"
/// если участников нет
class _DeleteChannelDialog extends StatefulWidget {
  final String chatTitle;
  final bool hasParticipants;
  final VoidCallback onTransfer;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  const _DeleteChannelDialog({
    required this.chatTitle,
    required this.hasParticipants,
    required this.onTransfer,
    required this.onDelete,
    required this.onCancel,
  });

  @override
  State<_DeleteChannelDialog> createState() => _DeleteChannelDialogState();
}

class _DeleteChannelDialogState extends State<_DeleteChannelDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  bool _cracked = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: -6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: -3), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -3, end: 3), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 3, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeInOut,
    ));

    _shakeController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _cracked = true);
      }
    });
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _handleTransferTap() {
    if (!widget.hasParticipants) {
      if (!_cracked) {
        _shakeController.forward(from: 0);
      }
      return;
    }
    widget.onTransfer();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Удалить канал?'),
      content: Text('Вы владелец канала "${widget.chatTitle}". Выберите действие:'),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: const Text('Отмена'),
        ),
        // Кнопка "Передать права и выйти" — с анимацией треска если некому передать
        AnimatedBuilder(
          animation: _shakeAnimation,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(_shakeAnimation.value, 0),
              child: child,
            );
          },
          child: AnimatedOpacity(
            opacity: _cracked ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 300),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 300),
              child: _cracked
                  ? const SizedBox.shrink()
                  : TextButton(
                      onPressed: _handleTransferTap,
                      child: Text(
                        'Передать права и выйти',
                        style: TextStyle(
                          color: widget.hasParticipants
                              ? null
                              : colors.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
            ),
          ),
        ),
        TextButton(
          onPressed: widget.onDelete,
          child: Text(
            'Удалить канал',
            style: TextStyle(color: colors.error),
          ),
        ),
      ],
    );
  }
}

class _GetoutDialog extends StatefulWidget {
  final String chatTitle;
  final int delaySeconds;
  final Future<void> Function() onConfirm;

  const _GetoutDialog({
    required this.chatTitle,
    required this.delaySeconds,
    required this.onConfirm,
  });

  @override
  State<_GetoutDialog> createState() => _GetoutDialogState();
}

class _GetoutDialogState extends State<_GetoutDialog>
    with SingleTickerProviderStateMixin {
  int _secondsLeft = 0;
  bool _enabled = false;
  bool _confirming = false;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.delaySeconds;
    _enabled = widget.delaySeconds == 0;

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 50),
    );
    _shakeAnimation = Tween<double>(begin: -1, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.linear),
    );

    if (widget.delaySeconds > 0) {
      _startTimer();
    } else {
      _startShaking();
    }
  }

  void _startTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) {
          _secondsLeft = 0;
          _enabled = true;
          _startShaking();
        }
      });
      return _secondsLeft > 0;
    });
  }

  void _startShaking() {
    _shakeController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('ВЫ УВЕРЕНЫ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Вы больше не сможете видеть чат "${widget.chatTitle}" ни при каких обстоятельствах в этой сессии.',
            style: const TextStyle(fontSize: 14),
          ),
          if (_secondsLeft > 0) ...[
            const SizedBox(height: 12),
            Text(
              'Кнопка станет доступна через $_secondsLeft сек...',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        AnimatedBuilder(
          animation: _shakeAnimation,
          builder: (context, child) {
            final shake = _enabled
                ? _shakeAnimation.value * 3
                : 0.0;
            return Transform.translate(
              offset: Offset(shake, 0),
              child: child,
            );
          },
          child: TextButton(
            onPressed: _enabled && !_confirming
                ? () async {
                    setState(() => _confirming = true);
                    Navigator.of(context).pop();
                    await widget.onConfirm();
                  }
                : null,
            style: TextButton.styleFrom(
              foregroundColor: colors.error,
            ),
            child: Text(
              _secondsLeft > 0 ? 'Я знаю что делаю ($_secondsLeft)' : 'Я знаю что делаю',
            ),
          ),
        ),
      ],
    );
  }
}

class _StrikethroughPainter extends CustomPainter {
  final Color color;
  const _StrikethroughPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.1, size.height * 0.9),
      Offset(size.width * 0.9, size.height * 0.1),
      paint,
    );
  }

  @override
  bool shouldRepaint(_StrikethroughPainter old) => old.color != color;
}
