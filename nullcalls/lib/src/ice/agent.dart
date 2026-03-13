import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../logger/logger.dart';

class IceAgent {
  RTCPeerConnection? _peerConnection;
  final List<Map<String, dynamic>> _iceServers = [];

  Future<void> initialize({
    required List<String> stunServers,
    required List<String> turnServers,
    required String turnUsername,
    required String turnPassword,
  }) async {
    MaxCallsLogger.debug('Initializing ICE agent');

    // Parse STUN servers
    for (final stunUrl in stunServers) {
      _iceServers.add({
        'urls': [stunUrl],
      });
    }

    // Parse TURN servers
    _iceServers.add({
      'urls': turnServers,
      'username': turnUsername,
      'credential': turnPassword,
    });

    // Create peer connection
    final configuration = {
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
    };

    _peerConnection = await createPeerConnection(configuration);
    MaxCallsLogger.info('ICE agent initialized');
  }

  RTCPeerConnection? get peerConnection => _peerConnection;

  void onIceCandidate(Function(RTCIceCandidate) callback) {
    _peerConnection?.onIceCandidate = (candidate) {
      MaxCallsLogger.debug('New ICE candidate: ${candidate.candidate}');
      callback(candidate);
    };
  }

  void onIceConnectionState(Function(RTCIceConnectionState) callback) {
    _peerConnection?.onIceConnectionState = (state) {
      MaxCallsLogger.info('ICE connection state: $state');
      callback(state);
    };
  }

  Future<void> addIceCandidate(String candidateString) async {
    if (_peerConnection == null) {
      throw StateError('Peer connection not initialized');
    }

    try {
      final candidate = RTCIceCandidate(
        candidateString,
        '',
        0,
      );
      await _peerConnection!.addCandidate(candidate);
      MaxCallsLogger.debug('Added ICE candidate');
    } catch (e) {
      MaxCallsLogger.error('Failed to add ICE candidate', e);
    }
  }

  Future<void> close() async {
    await _peerConnection?.close();
    _peerConnection = null;
  }
}
