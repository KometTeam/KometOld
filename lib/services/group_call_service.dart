import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:gwid/models/video_conference.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

class GroupCallService extends ChangeNotifier {
  static final GroupCallService _instance = GroupCallService._internal();
  static GroupCallService get instance => _instance;

  GroupCallService._internal();

  WebSocketChannel? _videoSocket;
  StreamSubscription? _videoSocketSubscription;
  bool _isConnected = false;
  
  VideoConference? _currentConference;
  ConversationConnection? _currentConnection;
  
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final Map<int, MediaStream> _remoteStreams = {};
  final Map<int, ConferenceParticipant> _participants = {};
  
  MediaSettings _currentMediaSettings = MediaSettings();
  
  int _messageSequence = 0;
  final Map<int, Completer<dynamic>> _pendingResponses = {};
  
  // Track ICE candidates for each participant
  final Map<int, RTCPeerConnection> _peerConnections = {};

  VideoConference? get currentConference => _currentConference;
  ConversationConnection? get currentConnection => _currentConnection;
  bool get isConnected => _isConnected;
  MediaSettings get currentMediaSettings => _currentMediaSettings;
  Map<int, MediaStream> get remoteStreams => Map.unmodifiable(_remoteStreams);
  Map<int, ConferenceParticipant> get participants => Map.unmodifiable(_participants);
  MediaStream? get localStream => _localStream;

