library;

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gwid/consts.dart';
import 'package:gwid/connection/connection_logger.dart';
import 'package:gwid/connection/connection_state.dart' as conn_state;
import 'package:gwid/connection/health_monitor.dart';
import 'package:gwid/core/server_config.dart';
import 'package:gwid/utils/image_cache_service.dart';
import 'package:gwid/models/call_request.dart';
import 'package:gwid/models/call_response.dart';
import 'package:gwid/models/complaint.dart';
import 'package:gwid/models/contact.dart';
import 'package:gwid/models/message.dart';
import 'package:gwid/models/profile.dart';
import 'package:gwid/models/video_conference.dart';

import 'package:gwid/services/account_manager.dart';
import 'package:gwid/services/avatar_cache_service.dart';
import 'package:gwid/services/cache_service.dart';
import 'package:gwid/services/chat_cache_service.dart';
import 'package:gwid/services/profile_cache_service.dart';
import 'package:gwid/services/message_queue_service.dart';
import 'package:gwid/utils/spoofing_service.dart';
import 'package:gwid/utils/log_utils.dart';
import 'package:gwid/utils/fresh_mode_helper.dart';
import 'package:gwid/utils/device_presets.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'packet_buffer.dart';
import 'protocol_handler.dart';
import 'pending_requests_manager.dart';
import '../screens/chat/widgets/chat_message_item.dart';
part 'api_service_connection.dart';
part 'api_service_auth.dart';
part 'api_service_calls.dart';
part 'api_service_contacts.dart';
part 'api_service_chats.dart';
part 'api_service_search.dart';
part 'api_service_media.dart';
part 'api_service_privacy.dart';
part 'api_service_complaints.dart';


typedef Lz4DecompressFunction =
Int32 Function(
    Pointer<Uint8> src,
    Pointer<Uint8> dst,
    Int32 compressedSize,
    Int32 dstCapacity,
    );
typedef Lz4Decompress =
int Function(
    Pointer<Uint8> src,
    Pointer<Uint8> dst,
    int compressedSize,
    int dstCapacity,
    );

class ApiService {
  ApiService._privateConstructor() {
    _packetBuffer = PacketBuffer();
    _pendingManager = PendingRequestsManager(
      requestTimeout: const Duration(seconds: 30),
      onTimeout: (seq, label) {
        print('⚠️ Запрос seq=$seq${label != null ? " ($label)" : ""} превысил таймаут');
      },
    );
  }
  static final ApiService instance = ApiService._privateConstructor();

  /// Ссылка-приглашение из config.server (заполняется при логине)
  String? serverInviteLink;
  String? serverInviteShort;

  int? _userId;
  int? get myUserId => _userId;
  late int _sessionId;
  int _actionId = 1;
  bool _isColdStartSent = false;
  late int _lastActionTime;

  bool _isAppInForeground = true;

  Socket? _socket;
  StreamSubscription? _socketSubscription;
  Timer? _pingTimer;
  Timer? _analyticsTimer;
  int _seq = 0;

  late final PendingRequestsManager _pendingManager;
  bool _socketConnected = false;
  late final PacketBuffer _packetBuffer;

  DynamicLibrary? _lz4Lib;
  Lz4Decompress? _lz4BlockDecompress;
  bool _lz4InitAttempted = false;

  final StreamController<Contact> _contactUpdatesController =
  StreamController<Contact>.broadcast();
  Stream<Contact> get contactUpdates => _contactUpdatesController.stream;

  final StreamController<String> _errorController =
  StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorController.stream;

  final _reconnectionCompleteController = StreamController<void>.broadcast();
  Stream<void> get reconnectionComplete =>
      _reconnectionCompleteController.stream;

  final Map<String, dynamic> _presenceData = {};
  String? authToken;
  String? userId;

  String? get token => authToken;

  String? _currentPasswordTrackId;
  String? _currentPasswordHint;
  String? _currentPasswordEmail;

  bool _isSessionOnline = false;
  bool _handshakeSent = false;
  Completer<void>? _onlineCompleter;
  final List<Map<String, dynamic>> _messageQueue = [];

  final Map<int, List<Message>> _messageCache = {};

  final Map<int, Contact> _contactCache = {};
  Contact? getCachedContact(int id) => _contactCache[id];

  // Глобальный кэш прочитанности: chatId -> последний прочитанный timestamp (opcode 130)
  final Map<int, int> _peerReadTimestamps = {};
  // Глобальный кэш прочитанности: chatId -> последний прочитанный messageId (opcode 50)
  final Map<int, int> _peerReadMessageIds = {};

