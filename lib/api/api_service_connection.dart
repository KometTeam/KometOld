part of 'api_service.dart';

extension ApiServiceConnection on ApiService {
  Future<void> _resetSocket({bool close = true}) async {
    _socketConnected = false;
    _isSessionOnline = false;
    _isSessionReady = false;
    _handshakeSent = false;
    if (_onlineCompleter?.isCompleted ?? false) {
      _onlineCompleter = Completer<void>();
    }

    _packetBuffer.reset();

    _socketSubscription?.cancel();
    _socketSubscription = null;

    if (close && _socket != null) {
      try {
        await _socket!.close();
      } catch (e) {
        print('⚠️ Ошибка закрытия сокета: $e');
      }
    }
    _socket = null;
  }

  Future<void> _connectWithFallback() async {
    if (_isConnecting) {
      print('⚠️ Подключение уже в процессе, пропускаем');
      return;
    }

    _isConnecting = true;
    _log('Начало подключения...');
    _updateConnectionState(
      conn_state.ConnectionState.connecting,
      message: 'Подключение к серверу',
    );

    try {
      await _connectToUrl('');
      _connectionLogController.add('✅ Подключено к серверу');
      _updateConnectionState(
        conn_state.ConnectionState.connecting,
        message: 'Соединение установлено, ожидание handshake',
      );
    } catch (e) {
      final errorMessage = '❌ Ошибка: ${e.toString().split(':').first}';
      _connectionLogController.add(errorMessage);
      _healthMonitor.onError(errorMessage);
      _updateConnectionState(
        conn_state.ConnectionState.error,
        message: 'Не удалось подключиться к серверу',
      );
      _stopHealthMonitoring();
      rethrow;
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> _connectToUrl(String url) async {
    await _resetSocket(close: true);
    _currentServerUrl = 'api.oneme.ru:443';
    final bool hadChatsFetched = _chatsFetchedInThisSession;
    final bool hasValidToken = authToken != null;

    if (!hasValidToken) {
      _chatsFetchedInThisSession = false;
    } else {
      _chatsFetchedInThisSession = hadChatsFetched;
    }

    _connectionStatusController.add('connecting');

    _initLz4BlockDecompress();

    try {
      final securityContext = SecurityContext.defaultContext;
      final rawSocket = await Socket.connect('api.oneme.ru', 443);
      _socket = await SecureSocket.secure(
        rawSocket,
        context: securityContext,
        host: 'api.oneme.ru',
        onBadCertificate: (certificate) => true,
      );

      _socketConnected = true;

      _packetBuffer.reset();
      _seq = 0;

      _listen();
      await _sendHandshake();
      _startPinging();
    } catch (e) {
      _socketConnected = false;
      rethrow;
    }
  }

  void _handleSessionTerminated() {
    _isSessionOnline = false;
    _isSessionReady = false;
    _stopHealthMonitoring();
    _updateConnectionState(
      conn_state.ConnectionState.disconnected,
      message: 'Сессия завершена сервером',
    );

    authToken = null;

    clearAllCaches();

    _messageController.add({
      'type': 'session_terminated',
      'message': 'Твоя сессия больше не активна, войди снова',
    });
  }

  void _handleInvalidToken() async {
    _isSessionOnline = false;
    _isSessionReady = false;
    _stopHealthMonitoring();
    _healthMonitor.onError('invalid_token');
    _updateConnectionState(
      conn_state.ConnectionState.error,
      message: 'Недействительный токен',
    );

    authToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('authToken');

    clearAllCaches();

    _socket?.close();
    _socket = null;
    _socketConnected = false;
    _pingTimer?.cancel();

    _messageController.add({
      'type': 'invalid_token',
      'message': 'Токен недействителен, требуется повторная авторизация',
    });
  }

  Future<void> _sendHandshake() async {
    if (_handshakeSent) {
      return;
    }

    final userAgentPayload = await _buildUserAgentPayload();

    final prefs = await SharedPreferences.getInstance();
    final deviceId =
        prefs.getString('spoof_deviceid') ?? generateRandomDeviceId();

    if (prefs.getString('spoof_deviceid') == null) {
      await prefs.setString('spoof_deviceid', deviceId);
    }

    String mtInstanceId = prefs.getString('session_mt_instanceid') ?? '';
    int clientSessionId = prefs.getInt('session_client_session_id') ?? 0;

    if (mtInstanceId.isEmpty || clientSessionId == 0) {
      mtInstanceId = const Uuid().v4();
      clientSessionId = Random().nextInt(100) + 1;
      await prefs.setString('session_mt_instanceid', mtInstanceId);
      await prefs.setInt('session_client_session_id', clientSessionId);
    }

    final payload = {
      'mt_instanceid': mtInstanceId,
      'clientSessionId': clientSessionId,
      'deviceId': deviceId,
      'userAgent': userAgentPayload,
    };


    await _sendMessage(6, payload, requireSessionReady: false);
    _handshakeSent = true;
  }

  void _startPinging() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (timer) async {
      if (_isSessionOnline && _isSessionReady && _isAppInForeground) {
        try {
          await _sendMessage(1, {"interactive": true});
        } catch (e) {
          print('Ошибка отправки ping: $e');
        }
      }
    });
  }

