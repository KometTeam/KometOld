# Integration Guide for Flutter Projects

This guide shows how to integrate `maxcalls_dart` into your Flutter project (e.g., Komet Client).

## Installation

### Option 1: From Local Path

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  maxcalls_dart:
    path: ../maxcalls_dart  # Adjust path as needed
```

### Option 2: From Git Repository

```yaml
dependencies:
  maxcalls_dart:
    git:
      url: https://github.com/your-repo/maxcalls_dart.git
      ref: main
```

### Option 3: From pub.dev (once published)

```yaml
dependencies:
  maxcalls_dart: ^0.1.0
```

Then run:
```bash
flutter pub get
```

## Basic Setup

### 1. Import the Package

```dart
import 'package:maxcalls_dart/maxcalls_dart.dart';
```

### 2. Initialize the Client

Create a calls service in your app:

```dart
class CallsService {
  final Calls _calls = Calls(debug: true);
  
  Future<void> initialize() async {
    // Listen for incoming calls
    _calls.onIncomingCall.listen(_handleIncomingCall);
  }
  
  void _handleIncomingCall(IncomingCall call) {
    // Show incoming call UI
    print('Incoming call from: ${call.callerId}');
  }
  
  Future<void> dispose() async {
    await _calls.close();
  }
}
```

## Authentication Flow

### Login with Phone Number

```dart
class AuthService {
  final Calls _calls = Calls(debug: true);
  
  // Step 1: Request verification code
  Future<String> requestCode(String phoneNumber) async {
    try {
      final token = await _calls.requestVerification(phoneNumber);
      return token;
    } catch (e) {
      print('Error requesting code: $e');
      rethrow;
    }
  }
  
  // Step 2: Verify code and complete login
  Future<void> verifyCode(String token, String code) async {
    try {
      await _calls.enterCode(token, code);
      print('Login successful!');
    } catch (e) {
      print('Error verifying code: $e');
      rethrow;
    }
  }
  
  // Alternative: Login with saved token
  Future<void> loginWithToken(String authToken) async {
    try {
      await _calls.loginWithToken(authToken);
      print('Login successful!');
    } catch (e) {
      print('Error logging in: $e');
      rethrow;
    }
  }
}
```

## Making Calls

### Outgoing Call Example

```dart
class CallScreen extends StatefulWidget {
  final String targetUserId;
  
