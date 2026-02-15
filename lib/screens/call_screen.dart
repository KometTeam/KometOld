import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:gwid/models/call_response.dart';
import 'package:gwid/api/api_service.dart';
import 'package:gwid/services/floating_call_manager.dart';
import 'package:gwid/services/call_overlay_service.dart';
import 'package:gwid/widgets/contact_avatar_widget.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import 'dart:async';
import 'dart:convert';

/// Экран активного звонка с WebRTC
class CallScreen extends StatefulWidget {
  final CallResponse callData;
  final String contactName;
  final int contactId;
  final String? contactAvatarUrl;
  final bool isOutgoing;
  final bool isVideo;
  final VoidCallback? onMinimize; // Callback для минимизации через Overlay
  final DateTime? callStartTime; // Опциональное время начала (для восстановления таймера)

  const CallScreen({
    super.key,
    required this.callData,
    required this.contactName,
    required this.contactId,
    this.contactAvatarUrl,
    required this.isOutgoing,
    this.isVideo = false,
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

  // WebSocket signaling
  WebSocketChannel? _signalingChannel;
  StreamSubscription? _signalingSubscription;
  int _sequenceNumber = 1;

  // UI State
  CallState _callState = CallState.connecting;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isVideoEnabled = false;
  bool _isRemoteVideoEnabled = false;
  bool _isRemoteMuted = false;
  int _callDuration = 0;
  Timer? _durationTimer;
  late DateTime _callStartTime;
  
  // Network Info
  NetworkInfo? _networkInfo;
  bool _showNetworkInfo = false;
  
  // Participant info
  int? _remoteParticipantInternalId; // INTERNAL ID второго участника
  
  // Audio level tracking
  bool _isRemoteSpeaking = false;
  Timer? _audioLevelTimer;
  
  // Cleanup protection
  bool _isCleaningUp = false;
  
  // Drag to minimize
  double _dragOffset = 0;

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
        print('✅ WebRTC инициализирован (входящий), ожидаем offer от звонящего...');
      }

      setState(() => _callState = CallState.ringing);
      _startDurationTimer();
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
      final newUri = uri.replace(queryParameters: {
        ...uri.queryParameters,
        'platform': 'WEB',
        'appVersion': '1.1',
        'version': '5',
        'device': 'browser',
        'capabilities': '2A03F',
        'clientType': 'ONE_ME', // КРИТИЧЕСКИ ВАЖНО!
        'tgt': 'start', // ВАЖНО!
      });
      
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
          }
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
    } catch (e) {
      print('❌ Ошибка парсинга connection notification: $e');
    }
  }

  void _handleSignalingMessage(Map<String, dynamic> message) {
    print('📥 Signaling message type: ${message['type'] ?? message['command'] ?? message['notification']}');
    print('📥 Full message: ${message.toString().substring(0, message.toString().length > 500 ? 500 : message.toString().length)}...');
    
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
          
          print('🔍 transmitted-data: participantId=$participantId, myId=$myId');
          
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
                _handleRemoteCandidate(data['candidate'] as Map<String, dynamic>);
              }
            } else {
              print('⚠️ Data is null!');
            }
          } else {
            print('⏭️ Пропускаем transmitted-data от себя или без participantId');
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
          print('📴 Звонок завершен');
          // Защита от двойного вызова
          if (_callState != CallState.ended && mounted) {
            setState(() => _callState = CallState.ended);
            _cleanup().then((_) {
              // Если используется Overlay - закрываем через сервис
              if (widget.onMinimize != null) {
                CallOverlayService.instance.closeCall();
              } else {
                // Иначе через Navigator
                if (mounted) {
                  Navigator.of(context).pop();
                }
              }
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
        _sendSignalingMessage({'command': 'pong', 'sequence': _sequenceNumber++});
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
      final parts = candidateStr.split(' ');
      if (parts.length >= 5) {
        final ip = parts[4];
        final type = candidateStr.contains('typ srflx') ? 'srflx' : 
                     candidateStr.contains('typ host') ? 'host' : 
                     candidateStr.contains('typ relay') ? 'relay' : 'unknown';
        
        // Обновляем IP собеседника (приоритет: srflx > host > relay)
        setState(() {
          _networkInfo ??= NetworkInfo();
          
          // Если ещё нет IP или новый тип приоритетнее
          final shouldUpdate = _networkInfo!.remoteAddress == null ||
              (type == 'srflx' && _networkInfo!.remoteConnectionType != 'srflx') ||
              (type == 'host' && _networkInfo!.remoteConnectionType == 'relay');
          
          if (shouldUpdate) {
            _networkInfo!.remoteAddress = ip;
            _networkInfo!.remoteConnectionType = type;
            print('Remote IP updated: $ip ($type)');
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
      }
    });
  }


  Future<void> _createPeerConnection() async {
    final configuration = {
      'iceServers': [
        // STUN серверы
        ...widget.callData.internalCallerParams.stun.urls.map((url) => {
          'urls': url,
        }),
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
        
        // Начинаем отслеживать уровень звука
        _startAudioLevelMonitoring();
      }
    };

    // Слушаем состояние соединения
    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      print('🔌 Connection State: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() => _callState = CallState.connected);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _showErrorAndClose('Соединение потеряно');
      }
    };
  }

  Future<void> _setupLocalMedia() async {
    final constraints = {
      'audio': true,
      'video': widget.isVideo ? {'facingMode': 'user'} : false,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      _localRenderer.srcObject = _localStream;

      // Добавляем треки в peer connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      setState(() {});
    } catch (e) {
      print('❌ Ошибка получения медиа: $e');
      rethrow;
    }
  }

  Future<void> _createAndSendOffer() async {
    try {
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': widget.isVideo,
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
    
    print('📤 Отправляем SDP на participantId=$recipientId (internal=${_remoteParticipantInternalId != null})');
    
    final message = {
      'command': 'transmit-data',
      'sequence': _sequenceNumber++,
      'participantId': recipientId, // INTERNAL ID собеседника!
      'data': {
        'sdp': {
          'type': description.type,
          'sdp': description.sdp,
        },
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
        }
      },
      'participantType': 'USER',
    };
    
    _sendSignalingMessage(message);
  }
  
  void _parseLocalCandidate(String candidateStr) {
    try {
      final parts = candidateStr.split(' ');
      if (parts.length >= 5) {
        final ip = parts[4];
        final type = candidateStr.contains('typ srflx') ? 'srflx' : 
                     candidateStr.contains('typ host') ? 'host' : 
                     candidateStr.contains('typ relay') ? 'relay' : 'unknown';
        
        if (type == 'srflx' && (_networkInfo?.localAddress == null || _networkInfo?.localAddress == '0.0.0.0')) {
          setState(() {
            _networkInfo ??= NetworkInfo();
            _networkInfo!.localAddress = ip;
            _networkInfo!.localConnectionType = type;
          });
          print('Local public IP: $ip ($type)');
        }
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
        
        if (name == 'websocket_connected' || name == 'signaling_connected' || name == 'call_start' || name == 'first_media_received') {
          final localAddress = item['local_address'] as String?;
          final localConnectionType = item['local_connection_type'] as String?;
          final remoteAddress = item['remote_address'] as String?;
          final remoteConnectionType = item['remote_connection_type'] as String?;
          final transport = item['transport'] as String?;
          final networkType = item['network_type'] as String?;
          final rtt = item['rtt'] as int?;
          
          if (localAddress != null || remoteAddress != null) {
            setState(() {
              _networkInfo ??= NetworkInfo();
              if (localAddress != null) _networkInfo!.localAddress = localAddress;
              if (localConnectionType != null) _networkInfo!.localConnectionType = localConnectionType;
              if (remoteAddress != null) _networkInfo!.remoteAddress = remoteAddress;
              if (remoteConnectionType != null) _networkInfo!.remoteConnectionType = remoteConnectionType;
              if (transport != null) _networkInfo!.transport = transport;
              if (networkType != null) _networkInfo!.networkType = networkType;
              if (rtt != null) _networkInfo!.rtt = rtt;
            });
            
            print('Network Info updated:');
            print('   Local: ${_networkInfo!.localAddress} (${_networkInfo!.localConnectionType})');
            print('   Remote: ${_networkInfo!.remoteAddress} (${_networkInfo!.remoteConnectionType})');
            print('   Transport: ${_networkInfo!.transport}, RTT: ${_networkInfo!.rtt}ms');
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
      }
    });
  }
  
  void _startAudioLevelMonitoring() {
    // Симуляция определения речи (в реальности нужен анализ аудио)
    // Для простоты будем рандомно показывать "говорит"
    _audioLevelTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_remoteStream != null && _callState == CallState.connected && mounted) {
        // TODO: Реализовать реальное определение уровня звука через Web Audio API
        // Пока просто рандом для демонстрации
        setState(() {
          _isRemoteSpeaking = DateTime.now().millisecondsSinceEpoch % 3 == 0;
        });
      }
    });
  }

  void _toggleMute() {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      for (var track in audioTracks) {
        track.enabled = _isMuted;
      }
      setState(() => _isMuted = !_isMuted);
    }
  }

  Future<void> _toggleVideo() async {
    if (_localStream == null || _isCleaningUp) return;
    final videoTracks = _localStream!.getVideoTracks();
    if (_isVideoEnabled) {
      for (var track in videoTracks) {
        track.enabled = false;
        await track.stop();
      }
      if (mounted) setState(() => _isVideoEnabled = false);
    } else {
      Future.microtask(() async {
        try {
          if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
            final cameraPermission = await Permission.camera.request();
            if (!cameraPermission.isGranted) return;
          }
          final videoStream = await navigator.mediaDevices.getUserMedia({'video': {'facingMode': 'user'}});
          if (_localStream == null || _isCleaningUp || !mounted) {
            videoStream.getTracks().forEach((t) => t.stop());
            return;
          }
          final newVideoTracks = videoStream.getVideoTracks();
          for (var track in newVideoTracks) {
            await _localStream!.addTrack(track);
            if (_peerConnection != null) {
              await _peerConnection!.addTrack(track, _localStream!);
            }
          }
          _localRenderer.srcObject = _localStream;
          if (mounted) setState(() => _isVideoEnabled = true);
          if (_peerConnection != null) {
            final offer = await _peerConnection!.createOffer();
            await _peerConnection!.setLocalDescription(offer);
            final recipientId = _remoteParticipantInternalId ?? widget.contactId;
            _sendSignalingMessage({
              'command': 'transmit-data',
              'sequence': _sequenceNumber++,
              'participantId': recipientId,
              'data': {'sdp': {'type': offer.type, 'sdp': offer.sdp}},
              'participantType': 'USER',
            });
          }
        } catch (e) {
          print('❌ Ошибка включения видео: $e');
        }
      });
      return;
    }
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
      }
    });
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    // TODO: Реализовать переключение динамика через platform channel
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

  void _endCall() async {
    // Защита от множественных вызовов
    if (_isCleaningUp) {
      print('⚠️ Cleanup уже в процессе, пропускаем');
      return;
    }
    
    try {
      print('📴 Завершение звонка...');
      
      setState(() => _callState = CallState.ended);
      
      final hangupType = _callState == CallState.connected ? 'HUNGUP' : 'CANCELED';
      
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
        await ApiService.instance.hangupCall(
          conversationId: widget.callData.conversationId,
          hangupType: hangupType,
          duration: _callDuration * 1000,
        ).timeout(const Duration(seconds: 3));
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
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
    
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _cleanup() async {
    // Защита от повторного вызова
    if (_isCleaningUp) {
      print('⚠️ Cleanup уже выполняется, пропускаем');
      return;
    }
    
    _isCleaningUp = true;
    print('🧹 Начинаем cleanup...');
    
    try {
      // 1. Останавливаем таймеры
      _durationTimer?.cancel();
      _durationTimer = null;
      _audioLevelTimer?.cancel();
      _audioLevelTimer = null;
      
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
      
      // 6. Dispose стримов
      try {
        await _localStream?.dispose();
        _localStream = null;
      } catch (e) {
        print('⚠️ Ошибка при dispose локального стрима (игнорируем): $e');
        _localStream = null;
      }
      
      try {
        await _remoteStream?.dispose();
        _remoteStream = null;
      } catch (e) {
        print('⚠️ Ошибка при dispose удалённого стрима (игнорируем): $e');
        _remoteStream = null;
      }
      
      // 7. Dispose рендереров
      try {
        await _localRenderer.dispose();
      } catch (e) {
        print('⚠️ Ошибка при dispose локального рендерера: $e');
      }
      
      try {
        await _remoteRenderer.dispose();
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
              // Drag indicator
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
                          const SizedBox(width: 40), // Spacer for symmetry
                          Expanded(
                            child: Text(
                              widget.contactName,
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _showNetworkInfo ? Icons.info : Icons.info_outline,
                              color: colors.primary,
                            ),
                            onPressed: () {
                              setState(() => _showNetworkInfo = !_showNetworkInfo);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _getCallStateText(),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (_callState == CallState.connected)
                        Text(
                          _formatDuration(_callDuration),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),

            // Видео (если включено)
            if (widget.isVideo) ...[
              Expanded(
                child: Stack(
                  children: [
                    // Удаленное видео (на весь экран)
                    if (_remoteStream != null)
                      RTCVideoView(_remoteRenderer, mirror: false)
                    else
                      Center(
                        child: CircularProgressIndicator(
                          color: colors.primary,
                        ),
                      ),
                    
                    // Локальное видео (в углу)
                    if (_localStream != null)
                      Positioned(
                        top: 16,
                        right: 16,
                        width: 120,
                        height: 160,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: RTCVideoView(_localRenderer, mirror: true),
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
                              // Зелёная пульсирующая обводка когда говорит
                              if (_isRemoteSpeaking && _callState == CallState.connected)
                                _SpeakingIndicator(
                                  size: 140,
                                  color: Colors.green,
                                ),
                              
                              // Сам аватар
                              ContactAvatarWidget(
                                contactId: widget.contactId,
                                originalAvatarUrl: widget.contactAvatarUrl,
                                radius: 60,
                                fallbackText: widget.contactName.isNotEmpty
                                    ? widget.contactName[0].toUpperCase()
                                    : '?',
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          if (_callState == CallState.connecting)
                            CircularProgressIndicator(color: colors.primary),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Кнопки управления
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Микрофон
                  _CallButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    label: _isMuted ? 'Откл' : 'Микрофон',
                    onPressed: _toggleMute,
                    backgroundColor: _isMuted ? colors.error : colors.surfaceContainerHighest,
                    foregroundColor: _isMuted ? colors.onError : colors.onSurface,
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
                    icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                    label: _isSpeakerOn ? 'Динамик' : 'Обычный',
                    onPressed: _toggleSpeaker,
                    backgroundColor: _isSpeakerOn ? colors.primary : colors.surfaceContainerHighest,
                    foregroundColor: _isSpeakerOn ? colors.onPrimary : colors.onSurface,
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
            child: _NetworkInfoPanel(networkInfo: _networkInfo!),
          ),
      ],
    ),
          ),
        ),
      ),
    ));
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
    FloatingCallManager.instance.removeListener(_onFloatingCallStateChanged);
    
    // Очищаем callback
    FloatingCallManager.instance.onEndCall = null;
    
    // Если используется Overlay - НЕ вызываем cleanup при dispose
    // (cleanup будет вызван только при closeCall)
    if (widget.onMinimize == null) {
      // Старый режим через Navigator - делаем cleanup
      if (!FloatingCallManager.instance.isMinimized) {
        _cleanup().then((_) {
          print('✅ Cleanup в dispose завершён');
        }).catchError((e) {
          print('❌ Ошибка в cleanup при dispose: $e');
        });
      } else {
        print('⏸️ CallScreen закрыт, но звонок минимизирован - cleanup пропущен');
      }
    } else {
      print('🎯 CallScreen dispose в Overlay режиме - cleanup управляется CallOverlayService');
    }
    
    super.dispose();
  }
}

/// Состояние звонка
enum CallState {
  connecting,
  ringing,
  connected,
  ended,
}

/// Кнопка управления звонком
class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool isLarge;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    this.isLarge = false,
  });

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
              child: Icon(
                icon,
                size: iconSize,
                color: foregroundColor,
              ),
            ),
          ),
                  _CallButton(
                    key: const ValueKey('video_button'),
                    icon: _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                    label: _isVideoEnabled ? 'Видео' : 'Камера',
                    onPressed: _toggleVideo,
                    backgroundColor: _isVideoEnabled ? colors.primary : colors.surfaceContainerHighest,
                    foregroundColor: _isVideoEnabled ? colors.onPrimary : colors.onSurface,
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

/// Модель сетевой информации
class NetworkInfo {
  String? localAddress;
  String? localConnectionType;
  String? remoteAddress;
  String? remoteConnectionType;
  String? transport;
  String? networkType;
  int? rtt;
}

/// Панель отображения сетевой информации
class _NetworkInfoPanel extends StatelessWidget {
  final NetworkInfo networkInfo;

  const _NetworkInfoPanel({required this.networkInfo});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: colors.surface.withValues(alpha: 0.95),
      child: Container(
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
                  value: _formatConnectionType(networkInfo.localConnectionType!),
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
                  value: _formatConnectionType(networkInfo.remoteConnectionType!),
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
          ],
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
  State<_AnimatedCallBackground> createState() => _AnimatedCallBackgroundState();
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
  }) : super(
          repaint: Listenable.merge([animation1, animation2, animation3]),
        );

  @override
  void paint(Canvas canvas, Size size) {
    final maxRadius = size.width > size.height ? size.width : size.height;

    // Рисуем 3 волны с разными параметрами ОТ ЦЕНТРА АВАТАРА
    _drawWave(canvas, avatarCenter, maxRadius, animation1.value, 0.15, 0.8);
    _drawWave(canvas, avatarCenter, maxRadius, animation2.value, 0.10, 0.6);
    _drawWave(canvas, avatarCenter, maxRadius, animation3.value, 0.08, 0.4);
  }

  void _drawWave(Canvas canvas, Offset center, double maxRadius,
      double progress, double opacity, double scale) {
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

  const _SpeakingIndicator({
    required this.size,
    required this.color,
  });

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
    
    _animation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
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
