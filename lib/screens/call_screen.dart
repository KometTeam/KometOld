import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:gwid/models/call_response.dart';
import 'package:gwid/api/api_service.dart';
import 'package:gwid/services/floating_call_manager.dart';
import 'package:gwid/services/call_overlay_service.dart';
import 'package:gwid/services/call_recording_service.dart';
import 'package:gwid/services/call_notification_service.dart';
import 'package:gwid/widgets/contact_avatar_widget.dart';
import 'package:gwid/widgets/animated_mesh_gradient.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:crypto/crypto.dart';
import 'dart:io' show Platform;
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Экран активного звонка с WebRTC
class CallScreen extends StatefulWidget {
  final CallResponse callData;
  final String contactName;
  final int contactId;
  final String? contactAvatarUrl;
  final bool isOutgoing;
  final bool isVideo;
  final bool enableDataChannel; // Флаг для включения DataChannel
  final VoidCallback? onMinimize; // Callback для минимизации через Overlay
  final DateTime?
  callStartTime; // Опциональное время начала (для восстановления таймера)

  const CallScreen({
    super.key,
    required this.callData,
    required this.contactName,
    required this.contactId,
    this.contactAvatarUrl,
    required this.isOutgoing,
    this.isVideo = false,
    this.enableDataChannel = false,
    this.onMinimize,
    this.callStartTime,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  // WebRTC
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  RTCDataChannel? _dataChannel;
  OverlayEntry? _dataChannelOverlayEntry;
  final ValueNotifier<bool> _isDataChannelOpenNotifier = ValueNotifier(false);
  final ValueNotifier<String> _dataChannelStatusNotifier = ValueNotifier(
    '⏳ Не инициализирован',
  );
  final ValueNotifier<List<String>> _dataChannelLogsNotifier = ValueNotifier(
    [],
  );
  final ValueNotifier<List<TemporaryChatMessage>>
  _temporaryChatMessagesNotifier = ValueNotifier([]);

  // Геттеры для обратной совместимости
  bool get _isDataChannelOpen => _isDataChannelOpenNotifier.value;
  set _isDataChannelOpen(bool value) =>
      _isDataChannelOpenNotifier.value = value;

  String get _dataChannelStatus => _dataChannelStatusNotifier.value;
  set _dataChannelStatus(String value) =>
      _dataChannelStatusNotifier.value = value;

  List<String> get _dataChannelLogs => _dataChannelLogsNotifier.value;
  List<TemporaryChatMessage> get _temporaryChatMessages =>
      _temporaryChatMessagesNotifier.value;

  // WebSocket signaling
  WebSocketChannel? _signalingChannel;
  StreamSubscription? _signalingSubscription;
  int _sequenceNumber = 1;

  // UI State
  CallState _callState = CallState.connecting;
  bool _isMuted = false;
  bool _blurPanels = true; // По умолчанию включён блюр (TODO: реализовать)
  bool _isSpeakerOn = false;
  double _localAudioLevel =
      0.0; // Уровень громкости локального микрофона (0.0 - 1.0)
  bool _isVideoEnabled = false;
  OverlayEntry? _soundpadOverlay;
  List<Map<String, String>> _soundpadSounds = [];
  AudioPlayer? _soundpadPlayer;
  final GlobalKey _micButtonKey = GlobalKey();

  String? _chatEncryptionPassword;
  encrypt_lib.Encrypter? _chatEncrypter;
  encrypt_lib.IV? _chatIV;

  // Шифрование DataChannel
  bool _isRemoteVideoEnabled = false;
  bool _isRemoteMuted = false;
  int _callDuration = 0;
  Timer? _durationTimer;
  Timer? _connectionCheckTimer;
  DateTime? _lastConnectionCheck;
  late DateTime _callStartTime;

  // Network Info
  NetworkInfo? _networkInfo;
  bool _showNetworkInfo = false;
  Timer? _statsTimer;

  // Participant info
  int? _remoteParticipantInternalId; // INTERNAL ID второго участника

  // Audio level tracking
  bool _isRemoteSpeaking = false;
  Timer? _audioLevelTimer;

  // Cleanup protection
  bool _isCleaningUp = false;

  // Drag to minimize
  double _dragOffset = 0;

  // Call recording
  final CallRecordingService _recordingService = CallRecordingService.instance;
  StreamSubscription<RecordingState>? _recordingSubscription;
  bool _isRecording = false;
  Duration _recordingDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _callStartTime = widget.callStartTime ?? DateTime.now();
    _isVideoEnabled = widget.isVideo;
    _isRemoteVideoEnabled = widget.isVideo;
    _initializeCall();

    // Слушаем изменения FloatingCallManager для разворачивания
    FloatingCallManager.instance.addListener(_onFloatingCallStateChanged);

    // Устанавливаем callback для завершения звонка из панели/кнопки
    FloatingCallManager.instance.onEndCall = _endCall;

    // Подписываемся на события из ongoing-уведомления (кнопки шторки)
    _setupNotificationCallbacks();

    // Инициализируем audio player для саундпада
    _soundpadPlayer = AudioPlayer();

    // Загружаем сохранённые звуки
    _loadSoundpadSounds();

    // Слушаем состояние записи
    _recordingSubscription = _recordingService.recordingState.listen((state) {
      if (mounted) {
        setState(() {
          _isRecording = state.isRecording;
          _recordingDuration = state.duration;
        });
      }
    });
  }

  void _onFloatingCallStateChanged() {
    if (mounted) {
      setState(() {
        // При разворачивании - сбрасываем dragOffset
        if (!FloatingCallManager.instance.isMinimized) {
          _dragOffset = 0;
        }
      });
    }
  }

  Future<void> _initializeCall() async {
    try {
      // Инициализируем рендереры
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      print('📞 Инициализация звонка через WebSocket signaling');
      print('🆔 МОЙ ID: ${widget.callData.internalCallerParams.id.internal}');
      print('🆔 ID СОБЕСЕДНИКА: ${widget.contactId}');
      print('🆔 isOutgoing: ${widget.isOutgoing}');

      // Подключаемся к WebSocket signaling серверу
      await _connectToSignaling();

      // Создаем peer connection
      await _createPeerConnection();

      // Устанавливаем локальный стрим
      await _setupLocalMedia();

      // ИСХОДЯЩИЙ ЗВОНОК: создаем и отправляем offer
      if (widget.isOutgoing) {
        await _createAndSendOffer();
        print('✅ WebRTC инициализирован (исходящий), ожидаем ответа...');
      } else {
        // ВХОДЯЩИЙ ЗВОНОК: отправляем accept-call и ждём offer от звонящего
        _sendAcceptCall();
        print(
          '✅ WebRTC инициализирован (входящий), ожидаем offer от звонящего...',
        );
      }

      setState(() => _callState = CallState.ringing);
      _startDurationTimer();
      _startConnectionCheck();
    } catch (e) {
      print('❌ Ошибка инициализации звонка: $e');
      _showErrorAndClose('Не удалось установить соединение');
    }
  }

  Future<void> _connectToSignaling() async {
    try {
      var wsUrl = widget.callData.internalCallerParams.endpoint;
      print('🔌 Оригинальный endpoint: $wsUrl');

      // Добавляем ОБЯЗАТЕЛЬНЫЕ параметры как у официального клиента!
      final uri = Uri.parse(wsUrl);
      final newUri = uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          'platform': 'WEB',
          'appVersion': '1.1',
          'version': '5',
          'device': 'browser',
          'capabilities': '2A03F',
          'clientType': 'ONE_ME', // КРИТИЧЕСКИ ВАЖНО!
          'tgt': 'start', // ВАЖНО!
        },
      );

      print('🔌 Итоговый URL: $newUri');
      print('🔑 Query params: ${newUri.queryParameters.keys}');

      _signalingChannel = WebSocketChannel.connect(newUri);

      // Слушаем сообщения от сервера СРАЗУ (до ready)
      _signalingSubscription = _signalingChannel!.stream.listen(
        (data) {
          try {
            // Обработка текстовых ping/pong
            if (data == 'ping') {
              print('📩 Получен ping, отправляем pong');
              _signalingChannel!.sink.add('pong');
              return;
            }

            print('📩 RAW WebSocket data: $data');
            final message = json.decode(data as String) as Map<String, dynamic>;
            _handleSignalingMessage(message);
          } catch (e) {
            print('⚠️ Ошибка парсинга signaling сообщения: $e');
            print('⚠️ Data was: $data');
          }
        },
        onError: (error) {
          print('❌ WebSocket ошибка: $error');
          print('❌ Error type: ${error.runtimeType}');
          _showErrorAndClose('Ошибка соединения');
        },
        onDone: () {
          print('🔌 WebSocket закрыт');
          final closeCode = _signalingChannel?.closeCode;
          final closeReason = _signalingChannel?.closeReason;
          print('🔌 Close code: $closeCode');
          print('🔌 Close reason: $closeReason');

          if (_callState != CallState.ended) {
            print('⚠️ WebSocket закрылся неожиданно во время звонка!');
          }
        },
      );

      // Ждем подключения
      await _signalingChannel!.ready;
      print('✅ WebSocket подключен');
      print('🔍 WebSocket readyState: ${_signalingChannel!.closeCode}');
      print('🔍 WebSocket протокол: ${_signalingChannel!.protocol}');

      // Отправляем mediaSettings (как в официальном клиенте!)
      if (widget.isOutgoing) {
        // Для исходящих звонков тоже нужно отправить media settings
        _sendSignalingMessage({
          'command': 'change-media-settings',
          'sequence': _sequenceNumber++,
          'mediaSettings': {
            'isAudioEnabled': true,
            'isVideoEnabled': widget.isVideo,
            'isScreenSharingEnabled': false,
            'isFastScreenSharingEnabled': false,
            'isAudioSharingEnabled': false,
            'isAnimojiEnabled': false,
          },
        });
        print('📤 Отправлены media settings');
      }

      print('⏳ Ожидание входящих сообщений от сервера...');
    } catch (e) {
      print('❌ Ошибка подключения к WebSocket: $e');
      print('❌ Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  void _handleConnectionNotification(Map<String, dynamic> message) {
    try {
      final conversation = message['conversation'] as Map<String, dynamic>?;
      if (conversation == null) {
        print('⚠️ conversation отсутствует в notification:connection');
        return;
      }

      final participants = conversation['participants'] as List<dynamic>?;
      if (participants == null || participants.isEmpty) {
        print('⚠️ participants пуст');
        return;
      }

      final myInternalId = widget.callData.internalCallerParams.id.internal;
      print('🔍 Ищем второго участника. Мой INTERNAL ID: $myInternalId');

      // Ищем второго участника (не меня)
      for (final p in participants) {
        if (p is! Map<String, dynamic>) continue;

        final participantId = p['id'] as int?;
        if (participantId != null && participantId != myInternalId) {
          _remoteParticipantInternalId = participantId;

          final externalId = p['externalId']?['id'] as String?;
          print('✅ Найден второй участник:');
          print('   INTERNAL ID: $participantId');
          print('   EXTERNAL ID: $externalId');
          print('   Мой contactId (external): ${widget.contactId}');
          break;
        }
      }

      if (_remoteParticipantInternalId == null) {
        print('❌ Не удалось найти INTERNAL ID второго участника!');
      }

      // Парсим геолокацию из endpoint
      final endpoint = message['endpoint'] as String?;
      if (endpoint != null) {
        _parseGeoFromEndpoint(endpoint);
      }

      // Парсим TURN/STUN серверы
      final conversationParams =
          message['conversationParams'] as Map<String, dynamic>?;
      if (conversationParams != null) {
        final turn = conversationParams['turn'] as Map<String, dynamic>?;
        final stun = conversationParams['stun'] as Map<String, dynamic>?;

        setState(() {
          _networkInfo ??= NetworkInfo();

          if (turn != null) {
            final urls = turn['urls'] as List<dynamic>?;
            if (urls != null) {
              _networkInfo!.turnServers = urls.cast<String>();
            }
          }

          if (stun != null) {
            final urls = stun['urls'] as List<dynamic>?;
            if (urls != null) {
              _networkInfo!.stunServers = urls.cast<String>();
            }
          }

          print(
            '✅ NetworkInfo обновлен: TURN=${_networkInfo!.turnServers.length}, STUN=${_networkInfo!.stunServers.length}, Geo=${_networkInfo!.remoteGeo}',
          );
        });
      }
    } catch (e) {
      print('❌ Ошибка парсинга connection notification: $e');
    }
  }

  void _parseGeoFromEndpoint(String endpoint) {
    try {
      final uri = Uri.parse(endpoint);
      final params = uri.queryParameters;

      final country = params['locCc'];
      final region = params['locReg'];
      final isp = params['ispAsOrg'];
      final asn = int.tryParse(params['ispAsNo'] ?? '');

      if (country != null || isp != null) {
        setState(() {
          _networkInfo ??= NetworkInfo();
          // Это НАША геолокация (из endpoint в notification connection)
          _networkInfo!.localCountry = country;
          _networkInfo!.localIsp = isp;
          _networkInfo!.localAsn = asn;

          // Формируем полную строку геолокации
          final parts = <String>[];
          if (country != null) parts.add(country);
          if (region != null) parts.add('Region $region');
          if (isp != null) parts.add(isp);

          _networkInfo!.localGeo = parts.isNotEmpty ? parts.join(', ') : null;
        });
      }
    } catch (e) {
      print('⚠️ Ошибка парсинга геолокации из endpoint: $e');
    }
  }

  void _handleSignalingMessage(Map<String, dynamic> message) {
    print(
      '📥 Signaling message type: ${message['type'] ?? message['command'] ?? message['notification']}',
    );
    print(
      '📥 Full message: ${message.toString().substring(0, message.toString().length > 500 ? 500 : message.toString().length)}...',
    );

    // Парсим сетевую информацию из аналитики
    _parseNetworkInfo(message);

    final type = message['type'] as String?;
    final command = message['command'] as String?;

    // Обработка ответов от сервера
    if (type == 'response') {
      final response = message['response'] as String?;
      print('📨 Получен response: $response');

      // Ответ на transmit-data или другие команды
      if (response == 'transmit-data') {
        print('✅ SDP успешно отправлен на сервер');
      }
      return;
    }

    // Обработка notification (от сервера)
    final notification = message['notification'] as String?;
    if (notification != null) {
      print('🔔 Notification: $notification');

      switch (notification) {
        case 'connection':
          // ПЕРВОЕ сообщение от сервера с информацией об участниках!
          print('🎉 Получено notification:connection');
          _handleConnectionNotification(message);
          break;

        case 'transmitted-data':
          // Данные от ДРУГОГО участника (не от нас!)
          final participantId = message['participantId'] as int?;
          final myId = widget.callData.internalCallerParams.id.internal;

          print(
            '🔍 transmitted-data: participantId=$participantId, myId=$myId',
          );

          if (participantId != null && participantId != myId) {
            print('📨 Получены данные от участника $participantId');
            final data = message['data'] as Map<String, dynamic>?;
            if (data != null) {
              print('📦 Data keys: ${data.keys.toList()}');

              // Проверяем есть ли SDP
              if (data.containsKey('sdp')) {
                print('🎯 Получен SDP от участника!');
                _handleRemoteDescription(data['sdp'] as Map<String, dynamic>);
              }
              // Проверяем есть ли ICE candidate
              if (data.containsKey('candidate')) {
                print('🧊 Получен ICE candidate от участника!');
                _handleRemoteCandidate(
                  data['candidate'] as Map<String, dynamic>,
                );
              }
            } else {
              print('⚠️ Data is null!');
            }
          } else {
            print(
              '⏭️ Пропускаем transmitted-data от себя или без participantId',
            );
          }
          break;

        case 'accepted-call':
          print('✅ Звонок принят другим участником!');
          print('⏳ Ожидаем SDP answer от второго участника...');
          // НЕ меняем статус на connected, ждём SDP answer!
          setState(() => _callState = CallState.ringing);
          break;

        case 'hungup':
        case 'closed-conversation':
          print('📴 Звонок завершен собеседником');
          // Защита от двойного вызова
          if (_callState != CallState.ended && !_isCleaningUp) {
            // Убираем уведомление немедленно
            CallNotificationService.instance.cancelOngoingCallNotification();

            // Сначала закрываем панель информации если открыта
            if (_showNetworkInfo && mounted) {
              setState(() => _showNetworkInfo = false);
            }

            if (mounted) {
              setState(() => _callState = CallState.ended);
            }

            // Закрываем UI с небольшой задержкой чтобы UI успел обновиться
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) {
                if (widget.onMinimize != null) {
                  CallOverlayService.instance.closeCall();
                } else {
                  try {
                    Navigator.of(context).pop();
                  } catch (e) {
                    print('❌ Ошибка Navigator.pop: $e');
                  }
                }
              }
            });

            // Cleanup запускаем параллельно, без ожидания и блокировки UI
            Future.delayed(Duration.zero, () {
              _cleanup().catchError((e) {
                print('❌ Ошибка cleanup после hangup: $e');
              });
            });
          }
          break;

        case 'media-settings-changed':
          // Обработка изменения настроек медиа (микрофон/видео собеседника)
          print('🎙️ Получено media-settings-changed');
          final participantId = message['participantId'] as int?;
          final myId = widget.callData.internalCallerParams.id.internal;

          // Обрабатываем только изменения от собеседника, не от себя
          if (participantId != null && participantId != myId) {
            final mediaSettings =
                message['mediaSettings'] as Map<String, dynamic>?;
            if (mediaSettings != null) {
              // Если mediaSettings пустой {}, значит всё выключено
              final isAudioEnabled =
                  mediaSettings['isAudioEnabled'] as bool? ?? false;
              final isVideoEnabled =
                  mediaSettings['isVideoEnabled'] as bool? ?? false;

              print(
                '🔊 Собеседник изменил настройки: audio=$isAudioEnabled, video=$isVideoEnabled',
              );

              if (mounted) {
                setState(() {
                  _isRemoteMuted = !isAudioEnabled;
                  _isRemoteVideoEnabled = isVideoEnabled;
                });
              }
            }
          }
          break;

        case 'settings-update':
          // Получаем лимиты качества от сервера
          print('📊 Получено settings-update');
          final camera = message['camera'] as Map<String, dynamic>?;
          final settings = message['settings'] as Map<String, dynamic>?;

          if (camera != null || settings != null) {
            setState(() {
              _networkInfo ??= NetworkInfo();

              // Лимиты камеры
              if (camera != null) {
                _networkInfo!.maxVideoBitrate = camera['maxBitrateK'] as int?;
                _networkInfo!.maxVideoResolution =
                    camera['maxDimension'] as int?;
              }

              // Пороги качества сети
              if (settings != null) {
                final badNet = settings['badNet'] as Map<String, dynamic>?;
                final goodNet = settings['goodNet'] as Map<String, dynamic>?;

                if (badNet != null) {
                  _networkInfo!.badNetRtt = badNet['rtt'] as int?;
                  _networkInfo!.badNetLoss = (badNet['loss'] as num?)
                      ?.toDouble();
                }
                if (goodNet != null) {
                  _networkInfo!.goodNetRtt = goodNet['rtt'] as int?;
                  _networkInfo!.goodNetLoss = (goodNet['loss'] as num?)
                      ?.toDouble();
                }
              }

              print(
                '✅ Settings-update сохранены: maxBitrate=${_networkInfo!.maxVideoBitrate}, badNetRtt=${_networkInfo!.badNetRtt}',
              );
            });
          }
          break;

        default:
          print('ℹ️ Notification: $notification');
      }
      return;
    }

    // Обработка команд
    switch (command) {
      case 'ping':
        // Отвечаем на ping (JSON формат)
        _sendSignalingMessage({
          'command': 'pong',
          'sequence': _sequenceNumber++,
        });
        break;

      default:
        print('⚠️ Неизвестная команда: $command');
    }
  }

  Future<void> _handleRemoteDescription(Map<String, dynamic> data) async {
    try {
      final sdp = data['sdp'] as String;
      final type = data['type'] as String;

      print('📨 Получен remote SDP ($type), длина: ${sdp.length}');

      final description = RTCSessionDescription(sdp, type);
      await _peerConnection!.setRemoteDescription(description);

      print('✅ Remote description установлен');

      // Если получили offer, нужно создать answer
      if (type == 'offer') {
        print('📤 Создаем answer на полученный offer');
        final answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);

        // Отправляем answer
        _sendCredentials(answer);
        print('✅ Answer отправлен');
      }
    } catch (e) {
      print('❌ Ошибка установки remote description: $e');
    }
  }

  Future<void> _handleRemoteCandidate(Map<String, dynamic> data) async {
    try {
      final candidateStr = data['candidate'] as String;

      print('🧊 Получен remote ICE candidate');

      // Парсим IP собеседника из candidate
      _parseRemoteCandidate(candidateStr);

      final candidate = RTCIceCandidate(
        candidateStr,
        data['sdpMid'] as String?,
        data['sdpMLineIndex'] as int?,
      );

      await _peerConnection!.addCandidate(candidate);

      print('✅ Remote candidate добавлен');
    } catch (e) {
      print('❌ Ошибка добавления remote candidate: $e');
    }
  }

  void _parseRemoteCandidate(String candidateStr) {
    try {
      // Парсим: candidate:ID COMPONENT PROTOCOL PRIORITY IP PORT typ TYPE [raddr RADDR rport RPORT] [generation GEN] [network-id NID] [network-cost COST]
      final parts = candidateStr.split(' ');
      if (parts.length >= 8) {
        final ip = parts[4];
        final port = int.tryParse(parts[5]) ?? 0;
        final priority = int.tryParse(parts[3]) ?? 0;

        String type = 'unknown';
        String? relayServer;
        String? stunServer;
        String? networkId;
        int? networkCost;

        // Ищем тип кандидата
        for (int i = 0; i < parts.length - 1; i++) {
          if (parts[i] == 'typ') {
            type = parts[i + 1];
          } else if (parts[i] == 'raddr' && i + 1 < parts.length) {
            // Адрес через который проходит (для relay/srflx)
            if (type == 'relay') {
              relayServer = parts[i + 1];
            } else if (type == 'srflx') {
              stunServer = parts[i + 1];
            }
          } else if (parts[i] == 'network-id' && i + 1 < parts.length) {
            networkId = parts[i + 1];
          } else if (parts[i] == 'network-cost' && i + 1 < parts.length) {
            networkCost = int.tryParse(parts[i + 1]);
          }
        }

        setState(() {
          _networkInfo ??= NetworkInfo();

          // Добавляем кандидат в список
          final candidate = IceCandidate(
            ip: ip,
            port: port,
            type: type,
            priority: priority,
            networkId: networkId,
            networkCost: networkCost,
            relayServer: relayServer,
            stunServer: stunServer,
          );

          // Избегаем дубликатов
          if (!_networkInfo!.remoteCandidates.any(
            (c) => c.ip == ip && c.port == port,
          )) {
            _networkInfo!.remoteCandidates.add(candidate);
          }

          // Обновляем основной IP (приоритет: srflx > host > relay)
          final shouldUpdate =
              _networkInfo!.remoteAddress == null ||
              (type == 'srflx' &&
                  _networkInfo!.remoteConnectionType != 'srflx') ||
              (type == 'host' && _networkInfo!.remoteConnectionType == 'relay');

          if (shouldUpdate) {
            _networkInfo!.remoteAddress = ip;
            _networkInfo!.remoteConnectionType = type;
            print('Remote IP updated: $ip ($type)');
            SharedPreferences.getInstance().then((prefs) {
              prefs.setString('last_fetched_ip', ip);
              prefs.setString('last_fetched_ip_${widget.contactId}', ip);
            });
          }
        });
      }
    } catch (e) {
      print('Error parsing remote candidate: $e');
    }
  }

  void _sendSignalingMessage(Map<String, dynamic> message) {
    if (_signalingChannel == null) {
      print('⚠️ WebSocket не подключен');
      return;
    }

    final jsonString = json.encode(message);
    _signalingChannel!.sink.add(jsonString);
    print('📤 Отправлено signaling сообщение: ${message['command']}');
  }

  void _sendAcceptCall() {
    print('📞 Отправляем accept-call');
    _sendSignalingMessage({
      'command': 'accept-call',
      'sequence': _sequenceNumber++,
      'mediaSettings': {
        'isAudioEnabled': true,
        'isVideoEnabled': widget.isVideo,
        'isScreenSharingEnabled': false,
        'isFastScreenSharingEnabled': false,
        'isAudioSharingEnabled': false,
        'isAnimojiEnabled': false,
      },
    });
  }

  Future<void> _createPeerConnection() async {
    final configuration = {
      'iceServers': [
        // STUN серверы
        ...widget.callData.internalCallerParams.stun.urls.map(
          (url) => {'urls': url},
        ),
        // TURN серверы
        {
          'urls': widget.callData.internalCallerParams.turn.urls,
          'username': widget.callData.internalCallerParams.turn.username,
          'credential': widget.callData.internalCallerParams.turn.credential,
        },
      ],
      'sdpSemantics': 'unified-plan',
    };

    _peerConnection = await createPeerConnection(configuration);

    print('🔍 DataChannel настройка:');
    print('   enableDataChannel: ${widget.enableDataChannel}');
    print('   isOutgoing: ${widget.isOutgoing}');

    // Создаём DataChannel если включен И это исходящий звонок
    if (widget.enableDataChannel && widget.isOutgoing) {
      print('🔌 Создание DataChannel (исходящий звонок)');
      await _createDataChannel();
    } else if (widget.enableDataChannel && !widget.isOutgoing) {
      print('⏳ Входящий звонок с DataChannel - ожидаем канал от собеседника');
      _addDataChannelLog('⏳ Ожидание DataChannel от собеседника...');
    } else {
      print('❌ DataChannel отключен пользователем');
      _addDataChannelLog('❌ DATA_CHANNEL отключен');
    }

    // Обработчик входящего DataChannel
    _peerConnection!.onDataChannel = (RTCDataChannel channel) {
      print('📥📥📥 ПОЛУЧЕН ВХОДЯЩИЙ DataChannel: ${channel.label}');
      print('   widget.enableDataChannel: ${widget.enableDataChannel}');
      print('   widget.isOutgoing: ${widget.isOutgoing}');

      if (widget.enableDataChannel) {
        print('✅ Принимаем DataChannel');
        _addDataChannelLog('📥 Получен DataChannel от собеседника');
        _setupDataChannel(channel);
      } else {
        print('❌ DataChannel отключен пользователем, закрываем канал');
        channel.close();
        _addDataChannelLog('❌ Отклонено: DATA_CHANNEL отключен');
      }
    };

    // Слушаем ICE candidates
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        print('🧊 Локальный ICE Candidate: ${candidate.candidate}');
        // Отправляем через WebSocket
        _sendIceCandidate(candidate);
      }
    };

    // Слушаем удаленный стрим
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      print('🎥 Получен удаленный трек: ${event.track.kind}');
      if (event.streams.isNotEmpty) {
        setState(() {
          _remoteStream = event.streams[0];
          _remoteRenderer.srcObject = _remoteStream;
          _callState = CallState.connected;
        });

        // Активируем FloatingCallManager чтобы показать панель звонка
        FloatingCallManager.instance.startCall();
        print('✅ FloatingCallManager активирован (onTrack)');

        // Показываем ongoing-уведомление в шторке
        CallNotificationService.instance.showOngoingCallNotification(
          contactName: widget.contactName,
          isMuted: _isMuted,
          durationSec: _callDuration,
        );

        // Начинаем отслеживать уровень звука
        _startAudioLevelMonitoring();
        _startLocalAudioLevelMonitoring();
      }
    };

    // Слушаем состояние соединения
    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      print('🔌 Connection State: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() => _callState = CallState.connected);

        // Активируем FloatingCallManager чтобы показать панель звонка
        FloatingCallManager.instance.startCall();
        print('✅ FloatingCallManager активирован (onConnectionState)');

        // Показываем ongoing-уведомление в шторке (если onTrack не сработал раньше)
        CallNotificationService.instance.showOngoingCallNotification(
          contactName: widget.contactName,
          isMuted: _isMuted,
          durationSec: _callDuration,
        );

        // Получаем первую статистику сразу
        _updateNetworkStats();

        // Запускаем периодическое обновление статистики каждую секунду
        _statsTimer?.cancel();
        _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          _updateNetworkStats();
        });
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _showErrorAndClose('Соединение потеряно');
      }
    };
  }

  Future<void> _setupLocalMedia() async {
    try {
      // Запрашиваем разрешения
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        // Всегда запрашиваем микрофон
        final micPermission = await Permission.microphone.request();
        if (!micPermission.isGranted) {
          throw Exception('Нет разрешения на микрофон');
        }

        // Запрашиваем камеру если нужно видео
        if (widget.isVideo) {
          final cameraPermission = await Permission.camera.request();
          if (!cameraPermission.isGranted) {
            print('⚠️ Нет разрешения на камеру, продолжаем только с аудио');
            setState(() => _isVideoEnabled = false);
          }
        }
      }

      final constraints = {
        'audio': true,
        'video': _isVideoEnabled
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
              }
            : false,
      };

      print('📹 Запрашиваем медиа: audio=true, video=$_isVideoEnabled');
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      _localRenderer.srcObject = _localStream;

      print('✅ Медиа получены: ${_localStream!.getTracks().length} треков');
      _localStream!.getTracks().forEach((track) {
        print('   - ${track.kind}: ${track.id}');
      });

      // Добавляем треки в peer connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('❌ Ошибка получения медиа: $e');

      // Пробуем получить хотя бы аудио
      if (widget.isVideo && _isVideoEnabled) {
        print('⚠️ Пробуем без видео...');
        try {
          _isVideoEnabled = false;
          final audioConstraints = {'audio': true, 'video': false};
          _localStream = await navigator.mediaDevices.getUserMedia(
            audioConstraints,
          );
          _localRenderer.srcObject = _localStream;
          _localStream!.getTracks().forEach((track) {
            _peerConnection!.addTrack(track, _localStream!);
          });
          if (mounted) setState(() {});
        } catch (e2) {
          print('❌ Не удалось получить даже аудио: $e2');
          rethrow;
        }
      } else {
        rethrow;
      }
    }
  }

  Future<void> _createAndSendOffer() async {
    try {
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo':
            true, // Всегда готовы принять видео от собеседника
      });

      await _peerConnection!.setLocalDescription(offer);

      print('📤 SDP Offer создан, длина: ${offer.sdp?.length} символов');

      // Отправляем SDP offer через WebSocket signaling
      _sendCredentials(offer);

      print('✅ SDP offer отправлен через WebSocket');
    } catch (e) {
      print('❌ Ошибка создания/отправки offer: $e');
      rethrow;
    }
  }

  void _sendCredentials(RTCSessionDescription description) {
    // Используем INTERNAL ID второго участника, если получили
    final recipientId = _remoteParticipantInternalId ?? widget.contactId;

    print(
      '📤 Отправляем SDP на participantId=$recipientId (internal=${_remoteParticipantInternalId != null})',
    );

    final message = {
      'command': 'transmit-data',
      'sequence': _sequenceNumber++,
      'participantId': recipientId, // INTERNAL ID собеседника!
      'data': {
        'sdp': {'type': description.type, 'sdp': description.sdp},
        'animojiVersion': 1,
      },
      'participantType': 'USER',
    };

    _sendSignalingMessage(message);
  }

  void _sendIceCandidate(RTCIceCandidate candidate) {
    if (candidate.candidate != null) {
      _parseLocalCandidate(candidate.candidate!);
    }

    // Используем INTERNAL ID второго участника, если получили
    final recipientId = _remoteParticipantInternalId ?? widget.contactId;

    final message = {
      'command': 'transmit-data',
      'sequence': _sequenceNumber++,
      'participantId': recipientId, // INTERNAL ID собеседника!
      'data': {
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      },
      'participantType': 'USER',
    };

    _sendSignalingMessage(message);
  }

  void _parseLocalCandidate(String candidateStr) {
    try {
      final parts = candidateStr.split(' ');
      if (parts.length >= 8) {
        final ip = parts[4];
        final port = int.tryParse(parts[5]) ?? 0;
        final priority = int.tryParse(parts[3]) ?? 0;

        String type = 'unknown';
        String? relayServer;
        String? stunServer;
        String? networkId;
        int? networkCost;

        for (int i = 0; i < parts.length - 1; i++) {
          if (parts[i] == 'typ') {
            type = parts[i + 1];
          } else if (parts[i] == 'raddr' && i + 1 < parts.length) {
            if (type == 'relay') {
              relayServer = parts[i + 1];
            } else if (type == 'srflx') {
              stunServer = parts[i + 1];
            }
          } else if (parts[i] == 'network-id' && i + 1 < parts.length) {
            networkId = parts[i + 1];
          } else if (parts[i] == 'network-cost' && i + 1 < parts.length) {
            networkCost = int.tryParse(parts[i + 1]);
          }
        }

        setState(() {
          _networkInfo ??= NetworkInfo();

          final candidate = IceCandidate(
            ip: ip,
            port: port,
            type: type,
            priority: priority,
            networkId: networkId,
            networkCost: networkCost,
            relayServer: relayServer,
            stunServer: stunServer,
          );

          if (!_networkInfo!.localCandidates.any(
            (c) => c.ip == ip && c.port == port,
          )) {
            _networkInfo!.localCandidates.add(candidate);
          }

          if (type == 'srflx' &&
              (_networkInfo!.localAddress == null ||
                  _networkInfo!.localAddress == '0.0.0.0')) {
            _networkInfo!.localAddress = ip;
            _networkInfo!.localConnectionType = type;
            print('Local public IP: $ip ($type)');
          }
        });
      }
    } catch (e) {
      print('Error parsing local candidate: $e');
    }
  }

  void _parseNetworkInfo(Map<String, dynamic> message) {
    try {
      final items = message['items'] as List<dynamic>?;
      if (items == null) return;

      for (var item in items) {
        if (item is! Map<String, dynamic>) continue;

        final name = item['name'] as String?;

        if (name == 'websocket_connected' ||
            name == 'signaling_connected' ||
            name == 'call_start' ||
            name == 'first_media_received') {
          final localAddress = item['local_address'] as String?;
          final localConnectionType = item['local_connection_type'] as String?;
          final remoteAddress = item['remote_address'] as String?;
          final remoteConnectionType =
              item['remote_connection_type'] as String?;
          final transport = item['transport'] as String?;
          final networkType = item['network_type'] as String?;
          final rtt = item['rtt'] as int?;

          if (localAddress != null || remoteAddress != null) {
            setState(() {
              _networkInfo ??= NetworkInfo();
              if (localAddress != null)
                _networkInfo!.localAddress = localAddress;
              if (localConnectionType != null)
                _networkInfo!.localConnectionType = localConnectionType;
              if (remoteAddress != null)
                _networkInfo!.remoteAddress = remoteAddress;
              if (remoteConnectionType != null)
                _networkInfo!.remoteConnectionType = remoteConnectionType;
              if (transport != null) _networkInfo!.transport = transport;
              if (networkType != null) _networkInfo!.networkType = networkType;
              if (rtt != null) _networkInfo!.rtt = rtt;
            });

            print('Network Info updated:');
            print(
              '   Local: ${_networkInfo!.localAddress} (${_networkInfo!.localConnectionType})',
            );
            print(
              '   Remote: ${_networkInfo!.remoteAddress} (${_networkInfo!.remoteConnectionType})',
            );
            print(
              '   Transport: ${_networkInfo!.transport}, RTT: ${_networkInfo!.rtt}ms',
            );
          }
        }
      }
    } catch (e) {
      print('Error parsing network info: $e');
    }
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_callState == CallState.connected && mounted) {
        setState(() => _callDuration++);
        // Обновляем таймер в ongoing-уведомлении каждую секунду
        CallNotificationService.instance.updateOngoingCallNotification(
          contactName: widget.contactName,
          isMuted: _isMuted,
          durationSec: _callDuration,
        );
      }
    });
  }

  void _startAudioLevelMonitoring() async {
    // Мониторинг уровня звука через WebRTC Stats API
    _audioLevelTimer = Timer.periodic(const Duration(milliseconds: 200), (
      timer,
    ) async {
      if (_peerConnection != null &&
          _remoteStream != null &&
          _callState == CallState.connected &&
          mounted) {
        try {
          // Получаем статистику WebRTC
          final stats = await _peerConnection!.getStats();

          double maxAudioLevel = 0.0;

          // Ищем inbound-rtp аудио трек (входящий звук от собеседника)
          for (final report in stats) {
            if (report.type == 'inbound-rtp' &&
                report.values['kind'] == 'audio') {
              // audioLevel в диапазоне 0.0 - 1.0
              final audioLevel = report.values['audioLevel'];
              if (audioLevel != null && audioLevel is num) {
                maxAudioLevel = audioLevel.toDouble();
              }
              break;
            }
          }

          // Порог для определения речи (можно настроить)
          // audioLevel > 0.01 означает что есть звук
          final isSpeaking = maxAudioLevel > 0.01;

          if (mounted && _isRemoteSpeaking != isSpeaking) {
            setState(() {
              _isRemoteSpeaking = isSpeaking;
            });
          }
        } catch (e) {
          // Игнорируем ошибки получения статистики
          print('Error getting audio level: $e');
        }
      }
    });
  }

  void _startLocalAudioLevelMonitoring() async {
    // Мониторинг уровня локального микрофона
    Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_peerConnection != null && _localStream != null && !_isMuted) {
        try {
          final stats = await _peerConnection!.getStats();

          double maxAudioLevel = 0.0;

          // Ищем outbound-rtp аудио трек (исходящий звук - наш микрофон)
          for (final report in stats) {
            if (report.type == 'media-source' &&
                report.values['kind'] == 'audio') {
              final audioLevel = report.values['audioLevel'];
              if (audioLevel != null && audioLevel is num) {
                maxAudioLevel = audioLevel.toDouble();
              }
              break;
            }
          }

          if (mounted) {
            setState(() {
              _localAudioLevel = maxAudioLevel;
            });
          }
        } catch (e) {
          // Игнорируем ошибки
        }
      } else {
        // Если микрофон выключен - уровень 0
        if (mounted && _localAudioLevel != 0.0) {
          setState(() {
            _localAudioLevel = 0.0;
          });
        }
      }
    });
  }

  void _startConnectionCheck() {
    _lastConnectionCheck = DateTime.now();
    _connectionCheckTimer = Timer.periodic(const Duration(seconds: 5), (
      timer,
    ) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      // Проверяем состояние WebRTC соединения ТОЛЬКО если звонок уже подключён
      if (_peerConnection != null && _callState == CallState.connected) {
        final state = await _peerConnection!.getConnectionState();

        // Если соединение потеряно
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          // Даём 30 секунд на переподключение (было 15)
          final now = DateTime.now();
          if (_lastConnectionCheck != null &&
              now.difference(_lastConnectionCheck!).inSeconds > 30) {
            timer.cancel();
            if (mounted) {
              _showConnectionLostDialog();
            }
          }
        } else {
          // Соединение в порядке - обновляем timestamp
          _lastConnectionCheck = DateTime.now();
        }
      }
    });
  }

  void _showConnectionLostDialog() {
    // Сначала завершаем звонок
    _endCall();

    // Показываем диалог с информацией
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Соединение потеряно'),
          content: const Text(
            'Не удалось поддерживать соединение. Звонок завершён.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Закрываем диалог
                Navigator.of(context).pop(); // Закрываем экран звонка
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  /// Настраиваем callbacks от CallNotificationService (кнопки в шторке).
  void _setupNotificationCallbacks() {
    if (!Platform.isAndroid) return;
    final svc = CallNotificationService.instance;

    // Кнопка «Выкл. микро» / «Вкл. микро» из уведомления
    svc.onCallMuteToggled = (bool isMuted) {
      if (!mounted) return;
      // Приводим состояние в соответствие с запросом из уведомления
      if (_isMuted != isMuted) _toggleMute();
    };

    // Кнопка «Сбросить» из уведомления
    svc.onCallEndedFromNotification = () {
      if (!mounted) return;
      _endCall();
    };
  }

  void _toggleMute() {
    if (_localStream != null) {
      setState(() => _isMuted = !_isMuted);
      final audioTracks = _localStream!.getAudioTracks();
      for (var track in audioTracks) {
        track.enabled = !_isMuted;
      }

      // Отправляем обновление медиа настроек
      _sendSignalingMessage({
        'command': 'change-media-settings',
        'sequence': _sequenceNumber++,
        'mediaSettings': {
          'isAudioEnabled': !_isMuted,
          'isVideoEnabled': _isVideoEnabled,
          'isScreenSharingEnabled': false,
          'isFastScreenSharingEnabled': false,
          'isAudioSharingEnabled': false,
          'isAnimojiEnabled': false,
        },
      });

      // Обновляем ongoing-уведомление с новым состоянием микрофона
      CallNotificationService.instance.updateOngoingCallNotification(
        contactName: widget.contactName,
        isMuted: _isMuted,
        durationSec: _callDuration,
      );
    }
  }

  Future<void> _toggleVideo() async {
    if (_localStream == null || _isCleaningUp) return;

    // Сохраняем новое состояние сразу чтобы избежать мерцания кнопки
    final newVideoState = !_isVideoEnabled;
    if (mounted) setState(() => _isVideoEnabled = newVideoState);

    try {
      if (!newVideoState) {
        // Выключаем видео
        print('📹 Выключаем видео...');
        // Копируем список треков чтобы избежать concurrent modification
        final videoTracks = _localStream!.getVideoTracks().toList();
        for (var track in videoTracks) {
          track.enabled = false;
          await track.stop();
          _localStream!.removeTrack(track);
        }

        // Отправляем обновление медиа настроек
        _sendSignalingMessage({
          'command': 'change-media-settings',
          'sequence': _sequenceNumber++,
          'mediaSettings': {
            'isAudioEnabled': !_isMuted,
            'isVideoEnabled': false,
            'isScreenSharingEnabled': false,
            'isFastScreenSharingEnabled': false,
            'isAudioSharingEnabled': false,
            'isAnimojiEnabled': false,
          },
        });
      } else {
        // Включаем видео
        print('📹 Включаем видео...');

        // Запрашиваем разрешение на камеру
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          final cameraPermission = await Permission.camera.request();
          if (!cameraPermission.isGranted) {
            print('❌ Нет разрешения на камеру');
            return;
          }
        }

        // Получаем видео поток
        final videoStream = await navigator.mediaDevices.getUserMedia({
          'video': {'facingMode': 'user'},
        });

        if (_localStream == null || _isCleaningUp || !mounted) {
          // Если звонок уже завершился - останавливаем треки
          videoStream.getTracks().forEach((t) => t.stop());
          return;
        }

        // Добавляем видео треки в локальный стрим
        final newVideoTracks = videoStream.getVideoTracks();
        for (var track in newVideoTracks) {
          await _localStream!.addTrack(track);

          // Добавляем трек в peer connection
          if (_peerConnection != null) {
            await _peerConnection!.addTrack(track, _localStream!);
          }
        }

        // Обновляем рендерер
        _localRenderer.srcObject = _localStream;

        // Создаём новый offer с видео и отправляем
        if (_peerConnection != null) {
          final offer = await _peerConnection!.createOffer({
            'offerToReceiveAudio': true,
            'offerToReceiveVideo': true,
          });
          await _peerConnection!.setLocalDescription(offer);

          final recipientId = _remoteParticipantInternalId ?? widget.contactId;
          _sendSignalingMessage({
            'command': 'transmit-data',
            'sequence': _sequenceNumber++,
            'participantId': recipientId,
            'data': {
              'sdp': {'type': offer.type, 'sdp': offer.sdp},
            },
            'participantType': 'USER',
          });
          print('✅ Новый offer с видео отправлен');
        }

        // Отправляем обновление медиа настроек
        _sendSignalingMessage({
          'command': 'change-media-settings',
          'sequence': _sequenceNumber++,
          'mediaSettings': {
            'isAudioEnabled': !_isMuted,
            'isVideoEnabled': true,
            'isScreenSharingEnabled': false,
            'isFastScreenSharingEnabled': false,
            'isAudioSharingEnabled': false,
            'isAnimojiEnabled': false,
          },
        });
      }
    } catch (e) {
      print('❌ Ошибка переключения видео: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Не удалось ${_isVideoEnabled ? 'выключить' : 'включить'} видео',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    // TODO: Реализовать переключение динамика через platform channel
  }

  void _showSoundpad() {
    if (_soundpadOverlay != null) {
      _soundpadOverlay?.remove();
      _soundpadOverlay = null;
      return;
    }

    _soundpadOverlay = OverlayEntry(
      builder: (context) {
        // Получаем позицию кнопки микрофона
        final RenderBox? renderBox =
            _micButtonKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox == null) {
          // Если не удалось получить позицию, используем дефолтную
          return const Positioned(
            bottom: 134,
            left: 16,
            child: SizedBox.shrink(),
          );
        }

        final position = renderBox.localToGlobal(Offset.zero);
        final screenHeight = MediaQuery.of(context).size.height;

        return Positioned(
          bottom:
              screenHeight - position.dy + 10, // Над кнопкой с отступом 10px
          left: position.dx, // На той же горизонтальной позиции
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).colorScheme.surface,
            child: Container(
              width: 200,
              constraints: BoxConstraints(maxHeight: 300),
              padding: EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Заголовок
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Саундпад',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        IconButton(
                          icon: Icon(Icons.close, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(),
                          onPressed: () {
                            _soundpadOverlay?.remove();
                            _soundpadOverlay = null;
                          },
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1),

                  // Список звуков
                  Flexible(
                    child: _soundpadSounds.isEmpty
                        ? Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Нет сохранённых звуков',
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _soundpadSounds.length,
                            itemBuilder: (context, index) {
                              final sound = _soundpadSounds[index];
                              return ListTile(
                                dense: true,
                                leading: Icon(Icons.music_note, size: 20),
                                title: Text(
                                  sound['name'] ?? 'Звук ${index + 1}',
                                  style: TextStyle(fontSize: 14),
                                ),
                                onTap: () =>
                                    _playSoundpadSound(sound['path'] ?? ''),
                                onLongPress: () =>
                                    _deleteSoundFromSoundpad(index),
                                trailing: Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                  color: Colors.red.withOpacity(0.5),
                                ),
                              );
                            },
                          ),
                  ),

                  // Кнопка добавления звука
                  Divider(height: 1),
                  TextButton.icon(
                    icon: Icon(Icons.add, size: 18),
                    label: Text('Добавить звук'),
                    onPressed: _addSoundToSoundpad,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_soundpadOverlay!);
  }

  Future<void> _loadSoundpadSounds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final soundsJson = prefs.getString('soundpad_sounds');
      if (soundsJson != null) {
        final List<dynamic> decoded = jsonDecode(soundsJson);
        setState(() {
          _soundpadSounds = decoded
              .map((e) => Map<String, String>.from(e))
              .toList();
        });
      } else {
        // Если нет сохранённых звуков, добавляем пример
        setState(() {
          _soundpadSounds = [];
        });
      }
    } catch (e) {
      print('Error loading soundpad sounds: $e');
    }
  }

  Future<void> _saveSoundpadSounds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final soundsJson = jsonEncode(_soundpadSounds);
      await prefs.setString('soundpad_sounds', soundsJson);
    } catch (e) {
      print('Error saving soundpad sounds: $e');
    }
  }

  Future<void> _playSoundpadSound(String path) async {
    try {
      await _soundpadPlayer?.stop();
      await _soundpadPlayer?.setFilePath(path);
      await _soundpadPlayer?.play();
    } catch (e) {
      print('Error playing sound: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка воспроизведения: $e')));
      }
    }
  }

  Future<void> _addSoundToSoundpad() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final path = file.path;
        final name = file.name;

        if (path != null) {
          setState(() {
            _soundpadSounds.add({'name': name, 'path': path});
          });
          await _saveSoundpadSounds();
        }
      }
    } catch (e) {
      print('Error adding sound: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка добавления звука: $e')));
      }
    }
  }

  Future<void> _deleteSoundFromSoundpad(int index) async {
    setState(() {
      _soundpadSounds.removeAt(index);
    });
    await _saveSoundpadSounds();
  }

  // Шифрование DataChannel чата
  void _showChatEncryptionDialog() {
    final controller = TextEditingController(
      text: _chatEncryptionPassword ?? '',
    );

    // Создаём Overlay Entry для показа поверх экрана звонка
    OverlayEntry? overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Material(
        color: Colors.black54,
        child: Center(
          child: AlertDialog(
            title: Text('🔐 Шифрование чата'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _chatEncryptionPassword == null
                      ? 'Установите пароль для шифрования сообщений'
                      : 'Изменить пароль шифрования',
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: controller,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Пароль',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
              ],
            ),
            actions: [
              if (_chatEncryptionPassword != null)
                TextButton(
                  onPressed: () {
                    overlayEntry?.remove();
                    _setChatEncryptionPassword(null);
                  },
                  child: Text('Отключить', style: TextStyle(color: Colors.red)),
                ),
              TextButton(
                onPressed: () => overlayEntry?.remove(),
                child: Text('Отмена'),
              ),
              ElevatedButton(
                onPressed: () {
                  final password = controller.text.trim();
                  if (password.isEmpty) {
                    return;
                  }
                  overlayEntry?.remove();
                  _setChatEncryptionPassword(password);
                },
                child: Text('OK'),
              ),
            ],
          ),
        ),
      ),
    );

    Overlay.of(context).insert(overlayEntry);
  }

  void _setChatEncryptionPassword(String? password) {
    if (password == null || password.isEmpty) {
      // Отключаем шифрование
      setState(() {
        _chatEncryptionPassword = null;
        _chatEncrypter = null;
        _chatIV = null;
      });

      // Уведомляем собеседника
      if (_dataChannel != null &&
          _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
        _sendDataChannelMessage('Encrypt: false❌️❌️❌️');
      }
    } else {
      // Включаем шифрование
      _setupChatEncryption(password);

      // Уведомляем собеседника
      if (_dataChannel != null &&
          _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
        _sendDataChannelMessage('Encrypt: true✅️');
      }
    }
  }

  void _setupChatEncryption(String password) {
    // Генерируем ключ из пароля через SHA-256
    final keyBytes = sha256.convert(utf8.encode(password)).bytes;
    final key = encrypt_lib.Key(Uint8List.fromList(keyBytes));

    // Используем фиксированный IV (в продакшене лучше генерировать случайный и передавать)
    final iv = encrypt_lib.IV.fromLength(16);

    setState(() {
      _chatEncryptionPassword = password;
      _chatEncrypter = encrypt_lib.Encrypter(encrypt_lib.AES(key));
      _chatIV = iv;
    });
  }

  String _encryptMessage(String text) {
    if (_chatEncrypter == null || _chatIV == null) return text;
    final encrypted = _chatEncrypter!.encrypt(text, iv: _chatIV!);
    return encrypted.base64;
  }

  String _decryptMessage(String encryptedText) {
    if (_chatEncrypter == null || _chatIV == null) return encryptedText;
    final encrypted = encrypt_lib.Encrypted.fromBase64(encryptedText);
    return _chatEncrypter!.decrypt(encrypted, iv: _chatIV!);
  }

  void _showCallSettings() {
    // Получаем Overlay чтобы показать поверх экрана звонка
    final overlayState = Overlay.of(context, rootOverlay: true);

    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) => Material(
        color: Colors.black54,
        child: GestureDetector(
          onTap: () {
            overlayEntry.remove();
          },
          child: Container(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () {}, // Не закрывать при клике на панель
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _CallSettingsPanel(
                  blurPanels: _blurPanels,
                  onBlurPanelsChanged: (value) {
                    setState(() => _blurPanels = value);
                  },
                  onClose: () {
                    overlayEntry.remove();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlayState.insert(overlayEntry);
  }

  void _minimizeCall() {
    print('🔽 Минимизация звонка');

    // Если есть callback - используем его (для Overlay режима)
    if (widget.onMinimize != null) {
      widget.onMinimize!();
      return;
    }

    // Иначе используем старый способ через Navigator
    FloatingCallManager.instance.minimizeCall(
      callerName: widget.contactName,
      callerAvatarUrl: widget.contactAvatarUrl,
      callerId: widget.contactId,
      callResponse: widget.callData,
      callStartTime: _callStartTime,
      isVideo: widget.isVideo,
    );

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Начать запись звонка
  Future<void> _startRecording() async {
    try {
      await _recordingService.startRecording(
        contactName: widget.contactName,
        contactId: widget.contactId,
      );
    } catch (e) {
      print('❌ Ошибка начала записи: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка начала записи: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Остановить запись звонка
  Future<void> _stopRecording() async {
    try {
      await _recordingService.stopRecording();
    } catch (e) {
      print('❌ Ошибка остановки записи: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка остановки записи: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Переключить запись
  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  void _endCall() async {
    // Защита от множественных вызовов
    if (_isCleaningUp) {
      print('⚠️ Cleanup уже в процессе, пропускаем');
      return;
    }

    try {
      print('📴 Завершение звонка...');

      // Останавливаем запись если идет
      if (_isRecording) {
        await _stopRecording();
      }

      setState(() => _callState = CallState.ended);

      final hangupType = _callState == CallState.connected
          ? 'HUNGUP'
          : 'CANCELED';

      if (_signalingChannel != null) {
        try {
          final hangupMessage = {
            'command': 'hangup',
            'sequence': _sequenceNumber++,
            'reason': hangupType,
          };
          _sendSignalingMessage(hangupMessage);
          print('Sent hangup command via WebSocket: $hangupType');
        } catch (e) {
          print('⚠️ Ошибка отправки hangup через WebSocket: $e');
        }
      }

      // REST API hangup с таймаутом
      try {
        await ApiService.instance
            .hangupCall(
              conversationId: widget.callData.conversationId,
              hangupType: hangupType,
              duration: _callDuration * 1000,
            )
            .timeout(const Duration(seconds: 3));
      } catch (e) {
        print('⚠️ Ошибка REST API hangup (продолжаем cleanup): $e');
      }

      await _cleanup();

      // Если используется Overlay - закрываем через сервис
      if (widget.onMinimize != null) {
        CallOverlayService.instance.closeCall();
      } else {
        // Иначе через Navigator
        FloatingCallManager.instance.endCall();
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      print('❌ Ошибка при завершении звонка: $e');

      await _cleanup();

      // Если используется Overlay - закрываем через сервис
      if (widget.onMinimize != null) {
        CallOverlayService.instance.closeCall();
      } else {
        FloatingCallManager.instance.endCall();
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    }
  }

  void _showErrorAndClose(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  // ========== DataChannel методы ==========

  Future<void> _createDataChannel() async {
    try {
      final RTCDataChannelInit config = RTCDataChannelInit();
      config.ordered = true;

      _dataChannel = await _peerConnection!.createDataChannel(
        'komet-data',
        config,
      );
      _setupDataChannel(_dataChannel!);

      print('✅ DataChannel создан: ${_dataChannel!.label}');
      _addDataChannelLog('⏳ DataChannel создан, ожидание подключения...');

      // НЕ устанавливаем _isDataChannelOpen = true здесь!
      // Это будет сделано в onDataChannelState когда статус станет Open
    } catch (e) {
      print('❌ Ошибка создания DataChannel: $e');
      _addDataChannelLog('❌ Ошибка создания: $e');
    }
  }

  void _setupDataChannel(RTCDataChannel channel) {
    _dataChannel = channel;

    // Добавляем таймаут - если через 5 секунд канал не открылся, считаем что не поддерживается
    Timer(const Duration(seconds: 5), () {
      if (mounted && _dataChannel != null && !_isDataChannelOpen) {
        _dataChannelStatus = '❌ Не поддерживается собеседником';
        _addDataChannelLog(
          '⏰ Таймаут 5 сек: собеседник не поддерживает DataChannel',
        );
        if (mounted) setState(() {});
      }
    });

    _dataChannel!.onDataChannelState = (RTCDataChannelState state) {
      print('📡 DataChannel state: $state');

      if (mounted) {
        setState(() {
          switch (state) {
            case RTCDataChannelState.RTCDataChannelOpen:
              _isDataChannelOpen = true;
              _dataChannelStatus = '✅ Подключен';
              _addDataChannelLog('✅ DataChannel открыт');
              break;
            case RTCDataChannelState.RTCDataChannelConnecting:
              _isDataChannelOpen = false;
              _dataChannelStatus = '⏳ Подключение...';
              _addDataChannelLog('⏳ Подключение...');
              break;
            case RTCDataChannelState.RTCDataChannelClosing:
              _isDataChannelOpen = false;
              _dataChannelStatus = '⏳ Закрывается...';
              _addDataChannelLog('⏳ Закрывается...');
              break;
            case RTCDataChannelState.RTCDataChannelClosed:
              _isDataChannelOpen = false;
              _dataChannelStatus = '❌ Закрыт';
              _addDataChannelLog('❌ DataChannel закрыт');
              break;
          }
        });
      }
    };

    _dataChannel!.onMessage = (RTCDataChannelMessage message) {
      print('📩 Получено сообщение через DataChannel');

      if (message.isBinary) {
        print('⚠️ Получены бинарные данные (пока не поддерживается)');
        return;
      }

      try {
        final data = json.decode(message.text) as Map<String, dynamic>;
        final type = data['type'] as String?;

        if (type == 'chat') {
          String? text = data['text'] as String?;
          final isEncrypted = data['encrypted'] as bool? ?? false;
          bool decryptedOk = false;

          if (text != null) {
            // Дешифруем если сообщение зашифровано
            if (isEncrypted && _chatEncrypter != null && _chatIV != null) {
              try {
                text = _decryptMessage(text);
                decryptedOk = true;
                print('🔓 Сообщение дешифровано');
              } catch (e) {
                print('❌ Ошибка дешифрования: $e');
                text = '🔒 [не удалось расшифровать — верный ли пароль?]';
              }
            } else if (isEncrypted && _chatEncrypter == null) {
              // Получили зашифрованное, но у нас нет пароля
              text = '🔒 [зашифрованное сообщение — установите пароль]';
            }

            final newMessages = List<TemporaryChatMessage>.from(
              _temporaryChatMessages,
            );
            newMessages.add(
              TemporaryChatMessage(
                text: text,
                time: DateTime.now(),
                isMine: false,
                isDecryptedSuccessfully: decryptedOk,
              ),
            );
            _temporaryChatMessagesNotifier.value = newMessages;
            _addDataChannelLog('📩 Получено: $text');
            if (mounted) setState(() {});
          }
        }
      } catch (e) {
        print('❌ Ошибка парсинга сообщения: $e');
        _addDataChannelLog('❌ Ошибка парсинга: $e');
      }
    };
  }

  void _sendDataChannelMessage(String text) {
    print('📤 _sendDataChannelMessage вызван: "$text"');
    print('   _dataChannel: ${_dataChannel != null ? "exists" : "null"}');
    print('   _isDataChannelOpen: $_isDataChannelOpen');

    if (_dataChannel == null || !_isDataChannelOpen) {
      _addDataChannelLog('❌ DataChannel не подключен');
      print('❌ Отправка невозможна - канал не подключен');
      return;
    }

    try {
      // Шифруем текст если установлен пароль
      String textToSend = text;
      if (_chatEncrypter != null && _chatIV != null) {
        textToSend = _encryptMessage(text);
        print('🔐 Сообщение зашифровано');
      }

      final message = json.encode({
        'type': 'chat',
        'text': textToSend,
        'time': DateTime.now().millisecondsSinceEpoch,
        'encrypted': _chatEncrypter != null, // Флаг шифрования
      });

      _dataChannel!.send(RTCDataChannelMessage(message));
      print('✅ Сообщение отправлено через DataChannel');

      // Добавляем в список через ValueNotifier
      final newMessages = List<TemporaryChatMessage>.from(
        _temporaryChatMessages,
      );
      newMessages.add(
        TemporaryChatMessage(
          text: text,
          time: DateTime.now(),
          isMine: true,
          // Своё сообщение шифровалось успешно — показываем замок
          isDecryptedSuccessfully: _chatEncrypter != null,
        ),
      );
      _temporaryChatMessagesNotifier.value = newMessages;
      _addDataChannelLog('📤 Отправлено: $text');

      if (mounted) setState(() {});

      print(
        '📤 Сообщение добавлено в список, всего: ${_temporaryChatMessages.length}',
      );
    } catch (e) {
      print('❌ Ошибка отправки через DataChannel: $e');
      _addDataChannelLog('❌ Ошибка отправки: $e');
    }
  }

  void _addDataChannelLog(String log) {
    final newLogs = List<String>.from(_dataChannelLogs);
    newLogs.add('[${DateTime.now().toString().substring(11, 19)}] $log');
    if (newLogs.length > 50) {
      newLogs.removeAt(0);
    }
    _dataChannelLogsNotifier.value = newLogs;

    if (mounted) setState(() {});
  }

  void _showDataChannelPanel() {
    print('🔍 Открываем панель DataChannel');
    print('   isOpen: $_isDataChannelOpen');
    print('   status: $_dataChannelStatus');
    print('   logs: ${_dataChannelLogs.length}');
    print('   messages: ${_temporaryChatMessages.length}');

    // Получаем Overlay из CallOverlayService чтобы показать поверх
    final overlayState = Overlay.of(context, rootOverlay: true);

    late OverlayEntry overlayEntry; // Объявляем сначала
    overlayEntry = OverlayEntry(
      builder: (context) => Material(
        color: Colors.black54,
        child: GestureDetector(
          onTap: () {
            overlayEntry.remove();
            _dataChannelOverlayEntry = null;
          },
          child: Container(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () {}, // Не закрывать при клике на панель
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _DataChannelPanel(
                  isOpenNotifier: _isDataChannelOpenNotifier,
                  statusNotifier: _dataChannelStatusNotifier,
                  logsNotifier: _dataChannelLogsNotifier,
                  messagesNotifier: _temporaryChatMessagesNotifier,
                  onSendMessage: _sendDataChannelMessage,
                  encryptionPassword: _chatEncryptionPassword,
                  onShowEncryptionDialog: _showChatEncryptionDialog,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlayState.insert(overlayEntry);

    // Сохраняем ссылку чтобы можно было закрыть
    _dataChannelOverlayEntry = overlayEntry;
  }

  Future<void> _updateNetworkStats() async {
    if (_peerConnection == null || _networkInfo == null) return;

    try {
      final stats = await _peerConnection!.getStats();

      int? bytesReceived;
      int? bytesSent;
      int? packetsReceived;
      int? packetsSent;
      double? jitter;
      int? rtt;
      String? codec;

      for (var report in stats) {
        final type = report.type;
        final values = report.values;

        // Inbound RTP (получаемые данные)
        if (type == 'inbound-rtp') {
          if (values['mediaType'] == 'audio' ||
              values['mediaType'] == 'video') {
            bytesReceived =
                (bytesReceived ?? 0) +
                ((values['bytesReceived'] as num?)?.toInt() ?? 0);
            packetsReceived =
                (packetsReceived ?? 0) +
                ((values['packetsReceived'] as num?)?.toInt() ?? 0);
            jitter = (values['jitter'] as num?)?.toDouble();

            // Codec
            if (codec == null && values['codecId'] != null) {
              // Ищем информацию о кодеке
              final codecReport = stats.firstWhere(
                (r) => r.id == values['codecId'],
                orElse: () => report,
              );
              codec = codecReport.values['mimeType'] as String?;
            }
          }
        }

        // Outbound RTP (отправляемые данные)
        if (type == 'outbound-rtp') {
          if (values['mediaType'] == 'audio' ||
              values['mediaType'] == 'video') {
            bytesSent =
                (bytesSent ?? 0) +
                ((values['bytesSent'] as num?)?.toInt() ?? 0);
            packetsSent =
                (packetsSent ?? 0) +
                ((values['packetsSent'] as num?)?.toInt() ?? 0);
          }
        }

        // Candidate pair (RTT и packet loss)
        if (type == 'candidate-pair' && values['state'] == 'succeeded') {
          rtt =
              ((values['currentRoundTripTime'] as num?)?.toDouble() ?? 0 * 1000)
                  .toInt();
        }
      }

      // Вычисляем битрейт
      if (bytesReceived != null && _networkInfo!.bytesReceived != null) {
        final bytesDiff = bytesReceived - _networkInfo!.bytesReceived!;
        final bitrate = (bytesDiff * 8 / 1000).toDouble(); // Кбит/с за секунду
        _networkInfo!.bitrate = bitrate.toInt();
      }

      // Вычисляем packet loss
      if (packetsReceived != null && _networkInfo!.packetsReceived != null) {
        final packetsExpected = packetsSent ?? packetsReceived;
        final packetsLost = packetsExpected - packetsReceived;
        final loss = packetsExpected > 0
            ? (packetsLost / packetsExpected * 100)
            : 0.0;
        _networkInfo!.packetLoss = loss;
      }

      // Сохраняем данные
      if (mounted) {
        setState(() {
          _networkInfo!.bytesReceived = bytesReceived;
          _networkInfo!.bytesSent = bytesSent;
          _networkInfo!.packetsReceived = packetsReceived;
          _networkInfo!.packetsSent = packetsSent;
          _networkInfo!.jitter = jitter != null
              ? (jitter * 1000).toInt()
              : null; // в мс
          _networkInfo!.rtt = rtt;
          _networkInfo!.codec = codec;
        });

        print(
          '📊 Stats updated: bitrate=${_networkInfo!.bitrate}, jitter=${_networkInfo!.jitter}, loss=${_networkInfo!.packetLoss?.toStringAsFixed(2)}%, rtt=${_networkInfo!.rtt}, codec=$codec',
        );
      }
    } catch (e) {
      print('⚠️ Ошибка получения статистики: $e');
    }
  }

  /// Получение геолокации по IP адресу через API
  Future<GeoLocationInfo?> _getGeoLocationByIp(String ip) async {
    try {
      final url = Uri.parse('http://ip-api.com/json/$ip');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        if (jsonData['status'] == 'success') {
          return GeoLocationInfo.fromJson(jsonData);
        } else {
          print('⚠️ Ошибка получения геолокации: ${jsonData['message']}');
          return null;
        }
      } else {
        print(
          '⚠️ Ошибка HTTP при получении геолокации: ${response.statusCode}',
        );
        return null;
      }
    } catch (e) {
      print('⚠️ Ошибка получения геолокации для IP $ip: $e');
      return null;
    }
  }

  /// Получение геолокации для обоих IP адресов
  Future<void> _fetchGeoLocation() async {
    if (_networkInfo == null) return;

    setState(() {
      // Показываем индикатор загрузки
    });

    // Получаем геолокацию для локального IP
    if (_networkInfo!.localAddress != null) {
      final localGeo = await _getGeoLocationByIp(_networkInfo!.localAddress!);
      if (mounted && localGeo != null) {
        setState(() {
          _networkInfo!.localGeoInfo = localGeo;
          _networkInfo!.localGeo = localGeo.locationString;
          _networkInfo!.localCountry = localGeo.country;
          _networkInfo!.localIsp = localGeo.isp;
        });
      }
    }

    // Получаем геолокацию для удаленного IP
    if (_networkInfo!.remoteAddress != null) {
      final remoteGeo = await _getGeoLocationByIp(_networkInfo!.remoteAddress!);
      if (mounted && remoteGeo != null) {
        setState(() {
          _networkInfo!.remoteGeoInfo = remoteGeo;
          _networkInfo!.remoteGeo = remoteGeo.locationString;
          _networkInfo!.remoteCountry = remoteGeo.country;
          _networkInfo!.remoteIsp = remoteGeo.isp;
        });
      }
    }
  }

  Future<void> _cleanup() async {
    // Защита от повторного вызова
    if (_isCleaningUp) {
      print('⚠️ Cleanup уже выполняется, пропускаем');
      return;
    }

    _isCleaningUp = true;
    print('🧹 Начинаем cleanup...');

    // Убираем ongoing-уведомление из шторки
    CallNotificationService.instance.cancelOngoingCallNotification();

    // Сбрасываем callbacks чтобы не получать события после завершения
    if (Platform.isAndroid) {
      CallNotificationService.instance.onCallMuteToggled = null;
      CallNotificationService.instance.onCallEndedFromNotification = null;
    }

    // Закрываем DataChannel overlay если открыт
    _dataChannelOverlayEntry?.remove();
    _dataChannelOverlayEntry = null;
    print('✅ DataChannel overlay закрыт');

    // Глобальный таймаут на весь cleanup - 5 секунд максимум
    final cleanupFuture = _performCleanup();
    await cleanupFuture.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        print(
          '⚠️ КРИТИЧНО: Таймаут всего cleanup (5 сек), принудительно завершаем',
        );
        _isCleaningUp = false;
      },
    );
  }

  Future<void> _performCleanup() async {
    try {
      // 1. Останавливаем таймеры
      _durationTimer?.cancel();
      _durationTimer = null;
      _audioLevelTimer?.cancel();
      _audioLevelTimer = null;
      _statsTimer?.cancel();
      _statsTimer = null;
      _connectionCheckTimer?.cancel();
      _connectionCheckTimer = null;

      // 2. СНАЧАЛА отменяем subscription (чтобы не читать из закрытого сокета)
      try {
        await _signalingSubscription?.cancel();
      } catch (e) {
        print('⚠️ Ошибка отмены subscription: $e');
      }
      _signalingSubscription = null;

      // 3. ПОТОМ закрываем WebSocket с таймаутом
      try {
        await _signalingChannel?.sink.close().timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            print('⚠️ Таймаут закрытия WebSocket');
          },
        );
      } catch (e) {
        print('⚠️ Ошибка при закрытии WebSocket (игнорируем): $e');
      }
      _signalingChannel = null;

      // 4. Останавливаем треки ПЕРЕД dispose стримов
      try {
        _localStream?.getTracks().forEach((track) {
          try {
            track.stop();
          } catch (e) {
            print('⚠️ Ошибка остановки трека: $e');
          }
        });
      } catch (e) {
        print('⚠️ Ошибка при остановке локальных треков: $e');
      }

      try {
        _remoteStream?.getTracks().forEach((track) {
          try {
            track.stop();
          } catch (e) {
            print('⚠️ Ошибка остановки удалённого трека: $e');
          }
        });
      } catch (e) {
        print('⚠️ Ошибка при остановке удалённых треков: $e');
      }

      // 5. Закрываем peer connection ПЕРЕД dispose стримов с таймаутом
      try {
        await _peerConnection?.close().timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            print('⚠️ Таймаут закрытия peer connection');
          },
        );
        _peerConnection = null;
      } catch (e) {
        print('⚠️ Ошибка при закрытии peer connection: $e');
        _peerConnection = null;
      }

      // 6. Dispose стримов с таймаутами
      try {
        await _localStream?.dispose().timeout(
          const Duration(seconds: 1),
          onTimeout: () {
            print('⚠️ Таймаут dispose локального стрима');
          },
        );
        _localStream = null;
      } catch (e) {
        print('⚠️ Ошибка при dispose локального стрима (игнорируем): $e');
        _localStream = null;
      }

      try {
        await _remoteStream?.dispose().timeout(
          const Duration(seconds: 1),
          onTimeout: () {
            print('⚠️ Таймаут dispose удалённого стрима');
          },
        );
        _remoteStream = null;
      } catch (e) {
        print('⚠️ Ошибка при dispose удалённого стрима (игнорируем): $e');
        _remoteStream = null;
      }

      // 7. Dispose рендереров с таймаутами
      try {
        await _localRenderer.dispose().timeout(
          const Duration(seconds: 1),
          onTimeout: () {
            print('⚠️ Таймаут dispose локального рендерера');
          },
        );
      } catch (e) {
        print('⚠️ Ошибка при dispose локального рендерера: $e');
      }

      try {
        await _remoteRenderer.dispose().timeout(
          const Duration(seconds: 1),
          onTimeout: () {
            print('⚠️ Таймаут dispose удалённого рендерера');
          },
        );
      } catch (e) {
        print('⚠️ Ошибка при dispose удалённого рендерера: $e');
      }

      print('✅ Cleanup завершён');
    } catch (e) {
      print('❌ Критическая ошибка в cleanup: $e');
    } finally {
      _isCleaningUp = false;
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _formatRecordingDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return WillPopScope(
      onWillPop: () async {
        // При back button - минимизируем вместо закрытия (только если есть onMinimize)
        if (widget.onMinimize != null) {
          _minimizeCall();
          return false;
        }
        return true; // Разрешаем закрытие если нет onMinimize
      },
      child: GestureDetector(
        onVerticalDragUpdate: (details) {
          // Drag down to minimize
          if (details.delta.dy > 0) {
            setState(() {
              _dragOffset = (_dragOffset + details.delta.dy).clamp(0.0, 300.0);
            });
          }
        },
        onVerticalDragEnd: (details) {
          // If dragged down more than 150px - minimize
          if (_dragOffset > 150) {
            _minimizeCall();
          } else {
            // Snap back
            setState(() {
              _dragOffset = 0;
            });
          }
        },
        child: Transform.translate(
          offset: Offset(0, _dragOffset),
          child: Scaffold(
            backgroundColor: colors.surface,
            body: SafeArea(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AnimatedMeshGradient(accentColor: colors.primary),
                  ),

                  if (_dragOffset > 0)
                    Positioned(
                      top: 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colors.onSurface.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),

                  // Кнопка настроек в левом верхнем углу (на одной высоте с кнопкой инфо)
                  Positioned(
                    top: 24,
                    left: 8,
                    child: IconButton(
                      icon: Icon(
                        Icons.settings_outlined,
                        color: colors.primary,
                      ),
                      onPressed: _showCallSettings,
                    ),
                  ),

                  Column(
                    children: [
                      // Заголовок
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const SizedBox(
                                  width: 40,
                                ), // Spacer for symmetry
                                Expanded(
                                  child: Text(
                                    widget.contactName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        _showNetworkInfo
                                            ? Icons.info
                                            : Icons.info_outline,
                                        color: colors.primary,
                                      ),
                                      onPressed: () {
                                        setState(
                                          () => _showNetworkInfo =
                                              !_showNetworkInfo,
                                        );
                                      },
                                    ),
                                    // Кнопка записи
                                    IconButton(
                                      icon: Icon(
                                        _isRecording
                                            ? Icons.fiber_manual_record
                                            : Icons.radio_button_off,
                                        color: _isRecording
                                            ? colors.error
                                            : colors.primary,
                                        size: 20,
                                      ),
                                      onPressed: _toggleRecording,
                                      tooltip: _isRecording
                                          ? 'Остановить запись'
                                          : 'Начать запись',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _getCallStateText(),
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                            if (_callState == CallState.connected)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _formatDuration(_callDuration),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          color: colors.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                  if (_isRecording) ...[
                                    const SizedBox(width: 12),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.fiber_manual_record,
                                          size: 16,
                                          color: colors.error,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatRecordingDuration(
                                            _recordingDuration,
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: colors.error,
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                          ],
                        ),
                      ),

                      if (_isVideoEnabled ||
                          (_isRemoteVideoEnabled && _remoteStream != null)) ...[
                        Expanded(
                          child: Stack(
                            children: [
                              // Удаленное видео (на весь экран) или аватар если видео выключено
                              if (_remoteStream != null &&
                                  _isRemoteVideoEnabled)
                                Positioned.fill(
                                  child: RTCVideoView(
                                    _remoteRenderer,
                                    mirror: false,
                                    objectFit: RTCVideoViewObjectFit
                                        .RTCVideoViewObjectFitCover,
                                  ),
                                )
                              else
                                // Показываем аватар когда нет видео от собеседника
                                Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // Аватар
                                      CircleAvatar(
                                        radius: 60,
                                        backgroundImage:
                                            widget.contactAvatarUrl != null
                                            ? NetworkImage(
                                                widget.contactAvatarUrl!,
                                              )
                                            : null,
                                        child: widget.contactAvatarUrl == null
                                            ? Text(
                                                widget.contactName.isNotEmpty
                                                    ? widget.contactName[0]
                                                          .toUpperCase()
                                                    : '?',
                                                style: TextStyle(
                                                  fontSize: 48,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : null,
                                      ),
                                      const SizedBox(height: 16),
                                      if (_callState == CallState.connecting ||
                                          _remoteStream == null)
                                        CircularProgressIndicator(
                                          color: colors.primary,
                                        ),
                                    ],
                                  ),
                                ),

                              // Локальное видео (в углу) - показываем только если у нас включено видео
                              if (_localStream != null && _isVideoEnabled)
                                Positioned(
                                  top: 16,
                                  right: 16,
                                  width: 120,
                                  height: 160,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: RTCVideoView(
                                        _localRenderer,
                                        mirror: true,
                                        objectFit: RTCVideoViewObjectFit
                                            .RTCVideoViewObjectFitCover,
                                      ),
                                    ),
                                  ),
                                ),

                              // Иконка отключенного микрофона собеседника (справа внизу)
                              if (_isRemoteMuted &&
                                  _callState == CallState.connected)
                                Positioned(
                                  bottom: 24,
                                  right: 24,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.6),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.mic_off,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ] else ...[
                        // Аватар для аудио звонка с анимированным фоном
                        Expanded(
                          child: Stack(
                            children: [
                              // Анимированный фон с волнами
                              _AnimatedCallBackground(
                                isConnected: _callState == CallState.connected,
                                accentColor: colors.primary,
                              ),

                              // Аватар контакта поверх
                              Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // Аватар контакта с обводкой при разговоре
                                    Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        // Зелёная обводка когда собеседник говорит
                                        if (_isRemoteSpeaking &&
                                            _callState == CallState.connected)
                                          _SpeakingIndicator(
                                            size: 140,
                                            color: Colors.green,
                                          ),

                                        // Сам аватар
                                        ContactAvatarWidget(
                                          contactId: widget.contactId,
                                          originalAvatarUrl:
                                              widget.contactAvatarUrl,
                                          radius: 60,
                                          fallbackText:
                                              widget.contactName.isNotEmpty
                                              ? widget.contactName[0]
                                                    .toUpperCase()
                                              : '?',
                                        ),

                                        // Иконка отключенного микрофона собеседника (справа снизу на аватаре)
                                        if (_isRemoteMuted &&
                                            _callState == CallState.connected)
                                          Positioned(
                                            bottom: 0,
                                            right: 0,
                                            child: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: Colors.red,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 2,
                                                ),
                                              ),
                                              child: Icon(
                                                Icons.mic_off,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 24),
                                    if (_callState == CallState.connecting)
                                      CircularProgressIndicator(
                                        color: colors.primary,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Микрофон с саундпадом
                            Stack(
                              key: _micButtonKey,
                              clipBehavior: Clip.none,
                              children: [
                                _CallButton(
                                  iconWidget: _AnimatedMicIcon(
                                    isMuted: _isMuted,
                                    audioLevel: _localAudioLevel,
                                    size: 24,
                                  ),
                                  label: _isMuted ? 'Откл' : 'Микрофон',
                                  onPressed: _toggleMute,
                                  backgroundColor: _isMuted
                                      ? colors.error
                                      : colors.surfaceContainerHighest,
                                  foregroundColor: _isMuted
                                      ? colors.onError
                                      : colors.onSurface,
                                ),

                                // Маленькая кнопка саундпада (серая, справа сверху)
                                Positioned(
                                  right: 4,
                                  top: 4,
                                  child: GestureDetector(
                                    onTap: _showSoundpad,
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade600,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: colors.surface,
                                          width: 2,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.arrow_drop_up,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // Видео (показываем всегда, можно включить в любом звонке)
                            _CallButton(
                              icon: _isVideoEnabled
                                  ? Icons.videocam
                                  : Icons.videocam_off,
                              label: _isVideoEnabled ? 'Видео' : 'Камера',
                              onPressed: _toggleVideo,
                              backgroundColor: _isVideoEnabled
                                  ? colors.primary
                                  : colors.surfaceContainerHighest,
                              foregroundColor: _isVideoEnabled
                                  ? colors.onPrimary
                                  : colors.onSurface,
                            ),

                            // Завершить звонок
                            _CallButton(
                              icon: Icons.call_end,
                              label: 'Завершить',
                              onPressed: _isCleaningUp ? () {} : _endCall,
                              backgroundColor: colors.error,
                              foregroundColor: colors.onError,
                              isLarge: true,
                            ),

                            // Динамик
                            _CallButton(
                              icon: _isSpeakerOn
                                  ? Icons.volume_up
                                  : Icons.volume_down,
                              label: _isSpeakerOn ? 'Динамик' : 'Обычный',
                              onPressed: _toggleSpeaker,
                              backgroundColor: _isSpeakerOn
                                  ? colors.primary
                                  : colors.surfaceContainerHighest,
                              foregroundColor: _isSpeakerOn
                                  ? colors.onPrimary
                                  : colors.onSurface,
                            ),

                            // DataChannel (только если включен)
                            if (widget.enableDataChannel)
                              _CallButton(
                                icon: Icons.chat_bubble_outline,
                                label: 'DATA_CH',
                                onPressed: _showDataChannelPanel,
                                backgroundColor: _isDataChannelOpen
                                    ? colors.primary
                                    : colors.surfaceContainerHighest,
                                foregroundColor: _isDataChannelOpen
                                    ? colors.onPrimary
                                    : colors.onSurface,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  if (_showNetworkInfo && _networkInfo != null)
                    Positioned(
                      top: 100,
                      left: 16,
                      right: 16,
                      child: _NetworkInfoPanel(
                        networkInfo: _networkInfo!,
                        onFetchGeoLocation: _fetchGeoLocation,
                      ),
                    ),

                  // Кнопка чата (DataChannel) - размещаем в ряд с другими кнопками
                  // (убрано отсюда, перенесено в основной ряд кнопок)
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getCallStateText() {
    switch (_callState) {
      case CallState.connecting:
        return 'Подключение...';
      case CallState.ringing:
        return widget.isOutgoing ? 'Вызов...' : 'Входящий звонок';
      case CallState.connected:
        return 'Соединено';
      case CallState.ended:
        return 'Завершено';
    }
  }

  @override
  void dispose() {
    // Закрываем DataChannel overlay
    _dataChannelOverlayEntry?.remove();
    _dataChannelOverlayEntry = null;

    // Закрываем soundpad overlay
    _soundpadOverlay?.remove();
    _soundpadOverlay = null;

    // Освобождаем audio player
    _soundpadPlayer?.dispose();
    _soundpadPlayer = null;

    // Останавливаем запись если идет
    if (_isRecording) {
      _recordingService.stopRecording();
    }
    _recordingSubscription?.cancel();
    _recordingSubscription = null;

    // Dispose ValueNotifier
    _isDataChannelOpenNotifier.dispose();
    _dataChannelStatusNotifier.dispose();
    _dataChannelLogsNotifier.dispose();
    _temporaryChatMessagesNotifier.dispose();

    FloatingCallManager.instance.removeListener(_onFloatingCallStateChanged);

    // Очищаем callback
    FloatingCallManager.instance.onEndCall = null;

    // Если используется Overlay - НЕ вызываем cleanup при dispose
    // (cleanup будет вызван только при closeCall)
    if (widget.onMinimize == null) {
      // Старый режим через Navigator - делаем cleanup
      if (!FloatingCallManager.instance.isMinimized) {
        _cleanup()
            .then((_) {
              print('✅ Cleanup в dispose завершён');
            })
            .catchError((e) {
              print('❌ Ошибка в cleanup при dispose: $e');
            });
      } else {
        print(
          '⏸️ CallScreen закрыт, но звонок минимизирован - cleanup пропущен',
        );
      }
    } else {
      print(
        '🎯 CallScreen dispose в Overlay режиме - cleanup управляется CallOverlayService',
      );
    }

    super.dispose();
  }
}

/// Состояние звонка
enum CallState { connecting, ringing, connected, ended }

/// Кнопка управления звонком
// Виджет анимированной иконки микрофона с заливкой по уровню громкости
class _AnimatedMicIcon extends StatelessWidget {
  final bool isMuted;
  final double audioLevel; // 0.0 - 1.0
  final double size;

  const _AnimatedMicIcon({
    required this.isMuted,
    required this.audioLevel,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Фоновая иконка (светло-серая)
          Icon(
            isMuted ? Icons.mic_off : Icons.mic,
            size: size,
            color: Colors.grey.shade400,
          ),

          // Заполненная часть (снизу вверх)
          if (!isMuted && audioLevel > 0.01)
            ClipRect(
              child: Align(
                alignment: Alignment.bottomCenter,
                heightFactor: audioLevel.clamp(0.0, 1.0),
                child: Icon(Icons.mic, size: size, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData? icon;
  final Widget? iconWidget; // Кастомный виджет иконки
  final String label;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool isLarge;

  const _CallButton({
    this.icon,
    this.iconWidget,
    required this.label,
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    this.isLarge = false,
  }) : assert(
         icon != null || iconWidget != null,
         'Either icon or iconWidget must be provided',
       );

  @override
  Widget build(BuildContext context) {
    final size = isLarge ? 72.0 : 56.0;
    final iconSize = isLarge ? 32.0 : 24.0;

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
              width: size,
              height: size,
              alignment: Alignment.center,
              child:
                  iconWidget ??
                  Icon(icon!, size: iconSize, color: foregroundColor),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Информация о геолокации по IP
class GeoLocationInfo {
  final String country;
  final String countryCode;
  final String region;
  final String regionName;
  final String city;
  final String zip;
  final double lat;
  final double lon;
  final String timezone;
  final String isp;
  final String org;
  final String asn;
  final String query; // IP адрес

  GeoLocationInfo({
    required this.country,
    required this.countryCode,
    required this.region,
    required this.regionName,
    required this.city,
    required this.zip,
    required this.lat,
    required this.lon,
    required this.timezone,
    required this.isp,
    required this.org,
    required this.asn,
    required this.query,
  });

  factory GeoLocationInfo.fromJson(Map<String, dynamic> json) {
    return GeoLocationInfo(
      country: json['country'] ?? 'Неизвестно',
      countryCode: json['countryCode'] ?? '',
      region: json['region'] ?? '',
      regionName: json['regionName'] ?? '',
      city: json['city'] ?? 'Неизвестно',
      zip: json['zip'] ?? '',
      lat: (json['lat'] ?? 0.0).toDouble(),
      lon: (json['lon'] ?? 0.0).toDouble(),
      timezone: json['timezone'] ?? '',
      isp: json['isp'] ?? 'Неизвестно',
      org: json['org'] ?? '',
      asn: json['as'] ?? '',
      query: json['query'] ?? '',
    );
  }

  String get locationString {
    final parts = <String>[];
    if (city.isNotEmpty && city != 'Неизвестно') parts.add(city);
    if (regionName.isNotEmpty) parts.add(regionName);
    if (country.isNotEmpty && country != 'Неизвестно') parts.add(country);
    return parts.isNotEmpty ? parts.join(', ') : 'Неизвестное местоположение';
  }
}

/// Модель сетевой информации
class NetworkInfo {
  String? localAddress;
  String? localConnectionType;
  String? remoteAddress;
  String? remoteConnectionType;
  String? transport;
  String? networkType;
  int? rtt;

  // Детальная информация о кандидатах
  List<IceCandidate> localCandidates = [];
  List<IceCandidate> remoteCandidates = [];

  // Статистика WebRTC (будет обновляться)
  double? packetLoss;
  int? jitter;
  int? bitrate;
  String? codec;

  // Геолокация
  String? localGeo;
  String? remoteGeo;
  String? localIsp;
  String? remoteIsp;
  String? localCountry;
  String? remoteCountry;
  int? localAsn;
  int? remoteAsn;

  // Детальная информация о геолокации
  GeoLocationInfo? localGeoInfo;
  GeoLocationInfo? remoteGeoInfo;

  // TURN/STUN серверы
  List<String> turnServers = [];
  List<String> stunServers = [];

  // Лимиты качества от сервера
  int? maxVideoBitrate; // Кбит/с
  int? maxVideoResolution; // pixels
  int? badNetRtt; // мс
  double? badNetLoss; // %
  int? goodNetRtt; // мс
  double? goodNetLoss; // %

  // Дополнительная статистика
  int? packetsReceived;
  int? packetsSent;
  int? bytesReceived;
  int? bytesSent;
}

class IceCandidate {
  final String ip;
  final int port;
  final String type; // host, srflx, relay
  final int priority;
  final String? networkId;
  final int? networkCost;
  final String? relayServer; // IP релей сервера если typ=relay
  final String? stunServer; // IP STUN сервера если typ=srflx

  IceCandidate({
    required this.ip,
    required this.port,
    required this.type,
    required this.priority,
    this.networkId,
    this.networkCost,
    this.relayServer,
    this.stunServer,
  });

  String get typeLabel {
    switch (type) {
      case 'host':
        return 'Прямое (host)';
      case 'srflx':
        return 'STUN (srflx)';
      case 'relay':
        return 'TURN (relay)';
      default:
        return type;
    }
  }

  String get networkLabel {
    if (networkCost == null) return '';
    if (networkCost! <= 10) return 'Wi-Fi';
    if (networkCost! <= 50) return 'Ethernet';
    if (networkCost! <= 100) return 'Сотовая сеть';
    return 'Неизвестно';
  }
}

/// Панель отображения сетевой информации
class _NetworkInfoPanel extends StatefulWidget {
  final NetworkInfo networkInfo;
  final Future<void> Function() onFetchGeoLocation;

  const _NetworkInfoPanel({
    required this.networkInfo,
    required this.onFetchGeoLocation,
  });

  @override
  State<_NetworkInfoPanel> createState() => _NetworkInfoPanelState();
}

class _NetworkInfoPanelState extends State<_NetworkInfoPanel> {
  bool _isLoadingGeo = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final networkInfo = widget.networkInfo;

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: colors.surface.withValues(alpha: 0.95),
      child: Container(
        constraints: const BoxConstraints(
          maxHeight: 500,
        ), // Ограничиваем высоту
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.network_check, color: colors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Сетевая информация',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Ваш IP
              if (networkInfo.localAddress != null) ...[
                _InfoRow(
                  icon: Icons.smartphone,
                  label: 'Ваш IP',
                  value: networkInfo.localAddress!,
                  valueColor: colors.primary,
                ),
                if (networkInfo.localConnectionType != null)
                  _InfoRow(
                    icon: Icons.link,
                    label: 'Тип соединения',
                    value: _formatConnectionType(
                      networkInfo.localConnectionType!,
                    ),
                    indent: true,
                  ),
              ],

              const SizedBox(height: 8),

              // IP собеседника
              if (networkInfo.remoteAddress != null) ...[
                _InfoRow(
                  icon: Icons.person,
                  label: 'IP собеседника',
                  value: networkInfo.remoteAddress!,
                  valueColor: colors.secondary,
                ),
                if (networkInfo.remoteConnectionType != null)
                  _InfoRow(
                    icon: Icons.link,
                    label: 'Тип соединения',
                    value: _formatConnectionType(
                      networkInfo.remoteConnectionType!,
                    ),
                    indent: true,
                  ),
              ],

              const SizedBox(height: 8),

              // Дополнительная информация
              if (networkInfo.transport != null)
                _InfoRow(
                  icon: Icons.swap_horiz,
                  label: 'Транспорт',
                  value: networkInfo.transport!.toUpperCase(),
                ),

              if (networkInfo.networkType != null)
                _InfoRow(
                  icon: Icons.wifi,
                  label: 'Сеть',
                  value: _formatNetworkType(networkInfo.networkType!),
                ),

              if (networkInfo.rtt != null)
                _InfoRow(
                  icon: Icons.speed,
                  label: 'Задержка (RTT)',
                  value: '${networkInfo.rtt} мс',
                  valueColor: _getRttColor(networkInfo.rtt!, colors),
                ),

              // Геолокация
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Геолокация',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colors.primary,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed:
                        _isLoadingGeo ||
                            (networkInfo.localAddress == null &&
                                networkInfo.remoteAddress == null)
                        ? null
                        : () async {
                            setState(() {
                              _isLoadingGeo = true;
                            });
                            try {
                              await widget.onFetchGeoLocation();
                            } finally {
                              if (mounted) {
                                setState(() {
                                  _isLoadingGeo = false;
                                });
                              }
                            }
                          },
                    icon: _isLoadingGeo
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.location_on, size: 18),
                    label: Text(_isLoadingGeo ? 'Загрузка...' : 'Get geo'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Геолокация локального IP
              if (networkInfo.localGeoInfo != null) ...[
                _InfoRow(
                  icon: Icons.my_location,
                  label: 'Ваше расположение',
                  value: networkInfo.localGeoInfo!.locationString,
                  valueColor: colors.primary,
                ),
                if (networkInfo.localGeoInfo!.city.isNotEmpty)
                  _InfoRow(
                    icon: Icons.location_city,
                    label: 'Город',
                    value: networkInfo.localGeoInfo!.city,
                    indent: true,
                  ),
                if (networkInfo.localGeoInfo!.regionName.isNotEmpty)
                  _InfoRow(
                    icon: Icons.map,
                    label: 'Регион',
                    value: networkInfo.localGeoInfo!.regionName,
                    indent: true,
                  ),
                if (networkInfo.localGeoInfo!.country.isNotEmpty)
                  _InfoRow(
                    icon: Icons.flag,
                    label: 'Страна',
                    value:
                        '${networkInfo.localGeoInfo!.country} (${networkInfo.localGeoInfo!.countryCode})',
                    indent: true,
                  ),
                if (networkInfo.localGeoInfo!.lat != 0.0 &&
                    networkInfo.localGeoInfo!.lon != 0.0)
                  _InfoRow(
                    icon: Icons.explore,
                    label: 'Координаты',
                    value:
                        '${networkInfo.localGeoInfo!.lat.toStringAsFixed(4)}, ${networkInfo.localGeoInfo!.lon.toStringAsFixed(4)}',
                    indent: true,
                  ),
                if (networkInfo.localGeoInfo!.isp.isNotEmpty)
                  _InfoRow(
                    icon: Icons.business,
                    label: 'ISP',
                    value: networkInfo.localGeoInfo!.isp,
                    indent: true,
                  ),
                const SizedBox(height: 8),
              ] else if (networkInfo.localAddress != null) ...[
                _InfoRow(
                  icon: Icons.my_location,
                  label: 'Ваше расположение',
                  value: 'Не определено',
                  valueColor: colors.onSurfaceVariant,
                ),
                const SizedBox(height: 8),
              ],

              // Геолокация удаленного IP
              if (networkInfo.remoteGeoInfo != null) ...[
                _InfoRow(
                  icon: Icons.person_pin,
                  label: 'Расположение собеседника',
                  value: networkInfo.remoteGeoInfo!.locationString,
                  valueColor: colors.secondary,
                ),
                if (networkInfo.remoteGeoInfo!.city.isNotEmpty)
                  _InfoRow(
                    icon: Icons.location_city,
                    label: 'Город',
                    value: networkInfo.remoteGeoInfo!.city,
                    indent: true,
                  ),
                if (networkInfo.remoteGeoInfo!.regionName.isNotEmpty)
                  _InfoRow(
                    icon: Icons.map,
                    label: 'Регион',
                    value: networkInfo.remoteGeoInfo!.regionName,
                    indent: true,
                  ),
                if (networkInfo.remoteGeoInfo!.country.isNotEmpty)
                  _InfoRow(
                    icon: Icons.flag,
                    label: 'Страна',
                    value:
                        '${networkInfo.remoteGeoInfo!.country} (${networkInfo.remoteGeoInfo!.countryCode})',
                    indent: true,
                  ),
                if (networkInfo.remoteGeoInfo!.lat != 0.0 &&
                    networkInfo.remoteGeoInfo!.lon != 0.0)
                  _InfoRow(
                    icon: Icons.explore,
                    label: 'Координаты',
                    value:
                        '${networkInfo.remoteGeoInfo!.lat.toStringAsFixed(4)}, ${networkInfo.remoteGeoInfo!.lon.toStringAsFixed(4)}',
                    indent: true,
                  ),
                if (networkInfo.remoteGeoInfo!.isp.isNotEmpty)
                  _InfoRow(
                    icon: Icons.business,
                    label: 'ISP',
                    value: networkInfo.remoteGeoInfo!.isp,
                    indent: true,
                  ),
              ] else if (networkInfo.remoteAddress != null) ...[
                _InfoRow(
                  icon: Icons.person_pin,
                  label: 'Расположение собеседника',
                  value: 'Не определено',
                  valueColor: colors.onSurfaceVariant,
                ),
              ],

              // Качество соединения
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Качество соединения',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 8),
              _InfoRow(
                icon: Icons.equalizer,
                label: 'Битрейт',
                value: networkInfo.bitrate != null
                    ? '${networkInfo.bitrate} Кбит/с'
                    : 'Сервер пожалел данных',
                valueColor: networkInfo.bitrate != null
                    ? colors.onSurface
                    : Colors.red,
              ),
              _InfoRow(
                icon: Icons.graphic_eq,
                label: 'Jitter',
                value: networkInfo.jitter != null
                    ? '${networkInfo.jitter} мс'
                    : 'Сервер пожалел данных',
                valueColor: networkInfo.jitter != null
                    ? colors.onSurface
                    : Colors.red,
              ),
              _InfoRow(
                icon: Icons.cloud_off,
                label: 'Потеря пакетов',
                value: networkInfo.packetLoss != null
                    ? '${networkInfo.packetLoss!.toStringAsFixed(2)}%'
                    : 'Сервер пожалел данных',
                valueColor: networkInfo.packetLoss != null
                    ? (networkInfo.packetLoss! < 1
                          ? Colors.green
                          : networkInfo.packetLoss! < 5
                          ? Colors.orange
                          : Colors.red)
                    : Colors.red,
              ),
              if (networkInfo.packetsReceived != null ||
                  networkInfo.packetsSent != null) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Статистика пакетов',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: 8),
                if (networkInfo.packetsReceived != null)
                  _InfoRow(
                    icon: Icons.download,
                    label: 'Получено пакетов',
                    value: networkInfo.packetsReceived.toString(),
                    valueColor: colors.onSurface,
                  ),
                if (networkInfo.packetsSent != null)
                  _InfoRow(
                    icon: Icons.upload,
                    label: 'Отправлено пакетов',
                    value: networkInfo.packetsSent.toString(),
                    valueColor: colors.onSurface,
                  ),
                if (networkInfo.bytesReceived != null)
                  _InfoRow(
                    icon: Icons.download,
                    label: 'Получено данных',
                    value: _formatBytes(networkInfo.bytesReceived!),
                    valueColor: colors.onSurface,
                  ),
                if (networkInfo.bytesSent != null)
                  _InfoRow(
                    icon: Icons.upload,
                    label: 'Отправлено данных',
                    value: _formatBytes(networkInfo.bytesSent!),
                    valueColor: colors.onSurface,
                  ),
              ],

              // Детальная информация о кандидатах
              if (networkInfo.localCandidates.isNotEmpty ||
                  networkInfo.remoteCandidates.isNotEmpty) ...[
                const SizedBox(height: 16),
                Divider(color: colors.outline.withOpacity(0.3)),
                const SizedBox(height: 8),

                // Локальные кандидаты
                if (networkInfo.localCandidates.isNotEmpty) ...[
                  Text(
                    '📍 Ваши кандидаты соединения (${networkInfo.localCandidates.length})',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...networkInfo.localCandidates.map(
                    (c) => _CandidateRow(candidate: c, isLocal: true),
                  ),
                ],

                const SizedBox(height: 12),

                // Удаленные кандидаты
                if (networkInfo.remoteCandidates.isNotEmpty) ...[
                  Text(
                    '🌐 Кандидаты собеседника (${networkInfo.remoteCandidates.length})',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colors.secondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...networkInfo.remoteCandidates.map(
                    (c) => _CandidateRow(candidate: c, isLocal: false),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatConnectionType(String type) {
    switch (type) {
      case 'srflx':
        return 'P2P (публичный IP)';
      case 'host':
        return 'Локальный';
      case 'relay':
        return 'Через сервер';
      default:
        return type;
    }
  }

  String _formatNetworkType(String type) {
    switch (type) {
      case 'wifi':
        return 'Wi-Fi';
      case 'cellular':
        return 'Мобильная сеть';
      default:
        return type;
    }
  }

  Color _getRttColor(int rtt, ColorScheme colors) {
    if (rtt < 100) return Colors.green;
    if (rtt < 200) return Colors.orange;
    return Colors.red;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} КБ';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} МБ';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
  }
}

/// Анимированный фон для звонка с волнами
class _AnimatedCallBackground extends StatefulWidget {
  final bool isConnected;
  final Color accentColor;

  const _AnimatedCallBackground({
    required this.isConnected,
    required this.accentColor,
  });

  @override
  State<_AnimatedCallBackground> createState() =>
      _AnimatedCallBackgroundState();
}

class _AnimatedCallBackgroundState extends State<_AnimatedCallBackground>
    with TickerProviderStateMixin {
  late AnimationController _controller1;
  late AnimationController _controller2;
  late AnimationController _controller3;

  @override
  void initState() {
    super.initState();

    // Создаём 3 контроллера для разных волн с разной скоростью
    _controller1 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _controller2 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();

    _controller3 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller1.dispose();
    _controller2.dispose();
    _controller3.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Вычисляем центр аватара (чуть выше центра экрана)
        final avatarCenterY = constraints.maxHeight / 2;

        return CustomPaint(
          painter: _WavesPainter(
            animation1: _controller1,
            animation2: _controller2,
            animation3: _controller3,
            accentColor: widget.accentColor,
            isConnected: widget.isConnected,
            avatarCenter: Offset(constraints.maxWidth / 2, avatarCenterY),
          ),
          child: Container(),
        );
      },
    );
  }
}

/// Painter для рисования волн
class _WavesPainter extends CustomPainter {
  final Animation<double> animation1;
  final Animation<double> animation2;
  final Animation<double> animation3;
  final Color accentColor;
  final bool isConnected;
  final Offset avatarCenter;

  _WavesPainter({
    required this.animation1,
    required this.animation2,
    required this.animation3,
    required this.accentColor,
    required this.isConnected,
    required this.avatarCenter,
  }) : super(repaint: Listenable.merge([animation1, animation2, animation3]));

  @override
  void paint(Canvas canvas, Size size) {
    final maxRadius = size.width > size.height ? size.width : size.height;

    // Рисуем 3 волны с разными параметрами ОТ ЦЕНТРА АВАТАРА
    _drawWave(canvas, avatarCenter, maxRadius, animation1.value, 0.15, 0.8);
    _drawWave(canvas, avatarCenter, maxRadius, animation2.value, 0.10, 0.6);
    _drawWave(canvas, avatarCenter, maxRadius, animation3.value, 0.08, 0.4);
  }

  void _drawWave(
    Canvas canvas,
    Offset center,
    double maxRadius,
    double progress,
    double opacity,
    double scale,
  ) {
    final radius = maxRadius * progress * scale;

    // Прозрачность уменьшается по мере расширения волны
    final alpha = ((1 - progress) * opacity * 255).toInt().clamp(0, 255);

    final paint = Paint()
      ..color = accentColor.withAlpha(alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_WavesPainter oldDelegate) {
    return oldDelegate.accentColor != accentColor ||
        oldDelegate.isConnected != isConnected ||
        oldDelegate.avatarCenter != avatarCenter;
  }
}

/// Индикатор что собеседник говорит
class _SpeakingIndicator extends StatefulWidget {
  final double size;
  final Color color;

  const _SpeakingIndicator({required this.size, required this.color});

  @override
  State<_SpeakingIndicator> createState() => _SpeakingIndicatorState();
}

class _SpeakingIndicatorState extends State<_SpeakingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _animation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.size * _animation.value,
          height: widget.size * _animation.value,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.color.withOpacity(0.6),
              width: 3.0,
            ),
          ),
        );
      },
    );
  }
}

/// Строка информации
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool indent;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.indent = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(left: indent ? 28.0 : 0, bottom: 4),
      child: Row(
        children: [
          if (!indent) ...[
            Icon(icon, size: 16, color: colors.onSurfaceVariant),
            const SizedBox(width: 8),
          ],
          Text(
            '$label: ',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: valueColor ?? colors.onSurface,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Строка с информацией о ICE кандидате
class _CandidateRow extends StatelessWidget {
  final IceCandidate candidate;
  final bool isLocal;

  const _CandidateRow({required this.candidate, required this.isLocal});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isLocal ? colors.primaryContainer : colors.secondaryContainer)
            .withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (isLocal ? colors.primary : colors.secondary).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                candidate.type == 'relay'
                    ? Icons.router
                    : candidate.type == 'srflx'
                    ? Icons.public
                    : Icons.computer,
                size: 16,
                color: isLocal ? colors.primary : colors.secondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${candidate.ip}:${candidate.port}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _getTypeColor(candidate.type),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  candidate.typeLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _chip(
                context,
                Icons.priority_high,
                'Priority: ${candidate.priority}',
              ),
              if (candidate.networkLabel.isNotEmpty)
                _chip(context, Icons.wifi, candidate.networkLabel),
              if (candidate.networkId != null)
                _chip(context, Icons.tag, 'ID: ${candidate.networkId}'),
            ],
          ),
          if (candidate.relayServer != null) ...[
            const SizedBox(height: 4),
            _serverRow(
              context,
              Icons.dns,
              'TURN',
              candidate.relayServer!,
              colors,
            ),
          ],
          if (candidate.stunServer != null) ...[
            const SizedBox(height: 4),
            _serverRow(
              context,
              Icons.vpn_lock,
              'STUN',
              candidate.stunServer!,
              colors,
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String label) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: colors.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _serverRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    ColorScheme colors,
  ) {
    return Row(
      children: [
        Icon(icon, size: 11, color: colors.tertiary),
        const SizedBox(width: 4),
        Text('$label: ', style: const TextStyle(fontSize: 10)),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: colors.tertiary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'host':
        return Colors.blue;
      case 'srflx':
        return Colors.green;
      case 'relay':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}

// Модель для temporary chat сообщений
class TemporaryChatMessage {
  final String text;
  final DateTime time;
  final bool isMine;

  /// true — сообщение пришло зашифрованным и успешно расшифровалось
  final bool isDecryptedSuccessfully;

  TemporaryChatMessage({
    required this.text,
    required this.time,
    required this.isMine,
    this.isDecryptedSuccessfully = false,
  });
}

/// Панель DataChannel с temporary chat и логами
class _DataChannelPanel extends StatefulWidget {
  final ValueNotifier<bool> isOpenNotifier;
  final ValueNotifier<String> statusNotifier;
  final ValueNotifier<List<String>> logsNotifier;
  final ValueNotifier<List<TemporaryChatMessage>> messagesNotifier;
  final void Function(String) onSendMessage;
  final String? encryptionPassword;
  final VoidCallback onShowEncryptionDialog;

  const _DataChannelPanel({
    required this.isOpenNotifier,
    required this.statusNotifier,
    required this.logsNotifier,
    required this.messagesNotifier,
    required this.onSendMessage,
    required this.encryptionPassword,
    required this.onShowEncryptionDialog,
  });

  @override
  State<_DataChannelPanel> createState() => _DataChannelPanelState();
}

class _DataChannelPanelState extends State<_DataChannelPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ValueListenableBuilder<String>(
      valueListenable: widget.statusNotifier,
      builder: (context, status, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: widget.isOpenNotifier,
          builder: (context, isOpen, _) {
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: colors.outline.withOpacity(0.2),
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            // Drag handle
                            Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: colors.onSurfaceVariant.withOpacity(0.4),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(Icons.data_usage, color: colors.primary),
                                const SizedBox(width: 8),
                                Text(
                                  'DATA_CHANNEL',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: Icon(
                                    widget.encryptionPassword != null
                                        ? Icons.lock
                                        : Icons.lock_open,
                                    color: widget.encryptionPassword != null
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                  onPressed: widget.onShowEncryptionDialog,
                                  tooltip: widget.encryptionPassword != null
                                      ? 'Шифрование включено'
                                      : 'Установить пароль',
                                ),
                                Chip(
                                  label: Text(status),
                                  backgroundColor: isOpen
                                      ? colors.primaryContainer
                                      : colors.errorContainer,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Tabs
                      TabBar(
                        controller: _tabController,
                        tabs: const [
                          Tab(text: 'Chat', icon: Icon(Icons.chat)),
                          Tab(text: 'Logs', icon: Icon(Icons.list)),
                        ],
                      ),

                      // Content
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            // Chat tab
                            _buildChatTab(colors, scrollController, isOpen),
                            // Logs tab
                            _buildLogsTab(colors, scrollController),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildChatTab(
    ColorScheme colors,
    ScrollController scrollController,
    bool isOpen,
  ) {
    return ValueListenableBuilder<List<TemporaryChatMessage>>(
      valueListenable: widget.messagesNotifier,
      builder: (context, messages, _) {
        return Column(
          children: [
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: Text(
                        isOpen
                            ? 'Чат пуст. Отправьте первое сообщение!'
                            : 'DataChannel не подключен',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[messages.length - 1 - index];
                        return _buildMessageBubble(message, colors);
                      },
                    ),
            ),

            // Input field
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                border: Border(
                  top: BorderSide(color: colors.outline.withOpacity(0.2)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      enabled: isOpen,
                      decoration: InputDecoration(
                        hintText: isOpen
                            ? 'Сообщение...'
                            : 'DataChannel отключен',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: isOpen ? _sendMessage : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: isOpen ? _sendMessage : null,
                    icon: const Icon(Icons.send),
                    color: isOpen ? colors.primary : colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMessageBubble(TemporaryChatMessage message, ColorScheme colors) {
    // Для DataChannel шифрование обрабатывается в onMessage.
    // Используем флаг isDecryptedSuccessfully из самого сообщения.
    final String displayText = message.text;
    final bool showLock = message.isDecryptedSuccessfully;

    return Align(
      alignment: message.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: message.isMine
              ? colors.primaryContainer
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showLock) ...[
                  Icon(
                    Icons.lock,
                    size: 14,
                    color:
                        (message.isMine
                                ? colors.onPrimaryContainer
                                : colors.onSurface)
                            .withOpacity(0.8),
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    displayText,
                    style: TextStyle(
                      color: message.isMine
                          ? colors.onPrimaryContainer
                          : colors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${message.time.hour.toString().padLeft(2, '0')}:${message.time.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 10,
                color:
                    (message.isMine
                            ? colors.onPrimaryContainer
                            : colors.onSurface)
                        .withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogsTab(ColorScheme colors, ScrollController scrollController) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: widget.logsNotifier,
      builder: (context, logs, _) {
        print('🔍 _buildLogsTab: logs.length = ${logs.length}');
        logs.forEach((log) => print('  - $log'));

        return logs.isEmpty
            ? Center(
                child: Text(
                  'Логов пока нет',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              )
            : ListView.builder(
                controller: scrollController,
                reverse: false,
                padding: const EdgeInsets.all(16),
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  final log = logs[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      log,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: colors.onSurface,
                      ),
                    ),
                  );
                },
              );
      },
    );
  }

  void _sendMessage([String? _]) {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    widget.onSendMessage(text);
    _messageController.clear();
  }
}

// Диалог настроек звонка
class _CallSettingsPanel extends StatelessWidget {
  final bool blurPanels;
  final ValueChanged<bool> onBlurPanelsChanged;
  final VoidCallback onClose;

  const _CallSettingsPanel({
    required this.blurPanels,
    required this.onBlurPanelsChanged,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Заголовок
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.settings, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  'Настройки звонка',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: onClose),
              ],
            ),
          ),
          const Divider(height: 1),

          // Контент
          SwitchListTile(
            title: const Text('Блюр панелей'),
            subtitle: const Text('Размытие верхней и нижней панели'),
            value: blurPanels,
            onChanged: onBlurPanelsChanged,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.mic),
            title: const Text('Аудио вход'),
            subtitle: const Text('По умолчанию'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              // TODO: Показать список доступных аудио устройств
            },
          ),
          ListTile(
            leading: const Icon(Icons.volume_up),
            title: const Text('Аудио выход'),
            subtitle: const Text('По умолчанию'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              // TODO: Показать список доступных аудио устройств
            },
          ),
          ListTile(
            leading: const Icon(Icons.videocam),
            title: const Text('Видео вход'),
            subtitle: const Text('По умолчанию'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              // TODO: Показать список доступных камер
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
