# nullcalls
An okcalls server client library.

# Installation
Add this to your `pubsec.yaml`:
```yaml
dependencies:
  maxcalls_dart:
    path: /path/to/library/maxcalls_dart
```

Then run:
```bash
dart pub get
```

# Quick start

## 1. Initialize
```dart
import 'package:maxcalls_dart/maxcalls_dart.dart';

final calls = Calls(debug: true);
```

## 2. Set session params
```dart
calls.setSessionParams(
  mtInstanceId: 'your-mt-instance-id',  // UUID v4
  clientSessionId: 1,                    // Integer
  deviceId: 'your-device-id',            // UUID v4
);
```

## 3. Authenticate
```dart
// Request verification code
final token = await calls.requestVerification('+79001234567');

// User receives SMS code
// Enter the code
await calls.enterCode(token, '123456');
```

## 4. Calls listening
**Incoming calls:**
```dart
calls.onIncomingCall.listen((incomingCall) {
  print('Incoming call from: ${incomingCall.callerId}');
  print('Conversation ID: ${incomingCall.conversationId}');
  print('Signaling server: ${incomingCall.signaling.url}');
  print('STUN server: ${incomingCall.stun}');
  print('TURN servers: ${incomingCall.turn.servers}');
});
```
**Outgoining calls**
```dart
// Audio-only call
final conversationInfo = await calls.call('1234567', isVideo: false);

print('Endpoint: ${conversationInfo.endpoint}');
print('STUN: ${conversationInfo.stunUrls}');
print('TURN: ${conversationInfo.turnUrls}');
```

# Examples
**See [`examples/`](https://github.com/KometTeam/maxcalls_dart/blob/master/example/)** for complete usage examples

This package based on [maxcalls](https://github.com/icyfalc0n/maxcalls) go library.