  // Глобальный кэш ID наших чатов (обновляется из ChatsScreen)
  final Set<int> _myChatIds = {};
  Set<int> get myChatIds => Set.unmodifiable(_myChatIds);
  void updateMyChatIds(List<int> ids) {
    _myChatIds
      ..clear()
      ..addAll(ids);
  }

  void updatePeerReadTimestamp(int chatId, int timestamp) {
    final current = _peerReadTimestamps[chatId];
    if (current == null || timestamp > current) {
      _peerReadTimestamps[chatId] = timestamp;
    }
  }

  void updatePeerReadMessageId(int chatId, int messageId) {
    final current = _peerReadMessageIds[chatId];
    if (current == null || messageId > current) {
      _peerReadMessageIds[chatId] = messageId;
    }
  }

  bool isPeerRead(int chatId, int messageTime, {int? messageId}) {
    // Проверяем по timestamp (opcode 130)
    final lastReadTs = _peerReadTimestamps[chatId];
    if (lastReadTs != null && messageTime <= lastReadTs) return true;
    // Проверяем по messageId (opcode 50)
    if (messageId != null) {
      final lastReadId = _peerReadMessageIds[chatId];
      if (lastReadId != null && messageId <= lastReadId) return true;
    }
    return false;
  }

  void cacheContact(Map<String, dynamic> contactJson) {
    try {
      final contact = Contact.fromJson(contactJson);
      _contactCache[contact.id] = contact;
    } catch (_) {}
  }

  // Кэш инфо о чатах (opcode 48)
  final Map<int, Map<String, dynamic>> _chatInfoCache = {};

  Map<String, dynamic>? getChatInfo(int chatId) => _chatInfoCache[chatId];

  Future<void> prefetchChatInfo(List<int> chatIds) async {
    if (chatIds.isEmpty) return;
    try {
      // Разбиваем на батчи по 50
      const batchSize = 50;
      for (var i = 0; i < chatIds.length; i += batchSize) {
        final batch = chatIds.sublist(i, (i + batchSize).clamp(0, chatIds.length));
        final response = await sendRequest(48, {'chatIds': batch});
        final chats = response['payload']?['chats'] as List?;
        if (chats == null) continue;
        for (final chat in chats) {
          final chatData = chat as Map<String, dynamic>;
          final id = chatData['id'] as int?;
          if (id != null) _chatInfoCache[id] = chatData;
        }
      }
    } catch (e) {
      debugPrint('prefetchChatInfo error: $e');
    }
  }

  // Настоящие контакты (не REMOVED, не боты) — из opcode 19/32
  final Set<int> _realContactIds = {};

  void setRealContacts(List<Contact> contacts) {
    _realContactIds.clear();
    for (final c in contacts) {
      if (!c.isRemoved && !c.isBot) {
        _realContactIds.add(c.id);
      }
    }
  }

  void addRealContact(int id) => _realContactIds.add(id);
  void removeRealContact(int id) => _realContactIds.remove(id);
  bool isRealContact(int id) => _realContactIds.contains(id);
  final Set<int> _missingContactIds = {};
  DateTime? _lastContactsUpdate;
  static const Duration _contactCacheExpiry = Duration(minutes: 5);

  final CacheService _cacheService = CacheService();
  final AvatarCacheService _avatarCacheService = AvatarCacheService();
  final ChatCacheService _chatCacheService = ChatCacheService();
  final MessageQueueService _queueService = MessageQueueService();
  bool _cacheServicesInitialized = false;

  final ConnectionLogger _connectionLogger = ConnectionLogger();
  final conn_state.ConnectionStateManager _connectionStateManager =
  conn_state.ConnectionStateManager();
  final HealthMonitor _healthMonitor = HealthMonitor();

  String? _currentServerUrl;

  bool _isLoadingBlockedContacts = false;

  bool _isSessionReady = false;
  bool get isSessionReady => _isSessionReady;

  bool _isTerminatingOtherSessions = false;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  final _connectionStatusController = StreamController<String>.broadcast();
  Stream<String> get connectionStatus => _connectionStatusController.stream;

  final _connectionLogController = StreamController<String>.broadcast();
  Stream<String> get connectionLog => _connectionLogController.stream;

  List<LogEntry> get logs => _connectionLogger.logs;

  Stream<conn_state.ConnectionInfo> get connectionState =>
      _connectionStateManager.stateStream;

