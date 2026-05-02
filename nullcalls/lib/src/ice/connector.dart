import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../logger/logger.dart';
import 'agent.dart';

class IceConnector {
  final IceAgent _agent = IceAgent();
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  Future<void> initialize({
    required List<String> stunServers,
    required List<String> turnServers,
    required String turnUsername,
    required String turnPassword,
  }) async {
    await _agent.initialize(
      stunServers: stunServers,
      turnServers: turnServers,
      turnUsername: turnUsername,
      turnPassword: turnPassword,
    );
  }

  Future<void> setupLocalMedia({bool audio = true, bool video = false}) async {
    MaxCallsLogger.debug('Setting up local media');

    final constraints = {
      'audio': audio,
      'video': video,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    
    // Add tracks to peer connection
    _localStream?.getTracks().forEach((track) {
      _agent.peerConnection?.addTrack(track, _localStream!);
    });

    MaxCallsLogger.info('Local media setup complete');
  }

  void onRemoteStream(Function(MediaStream) callback) {
    _agent.peerConnection?.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        MaxCallsLogger.info('Received remote stream');
        callback(_remoteStream!);
      }
    };
  }

  void onIceCandidate(Function(RTCIceCandidate) callback) {
    _agent.onIceCandidate(callback);
  }

  void onIceConnectionState(Function(RTCIceConnectionState) callback) {
    _agent.onIceConnectionState(callback);
  }

  Future<RTCSessionDescription> createOffer() async {
    MaxCallsLogger.debug('Creating offer');
    final offer = await _agent.peerConnection!.createOffer();
    await _agent.peerConnection!.setLocalDescription(offer);
    MaxCallsLogger.info('Offer created and set as local description');
    return offer;
  }

  Future<RTCSessionDescription> createAnswer() async {
    MaxCallsLogger.debug('Creating answer');
    final answer = await _agent.peerConnection!.createAnswer();
    await _agent.peerConnection!.setLocalDescription(answer);
    MaxCallsLogger.info('Answer created and set as local description');
    return answer;
  }

  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    MaxCallsLogger.debug('Setting remote description');
    await _agent.peerConnection!.setRemoteDescription(description);
    MaxCallsLogger.info('Remote description set');
  }

  Future<void> addIceCandidate(String candidateString) async {
    await _agent.addIceCandidate(candidateString);
  }

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  Future<void> close() async {
    await _localStream?.dispose();
    await _remoteStream?.dispose();
    await _agent.close();
  }
}
