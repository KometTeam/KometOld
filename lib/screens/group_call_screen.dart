import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:gwid/models/video_conference.dart';
import 'package:gwid/services/group_call_service.dart';

class GroupCallScreen extends StatefulWidget {
  final VideoConference conference;
  final ConversationConnection connection;

  const GroupCallScreen({
    Key? key,
    required this.conference,
    required this.connection,
  }) : super(key: key);

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  final GroupCallService _groupCallService = GroupCallService.instance;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _isAudioMuted = false;
  bool _isVideoMuted = true;

  @override
  void initState() {
    super.initState();
    // Запускаем инициализацию асинхронно чтобы не блокировать UI
    Future.microtask(() => _initializeCall());
  }

  Future<void> _initializeCall() async {
    try {
      print('🎬 Инициализация группового звонка...');
      
      await _localRenderer.initialize();
      print('✅ Локальный рендерер инициализирован');
      
      // Подключаемся к серверу видеозвонков с таймаутом
      await _groupCallService.connectToVideoServer(widget.connection)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Таймаут подключения к серверу звонков');
            },
          );
      print('✅ Подключение к серверу установлено');
      
      if (!mounted) return;
      
      // Запускаем локальные медиа
      await _groupCallService.startLocalMedia(
        audio: !_isAudioMuted,
        video: !_isVideoMuted,
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('⚠️ Таймаут запуска медиа');
        },
      );
      print('✅ Локальные медиа запущены');

      if (!mounted) return;
      
      if (_groupCallService.localStream != null) {
        _localRenderer.srcObject = _groupCallService.localStream;
        print('✅ Локальный поток установлен');
      }

      _groupCallService.addListener(_onServiceUpdate);
      
      if (mounted) {
        setState(() {});
      }
      
      print('🎉 Инициализация завершена успешно');
    } catch (e, stackTrace) {
      print('❌ Ошибка инициализации группового звонка: $e');
      print(stackTrace);
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка подключения: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      
      // Возвращаемся назад
      Navigator.of(context).pop();
    }
  }

  void _onServiceUpdate() {
    if (mounted) {
      // Проверяем не закрылось ли соединение
      if (!_groupCallService.isConnected) {
        print('🔌 Соединение закрыто, возвращаемся назад');
        Navigator.of(context).pop();
        return;
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    _groupCallService.removeListener(_onServiceUpdate);
    _groupCallService.disconnect();
    _localRenderer.dispose();
    super.dispose();
  }

  void _toggleAudio() {
    _groupCallService.toggleAudio();
    setState(() {
      _isAudioMuted = !_groupCallService.currentMediaSettings.isAudioEnabled;
    });
  }

  void _toggleVideo() {
    _groupCallService.toggleVideo();
    setState(() {
      _isVideoMuted = !_groupCallService.currentMediaSettings.isVideoEnabled;
    });
  }

  void _endCall() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final participants = _groupCallService.participants;
    final remoteStreams = _groupCallService.remoteStreams;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.conference.callName,
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            Text(
              '${participants.length + 1} участников',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          // Grid layout for participants
          if (participants.isEmpty)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: colors.primary,
                    child: Text(
                      widget.conference.owner.displayName.isNotEmpty
                          ? widget.conference.owner.displayName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(height: 24),
                  Text(
                    widget.conference.owner.displayName,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    _groupCallService.isConnected ? 'Ожидание участников...' : 'Подключение...',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            )
          else
            _buildParticipantsGrid(participants, remoteStreams),

          // Local video preview (small corner view)
          if (!_isVideoMuted && _groupCallService.localStream != null)
            Positioned(
              top: 100,
              right: 16,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 120,
                  height: 160,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    children: [
                      RTCVideoView(_localRenderer, mirror: true),
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Вы',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Call controls
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _CallButton(
                  icon: _isAudioMuted ? Icons.mic_off : Icons.mic,
                  label: _isAudioMuted ? 'Откл' : 'Микрофон',
                  onPressed: _toggleAudio,
                  backgroundColor: _isAudioMuted ? colors.error : colors.surfaceContainerHighest,
                  foregroundColor: _isAudioMuted ? colors.onError : colors.onSurface,
                ),
                
                if (widget.conference.isVideoCall)
                  _CallButton(
                    icon: _isVideoMuted ? Icons.videocam_off : Icons.videocam,
                    label: _isVideoMuted ? 'Откл' : 'Камера',
                    onPressed: _toggleVideo,
                    backgroundColor: _isVideoMuted ? colors.error : colors.surfaceContainerHighest,
                    foregroundColor: _isVideoMuted ? colors.onError : colors.onSurface,
                  ),

                _CallButton(
                  icon: Icons.call_end,
                  label: 'Завершить',
                  onPressed: _endCall,
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  isLarge: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantsGrid(
    Map<int, ConferenceParticipant> participants,
    Map<int, MediaStream> remoteStreams,
  ) {
    final participantList = participants.entries.toList();
    final count = participantList.length;
    
    // Determine grid layout based on participant count
    int crossAxisCount = 1;
    if (count > 1) crossAxisCount = 2;
    if (count > 4) crossAxisCount = 3;

    return Padding(
      padding: EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 140),
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.75,
        ),
        itemCount: count,
        itemBuilder: (context, index) {
          final entry = participantList[index];
          final participantId = entry.key;
          final participant = entry.value;
          final stream = remoteStreams[participantId];

          return _ParticipantTile(
            participant: participant,
            participantId: participantId,
            stream: stream,
          );
        },
      ),
    );
  }
}

class _ParticipantTile extends StatefulWidget {
  final ConferenceParticipant participant;
  final int participantId;
  final MediaStream? stream;

  const _ParticipantTile({
    required this.participant,
    required this.participantId,
    required this.stream,
  });

  @override
  State<_ParticipantTile> createState() => _ParticipantTileState();
}

class _ParticipantTileState extends State<_ParticipantTile> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initRenderer();
  }

  Future<void> _initRenderer() async {
    await _renderer.initialize();
    if (widget.stream != null) {
      _renderer.srcObject = widget.stream;
    }
    if (mounted) {
      setState(() {
        _initialized = true;
      });
    }
  }

  @override
  void didUpdateWidget(_ParticipantTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stream != oldWidget.stream && _initialized) {
      _renderer.srcObject = widget.stream;
    }
  }

  @override
  void dispose() {
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasVideo = widget.stream != null && 
                     widget.participant.mediaSettings.isVideoEnabled;
    final isScreenSharing = widget.participant.mediaSettings.isScreenSharingEnabled;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isScreenSharing ? Colors.blue : Colors.white24, 
            width: isScreenSharing ? 3 : 1,
          ),
        ),
        child: Stack(
          children: [
            // Video or placeholder
            if (hasVideo && _initialized)
              Positioned.fill(
                child: RTCVideoView(_renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              )
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: colors.primary,
                      child: Text(
                        widget.participant.externalId.id.isNotEmpty
                            ? widget.participant.externalId.id[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (isScreenSharing) ...[
                      SizedBox(height: 12),
                      Icon(
                        Icons.screen_share,
                        color: Colors.blue,
                        size: 32,
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Демонстрация экрана',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

            // Participant info overlay
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black87,
                      Colors.black54,
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'User ${widget.participant.externalId.id}',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: 8),
                    if (!widget.participant.mediaSettings.isAudioEnabled)
                      Icon(
                        Icons.mic_off,
                        size: 16,
                        color: Colors.red,
                      ),
                  ],
                ),
              ),
            ),

            // Connection state indicator
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: widget.participant.state == 'ACCEPTED' 
                      ? Colors.green.withOpacity(0.8)
                      : Colors.orange.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.participant.state == 'ACCEPTED' ? 'В сети' : widget.participant.state,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
        InkWell(
          onTap: onPressed,
          customBorder: CircleBorder(),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: iconSize,
              color: foregroundColor,
            ),
          ),
        ),
        SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