  Stream<HealthMetrics> get healthMetrics => _healthMonitor.metricsStream;

  final List<String> _connectionLogCache = [];
  List<String> get connectionLogCache => _connectionLogCache;

  bool get isOnline => _isSessionOnline;

  Future<void> waitUntilOnline() async {
    if (_isSessionOnline) return;
    if (_onlineCompleter == null || _onlineCompleter!.isCompleted) {
      _onlineCompleter = Completer<void>();
    }
    return _onlineCompleter!.future;
  }

  bool get isActuallyConnected {
    try {
      if (!_socketConnected || _socket == null || !_isSessionOnline) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  Completer<Map<String, dynamic>>? _inflightChatsCompleter;
  Completer<Map<String, dynamic>>? _authBootstrapCompleter;
  Map<String, dynamic>? _lastChatsPayload;
  DateTime? _lastChatsAt;
  final Duration _chatsCacheTtl = const Duration(seconds: 5);
  bool _chatsFetchedInThisSession = false;

  Map<String, dynamic>? get lastChatsPayload => _lastChatsPayload;

  /// Убирает чат из кэшированного payload чтобы не воскрес после перезапуска
  void removeChatFromLastPayload(int chatId) {
    if (_lastChatsPayload == null) return;
    final chats = _lastChatsPayload!['chats'];
    if (chats is List) {
      chats.removeWhere((c) {
        if (c is Map) return c['id'] == chatId;
        return false;
      });
    }
  }

  /// Сбрасывает флаг загруженных чатов для принудительной перезагрузки
  void resetChatsFetchedFlag() {
    _chatsFetchedInThisSession = false;
  }

  /// Загружает данные конкретного чата с сервера (включая список админов)
  Future<void> loadChatData(int chatId) async {
    try {
      await waitUntilOnline();
      final payload = {
        'chatId': chatId,
        'from': DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
        'forward': 0,
        'backward': 1, // Запрашиваем хотя бы 1 сообщение, чтобы получить данные чата
        'getMessages': true, // Нужно true, иначе сервер возвращает пустой ответ
      };
      await sendRequest(49, payload); // opcode 49 = loadChat
      print('📥 [ApiService] Запрошены данные чата $chatId (opcode 49)');
    } catch (e) {
      print('❌ [ApiService] Ошибка загрузки данных чата $chatId: $e');
      rethrow;
    }
  }

  /// Получает детальную информацию о канале (opcode 48)
  Future<Map<String, dynamic>?> getChannelDetails(int chatId) async {
    try {
      await waitUntilOnline();
      
      final payload = {
        'chatIds': [chatId],
      };

      final response = await sendRequest(48, payload).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Таймаут получения деталей канала');
        },
      );
      
      // Проверяем ответ
      final cmd = response['cmd'] as int?;
      if (cmd != 0x100 && cmd != 256) {
        return null;
      }
      
      final responsePayload = response['payload'] as Map<String, dynamic>?;
      if (responsePayload == null) {
        print('❌ [ApiService] Пустой payload в ответе');
        return null;
      }
      
      final chats = responsePayload['chats'] as List<dynamic>?;
      if (chats == null || chats.isEmpty) {
        print('❌ [ApiService] Нет чатов в ответе');
        return null;
      }
      
      final chat = chats[0] as Map<String, dynamic>;
      if (chat['id'] != chatId) {
        return null;
      }
      return chat;
    } on TimeoutException catch (e) {
      print('⏱️ [ApiService] Таймаут получения деталей канала $chatId: $e');
      return null;
    } catch (e, stackTrace) {
      print('❌ [ApiService] Ошибка получения деталей канала $chatId: $e');
      print('❌ [ApiService] Stack trace: $stackTrace');
      return null;
    }
  }