  Future<void> connect() async {
    if (_socketConnected && _isSessionOnline) {
      return;
    }

    if (_isConnecting) {
      print('⚠️ Подключение уже в процессе, пропускаем');
      return;
    }

    _isSessionOnline = false;
    _isSessionReady = false;
    
    clearChatMessageContactCache();
    _missingContactIds.clear();

    _connectionStatusController.add("connecting");
    _updateConnectionState(
      conn_state.ConnectionState.connecting,
      message: 'Инициализация подключения',
    );
    try {
      await _connectWithFallback();
    } catch (e) {
      _reconnect();
    }
  }

  Future<void> reconnect() async {
    _reconnectAttempts = 0;

    _connectionStatusController.add("connecting");
    try {
      await _connectWithFallback();
    } catch (e) {
      _reconnect();
    }
  }

  Future<void> sendFullJsonRequest(String jsonString) async {
    if (!_socketConnected || _socket == null) {
      throw Exception('Socket is not connected. Connect first.');
    }
    try {
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      final opcode = decoded['opcode'];
      final payload = decoded['payload'];
      _log(
        '➡️ SEND: opcode=$opcode, payload=${truncatePayloadObjectForLog(payload)}',
      );
      await _sendMessage(opcode, payload);
    } catch (_) {
      _log('➡️ SEND (raw): $jsonString');
    }
  }

  Future<int> sendRawRequest(int opcode, Map<String, dynamic> payload) async {
    if (!_socketConnected || _socket == null) {
      print('Socket не подключен!');
      throw Exception('Socket is not connected. Connect first.');
    }

    return await _sendMessage(opcode, payload);
  }

  Future<dynamic> sendRequest(
      int opcode,
      Map<String, dynamic> payload, {
        Duration timeout = const Duration(seconds: 30),
      }) async {

    // Не ждем готовности сессии для Opcode 19 (Auth), иначе она будет ждать саму себя
    if (opcode != 19) {
      await waitUntilOnline();
    }

    if (!_socketConnected || _socket == null) {
      throw Exception('Socket is not connected. Connect first.');
    }


    final seq = await _sendMessage(opcode, payload, requireSessionReady: false);

    if (seq == -1) {
      throw Exception('Ошибка отправки сообщения (сокет закрыт или не готов)');
    }

    final completer = _pendingManager.get(seq);

    if (completer == null) {
      // Такое маловероятно, если _sendMessage отработал корректно
      throw Exception('Внутренняя ошибка: запрос не был зарегистрирован');
    }

    return completer.future.timeout(timeout);
  }

  Future<int> sendAndTrackFullJsonRequest(String jsonString) async {
    if (!_socketConnected || _socket == null) {
      throw Exception('Socket is not connected. Connect first.');
    }

    final message = jsonDecode(jsonString) as Map<String, dynamic>;
    final opcode = message['opcode'];
    final payload = message['payload'] as Map<String, dynamic>;

    return await _sendMessage(opcode, payload);
  }


  void _listen() async {
    if (!_socketConnected || _socket == null) {
      return;
    }

    if (_socketSubscription != null) {
      return;
    }

    _socketSubscription = _socket!.listen(
      _handleSocketData, // Метод определен в ApiService (main file)
      onError: (error) {
        print('← ERROR Socket: $error');
        _isSessionOnline = false;
        _isSessionReady = false;
        _socketConnected = false;
        _pendingManager.clearAll(reason: 'Socket error: $error');
        _healthMonitor.onError(error.toString());
        _updateConnectionState(
          conn_state.ConnectionState.error,
          message: error.toString(),
        );
        _reconnect();
      },
      onDone: () {
        print('← Socket closed');
        _isSessionOnline = false;
        _isSessionReady = false;
        _socketConnected = false;
        _pendingManager.clearAll(reason: 'Connection closed');
        _stopHealthMonitoring();
        _updateConnectionState(
          conn_state.ConnectionState.disconnected,
          message: 'Соединение закрыто',
        );
        _reconnect();
      },
      cancelOnError: true,
    );
  }

