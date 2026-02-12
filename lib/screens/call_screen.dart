import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:gwid/models/call_response.dart';
import 'package:gwid/api/api_service.dart';
import 'package:gwid/widgets/contact_avatar_widget.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
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

  const CallScreen({
    super.key,
    required this.callData,
    required this.contactName,
    required this.contactId,
    this.contactAvatarUrl,
    required this.isOutgoing,
    this.isVideo = false,
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
  int _callDuration = 0;
  Timer? _durationTimer;

  @override
  void initState() {
    super.initState();
    _initializeCall();
  }

  Future<void> _initializeCall() async {
    try {
      // Инициализируем рендереры
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      print('📞 Инициализация звонка через WebSocket signaling');

      // Подключаемся к WebSocket signaling серверу
      await _connectToSignaling();

      // Создаем peer connection
      await _createPeerConnection();

      // Устанавливаем локальный стрим
      await _setupLocalMedia();

      // Создаем и отправляем offer СРАЗУ после подключения
      await _createAndSendOffer();

      setState(() => _callState = CallState.ringing);
      _startDurationTimer();
      
      print('✅ WebRTC инициализирован, ожидаем ответа...');
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
          // Проверяем closeCode и closeReason
          final closeCode = _signalingChannel?.closeCode;
          final closeReason = _signalingChannel?.closeReason;
          print('🔌 Close code: $closeCode');
          print('🔌 Close reason: $closeReason');
        },
      );
      
      // Ждем подключения
      await _signalingChannel!.ready;
      print('✅ WebSocket подключен');
      
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

  void _handleSignalingMessage(Map<String, dynamic> message) {
    print('📥 Signaling message type: ${message['type'] ?? message['command']}');
    print('📥 Full message: $message');
    
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
        case 'transmitted-data':
          // Данные от ДРУГОГО участника (не от нас!)
          final participantId = message['participantId'] as int?;
          final myId = widget.callData.internalCallerParams.id.internal;
          
          if (participantId != null && participantId != myId) {
            print('📨 Получены данные от участника $participantId');
            final data = message['data'] as Map<String, dynamic>?;
            if (data != null) {
              // Проверяем есть ли SDP
              if (data.containsKey('sdp')) {
                _handleRemoteDescription(data['sdp'] as Map<String, dynamic>);
              }
              // Проверяем есть ли ICE candidate
              if (data.containsKey('candidate')) {
                _handleRemoteCandidate(data['candidate'] as Map<String, dynamic>);
              }
            }
          }
          break;
          
        case 'accepted-call':
          print('✅ Звонок принят другим участником!');
          setState(() => _callState = CallState.connected);
          break;
          
        case 'hungup':
        case 'closed-conversation':
          print('📴 Звонок завершен');
          Navigator.of(context).pop();
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

  void _sendSignalingMessage(Map<String, dynamic> message) {
    if (_signalingChannel == null) {
      print('⚠️ WebSocket не подключен');
      return;
    }
    
    final jsonString = json.encode(message);
    _signalingChannel!.sink.add(jsonString);
    print('📤 Отправлено signaling сообщение: ${message['command']}');
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
    // ПРАВИЛЬНЫЙ формат как у официального клиента!
    final message = {
      'command': 'transmit-data',
      'sequence': _sequenceNumber++,
      'participantId': widget.callData.internalCallerParams.id.internal, // ID звонящего
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
    // Формат как у официального клиента (если нужен)
    final message = {
      'command': 'transmit-data',
      'sequence': _sequenceNumber++,
      'participantId': widget.callData.internalCallerParams.id.internal,
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

  void _sendAcceptCall() {
    print('📞 Отправка accept-call');
    final message = {
      'command': 'accept-call',
      'sequence': _sequenceNumber++,
      'participant-id': 1, // ID участника
    };
    
    _sendSignalingMessage(message);
  }


  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_callState == CallState.connected) {
        setState(() => _callDuration++);
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

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    // TODO: Реализовать переключение динамика через platform channel
  }

  void _endCall() async {
    try {
      print('📴 Завершение звонка...');
      
      // Определяем тип завершения
      final hangupType = _callState == CallState.connected ? 'HUNGUP' : 'CANCELED';
      
      // Отправляем уведомление об отмене/завершении звонка
      await ApiService.instance.hangupCall(
        conversationId: widget.callData.conversationId,
        hangupType: hangupType,
        duration: _callDuration * 1000, // в миллисекундах
      );
      
      await _cleanup();
      
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('❌ Ошибка при завершении звонка: $e');
      
      await _cleanup();
      
      if (mounted) {
        Navigator.of(context).pop();
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
    _durationTimer?.cancel();
    _signalingSubscription?.cancel();
    await _signalingChannel?.sink.close();
    
    await _localStream?.dispose();
    await _remoteStream?.dispose();
    await _peerConnection?.close();
    await _localRenderer.dispose();
    await _remoteRenderer.dispose();
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Заголовок
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Text(
                    widget.contactName,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
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
              // Аватар для аудио звонка
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Аватар контакта
                      ContactAvatarWidget(
                        contactId: widget.contactId,
                        originalAvatarUrl: widget.contactAvatarUrl,
                        radius: 60,
                        fallbackText: widget.contactName.isNotEmpty
                            ? widget.contactName[0].toUpperCase()
                            : '?',
                      ),
                      const SizedBox(height: 24),
                      if (_callState == CallState.connecting)
                        CircularProgressIndicator(color: colors.primary),
                    ],
                  ),
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
                    onPressed: _endCall,
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
    _cleanup();
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