  void updateChatInListLocally(
      int chatId,
      Map<String, dynamic> messageJson, [
        Map<String, dynamic>? chatJson,
      ]) {
    try {
      _lastChatsPayload ??= {
        'chats': <dynamic>[],
        'contacts': <dynamic>[],
        'profile': null,
        'presence': null,
        'config': null,
      };

      final chats = _lastChatsPayload!['chats'] as List<dynamic>;
      final existingIndex = chats.indexWhere(
            (c) => c is Map && c['id'] == chatId,
      );

      if (existingIndex != -1) {
        final chat = Map<String, dynamic>.from(chats[existingIndex] as Map);
        chat['lastMessage'] = messageJson;

        final currentUserId = userId;
        final newMessageSenderId = messageJson['sender'];
        final isMyMessage =
            currentUserId != null &&
                (newMessageSenderId.toString() == currentUserId ||
                    chat['ownerId'] == newMessageSenderId);

        if (!isMyMessage) {
          final currentCount = chat['newMessages'] as int? ?? 0;
          chat['newMessages'] = currentCount + 1;
        }

        chats[existingIndex] = chat;

        _emitLocal({
          'ver': 11,
          'cmd': 0,
          'seq': -1,
          'opcode': 64,
          'payload': {'chatId': chatId, 'chat': chat},
        });
      } else if (chatJson != null) {
        chats.insert(0, chatJson);

        _emitLocal({
          'ver': 11,
          'cmd': 0,
          'seq': -1,
          'opcode': 64,
          'payload': {'chatId': chatId, 'chat': chatJson},
        });
      }
    } catch (e) {
      _log('Ошибка обновления чата в списке', level: LogLevel.error, data: {'error': e.toString()});
    }
  }

  int _reconnectDelaySeconds = 2;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 1000;
  Timer? _reconnectTimer;
  bool _isReconnecting = false;
  bool _isConnecting = false;

  int? currentActiveChatId;

  bool get isConnecting {
    if (_isConnecting || _isReconnecting) return true;
    final state = _connectionStateManager.currentInfo.state;
    return state == conn_state.ConnectionState.connecting ||
        state == conn_state.ConnectionState.reconnecting ||
        state == conn_state.ConnectionState.connected;
  }

  void _log(
      String message, {
        LogLevel level = LogLevel.info,
        String category = 'API',
        Map<String, dynamic>? data,
      }) {
    _connectionLogCache.add(message);
    if (!_connectionLogController.isClosed) {
      _connectionLogController.add(message);
    }
    _connectionLogger.log(
      message,
      level: level,
      category: category,
      data: data,
    );
  }

  void _emitLocal(Map<String, dynamic> frame) {
    try {
      _messageController.add(frame);
    } catch (e) {
      _log('Ошибка отправки сообщения в контроллер', level: LogLevel.error, data: {'error': e.toString()});
    }
  }

  String generateRandomDeviceId() {
    final random = Random();
    final bytes = List<int>.generate(8, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<void> clearSessionValues() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('session_mt_instanceid');
    await prefs.remove('session_client_session_id');
  }

  Future<Map<String, dynamic>> _buildUserAgentPayload() async {
    final spoofedData = await SpoofingService.getSpoofedSessionData();

    if (spoofedData != null) {
      return {
        'deviceType': spoofedData['device_type'] as String? ?? 'ANDROID',
        'locale': spoofedData['locale'] as String? ?? 'ru',
        'deviceLocale': spoofedData['locale'] as String? ?? 'ru',
        'osVersion': spoofedData['os_version'] as String? ?? 'Android 14',
        'deviceName':
        spoofedData['device_name'] as String? ?? 'Samsung Galaxy S23',
        'appVersion': spoofedData['app_version'] as String? ?? '25.21.3',
        'screen': spoofedData['screen'] as String? ?? 'xxhdpi 480dpi 1080x2340',
        'timezone': spoofedData['timezone'] as String? ?? 'Europe/Moscow',
        'pushDeviceType': 'GCM',
        'arch': spoofedData['arch'] as String? ?? 'arm64-v8a',
        'buildNumber': spoofedData['build_number'] as int? ?? 6498,
      };
    } else {
      await _generateAndSaveRandomSpoofing();
      final generatedData = await SpoofingService.getSpoofedSessionData();

      if (generatedData != null) {
        return {
          'deviceType': generatedData['device_type'] as String? ?? 'ANDROID',
          'locale': generatedData['locale'] as String? ?? 'ru',
          'deviceLocale': generatedData['locale'] as String? ?? 'ru',
          'osVersion': generatedData['os_version'] as String? ?? 'Android 14',
          'deviceName':
          generatedData['device_name'] as String? ?? 'Samsung Galaxy S23',
          'appVersion': generatedData['app_version'] as String? ?? '25.21.3',
          'screen':
          generatedData['screen'] as String? ?? 'xxhdpi 480dpi 1080x2340',
          'timezone': generatedData['timezone'] as String? ?? 'Europe/Moscow',
          'pushDeviceType': 'GCM',
          'arch': generatedData['arch'] as String? ?? 'arm64-v8a',
          'buildNumber': generatedData['build_number'] as int? ?? 6498,
        };
      }

      return {
        'deviceType': 'ANDROID',
        'locale': 'ru',
        'deviceLocale': 'ru',
        'osVersion': 'Android 14',
        'deviceName': 'Samsung Galaxy S23',
        'appVersion': SpoofingService.hardcodedAppVersion,
        'screen': 'xxhdpi 480dpi 1080x2340',
        'timezone': 'Europe/Moscow',
        'pushDeviceType': 'GCM',
        'arch': 'arm64-v8a',
        'buildNumber': 6498,
      };
    }
  }

  Future<void> _generateAndSaveRandomSpoofing() async {
    final prefs = await SharedPreferences.getInstance();

    if (prefs.getBool('spoofing_enabled') == true) {
      return;
    }

    final availablePresets = devicePresets
        .where((p) => p.deviceType == 'ANDROID')
        .toList();

    if (availablePresets.isEmpty) {
      return;
    }

    final random = Random();
    final preset = availablePresets[random.nextInt(availablePresets.length)];

    String timezone;
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      timezone = timezoneInfo.identifier;
    } catch (_) {
      timezone = preset.timezone;
    }

    final locale = Platform.localeName.split('_').first;

    final deviceId = generateRandomDeviceId();

    await prefs.setBool('spoofing_enabled', true);
    await prefs.setString('spoof_devicename', preset.deviceName);
    await prefs.setString('spoof_osversion', preset.osVersion);
    await prefs.setString('spoof_screen', preset.screen);
    await prefs.setString('spoof_timezone', timezone);
    await prefs.setString('spoof_locale', locale);
    await prefs.setString('spoof_deviceid', deviceId);
    await prefs.setString('spoof_devicetype', preset.deviceType);
    await prefs.setString('spoof_appversion', SpoofingService.hardcodedAppVersion);
    await prefs.setString('spoof_arch', 'arm64-v8a');
    await prefs.setInt('spoof_buildnumber', 6498);

    print(
      '✅ Автоматически сгенерирован спуфинг: ${preset.deviceType} - ${preset.deviceName}',
    );
  }

