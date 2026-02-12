/// A Dart package for MAX messenger call API integration using TCP sockets.
///
/// This library provides a socket-based implementation of the MAX messenger
/// call API, designed specifically for Komet Client.
///
/// ## Features
/// - Phone number authentication with SMS verification
/// - Outgoing calls to other MAX users with WebRTC
/// - Incoming call notifications and handling
/// - TCP socket connection for API (MessagePack + LZ4)
/// - WebSocket for signaling
/// - WebRTC for media (audio/video)
///
/// ## Architecture
/// - **OneMe API**: TCP socket with MessagePack for authentication and call notifications
/// - **Calls API**: HTTP REST API for session management
/// - **Signaling**: WebSocket for WebRTC signaling
/// - **Media**: WebRTC peer connection for audio/video streams
///
/// ## Usage
///
/// ```dart
/// import 'package:maxcalls_dart/maxcalls_dart.dart';
///
/// // Initialize the client
/// final calls = Calls(debug: true);
///
/// // Set session params (should be persisted)
/// calls.setSessionParams(
///   mtInstanceId: 'saved-mt-instance-id',
///   clientSessionId: 1,
///   deviceId: 'saved-device-id',
/// );
///
/// // Login with phone number
/// final token = await calls.requestVerification('+1234567890');
/// // ... receive SMS code ...
/// await calls.enterCode(token, '123456');
///
/// // Make an outgoing call
/// final connection = await calls.call('user-id');
/// print('Local stream: ${connection.localStream}');
/// print('Remote stream: ${connection.remoteStream}');
///
/// // Wait for incoming call
/// final incomingConnection = await calls.waitForCall();
/// 
/// // Close connection when done
/// await connection.close();
/// ```
library maxcalls_dart;

// Core classes
export 'src/calls.dart';
export 'src/connection.dart';

// Models
export 'src/models/incoming_call.dart';
export 'src/models/client_hello.dart';
export 'src/models/verification_request.dart';
export 'src/models/code_enter.dart';
export 'src/models/chat_sync.dart';
export 'src/models/call_token.dart';

// Protocol clients (for advanced usage)
export 'src/protocol/calls_client.dart';

// Signaling (for advanced usage)
export 'src/api/signaling/client.dart';
export 'src/api/signaling/messages/credentials.dart';
export 'src/api/signaling/messages/new_candidate.dart';

// Logger
export 'src/logger/logger.dart';
