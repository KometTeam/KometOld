import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'ice/connector.dart';
import 'logger/logger.dart';

/// Represents an established call connection with a remote peer.
/// It wraps a WebRTC connection and provides methods to manage the connection lifecycle.
class Connection {
  final IceConnector _connector;
  final MediaStream? _localStream;
  final MediaStream? _remoteStream;
  final RTCIceConnectionState _connectionState = RTCIceConnectionState.RTCIceConnectionStateNew;

  Connection({
    required IceConnector connector,
    MediaStream? localStream,
    MediaStream? remoteStream,
  })  : _connector = connector,
        _localStream = localStream,
        _remoteStream = remoteStream;

  /// Get the local media stream (audio/video from this device)
  MediaStream? get localStream => _localStream;

  /// Get the remote media stream (audio/video from the other peer)
  MediaStream? get remoteStream => _remoteStream;

  /// Get the current ICE connection state
  RTCIceConnectionState get connectionState => _connectionState;

  /// Check if the connection is established
  bool get isConnected =>
      _connectionState == RTCIceConnectionState.RTCIceConnectionStateConnected ||
      _connectionState == RTCIceConnectionState.RTCIceConnectionStateCompleted;


  /// Wait for the connection to be established
  Future<void> waitForConnection({Duration timeout = const Duration(seconds: 30)}) async {
    final startTime = DateTime.now();
    
    while (!isConnected) {
      if (DateTime.now().difference(startTime) > timeout) {
        throw TimeoutException('Connection timeout');
      }
      
      if (_connectionState == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          _connectionState == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        throw StateError('Connection failed or closed');
      }
      
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Close the connection and release all associated resources.
  /// After calling close, the Connection should not be used.
  Future<void> close() async {
    MaxCallsLogger.info('Closing connection');
    await _connector.close();
  }
}