  bool get isAppInForeground => _isAppInForeground;

  void setAppInForeground(bool isForeground) {
    _isAppInForeground = isForeground;
  }

  void _updateConnectionState(
      conn_state.ConnectionState state, {
        String? message,
        int? attemptNumber,
        Duration? reconnectDelay,
        int? latency,
        Map<String, dynamic>? metadata,
      }) {
    _connectionStateManager.setState(
      state,
      message: message,
      attemptNumber: attemptNumber,
      reconnectDelay: reconnectDelay,
      serverUrl: _currentServerUrl,
      latency: latency,
      metadata: metadata,
    );
  }

  void _startHealthMonitoring() {
    _healthMonitor.startMonitoring(serverUrl: _currentServerUrl);
  }

  void _stopHealthMonitoring() {
    _healthMonitor.stopMonitoring();
  }

  Future<void> initialize() async {
    await _ensureCacheServicesInitialized();
  }

  Future<void> _ensureCacheServicesInitialized() async {
    if (_cacheServicesInitialized) return;
    await Future.wait([
      _cacheService.initialize(),
      _avatarCacheService.initialize(),
      _chatCacheService.initialize(),
      ImageCacheService.instance.initialize(),
    ]);
    _cacheServicesInitialized = true;
  }

  Future<String?> getClipboardData() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  void _initLz4BlockDecompress() {
    if (_lz4BlockDecompress != null || _lz4InitAttempted) return;
    _lz4InitAttempted = true;

    try {
      if (!Platform.isWindows) return;

      const dllPath = 'eslz4-win64.dll';
      _lz4Lib = DynamicLibrary.open(dllPath);
      try {
        _lz4BlockDecompress = _lz4Lib!
            .lookup<NativeFunction<Lz4DecompressFunction>>(
          'LZ4_decompress_safe',
        )
            .asFunction();
      } catch (_) {
        try {
          _lz4BlockDecompress = _lz4Lib!
              .lookup<NativeFunction<Lz4DecompressFunction>>(
            'LZ4_decompress_fast',
          )
              .asFunction();
        } catch (e) {
          print(
            'LZ4 DLL loaded, but no supported decompress symbol found. '
            'Using Dart fallback: $e',
          );
        }
      }
    } catch (e) {
      // Optional optimization only; message decoding continues via Dart fallback.
      print('LZ4 DLL unavailable, using Dart fallback: $e');
    }
  }

