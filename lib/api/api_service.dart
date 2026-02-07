library;

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:gwid/connection/connection_logger.dart';
import 'package:gwid/connection/connection_state.dart' as conn_state;
import 'package:gwid/connection/health_monitor.dart';
import 'package:gwid/utils/image_cache_service.dart';
import 'package:gwid/models/complaint.dart';
import 'package:gwid/models/contact.dart';
import 'package:gwid/models/message.dart';
import 'package:gwid/models/profile.dart';
import 'package:gwid/utils/proxy_service.dart';
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
import 'package:gwid/app_urls.dart';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'packet_buffer.dart';
import 'protocol_handler.dart';
import 'pending_requests_manager.dart';
part 'api_service_connection.dart';
part 'api_service_auth.dart';
part 'api_service_contacts.dart';
part 'api_service_chats.dart';
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

  int? _userId;
  late int _sessionId;
  int _actionId = 1;
  bool _isColdStartSent = false;
  late int _lastActionTime;

  bool _isAppInForeground = true;

  int _currentUrlIndex = 0;
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
    if (_isSessionOnline && _isSessionReady) return;
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
  Map<String, dynamic>? _lastChatsPayload;
  DateTime? _lastChatsAt;
  final Duration _chatsCacheTtl = const Duration(seconds: 5);
  bool _chatsFetchedInThisSession = false;

  Map<String, dynamic>? get lastChatsPayload => _lastChatsPayload;

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
    } catch (e) {}
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
    } catch (_) {}
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
      final String finalDeviceId;
      final String? idFromSpoofing = spoofedData['device_id'] as String?;

      if (idFromSpoofing != null && idFromSpoofing.isNotEmpty) {
        finalDeviceId = idFromSpoofing;
      } else {
        finalDeviceId = generateRandomDeviceId();
      }
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
        'appVersion': '25.21.3',
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
    await prefs.setString('spoof_appversion', '25.21.3');
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
    if (_lz4BlockDecompress != null) return;

    try {
      if (Platform.isWindows) {
        final dllPath = 'eslz4-win64.dll';
        _lz4Lib = DynamicLibrary.open(dllPath);
        try {
          _lz4BlockDecompress = _lz4Lib!
              .lookup<NativeFunction<Lz4DecompressFunction>>(
            'LZ4_decompress_safe',
          )
              .asFunction();
        } catch (e) {
          try {
            _lz4BlockDecompress = _lz4Lib!
                .lookup<NativeFunction<Lz4DecompressFunction>>(
              'LZ4_decompress_fast',
            )
                .asFunction();
          } catch (e2) {}
        }
      }
    } catch (e) {}
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

      // Отправляем в стрим
      _emitLocal(message);

      _pendingManager.complete(parsed.seq, parsed.payload);

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
    final bool shouldWait = requireSessionReady && opcode != 19 && opcode != 6;

    if (shouldWait) {
      await waitUntilOnline();
    } else {
      // Для служебных сообщений достаточно проверить подключение сокета
      if (!_socketConnected || _socket == null) {
        print('⚠️ Сокет не подключен, пропускаем opcode=$opcode');
        return -1;
      }
    }

    final seq = _seq++ % 256;

    // Регистрируем pending request ДО отправки
    final completer = _pendingManager.register(
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

  // Очистка при разрыве соединения (вызывается из api_service_connection.dart)
  void _handleDisconnection() {
    //  Очищаем все ожидающие запросы
    _pendingManager.clearAll(reason: 'Connection lost');

    //  Сбрасываем буфер для экономии памяти
    _packetBuffer.reset();

    _socketConnected = false;
    _isSessionOnline = false;
    _isSessionReady = false;
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
    final streamed = await request.send();
    onProgress?.call(0.0);
    final httpResp = await http.Response.fromStream(streamed);
    onProgress?.call(1.0);
    if (httpResp.statusCode != 200) {
      throw Exception(
        'Ошибка загрузки аудио: ${httpResp.statusCode} ${httpResp.body}',
      );
    }

    String? token;
    try {
      final decoded = jsonDecode(httpResp.body);
      if (decoded is Map) {
        token = decoded['token']?.toString();
      }
    } catch (_) {}

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