  void handleSocketMessage(Map<String, dynamic> decodedMessage) {
    try {
      final ver = decodedMessage['ver'] as int?;
      final opcode = decodedMessage['opcode'] as int?;
      final cmd = decodedMessage['cmd'] as int?;
      final seq = decodedMessage['seq'] as int?;
      final payload = decodedMessage['payload'];

      if (opcode == null || cmd == null || seq == null) {
        print(
          '⚠️ Некорректное сообщение: ver=$ver, opcode=$opcode, cmd=$cmd, seq=$seq',
        );
        return;
      }

      final cmdType = (cmd == 0x100 || cmd == 256)
          ? 'OK'
          : (cmd == 0x300 || cmd == 768)
          ? 'ERROR'
          : 'UNKNOWN($cmd)';
      _log(
        '📥 ПОЛУЧЕНО: ver=$ver, cmd=$cmd ($cmdType), seq=$seq, opcode=$opcode',
      );
      if (opcode != 19) {
        final bool shouldLogPayload =
            opcode != 132 &&
            opcode != 48 &&
            opcode != 49;

        if (shouldLogPayload) {
          if (opcode == 129) {
            _log('📥 🔔 OPCODE 129 PAYLOAD: $payload');
          } else {
            _log('📥 PAYLOAD: ${truncatePayloadObjectForLog(payload)}');
          }
        }
      }

      if (opcode == 2) {
        _healthMonitor.onPongReceived();
      }

      // Обновляем кэш профиля при получении push-уведомления opcode 159
      if (opcode == 159 && payload != null) {
        final profileData = payload['profile'] as Map<String, dynamic>?;
        if (profileData != null && _lastChatsPayload != null) {
          _lastChatsPayload!['profile'] = profileData;
          print('🔄 Кэш профиля обновлён из push opcode 159');
        }
      }

      if (cmd == 0x300 || cmd == 768) {
        print('❌ ОШИБКА СЕРВЕРА: opcode=$opcode, seq=$seq');
        print('❌ Детали ошибки: ${truncatePayloadObjectForLog(payload)}');
      }

      if (decodedMessage['opcode'] == 97 &&
          (decodedMessage['cmd'] == 0x100 || decodedMessage['cmd'] == 256) &&
          decodedMessage['payload'] != null &&
          decodedMessage['payload']['token'] != null) {
        if (!_isTerminatingOtherSessions) {
          _handleSessionTerminated();
        }
        return;
      }

      if (decodedMessage['opcode'] == 6 &&
          (decodedMessage['cmd'] == 0x100 || decodedMessage['cmd'] == 256)) {
        _isSessionOnline = true;
        _isSessionReady = false;
        _reconnectDelaySeconds = 2;
        _reconnectAttempts = 0;
        _connectionStatusController.add("authorizing");
        _updateConnectionState(
          conn_state.ConnectionState.connected,
          message: 'Handshake успешен',
        );
        _startHealthMonitoring();

        _startPinging();

        if (authToken != null && !_chatsFetchedInThisSession) {
          unawaited(_sendAuthRequestAfterHandshake());
        } else if (authToken == null) {
          _isSessionReady = true;
          if (_onlineCompleter != null && !_onlineCompleter!.isCompleted) {
            _onlineCompleter!.complete();
          }
        }
      }

      if (decodedMessage['cmd'] == 0x300 || decodedMessage['cmd'] == 768) {
        final error = decodedMessage['payload'];
        final errorMsg = error?['message'] ?? error?['error'] ?? 'server_error';
        print('← ERROR: $errorMsg');
        _healthMonitor.onError(errorMsg);

        if (error != null && error['localizedMessage'] != null) {
          _errorController.add(error['localizedMessage']);
        } else if (error != null && error['message'] != null) {
          _errorController.add(error['message']);
        }

        if (error != null && error['message'] == 'FAIL_WRONG_PASSWORD') {
          _errorController.add('FAIL_WRONG_PASSWORD');
        }

        if (error != null && error['error'] == 'password.invalid') {
          _errorController.add('Неверный пароль');
        }

        if (error != null && error['error'] == 'proto.state') {
          print('⚠️ Ошибка proto.state: сессия не готова для этого запроса');

          if (decodedMessage['opcode'] == 64) {
            final messagePayload = decodedMessage['payload'];
            if (messagePayload != null && messagePayload['message'] != null) {
              final messageData =
              messagePayload['message'] as Map<String, dynamic>;
              final cid = messageData['cid'] as int?;
              if (cid != null) {
                final queueItem = QueueItem(
                  id: 'retry_msg_$cid',
                  type: QueueItemType.sendMessage,
                  opcode: 64,
                  payload: messagePayload,
                  createdAt: DateTime.now(),
                  persistent: true,
                  chatId: messagePayload['chatId'] as int?,
                  cid: cid,
                );
                _queueService.addToQueue(queueItem);
                print('Сообщение возвращено в очередь из-за proto.state');
              }
            }
          }
          return;
        }

        if (error != null && error['error'] == 'login.token') {
          _handleInvalidToken();
          return;
        }

        if (error != null && error['message'] == 'FAIL_WRONG_PASSWORD') {
          _clearAuthToken().then((_) {
            _chatsFetchedInThisSession = false;
            _messageController.add({
              'type': 'invalid_token',
              'message':
              'Токен авторизации недействителен. Требуется повторная авторизация.',
            });
            _reconnect();
          });
          return;
        }
      }

      if (decodedMessage['opcode'] == 18 &&
          (decodedMessage['cmd'] == 0x100 || decodedMessage['cmd'] == 256) &&
          decodedMessage['payload'] != null) {
        final payload = decodedMessage['payload'];
        if (payload['passwordChallenge'] != null) {
          final challenge = payload['passwordChallenge'];
          _currentPasswordTrackId = challenge['trackId'];
          _currentPasswordHint = challenge['hint'];
          _currentPasswordEmail = challenge['email'];

          _messageController.add({
            'type': 'password_required',
            'trackId': _currentPasswordTrackId,
            'hint': _currentPasswordHint,
            'email': _currentPasswordEmail,
          });
          return;
        }
      }

      if (decodedMessage['opcode'] == 22 &&
          (decodedMessage['cmd'] == 0x100 || decodedMessage['cmd'] == 256)) {
        final payload = decodedMessage['payload'];
        _messageController.add({
          'type': 'privacy_settings_updated',
          'settings': payload,
        });
      }

      if (decodedMessage['opcode'] == 116 &&
          (decodedMessage['cmd'] == 0x100 || decodedMessage['cmd'] == 256)) {
        final payload = decodedMessage['payload'];
        _messageController.add({
          'type': 'password_set_success',
          'payload': payload,
        });
      }

      // opcode 112: Начало установки 2FA - получаем trackId
      if (decodedMessage['opcode'] == 112 &&
          (decodedMessage['cmd'] == 0x100 || decodedMessage['cmd'] == 256)) {
        final payload = decodedMessage['payload'];
        _messageController.add({
          'type': '2fa_setup_started',
          'trackId': payload?['trackId'],
          'payload': payload,
        });
      }

      // opcode 107: Пароль 2FA установлен
      if (decodedMessage['opcode'] == 107 &&
          (decodedMessage['cmd'] == 0x100 || decodedMessage['cmd'] == 256)) {
        _messageController.add({
          'type': '2fa_password_set',
          'payload': decodedMessage['payload'],
        });
      }

      // opcode 108: Подсказка 2FA установлена
      if (decodedMessage['opcode'] == 108 &&
          (decodedMessage['cmd'] == 0x100 || decodedMessage['cmd'] == 256)) {
        _messageController.add({
          'type': '2fa_hint_set',
          'payload': decodedMessage['payload'],
        });
      }

      // opcode 109: Email для 2FA установлен, получаем данные для ввода кода
      if (decodedMessage['opcode'] == 109 &&
          (decodedMessage['cmd'] == 0x100 || decodedMessage['cmd'] == 256)) {
        final payload = decodedMessage['payload'];
        _messageController.add({
          'type': '2fa_email_set',
          'blockingDuration': payload?['blockingDuration'],
          'codeLength': payload?['codeLength'],
          'trackId': payload?['trackId'],
          'payload': payload,
        });
      }

      // opcode 110: Email подтверждён
      if (decodedMessage['opcode'] == 110 &&
          (decodedMessage['cmd'] == 0x100 || decodedMessage['cmd'] == 256)) {
        final payload = decodedMessage['payload'];
        _messageController.add({
          'type': '2fa_email_verified',
          'email': payload?['email'],
          'trackId': payload?['trackId'],
          'payload': payload,
        });
      }

      // opcode 111: 2FA успешно установлен
      if (decodedMessage['opcode'] == 111 &&
          (decodedMessage['cmd'] == 0x100 || decodedMessage['cmd'] == 256)) {
        _messageController.add({
          'type': '2fa_setup_complete',
          'payload': decodedMessage['payload'],
        });
      }

      // 2FA Setup error handlers
      if (decodedMessage['cmd'] == 3 &&
          [107, 108, 109, 110, 111, 112].contains(decodedMessage['opcode'])) {
        _messageController.add({
          'type': '2fa_error',
          'opcode': decodedMessage['opcode'],
          'payload': decodedMessage['payload'],
        });
      }

      if (decodedMessage['opcode'] == 57 &&
          (decodedMessage['cmd'] == 0x100 || decodedMessage['cmd'] == 256)) {
        final payload = decodedMessage['payload'];
        _messageController.add({
          'type': 'group_join_success',
          'payload': payload,
        });
      }

      if (decodedMessage['opcode'] == 46 &&
          (decodedMessage['cmd'] == 0x100 || decodedMessage['cmd'] == 256)) {
        final payload = decodedMessage['payload'];
        _messageController.add({'type': 'contact_found', 'payload': payload});
      }

      if (decodedMessage['opcode'] == 46 &&
          (decodedMessage['cmd'] == 0x300 || decodedMessage['cmd'] == 768)) {
        final payload = decodedMessage['payload'];
        _messageController.add({
          'type': 'contact_not_found',
          'payload': payload,
        });
      }

      if (decodedMessage['opcode'] == 32 &&
          (decodedMessage['cmd'] == 0x100 || decodedMessage['cmd'] == 256)) {
        final payload = decodedMessage['payload'];
        _messageController.add({'type': 'channels_found', 'payload': payload});
      }

      if (decodedMessage['opcode'] == 32 &&
          (decodedMessage['cmd'] == 0x300 || decodedMessage['cmd'] == 768)) {
        final payload = decodedMessage['payload'];
        _messageController.add({
          'type': 'channels_not_found',
          'payload': payload,
        });
      }

      // Обработка ответа на loadChat (opcode 49) - обновляем данные чата
      if (decodedMessage['opcode'] == 49 &&
          (decodedMessage['cmd'] == 0x100 || decodedMessage['cmd'] == 256)) {
        final payload = decodedMessage['payload'];
        print('📥 [Connection] Ответ на opcode 49. Ключи payload: ${payload?.keys.toList()}');
        final chat = payload['chat'] as Map<String, dynamic>?;
        
        if (chat != null) {
          print('✅ [Connection] Получены данные чата из opcode 49, обновляем кэш');
          print('   Ключи chat: ${chat.keys.toList()}');
          if (chat.containsKey('admins')) {
            print('   Админы: ${chat['admins']}');
          }
          updateChatInCacheFromJson(chat);
        } else {
          print('⚠️ [Connection] payload[\'chat\'] отсутствует в opcode 49!');
        }
      }

      if (decodedMessage['opcode'] == 89 &&
          (decodedMessage['cmd'] == 0x100 || decodedMessage['cmd'] == 256)) {
        final payload = decodedMessage['payload'];
        final chat = payload['chat'] as Map<String, dynamic>?;

        if (chat != null) {
          final chatType = chat['type'] as String?;
          if (chatType == 'CHAT') {
            _messageController.add({
              'type': 'group_join_success',
              'payload': payload,
            });
          } else {
            _messageController.add({
              'type': 'channel_entered',
              'payload': payload,
            });
          }
        } else {
          _messageController.add({
            'type': 'channel_entered',
            'payload': payload,
          });
        }
      }

      if (decodedMessage['opcode'] == 89 &&
          (decodedMessage['cmd'] == 0x300 || decodedMessage['cmd'] == 768)) {
        final payload = decodedMessage['payload'];
        _messageController.add({'type': 'channel_error', 'payload': payload});
      }

      if (decodedMessage['opcode'] == 57 &&
          (decodedMessage['cmd'] == 0x100 || decodedMessage['cmd'] == 256)) {
        final payload = decodedMessage['payload'];
        _messageController.add({
          'type': 'channel_subscribed',
          'payload': payload,
        });
      }

      if (decodedMessage['opcode'] == 57 &&
          (decodedMessage['cmd'] == 0x300 || decodedMessage['cmd'] == 768)) {
        final payload = decodedMessage['payload'];
        _messageController.add({'type': 'channel_error', 'payload': payload});
      }

      if (decodedMessage['opcode'] == 59 &&
          (decodedMessage['cmd'] == 0x100 || decodedMessage['cmd'] == 256)) {
        final payload = decodedMessage['payload'];
        _messageController.add({'type': 'group_members', 'payload': payload});
      }

      if (decodedMessage['opcode'] == 162 &&
          (decodedMessage['cmd'] == 0x100 || decodedMessage['cmd'] == 256)) {
        final payload = decodedMessage['payload'];
        try {
          final complaintData = ComplaintData.fromJson(payload);
          _messageController.add({
            'type': 'complaints_data',
            'complaintData': complaintData,
          });
        } catch (e) {
          print('← ERROR parsing complaints: $e');
        }
      }

      _messageController.add(decodedMessage);
    } catch (e) {
      print('← ERROR invalid message: $e');
    }
  }