  //  обработка входящих данных
  void _handleSocketData(Uint8List data) {
    _processIncomingData(data);
  }

  void _processIncomingData(Uint8List newData) {
    // Добавляем новые данные в буфер (БЕЗ пересоздания массива!)
    _packetBuffer.append(newData);

    // Обрабатываем все полные пакеты из буфера
    while (true) {
      // Пытаемся прочитать заголовок
      final headerBytes = _packetBuffer.peek(ProtocolHandler.headerSize);
      if (headerBytes == null) break; // Недостаточно данных для заголовка

      // Парсим длину payload из заголовка
      final payloadLen = ProtocolHandler.tryParseHeader(headerBytes);
      if (payloadLen == null) break; // Некорректный заголовок

      // Проверяем, что пришел полный пакет
      final fullPacketSize = ProtocolHandler.headerSize + payloadLen;
      if (_packetBuffer.length < fullPacketSize) break; // Ждем еще данных

      // Извлекаем полный пакет из буфера
      final fullPacket = _packetBuffer.extract(fullPacketSize);
      if (fullPacket == null) break; // Не должно случиться, но на всякий случай

      // Обрабатываем пакет
      _processPacket(fullPacket);
    }
  }

  void _processPacket(Uint8List packet) {
    try {
      final parsed = ProtocolHandler.parsePacket(packet);
      if (parsed == null) {
        print('⚠️ Не удалось распарсить пакет длиной ${packet.length} байт');
        return;
      }

      final message = parsed.toMap();


      if (!_socketConnected) {
        _socketConnected = true;
        _log('🔌 Соединение восстановлено (получены данные)', level: LogLevel.info);
      }

      if (!_isSessionOnline) {
        _isSessionOnline = true;
        if (_onlineCompleter != null && !_onlineCompleter!.isCompleted) {
          _onlineCompleter!.complete();
        }
      }

      // Если получаем данные (opcode 32 - контакты/чаты), значит сессия точно готова
      if (!_isSessionReady && (parsed.opcode == 32 || parsed.opcode == 64 || parsed.opcode == 128)) {
        _isSessionReady = true;
        _updateConnectionState(conn_state.ConnectionState.connected,
            message: 'Сессия активна', latency: 0);
        _connectionStatusController.add('connected');
      }

      // Отправляем в стрим
      _emitLocal(message);

      // Завершаем pending только для пакетов-ответов (cmd ∈ {256/0x100=ok, 512/0x200=notFound, 768/0x300=error}).
      // Пуши от сервера приходят с cmd=0/request и могут случайно совпасть по seq c нашим pending,
      // что и приводило к крешам типа `payload=40` — pending получал чужой push вместо ответа.
      final cmd = parsed.cmd;
      final isResponse = cmd == 256 || cmd == 512 || cmd == 768;
      if (isResponse) {
        // Передаем ВЕСЬ message (включая cmd), а не только payload
        _pendingManager.complete(parsed.seq, message);
      }

      try {
        handleSocketMessage(message);
      } catch (e, stackTrace) {
        print('Ошибка вызова handleSocketMessage: $e');
        print('Stack trace: $stackTrace');
      }

    } catch (e, stack) {
      print('❌ Ошибка обработки пакета: $e');
      print(stack);
    }
  }