  const CallScreen({required this.targetUserId});
  
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final Calls _calls = Calls(debug: true);
  Connection? _connection;
  
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  
  @override
  void initState() {
    super.initState();
    _initRenderers();
    _startCall();
  }
  
  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }
  
  Future<void> _startCall() async {
    try {
      // Make the call
      _connection = await _calls.call(
        widget.targetUserId,
        isVideo: true, // Set to false for audio-only
      );
      
      // Attach streams to renderers
      if (_connection!.localStream != null) {
        _localRenderer.srcObject = _connection!.localStream;
      }
      
      if (_connection!.remoteStream != null) {
        _remoteRenderer.srcObject = _connection!.remoteStream;
      }
      
      // Wait for connection
      await _connection!.waitForConnection();
      
      setState(() {});
      print('Call connected!');
    } catch (e) {
      print('Error starting call: $e');
      Navigator.pop(context);
    }
  }
  
  Future<void> _endCall() async {
    await _connection?.close();
    Navigator.pop(context);
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Call')),
      body: Column(
        children: [
          Expanded(
            child: RTCVideoView(_remoteRenderer),
          ),
          SizedBox(
            height: 150,
            child: RTCVideoView(_localRenderer, mirror: true),
          ),
          ElevatedButton(
            onPressed: _endCall,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('End Call'),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _connection?.close();
    super.dispose();
  }
}
```

## Receiving Calls

### Incoming Call Handler

```dart
class IncomingCallScreen extends StatefulWidget {
  final IncomingCall incomingCall;
  
  const IncomingCallScreen({required this.incomingCall});
  
  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  final Calls _calls = Calls(debug: true);
  Connection? _connection;
  
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  
  bool _isAccepted = false;
  
  @override
  void initState() {
    super.initState();
    _initRenderers();
  }
  
  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }
  
  Future<void> _acceptCall() async {
    setState(() => _isAccepted = true);
    
    try {
      // Accept the call
      _connection = await _calls.acceptCall(widget.incomingCall);
      
      // Attach streams
      if (_connection!.localStream != null) {
        _localRenderer.srcObject = _connection!.localStream;
      }
      
      if (_connection!.remoteStream != null) {
        _remoteRenderer.srcObject = _connection!.remoteStream;
      }
      
      // Wait for connection
      await _connection!.waitForConnection();
      
      setState(() {});
      print('Call accepted and connected!');
    } catch (e) {
      print('Error accepting call: $e');
      Navigator.pop(context);
    }
  }
  
  Future<void> _rejectCall() async {
    // Just close the screen - call will timeout
    Navigator.pop(context);
  }
  
  @override
  Widget build(BuildContext context) {
    if (!_isAccepted) {
      return Scaffold(
        appBar: AppBar(title: Text('Incoming Call')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.phone_in_talk, size: 100),
              SizedBox(height: 20),
              Text(
                'Incoming call from ${widget.incomingCall.callerId}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _rejectCall,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: Text('Reject'),
                  ),
                  ElevatedButton(
                    onPressed: _acceptCall,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child: Text('Accept'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    
    // Call in progress UI (same as outgoing call)
    return Scaffold(
      appBar: AppBar(title: Text('Call')),
      body: Column(
        children: [
          Expanded(
            child: RTCVideoView(_remoteRenderer),
          ),
          SizedBox(
            height: 150,
            child: RTCVideoView(_localRenderer, mirror: true),
          ),
          ElevatedButton(
            onPressed: () async {
              await _connection?.close();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('End Call'),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _connection?.close();
    super.dispose();
  }
}
```

## Global Call Manager

Create a singleton to manage calls across your app:

```dart
class CallManager {
  static final CallManager _instance = CallManager._internal();
  factory CallManager() => _instance;
  CallManager._internal();
  
  final Calls _calls = Calls(debug: true);
  StreamSubscription? _incomingCallSubscription;
  
  Future<void> initialize() async {
    // Listen for incoming calls globally
    _incomingCallSubscription = _calls.onIncomingCall.listen(_handleIncomingCall);
  }
  
  void _handleIncomingCall(IncomingCall call) {
    // Navigate to incoming call screen or show notification
    // You'll need access to NavigatorKey or use a service locator
    print('Incoming call from: ${call.callerId}');
    
    // Example with GetX:
    // Get.to(() => IncomingCallScreen(incomingCall: call));
    
    // Example with Provider/Riverpod:
    // ref.read(navigationProvider).push(IncomingCallScreen(incomingCall: call));
  }
  
  Calls get calls => _calls;
  
  Future<void> dispose() async {
    await _incomingCallSubscription?.cancel();
    await _calls.close();
  }
}
```

## Platform-Specific Configuration

### Android

Add permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
```

### iOS

Add permissions to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access for video calls</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for calls</string>
```

## Error Handling

```dart
try {
  final connection = await calls.call(userId);
  await connection.waitForConnection();
} on TimeoutException {
  // Connection timeout
  print('Call timed out');
} on StateError catch (e) {
  // Connection failed
  print('Connection failed: $e');
} catch (e) {
  // Other errors
  print('Error: $e');
}
```

## Best Practices

1. **Initialize early**: Initialize the Calls client during app startup
2. **Handle permissions**: Request camera/microphone permissions before making calls
3. **Manage state**: Use state management to track call status
4. **Clean up**: Always close connections when done
5. **Error handling**: Handle network errors and timeouts gracefully
6. **Background handling**: Consider background call handling for mobile apps

## Next Steps

- Implement call notifications for background calls
- Add call history tracking
- Implement call quality indicators
- Add mute/unmute functionality
- Add speaker/headset switching