  void _reconnect() {
    if (_isReconnecting) return;

    _isReconnecting = true;
    _reconnectAttempts++;
    _healthMonitor.onReconnect();

    if (_reconnectAttempts > ApiService._maxReconnectAttempts) {
      print("← ERROR max reconnect attempts");
      _connectionStatusController.add("disconnected");
      _isReconnecting = false;
      _updateConnectionState(
        conn_state.ConnectionState.error,
        message: 'Превышено число попыток переподключения',
      );
      return;
    }

    _pingTimer?.cancel();
    _analyticsTimer?.cancel();
    _reconnectTimer?.cancel();
    _socketSubscription?.cancel();
    _socketSubscription = null;

    // Очищаем все pending requests при переподключении
    _pendingManager.clearAll(reason: 'Reconnecting');

    if (_socket != null) {
      try {
        _socket!.close();
      } catch (e) {
        print('⚠️ Ошибка закрытия сокета при переподключении: $e');
      }
      _socket = null;
    }
    _socketConnected = false;

    _isSessionOnline = false;
    _isSessionReady = false;
    _handshakeSent = false;
    if (_onlineCompleter?.isCompleted ?? false) {
      _onlineCompleter = Completer<void>();
    }
    _chatsFetchedInThisSession = false;

    _reconnectDelaySeconds = (_reconnectDelaySeconds * 2).clamp(1, 30);
    final jitter = (DateTime.now().millisecondsSinceEpoch % 1000) / 1000.0;
    final delay = Duration(seconds: _reconnectDelaySeconds + jitter.round());

    _reconnectTimer = Timer(delay, () async {
      _isReconnecting = false;
      _updateConnectionState(
        conn_state.ConnectionState.reconnecting,
        attemptNumber: _reconnectAttempts,
        reconnectDelay: delay,
      );
      try {
        await _connectWithFallback();
      } catch (e) {
        print('Ошибка при автоматическом переподключении: $e');
        if (!_socketConnected) {
          _reconnect();
        }
      }
    });
  }