  Future<Map<String, dynamic>> sendRequest(int opcode, Map<String, dynamic> payload) async {
    // Opcode 19 (auth) и 6 (handshake) создают сессию, они не требуют готовой сессии
    final bool isAuthOpcode = opcode == 19 || opcode == 6;

    if (isAuthOpcode) {
      // Для авторизации достаточно, чтобы сокет был подключен
      await waitUntilOnline();
    } else {
      // Для остальных запросов ждем полной готовности сессии
      await waitUntilOnline();
      if (!_isSessionReady) {
        // Если сессия не готова, ждем (с таймаутом)
        await Future.any([
          Future.doWhile(() async {
            if (_isSessionReady) return false;
            await Future.delayed(const Duration(milliseconds: 50));
            return true;
          }),
          Future.delayed(const Duration(seconds: 10)).then((_) =>
          throw TimeoutException('Session not ready after 10s')
          ),
        ]);
      }
    }

    final seq = _seq++ % 256;

    final completer = _pendingManager.register(
      seq,
      debugLabel: 'opcode_$opcode',
    );

    try {
      final packet = _packPacket(11, 0, seq, opcode, payload);

      _socket?.add(packet);
      _lastActionTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    } catch (e) {
      _pendingManager.completeError(seq, e);
      rethrow;
    }

    final result = await completer.future;
    return result as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sendRequestWithVersion(
    int ver,
    int opcode,
    Map<String, dynamic> payload,
  ) async {
    final bool isAuthOpcode = opcode == 19 || opcode == 6;

    if (isAuthOpcode) {
      await waitUntilOnline();
    } else {
      await waitUntilOnline();
      if (!_isSessionReady) {
        await Future.any([
          Future.doWhile(() async {
            if (_isSessionReady) return false;
            await Future.delayed(const Duration(milliseconds: 50));
            return true;
          }),
          Future.delayed(const Duration(seconds: 10)).then(
            (_) => throw TimeoutException('Session not ready after 10s'),
          ),
        ]);
      }
    }

    final seq = _seq++ % 256;

    final completer = _pendingManager.register(
      seq,
      debugLabel: 'opcode_$opcode',
    );

    try {
      final packet = _packPacket(ver, 0, seq, opcode, payload);
      _socket?.add(packet);
      _lastActionTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    } catch (e) {
      _pendingManager.completeError(seq, e);
      rethrow;
    }

    final result = await completer.future;
    return result as Map<String, dynamic>;
  }

  Uint8List _packPacket(
      int ver,
      int cmd,
      int seq,
      int opcode,
      Map<String, dynamic> payload,
      ) {
    final verB = Uint8List(1)..[0] = ver;
    final cmdB = Uint8List(2)
      ..buffer.asByteData().setUint16(0, cmd, Endian.big);
    final seqB = Uint8List(1)..[0] = seq;
    final opcodeB = Uint8List(2)
      ..buffer.asByteData().setUint16(0, opcode, Endian.big);

    final payloadBytes = msgpack.serialize(payload);
    final payloadLen = payloadBytes.length & 0xFFFFFF;
    final payloadLenB = Uint8List(4)
      ..buffer.asByteData().setUint32(0, payloadLen, Endian.big);

    return Uint8List.fromList(
      verB + cmdB + seqB + opcodeB + payloadLenB + payloadBytes,
    );
  }

  Future<int> _sendMessage(
      int opcode,
      Map<String, dynamic> payload, {
        String? debugLabel,
        bool requireSessionReady = true,
      }) async {


    // Мы принудительно отключаем ожидание сессии для Opcode 19 (Auth) и 6 (Handshake),
    // даже если requireSessionReady = true.
    // Это нужно, потому что эти пакеты и создают сессию.
    final bool isAuthOpcode = opcode == 19 || opcode == 6 || opcode == 17 || opcode == 18;
    final bool shouldWait = requireSessionReady && !isAuthOpcode;

    if (shouldWait) {
      await waitUntilOnline();
      // Дополнительная проверка: если сессия требуется но не готова, ждем
      if (requireSessionReady && !_isSessionReady) {
        print('⏳ _sendMessage opcode=$opcode: ждем готовности сессии...');
        int attempts = 0;
        while (!_isSessionReady && attempts < 50) {
          await Future.delayed(const Duration(milliseconds: 50));
          attempts++;
        }
        if (!_isSessionReady) {
          print('❌ _sendMessage opcode=$opcode: сессия не готова после ожидания, отменяем');
          return -1;
        }
      }
    } else {
      // Для служебных сообщений достаточно проверить подключение сокета
      if (!_socketConnected || _socket == null) {
        print('⚠️ Сокет не подключен, пропускаем opcode=$opcode');
        return -1;
      }
    }

    final seq = _seq++ % 256;

    // Регистрируем pending request ДО отправки
    _pendingManager.register(
      seq,
      debugLabel: debugLabel ?? 'opcode_$opcode',
    );

    try {
      final packet = _packPacket(11, 0, seq, opcode, payload);

      _log('📤 ОТПРАВКА: ver=10, cmd=0, seq=$seq, opcode=$opcode');
      _log('📤 PAYLOAD: ${truncatePayloadObjectForLog(payload)}');
      _log('📤 Размер пакета: ${packet.length} байт');

      _socket?.add(packet);
      _lastActionTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    } catch (e) {
      // Если отправка не удалась, сразу завершаем с ошибкой
      _pendingManager.completeError(seq, e);
      rethrow;
    }

    return seq;
  }



  void dispose() {
    _pingTimer?.cancel();
    _analyticsTimer?.cancel();
    _socketSubscription?.cancel();
    _socket?.close();
    _reconnectionCompleteController.close();
    _messageController.close();

    _pendingManager.dispose();
  }

  Future<void> sendVoiceMessage(
      int chatId, {
        required String localPath,
        required int durationSeconds,
        required int fileSize,
        int? senderId,
        int maxNotReadyRetries = 6,
        Function(double)? onProgress,
      }) async {
    await waitUntilOnline();

    final int cid = DateTime.now().millisecondsSinceEpoch;

    final int seq82 = await _sendMessage(82, {'type': 2, 'count': 1});
    if (seq82 == -1) {
      throw Exception('Не удалось отправить запрос на загрузку аудио (opcode 82)');
    }

    final resp82 = await messages.firstWhere((m) => m['seq'] == seq82);
    final infoList = resp82['payload']?['info'];
    if (infoList is! List || infoList.isEmpty) {
      throw Exception('Неверный ответ на opcode 82: отсутствует info');
    }

    final uploadInfo = infoList.first;
    final String uploadUrl = uploadInfo['url'];
    final dynamic idCandidate =
        uploadInfo['id'] ?? uploadInfo['audioId'] ?? uploadInfo['videoId'];
    if (idCandidate == null || idCandidate is! num) {
      throw Exception('Неверный ответ на opcode 82: отсутствует id/audioId/videoId');
    }

    final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
    request.files.add(await http.MultipartFile.fromPath('file', localPath));
    
    print('🔄 Начинаем загрузку аудио, размер файла: $fileSize bytes');
    if (onProgress != null) {
      onProgress(0.1);
      print('📊 Progress: 10% - начинаем отправку');
    }
    
    final streamed = await request.send();
    
    if (onProgress != null) {
      onProgress(0.3);
      print('📊 Progress: 30% - файл отправлен на сервер');
    }
    
    final httpResp = await http.Response.fromStream(streamed);
    
    if (onProgress != null) {
      onProgress(0.6);
      print('📊 Progress: 60% - получен ответ от сервера');
    }
    
    if (httpResp.statusCode != 200) {
      throw Exception(
        'Ошибка загрузки аудио: ${httpResp.statusCode} ${httpResp.body}',
      );
    }
    
    if (onProgress != null) {
      onProgress(0.8);
      print('📊 Progress: 80% - файл загружен');
    }

    String? token;
    try {
      final decoded = jsonDecode(httpResp.body);
      if (decoded is Map) {
        token = decoded['token']?.toString();
      }
    } catch (e) {
      _log('Ошибка парсинга ответа загрузки аудио', level: LogLevel.warning, data: {'error': e.toString()});
    }

    token ??= uploadInfo['token']?.toString();

    if (token == null || token.isEmpty) {
      throw Exception('Не получен token после загрузки аудио');
    }

    Future<void> trySendWithToken() async {
      final payload = {
        'chatId': chatId,
        'message': {
          'isLive': false,
          'detectShare': false,
          'elements': [],
          'cid': cid,
          'attaches': [
            {
              '_type': 'AUDIO',
              'token': token,
              'count': durationSeconds,
              'size': fileSize,
              'sender': senderId ?? 0,
            },
          ],
        },
        'notify': true,
      };
      clearChatsCache();

      final int seq64 = await _sendMessage(64, payload);
      if (seq64 == -1) {
        throw Exception('Не удалось отправить сообщение (opcode 64)');
      }

      final resp64 = await messages.firstWhere((m) => m['seq'] == seq64);
      final cmd = resp64['cmd'] as int?;
      if (cmd == 0x300 || cmd == 768) {
        final err = resp64['payload'];
        if (err is Map && err['error'] == 'attachment.not.ready') {
          throw err;
        }
        throw Exception(err?.toString() ?? 'Ошибка отправки аудио');
      }
      
      // Финальный прогресс - сообщение отправлено
      if (onProgress != null) {
        onProgress(1.0);
        print('✅ Progress: 100% - сообщение отправлено');
      }
    }

    int attempt = 0;
    while (true) {
      try {
        await trySendWithToken();
        return;
      } catch (e) {
        if (e is Map && e['error'] == 'attachment.not.ready') {
          if (attempt >= maxNotReadyRetries) {
            throw Exception('attachment.not.ready (max retries exceeded)');
          }
          final backoffMs = 250 * (attempt + 1);
          await Future.delayed(Duration(milliseconds: backoffMs));
          attempt += 1;
          continue;
        }
        rethrow;
      }
    }
  }
}