  Future<void> connectToVideoServer(ConversationConnection connection) async {
    if (_isConnected) {
      print('⚠️ Already connected to video server');
      return;
    }

    _currentConnection = connection;

    try {
      print('🔌 [1/4] Connecting to video server: ${connection.endpoint}');
      _videoSocket = WebSocketChannel.connect(Uri.parse(connection.endpoint));
      print('✅ [1/4] WebSocket created');
      
      _videoSocketSubscription = _videoSocket!.stream.listen(
        _handleVideoMessage,
        onError: (error) {
          print('❌ Video WebSocket error: $error');
          _isConnected = false;
          notifyListeners();
        },
        onDone: () {
          print('📴 Video WebSocket closed');
          _isConnected = false;
          notifyListeners();
        },
      );
      print('✅ [2/4] WebSocket listener started');

      _isConnected = true;
      notifyListeners();

      print('🔧 [3/4] Initializing peer connection...');
      await _initializePeerConnection(connection.conversationParams);
      print('✅ [3/4] Peer connection initialized');
      
      print('📤 [4/4] Sending initial media settings...');
      await _sendChangeMediaSettings(_currentMediaSettings);
      print('✅ [4/4] Connection complete!');

    } catch (e, stackTrace) {
      print('❌ Error connecting to video server: $e');
      print('Stack trace: $stackTrace');
      _isConnected = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _initializePeerConnection(ConversationParams params) async {
    print('   🔧 Building ICE servers configuration...');
    final iceServers = <Map<String, dynamic>>[];
    
    for (final stunUrl in params.stun.urls) {
      iceServers.add({'urls': stunUrl});
    }
    
    if (params.turn.urls.isNotEmpty) {
      iceServers.add({
        'urls': params.turn.urls,
        'username': params.turn.username,
        'credential': params.turn.credential,
      });
    }
    print('   ✅ ICE servers: ${iceServers.length} configured');

    final configuration = {
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    };

    print('   🔧 Creating RTCPeerConnection...');
    _peerConnection = await createPeerConnection(configuration);
    print('   ✅ RTCPeerConnection created');

    _peerConnection!.onIceCandidate = (candidate) {
      print('🧊 ICE Candidate: ${candidate.candidate}');
    };

    _peerConnection!.onTrack = (event) {
      print('🎥 Remote track received');
      if (event.streams.isNotEmpty) {
        final stream = event.streams[0];
        print('Stream ID: ${stream.id}');
      }
    };

    _peerConnection!.onConnectionState = (state) {
      print('🔗 Connection state: $state');
    };

    print('   ✅ Peer connection callbacks configured');
  }

  Future<void> startLocalMedia({bool audio = true, bool video = false}) async {
    try {
      print('🎤 [1/5] Starting local media (audio: $audio, video: $video)...');
      final mediaConstraints = {
        'audio': audio,
        'video': video ? {'facingMode': 'user'} : false,
      };
      print('   Constraints: $mediaConstraints');

      print('🎤 [2/5] Requesting getUserMedia... (This may take a few seconds)');
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Timeout waiting for getUserMedia');
            },
          );
      print('✅ [2/5] getUserMedia completed');

      print('🎤 [3/5] Adding tracks to peer connection...');
      _localStream!.getTracks().forEach((track) {
        _peerConnection?.addTrack(track, _localStream!);
        print('   Added track: ${track.kind}');
      });
      print('✅ [3/5] Tracks added');

      print('🎤 [4/5] Updating media settings...');
      _currentMediaSettings = _currentMediaSettings.copyWith(
        isAudioEnabled: audio,
        isVideoEnabled: video,
      );

      await _sendChangeMediaSettings(_currentMediaSettings);
      print('✅ [4/5] Media settings sent');

      notifyListeners();
      print('✅ [5/5] Local media started successfully');
    } catch (e, stackTrace) {
      print('❌ Error starting local media: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> toggleAudio() async {
    if (_localStream == null) return;

    final audioTracks = _localStream!.getAudioTracks();
    if (audioTracks.isNotEmpty) {
      final newState = !audioTracks.first.enabled;
      audioTracks.first.enabled = newState;
      
      _currentMediaSettings = _currentMediaSettings.copyWith(
        isAudioEnabled: newState,
      );
      
      await _sendChangeMediaSettings(_currentMediaSettings);
      notifyListeners();
    }
  }

  Future<void> toggleVideo() async {
    if (_localStream == null) return;

    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isNotEmpty) {
      final newState = !videoTracks.first.enabled;
      videoTracks.first.enabled = newState;
      
      _currentMediaSettings = _currentMediaSettings.copyWith(
        isVideoEnabled: newState,
      );
      
      await _sendChangeMediaSettings(_currentMediaSettings);
      notifyListeners();
    }
  }

  Future<void> _sendChangeMediaSettings(MediaSettings settings) async {
    if (!_isConnected || _videoSocket == null) return;

    final message = {
      'command': 'change-media-settings',
      'sequence': ++_messageSequence,
      'mediaSettings': settings.toJson(),
    };

    _videoSocket!.sink.add(jsonEncode(message));
    print('📤 Sent media settings: ${settings.toJson()}');
  }

  void _handleVideoMessage(dynamic data) {
    try {
      final message = jsonDecode(data as String);
      
      // Handle different message types
      if (message['type'] == 'notification') {
        _handleNotification(message);
      } else if (message['type'] == 'response') {
        _handleResponse(message);
      } else if (message['command'] == 'transmit-data') {
        _handleTransmitData(message);
      } else {
        print('📨 Video server message: ${message['type'] ?? message['command'] ?? message['notification']}');
      }
    } catch (e) {
      print('❌ Error handling video message: $e');
      print('Message data: $data');
    }
  }

  void _handleNotification(Map<String, dynamic> message) {
    final notification = message['notification'];

    switch (notification) {
      case 'connection':
        print('✅ Connected to video server');
        break;
      case 'settings-update':
        print('⚙️ Settings updated');
        break;
      case 'participant-joined':
        _handleParticipantJoined(message);
        break;
      case 'registered-peer':
        _handleRegisteredPeer(message);
        break;
      case 'hungup':
        _handleParticipantHungUp(message);
        break;
      case 'closed-conversation':
        print('🔚 Conversation closed');
        disconnect();
        break;
      default:
        print('ℹ️ Unknown notification: $notification');
    }
  }

  void _handleParticipantJoined(Map<String, dynamic> message) {
    try {
      final notification = ParticipantJoinedNotification.fromJson(message);
      print('👤 Participant joined: ${notification.participantId}');
      print('   State: ${notification.participant.state}');
      print('   Audio: ${notification.mediaSettings.isAudioEnabled}');
      print('   Video: ${notification.mediaSettings.isVideoEnabled}');
      
      _participants[notification.participantId] = notification.participant;
      notifyListeners();
    } catch (e) {
      print('❌ Error handling participant-joined: $e');
    }
  }

  void _handleRegisteredPeer(Map<String, dynamic> message) {
    try {
      final notification = RegisteredPeerNotification.fromJson(message);
      print('🔗 Peer registered: ${notification.participantId}');
      print('   Platform: ${notification.platform}');
      print('   Client: ${notification.clientType}');
      print('   Peer ID: ${notification.peerId.id}');
    } catch (e) {
      print('❌ Error handling registered-peer: $e');
    }
  }

  void _handleParticipantHungUp(Map<String, dynamic> message) {
    final participantId = message['participantId'] as int?;
    if (participantId != null) {
      print('📴 Participant hung up: $participantId');
      _participants.remove(participantId);
      _remoteStreams.remove(participantId);
      _peerConnections[participantId]?.close();
      _peerConnections.remove(participantId);
      notifyListeners();
    }
  }

  void _handleTransmitData(Map<String, dynamic> message) {
    try {
      final command = TransmitDataCommand.fromJson(message);
      print('📨 Transmit data from participant ${command.participantId}');
      
      final data = command.data;
      
      // Handle SDP (offer/answer)
      if (data.containsKey('sdp')) {
        _handleRemoteSdp(command.participantId, data['sdp']);
      }
      
      // Handle ICE candidate
      if (data.containsKey('candidate')) {
        _handleRemoteCandidate(command.participantId, data['candidate']);
      }
    } catch (e) {
      print('❌ Error handling transmit-data: $e');
    }
  }

  Future<void> _handleRemoteSdp(int participantId, Map<String, dynamic> sdpData) async {
    try {
      final type = sdpData['type'] as String;
      final sdp = sdpData['sdp'] as String;
      
      print('🎯 Received SDP $type from participant $participantId');
      
      // Get or create peer connection for this participant
      RTCPeerConnection? pc = _peerConnections[participantId];
      if (pc == null) {
        pc = await _createPeerConnectionForParticipant(participantId);
        _peerConnections[participantId] = pc;
      }
      
      // Set remote description
      final rtcSdp = RTCSessionDescription(sdp, type);
      await pc.setRemoteDescription(rtcSdp);
      print('✅ Set remote SDP for participant $participantId');
      
      // If it's an offer, create and send answer
      if (type == 'offer') {
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        
        // Send answer back
        _sendTransmitData(participantId, {
          'sdp': {
            'type': answer.type,
            'sdp': answer.sdp,
          },
          'animojiVersion': 1,
        });
        print('📤 Sent SDP answer to participant $participantId');
      }
    } catch (e) {
      print('❌ Error handling remote SDP: $e');
    }
  }

  Future<void> _handleRemoteCandidate(int participantId, Map<String, dynamic> candidateData) async {
    try {
      final candidateStr = candidateData['candidate'] as String?;
      final sdpMid = candidateData['sdpMid'] as String?;
      final sdpMLineIndex = candidateData['sdpMLineIndex'] as int?;
      
      if (candidateStr == null) return;
      
      print('🧊 Received ICE candidate from participant $participantId');
      
      final pc = _peerConnections[participantId];
      if (pc != null) {
        final candidate = RTCIceCandidate(
          candidateStr,
          sdpMid ?? '',
          sdpMLineIndex ?? 0,
        );
        await pc.addCandidate(candidate);
        print('✅ Added ICE candidate for participant $participantId');
      } else {
        print('⚠️ No peer connection found for participant $participantId');
      }
    } catch (e) {
      print('❌ Error handling remote candidate: $e');
    }
  }

  Future<RTCPeerConnection> _createPeerConnectionForParticipant(int participantId) async {
    final params = _currentConnection?.conversationParams;
    if (params == null) {
      throw Exception('No connection params available');
    }
    
    final iceServers = <Map<String, dynamic>>[];
    
    for (final stunUrl in params.stun.urls) {
      iceServers.add({'urls': stunUrl});
    }
    
    if (params.turn.urls.isNotEmpty) {
      iceServers.add({
        'urls': params.turn.urls,
        'username': params.turn.username,
        'credential': params.turn.credential,
      });
    }

    final configuration = {
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    };

    final pc = await createPeerConnection(configuration);

    // Handle ICE candidates
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        print('🧊 Local ICE candidate for participant $participantId');
        _sendTransmitData(participantId, {
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
            'usernameFragment': candidate.candidate?.split(' ')[5] ?? '',
          }
        });
      }
    };

    // Handle remote tracks
    pc.onTrack = (event) {
      print('🎥 Remote track received from participant $participantId');
      if (event.streams.isNotEmpty) {
        final stream = event.streams[0];
        _remoteStreams[participantId] = stream;
        notifyListeners();
        print('✅ Added remote stream for participant $participantId');
      }
    };

    pc.onConnectionState = (state) {
      print('🔗 Connection state for participant $participantId: $state');
    };

    // Add local stream to this peer connection
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        pc.addTrack(track, _localStream!);
      });
    }

    print('✅ Created peer connection for participant $participantId');
    return pc;
  }

  void _sendTransmitData(int participantId, Map<String, dynamic> data) {
    if (!_isConnected || _videoSocket == null) return;

    final message = TransmitDataCommand(
      command: 'transmit-data',
      sequence: ++_messageSequence,
      participantId: participantId,
      data: data,
      participantType: 'USER',
    );

    _videoSocket!.sink.add(jsonEncode(message.toJson()));
  }

  void _handleResponse(Map<String, dynamic> message) {
    final sequence = message['sequence'] as int?;
    if (sequence != null && _pendingResponses.containsKey(sequence)) {
      _pendingResponses[sequence]!.complete(message);
      _pendingResponses.remove(sequence);
    }
  }

  Future<void> disconnect() async {
    print('🔌 Disconnecting from group call');

    _videoSocketSubscription?.cancel();
    _videoSocketSubscription = null;

    _videoSocket?.sink.close(status.goingAway);
    _videoSocket = null;

    await _localStream?.dispose();
    _localStream = null;

    for (final stream in _remoteStreams.values) {
      await stream.dispose();
    }
    _remoteStreams.clear();

    await _peerConnection?.close();
    _peerConnection = null;

    // Close all participant peer connections
    for (final pc in _peerConnections.values) {
      await pc.close();
    }
    _peerConnections.clear();
    _participants.clear();

    _isConnected = false;
    _currentConference = null;
    _currentConnection = null;
    _currentMediaSettings = MediaSettings();

    notifyListeners();
    print('✅ Disconnected from group call');
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