  void _processMessageQueue() {
    if (_messageQueue.isEmpty) {
      _processQueueService();
      return;
    }
    for (var message in _messageQueue) {
      unawaited(_sendMessage(message['opcode'], message['payload']));
    }
    _messageQueue.clear();
    _processQueueService();
  }

  void _processQueueService() {
    if (!_isSessionReady) {
      print('Сессия не готова, откладываем обработку очереди');
      return;
    }

    final persistentItems = _queueService.getPersistentItems();
    print('Обработка постоянной очереди: ${persistentItems.length} элементов');
    for (var item in persistentItems) {
      if (_queueService.isMessageProcessed(item.id)) {
        print(
          'Сообщение ${item.id} уже было обработано, пропускаем и удаляем из очереди',
        );
        _queueService.removeFromQueue(item.id);
        continue;
      }

      print(
        'Отправляем из очереди: ${item.type.name}, opcode=${item.opcode}, cid=${item.cid}',
      );

      unawaited(
        _sendMessage(item.opcode, item.payload)
            .then((_) {
          print(
            'Сообщение из очереди успешно отправлено, удаляем из очереди: ${item.id}',
          );

          _queueService.markMessageAsProcessed(item.id);
          _queueService.removeFromQueue(item.id);
        })
            .catchError((e) {
          print('Ошибка отправки из очереди: $e, оставляем в очереди');
        }),
      );
    }

    final temporaryItems = _queueService.getTemporaryItems();
    print('Обработка временной очереди: ${temporaryItems.length} элементов');
    for (var item in temporaryItems) {
      if (item.type == QueueItemType.loadChat && item.chatId != null) {
        if (currentActiveChatId == item.chatId) {
          print('Отправляем запрос загрузки чата ${item.chatId} из очереди');
          unawaited(
            _sendMessage(item.opcode, item.payload)
                .then((_) {
              _queueService.removeFromQueue(item.id);
            })
                .catchError((e) {
              print('Ошибка загрузки чата из очереди: $e');
            }),
          );
        } else {
          print(
            'Пользователь больше не в чате ${item.chatId}, удаляем из очереди',
          );
          _queueService.removeFromQueue(item.id);
        }
      }
    }
  }

