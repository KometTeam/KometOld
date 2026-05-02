import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../../models/message.dart';
import '../../../models/contact.dart';
import '../../../services/chat_cache_service.dart';

/// Состояние загрузки сообщений
enum MessageLoadingState {
  initial,
  loading,
  loaded,
  error,
  loadingMore,
}

/// Контроллер для управления состоянием чата
/// 
/// Вынесен из ChatScreen для разделения логики и UI
class ChatController extends ChangeNotifier {
  final int chatId;
  final bool isGroupChat;
  final bool isChannel;
  
  ChatController({
    required this.chatId,
    this.isGroupChat = false,
    this.isChannel = false,
  });

  // State
  final List<Message> _messages = [];
  MessageLoadingState _loadingState = MessageLoadingState.initial;
  String? _errorMessage;
  final bool _hasMoreMessages = true;
  int? _oldestLoadedTime;
  
  // Pagination
  int _maxViewedIndex = 0;
  
  // Contact cache
  final Map<int, Contact> _contactCache = {};
  final Set<int> _loadingContactIds = {};
  
  // Subscriptions
  StreamSubscription? _messageSubscription;
  bool _isDisposed = false;
  
  // Scroll controller для скролла к сообщениям
  ItemScrollController? _itemScrollController;

  // Getters
  List<Message> get messages => List.unmodifiable(_messages);
  MessageLoadingState get loadingState => _loadingState;
  String? get errorMessage => _errorMessage;
  bool get hasMoreMessages => _hasMoreMessages;
  bool get isLoading => _loadingState == MessageLoadingState.loading;
  bool get isLoadingMore => _loadingState == MessageLoadingState.loadingMore;
  
  /// Инициализация контроллера
  Future<void> initialize() async {
    await _loadCachedMessages();
    await loadMessages();
  }
  
  /// Загрузить кэшированные сообщения
  Future<void> _loadCachedMessages() async {
    try {
      final cached = await ChatCacheService().getCachedChatMessages(chatId);
      if (cached != null && cached.isNotEmpty && _messages.isEmpty) {
        _messages.addAll(cached);
        _oldestLoadedTime = _messages.first.time;
        _loadingState = MessageLoadingState.loaded;
        _notifyListenersSafe();
      }
    } catch (e) {
      print('⚠️ Ошибка загрузки кэшированных сообщений: $e');
    }
  }
  
  /// Загрузить сообщения
  Future<void> loadMessages() async {
    if (_loadingState == MessageLoadingState.loading) return;
    
    _loadingState = MessageLoadingState.loading;
    _errorMessage = null;
    _notifyListenersSafe();
    
    try {
      // TODO: Загрузка с API
      await Future.delayed(const Duration(milliseconds: 500)); // Имитация задержки API
      
      // Загрузить контакты отправителей для группового чата
      if ((isGroupChat || isChannel) && _messages.isNotEmpty) {
        final senderIds = _messages.map((m) => m.senderId).toSet();
        await loadContacts(senderIds.toList());
      }
      
      _loadingState = MessageLoadingState.loaded;
      if (_messages.isNotEmpty) {
        _oldestLoadedTime = _messages.first.time;
      }
    } catch (e) {
      _loadingState = MessageLoadingState.error;
      _errorMessage = e.toString();
    } finally {
      _notifyListenersSafe();
    }
  }
  
  /// Загрузить больше сообщений (пагинация)
  Future<void> loadMoreMessages() async {
    if (_loadingState == MessageLoadingState.loadingMore || 
        !_hasMoreMessages ||
        _oldestLoadedTime == null) {
      return;
    }
    
    _loadingState = MessageLoadingState.loadingMore;
    _notifyListenersSafe();
    
    try {
      // TODO: Загрузка старых сообщений с API
      await Future.delayed(const Duration(milliseconds: 500)); // Имитация задержки API
      
      _loadingState = MessageLoadingState.loaded;
    } catch (e) {
      _loadingState = MessageLoadingState.error;
      _errorMessage = e.toString();
    } finally {
      _notifyListenersSafe();
    }
  }
  
  /// Добавить новое сообщение
  void addMessage(Message message) {
    if (_messages.any((m) => m.id == message.id)) return;
    
    _messages.add(message);
    _messages.sort((a, b) => a.time.compareTo(b.time));
    
    // Загрузить контакт отправителя, если это групповой чат
    if (isGroupChat || isChannel) {
      _loadContactIfNeeded(message.senderId);
    }
    
    unawaited(ChatCacheService().addMessageToCache(chatId, message));
    
    _notifyListenersSafe();
  }
  
