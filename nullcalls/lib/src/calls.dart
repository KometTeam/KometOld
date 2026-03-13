import 'dart:async';
import 'logger/logger.dart';
import 'protocol/oneme_client.dart';
import 'protocol/calls_client.dart';
import 'models/incoming_call.dart';
import 'connection.dart';
import 'ice/connector.dart';
import 'api/signaling/client.dart';

/// Основной класс для работы со звонками MAX messenger
/// 
/// Использует TCP socket соединение вместо WebSocket
class Calls {
  final OneMeClient _onemeClient = OneMeClient();
  final CallsClient _callsClient = CallsClient();
  
  bool _initialized = false;
  String? _mtInstanceId;
  int? _clientSessionId;
  String? _deviceId;

  final StreamController<IncomingCall> _incomingCallController =
      StreamController.broadcast();

  /// Stream входящих звонков
  Stream<IncomingCall> get onIncomingCall => _incomingCallController.stream;

  /// Инициализирует логгер
  Calls({bool debug = false}) {
    MaxCallsLogger.init(debug: debug);
  }

  /// Устанавливает параметры сессии
  /// 
  /// Эти параметры должны сохраняться между сессиями для одного устройства
  void setSessionParams({
    String? mtInstanceId,
    int? clientSessionId,
    String? deviceId,
  }) {
    _mtInstanceId = mtInstanceId;
    _clientSessionId = clientSessionId;
    _deviceId = deviceId;
  }

  /// Запрашивает код верификации
  /// 
  /// [phoneNumber] - номер телефона в международном формате
  /// 
  /// Возвращает токен верификации для последующего вызова enterCode()
  Future<String> requestVerification(String phoneNumber) async {
    MaxCallsLogger.info('Requesting verification for $phoneNumber');

    await _onemeClient.connect();
    await _onemeClient.sendClientHello(
      mtInstanceId: _mtInstanceId,
      clientSessionId: _clientSessionId,
      deviceId: _deviceId,
    );

    final token = await _onemeClient.requestVerification(phoneNumber);
    return token;
  }

  /// Вводит код верификации для завершения авторизации
  /// 
  /// [verificationToken] - токен из requestVerification()
  /// [code] - код из SMS
  Future<void> enterCode(String verificationToken, String code) async {
    MaxCallsLogger.info('Entering verification code');

    final authToken = await _onemeClient.enterCode(verificationToken, code);
    await _initialize(authToken);
  }

  /// Авторизуется с существующим токеном
  /// 
  /// [authToken] - сохраненный токен авторизации
  Future<void> loginWithToken(String authToken) async {
    MaxCallsLogger.info('Logging in with existing token');

    await _onemeClient.connect();
    await _onemeClient.sendClientHello(
      mtInstanceId: _mtInstanceId,
      clientSessionId: _clientSessionId,
      deviceId: _deviceId,
    );
    await _initialize(authToken);
  }

  /// Инициализирует клиент после авторизации
  Future<void> _initialize(String authToken) async {
    // Синхронизируем чаты
    await _onemeClient.syncChats(authToken);

    // Получаем токен для звонков
    final callToken = await _onemeClient.getCallToken();

    // Авторизуемся в Calls API
    await _callsClient.login(callToken);

    _initialized = true;
    MaxCallsLogger.info('Calls client initialized');

    // Перенаправляем входящие звонки
    _onemeClient.onIncomingCall.listen((incomingCall) {
      _incomingCallController.add(incomingCall);
    });
  }

  /// Совершает исходящий звонок
  /// 
  /// [userId] - ID пользователя в MAX messenger
  /// [isVideo] - включить видео (по умолчанию false)
  /// 
  /// Возвращает Connection для работы со звонком
  Future<Connection> call(
    String userId, {
    bool isVideo = false,
  }) async {
    if (!_initialized) {
      throw StateError('Calls client not initialized. Call login() first.');
    }

    MaxCallsLogger.info('Starting outgoing call to $userId');

    // 1. Начинаем conversation через Calls API
    final conversationInfo = await _callsClient.startConversation(
      userId,
      isVideo: isVideo,
    );

    try {
      // 2. Создаем signaling client
      final signalingClient = SignalingClient();
      await signalingClient.connect(
        conversationInfo.endpoint,
        '', // token передается в URL endpoint
      );

      // 3. Создаем ICE connector и устанавливаем WebRTC соединение
      final connector = IceConnector();
      await connector.initialize(
        stunServers: conversationInfo.stunUrls,
        turnServers: conversationInfo.turnUrls,
        turnUsername: conversationInfo.turnUsername,
        turnPassword: conversationInfo.turnPassword,
      );

      // 4. Устанавливаем медиа (аудио/видео)
      await connector.setupLocalMedia(audio: true, video: isVideo);

      // 5. Создаем Connection
      final connection = Connection(
        connector: connector,
        localStream: connector.localStream,
        remoteStream: connector.remoteStream,
      );

      MaxCallsLogger.info('Outgoing call established');
      return connection;
    } catch (e) {
      MaxCallsLogger.error('Failed to establish outgoing call', e);
      rethrow;
    }
  }

  /// Ожидает входящий звонок и устанавливает соединение
  /// 
  /// Блокируется до получения входящего звонка
  /// 
  /// Возвращает Connection для работы со звонком
  Future<Connection> waitForCall() async {
    if (!_initialized) {
      throw StateError('Calls client not initialized. Call login() first.');
    }

    MaxCallsLogger.info('Waiting for incoming call');
    
    // 1. Ждем входящий звонок
    final incomingCall = await onIncomingCall.first;
    
    MaxCallsLogger.info('Received incoming call from ${incomingCall.callerId}');

    try {
      // 2. Создаем signaling client
      final signalingClient = SignalingClient();
      await signalingClient.connect(
        incomingCall.signaling.url,
        incomingCall.signaling.token,
      );

      // 3. Принимаем звонок через signaling
      signalingClient.acceptCall();

      // 4. Создаем ICE connector
      final connector = IceConnector();
      await connector.initialize(
        stunServers: [incomingCall.stun],
        turnServers: incomingCall.turn.servers,
        turnUsername: incomingCall.turn.user,
        turnPassword: incomingCall.turn.password,
      );

      // 5. Устанавливаем медиа
      await connector.setupLocalMedia(audio: true, video: false);

      // 6. Создаем Connection
      final connection = Connection(
        connector: connector,
        localStream: connector.localStream,
        remoteStream: connector.remoteStream,
      );

      MaxCallsLogger.info('Incoming call established');
      return connection;
    } catch (e) {
      MaxCallsLogger.error('Failed to establish incoming call', e);
      rethrow;
    }
  }

  /// Получает external user ID текущего пользователя
  String? get externalUserId => _callsClient.externalUserId;

  /// Закрывает клиент и освобождает ресурсы
  Future<void> close() async {
    MaxCallsLogger.info('Closing Calls client');
    await _onemeClient.close();
    await _incomingCallController.close();
  }
}