  void forceReconnect() {
    _pingTimer?.cancel();
    _analyticsTimer?.cancel();
    _reconnectTimer?.cancel();
    if (_socket != null) {
      _socket!.close();
      _socket = null;
    }
    _socketConnected = false;

    // Очищаем все pending requests при принудительном переподключении
    _pendingManager.clearAll(reason: 'Force reconnect');

    _isReconnecting = false;
    _reconnectAttempts = 0;
    _reconnectDelaySeconds = 2;
    _isSessionOnline = false;
    _isSessionReady = false;
    _chatsFetchedInThisSession = false;
    if (_onlineCompleter?.isCompleted ?? false) {
      _onlineCompleter = Completer<void>();
    }

    _messageQueue.clear();
    _presenceData.clear();

    _connectionStatusController.add("connecting");
    _log("Запускаем новую сессию подключения...");

    _connectWithFallback();
  }

  Future<void> performFullReconnection() async {
    try {
      _pingTimer?.cancel();
      _analyticsTimer?.cancel();
      _reconnectTimer?.cancel();

      _socketSubscription?.cancel();
      _socketSubscription = null;

      if (_socket != null) {
        try {
          _socket!.close();
        } catch (e) {
          print('⚠️ Ошибка закрытия сокета при полном переподключении: $e');
        }
        _socket = null;
      }
      _socketConnected = false;

      // Очищаем все pending requests при полном переподключении
      _pendingManager.clearAll(reason: 'Full reconnection');

      _isReconnecting = false;
      _reconnectAttempts = 0;
      _reconnectDelaySeconds = 2;
      _isSessionOnline = false;
      _isSessionReady = false;
      _handshakeSent = false;
      _chatsFetchedInThisSession = false;
      if (_onlineCompleter?.isCompleted ?? false) {
        _onlineCompleter = Completer<void>();
      }
      _seq = 0;

      _lastChatsPayload = null;
      _lastChatsAt = null;

      _connectionStatusController.add("disconnected");

      await connect();

      await Future.delayed(const Duration(milliseconds: 1500));

      if (!_reconnectionCompleteController.isClosed) {
        _reconnectionCompleteController.add(null);
      }
    } catch (e) {
      print("← ERROR full reconnect: $e");
      rethrow;
    }
  }

  void disconnect() {
    _pingTimer?.cancel();
    _analyticsTimer?.cancel();
    _reconnectTimer?.cancel();
    _socketSubscription?.cancel();
    _isSessionOnline = false;
    _isSessionReady = false;
    _handshakeSent = false;
    if (_onlineCompleter?.isCompleted ?? false) {
      _onlineCompleter = Completer<void>();
    }
    _chatsFetchedInThisSession = false;
    _stopHealthMonitoring();
    _updateConnectionState(
      conn_state.ConnectionState.disconnected,
      message: 'Отключено пользователем',
    );

    // Очищаем все pending requests при отключении
    _pendingManager.clearAll(reason: 'Disconnected by user');

    _socket?.close();
    _socket = null;
    _socketConnected = false;
    _socketSubscription = null;

    _connectionStatusController.add("disconnected");
  }
}