  /// Загрузить контакт, если он еще не в кэше
  Future<void> _loadContactIfNeeded(int contactId) async {
    if (_contactCache.containsKey(contactId) || _loadingContactIds.contains(contactId)) {
      return;
    }
    
    _loadingContactIds.add(contactId);
    
    try {
      // TODO: Загрузка контакта с API
      // Например: final contact = await ApiService.instance.getContact(contactId);
      // _contactCache[contactId] = contact;
      // _notifyListenersSafe();
    } finally {
      _loadingContactIds.remove(contactId);
    }
  }
  
  /// Обновить сообщение
  void updateMessage(Message updated) {
    final index = _messages.indexWhere((m) => m.id == updated.id);
    if (index == -1) {
      if (updated.cid != null) {
        final cidIndex = _messages.indexWhere((m) => m.cid == updated.cid);
        if (cidIndex != -1) {
          _messages[cidIndex] = updated;
          unawaited(ChatCacheService().addMessageToCache(chatId, updated));
          _notifyListenersSafe();
        }
      }
      return;
    }
    
    _messages[index] = updated;
    unawaited(ChatCacheService().addMessageToCache(chatId, updated));
    _notifyListenersSafe();
  }
  
  /// Удалить сообщения
  void removeMessages(List<String> messageIds) {
    _messages.removeWhere((m) => messageIds.contains(m.id));
    // Удаляем из кэша по одному
    for (final id in messageIds) {
      unawaited(ChatCacheService().removeMessageFromCache(chatId, id));
    }
    _notifyListenersSafe();
  }
  
  /// Получить контакт по ID (с кэшированием)
  Contact? getContact(int id) {
    return _contactCache[id];
  }
  
  /// Загрузить данные контактов
  Future<void> loadContacts(List<int> ids) async {
    final idsToLoad = ids.where((id) => 
        id != 0 && !_contactCache.containsKey(id) && !_loadingContactIds.contains(id)
    ).toList();
    
    if (idsToLoad.isEmpty) return;
    
    _loadingContactIds.addAll(idsToLoad);
    
    try {
      // TODO: Загрузка контактов с API
      // Например:
      // final contacts = await ApiService.instance.getContacts(idsToLoad);
      // for (final contact in contacts) {
      //   _contactCache[contact.id] = contact;
      // }
      // _notifyListenersSafe();
      await Future.delayed(const Duration(milliseconds: 300)); // Имитация задержки API
    } finally {
      _loadingContactIds.removeAll(idsToLoad);
    }
  }
  
  /// Добавить контакт в кэш
  void addContactToCache(Contact contact) {
    _contactCache[contact.id] = contact;
    _notifyListenersSafe();
  }
  
  /// Отметить прочтение сообщений
  void markAsRead() {
    // TODO: Отправка на сервер
  }
  
  /// Установить scroll controller
  void setScrollController(ItemScrollController controller, ItemPositionsListener listener) {
    _itemScrollController = controller;
  }
  
  /// Скролл к сообщению по ID
  Future<void> scrollToMessage(String messageId) async {
    if (_itemScrollController == null || !_itemScrollController!.isAttached) {
      print('⚠️ ScrollController не готов для скролла к сообщению $messageId');
      return;
    }
    
    // Находим индекс сообщения
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) {
      // Сообщение не найдено, возможно нужно подгрузить историю
      print('⚠️ Сообщение $messageId не найдено для скролла');
      return;
    }
    
    // Вычисляем индекс для reverse списка
    // В ScrollablePositionedList с reverse=true индекс 0 соответствует последнему элементу
    final visualIndex = _messages.length - 1 - index;
    
    // Используем addPostFrameCallback для гарантии, что виджет построен
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_itemScrollController == null || !_itemScrollController!.isAttached) return;
      try {
        _itemScrollController!.jumpTo(index: visualIndex);
      } catch (e) {
        print('⚠️ Ошибка скролла к сообщению: $e');
      }
    });
  }
  
  /// Обновить максимальный просмотренный индекс
  void updateMaxViewedIndex(int index) {
    if (index > _maxViewedIndex) {
      _maxViewedIndex = index;
      
      // Проверяем необходимость подгрузки
      if (_maxViewedIndex >= _messages.length - 10 && _hasMoreMessages) {
        loadMoreMessages();
      }
    }
  }
  
  void _notifyListenersSafe() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }
  
  @override
  void dispose() {
    _isDisposed = true;
    _messageSubscription?.cancel();
    super.dispose();
  }
}
