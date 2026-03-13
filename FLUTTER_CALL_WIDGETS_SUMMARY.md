# Flutter Call Screens & Widgets - Complete Summary

## Overview
This document provides a detailed analysis of the call-related screens and widgets in the Flutter workspace, including their architecture, dependencies, and functionality.

---

## 1. Dependencies (pubspec.yaml)

### Key Notification & Background Packages
- **flutter_local_notifications: ^19.5.0** - Local notifications for incoming calls
- **flutter_background_service: ^5.0.1** - Background task execution
- **wakelock_plus: ^1.2.8** - Keep device screen on during calls
- **permission_handler: ^11.3.0** - Runtime permissions for camera/microphone

### WebRTC & Media
- **flutter_webrtc: ^1.3.0** - WebRTC implementation for peer-to-peer calls
- **just_audio: ^0.9.40** - Audio playback (soundpad functionality)
- **record: ^6.1.2** - Audio recording for call recording
- **camera: ^0.10.5+3** - Camera access for video calls
- **media_kit: ^1.1.10** - Media player utilities

### Other Relevant Packages
- **web_socket_channel: ^2.4.0** - WebSocket signaling for calls
- **shared_preferences: ^2.2.3** - Store preferences (e.g., last fetched IP)
- **encrypt: ^5.0.3** - Encryption for DataChannel messages
- **http: ^1.5.0** - HTTP requests for API calls

---

## 2. lib/screens/call_screen.dart

**Type:** Main call UI screen for active calls (audio and video)  
**Size:** ~4700 lines  
**Architecture:** Stateful widget with complex WebRTC management

### Key Responsibilities

#### WebRTC & Signaling
- Initializes and manages `RTCPeerConnection` for peer-to-peer communication
- Handles WebSocket signaling connection with proper query parameters
- Creates and sends SDP offers/answers
- Manages ICE candidates for connection establishment
- Supports both outgoing and incoming calls

#### Media Management
- Acquires local audio/video streams via `getUserMedia`
- Initializes `RTCVideoRenderer` for local and remote video display
- Requests microphone and camera permissions
- Supports audio-only fallback if video fails
- Tracks and displays audio levels for both local and remote participants

#### DataChannel
- Optional DataChannel creation for temporary chat during calls
- Handles encrypted messaging through DataChannel
- Can be toggled per call

#### Call Control Features
- **Mute/Unmute** microphone
- **Video Enable/Disable** with remote video status tracking
- **Speaker Toggle** for audio routing
- **Call Recording** integration via `CallRecordingService`
- **Call Duration Timer** tracking active call time
- **Drag-to-Minimize** gesture support

#### Network & Statistics
- Collects ICE candidates (host, srflx, relay)
- Parses local and remote IP addresses from candidates
- Tracks network info: RTT, connection type, STUN/TURN servers
- Monitors connection quality metrics
- Displays network diagnostics panel
- Saves fetched IPs to SharedPreferences

#### Floating Call Management
- Integration with `FloatingCallManager` for minimize/maximize
- Callback for ending call from floating panel
- State synchronization with floating widgets

#### Soundpad Feature
- Audio playback of custom sounds during calls
- Saves and loads user sound preferences
- Uses `AudioPlayer` for playback

#### Error Handling
- Connection lost detection and user notification
- Graceful cleanup of resources
- Handles WebSocket disconnections

### Key Classes & Enums

```dart
enum CallState {
  connecting,
  ringing,
  connected,
  ended,
}

class NetworkInfo {
  String? localAddress;
  String? localConnectionType;
  String? remoteAddress;
  String? remoteConnectionType;
  List<IceCandidate> localCandidates;
  List<IceCandidate> remoteCandidates;
  List<String> stunServers;
  List<String> turnServers;
  String? transport;
  String? networkType;
  int? rtt;
  // ... and more network metrics
}

class IceCandidate {
  String ip;
  int port;
  String type; // 'host', 'srflx', 'relay', etc.
  int priority;
  String? networkId;
  int? networkCost;
  String? relayServer;
  String? stunServer;
}
```

### Key Methods

| Method | Purpose |
|--------|---------|
| `_initializeCall()` | Sets up renderers, WebSocket, peer connection, and media |
| `_connectToSignaling()` | Establishes WebSocket connection with proper parameters |
| `_createPeerConnection()` | Initializes RTCPeerConnection with STUN/TURN servers |
| `_setupLocalMedia()` | Acquires user media (audio/video) with permissions |
| `_createAndSendOffer()` | Creates and sends SDP offer (outgoing calls) |
| `_handleSignalingMessage()` | Routes incoming signaling messages |
| `_handleRemoteDescription()` | Processes remote SDP (offer/answer) |
| `_handleRemoteCandidate()` | Adds ICE candidates to peer connection |
| `_startAudioLevelMonitoring()` | Monitors remote participant's audio level |
| `_startLocalAudioLevelMonitoring()` | Monitors local microphone audio level |
| `_parseLocalCandidate()` / `_parseRemoteCandidate()` | Extracts IP/port/type from ICE candidates |
| `_updateNetworkStats()` | Gathers WebRTC stats (bitrate, packets, etc.) |
| `_endCall()` | Graceful call termination |
| `_cleanup()` | Releases all resources |

### Signaling Message Types Handled

- **connection** - Server notification with participant info and TURN/STUN servers
- **transmitted-data** - SDP/ICE candidates from remote peer
- **accepted-call** - Call accepted by other participant
- **hungup/closed-conversation** - Call ended
- **media-settings-changed** - Remote participant's media settings (mic/camera)
- **settings-update** - Server quality limits and thresholds
- **ping** - Keep-alive from server

### UI Build

- Full-screen video display with local/remote renderers
- Overlay controls: mute, speaker, video toggle, hangup
- Duration display
- Network info debug panel (toggleable)
- Soundpad interface
- Drag-to-minimize gesture detector

---

## 3. lib/widgets/floating_call_button.dart

**Type:** Draggable floating button for minimized calls  
**Size:** 140 lines  
**Architecture:** Stateful widget with animation

### Purpose
Displays a compact circular button (in chats or other screens) showing:
- Caller's avatar
- Call duration
- Drag-to-reposition functionality
- Tap to expand/restore call

### Key Features

#### UI Components
- **CircleAvatar** (radius 30) with caller's avatar
- **Duration badge** showing elapsed time (MM:SS format)
- **Animated appearance** with elastic scale animation

#### Positioning
- Initial position: `Offset(20, 100)` (top-left area)
- Draggable within screen bounds
- Clamped to prevent going off-screen
- Updated position stored in `_position` variable

#### Animations
- **Scale animation** with `Curves.elasticOut` for bounce effect on appearance
- Controlled by `AnimationController` (300ms duration)

#### Timer
- Updates duration every second
- Calculates elapsed time from `callStartTime`
- Stops on widget disposal

### Constructor Parameters
```dart
final String callerName;
final String? callerAvatarUrl;
final VoidCallback onTap;           // Restore full call screen
final VoidCallback onHangup;         // End the call
final DateTime callStartTime;
```

### State Variables
```dart
Timer? _timer;
String _callDuration = '00:00';
Offset _position = const Offset(20, 100);
AnimationController _scaleController;
Animation<double> _scaleAnimation;
```

---

## 4. lib/widgets/floating_call_overlay.dart

**Type:** Overlay widget wrapping the entire app  
**Size:** 72 lines  
**Architecture:** Stateless widget using ListenableBuilder

### Purpose
Manages the visibility and display of minimized call UI (either button or panel) when a call is active and minimized.

### Architecture
- **Observes** `FloatingCallManager.instance` (Listenable)
- **Conditionally renders** child widget or call UI
- **Delegates actions** to `CallOverlayService`

### Key Logic

```dart
if (!manager.hasActiveCall || !manager.isMinimized) {
  return child;  // Show normal app UI
}

// Show floating call UI based on shouldShowAsPanel/shouldShowAsButton
if (manager.shouldShowAsPanel)
  FloatingCallPanel(...)
if (manager.shouldShowAsButton)
  FloatingCallButton(...)
```

### Methods
- `_maximizeCall(context)` - Calls `CallOverlayService.instance.maximizeCall()`
- `_hangupCall(context)` - Calls `manager.onEndCall()` or `CallOverlayService.instance.closeCall()`

### Dependencies
- `FloatingCallManager` - Manages call state and display preferences
- `CallOverlayService` - Handles overlay operations

---

## 5. lib/widgets/floating_call_panel.dart

**Type:** Horizontal panel widget for minimized calls  
**Size:** 150 lines  
**Architecture:** Stateful widget with animation

### Purpose
Bottom-of-screen panel showing:
- Caller's avatar
- Caller's name
- Call duration
- Hangup button
- Tap to expand full call

### UI Layout
```
[Avatar (radius 24)] [Name + Duration] [Hangup Button]
```

**Height:** 64 dp  
**Material:** Elevated with `colors.primaryContainer` background  
**Animation:** Slide up from bottom with `Curves.easeOut`

### Key Features

#### Components
- **CircleAvatar** (radius 24, primary colored)
- **Caller name** (bold, 16pt)
- **Duration** (sub-text, 14pt, with opacity)
- **Hangup IconButton** with red call-end icon

#### Animations
- **Slide animation** from `Offset(0, 1)` to `Offset.zero`
- Duration: 300ms
- Smooth easing with `Curves.easeOut`

#### Timer
- Updates duration every second
- Calculates MM:SS format
- Cleaned up on dispose

### Constructor Parameters (identical to FloatingCallButton)
```dart
final String callerName;
final String? callerAvatarUrl;
final VoidCallback onTap;
final VoidCallback onHangup;
final DateTime callStartTime;
```

---

## 6. lib/widgets/incoming_call_overlay.dart

**Type:** Dialog overlay for incoming calls  
**Size:** 325 lines  
**Architecture:** Stateless overlay + Stateful dialog with animations

### Purpose
Full-screen dialog for accepting/rejecting incoming calls before `CallScreen` opens.

### Architecture

#### IncomingCallOverlay (Stateless)
- Observes `CallsService.instance` (Listenable)
- Shows `_IncomingCallDialog` when `currentIncomingCall != null`
- Returns `SizedBox.shrink()` when no incoming call

#### _IncomingCallDialog (Stateful)
- Displays caller information
- Provides accept/reject buttons
- Allows DataChannel toggle checkbox

### UI Components

#### Layout
1. **Avatar with pulse effect** (ripple animation)
   - Outer pulsing circle border (green)
   - Inner avatar (also scaled)
   - Radius: 45 for avatar, 120 for container

2. **Caller Name**
   - Headline style, bold, centered
   - Uses `widget.call.callerName`

3. **Call Type**
   - "Видеозвонок" or "Аудиозвонок"
   - Smaller text below name

4. **DataChannel Toggle**
   - `CheckboxListTile` for enabling temporary chat
   - Optional feature per call

5. **Action Buttons**
   - **Reject** (red, left): `Icons.call_end`
   - **Accept** (green, right): `Icons.call`
   - Custom circular button design

### Animations

#### Scale Animation
- Entry: `Curves.easeOutBack` (250ms)
- Creates bouncy appearance
- Applied to dialog container

#### Pulse Animation
- Repeating: `duration: 2000ms, reverse: true`
- Scale from 1.0 to 1.05
- Applied to avatar and ripple circle
- Makes avatar "breathe"

### Key Methods

```dart
_acceptCall()
  - Marks call as accepted in CallsService
  - Calls CallsService.instance.acceptCall()
  - Shows CallScreen via CallOverlayService
  - Passes _enableDataChannel flag

_rejectCall()
  - Clears incoming call from service
  - Calls CallsService.instance.rejectCall()
```

### Data Model

```dart
class IncomingCallData {
  int conversationId;
  int callerId;
  String callerName;
  String? callerAvatarUrl;
  bool isVideo;
}
```

### Dialog Styling
- **Background:** `colors.surface` with rounded corners (24pt)
- **Scrim:** Black54 overlay
- **Elevation:** Shadow with 20 blur radius
- **Dialog margin:** 24pt on all sides
- **Dialog padding:** 24pt on all sides

---

## 7. Service Integration

### FloatingCallManager
**Purpose:** Singleton managing minimize/maximize state  
**Key Properties:**
- `hasActiveCall` - Whether a call is active
- `isMinimized` - Whether call is minimized
- `shouldShowAsPanel` - Show bottom panel
- `shouldShowAsButton` - Show draggable button
- `callerName`, `callerAvatarUrl`, `callStartTime`
- `onEndCall` - Callback when ending from floating UI

### CallOverlayService
**Purpose:** Manages call overlay display  
**Key Methods:**
- `showCall()` - Display CallScreen in overlay
- `maximizeCall()` - Restore full CallScreen
- `closeCall()` - End call and close overlay

### CallsService
**Purpose:** Call lifecycle management  
**Key Methods:**
- `acceptCall(conversationId, callerId)` - Accept incoming call
- `rejectCall(conversationId, callerId)` - Reject incoming call
- `markCallAsAccepted()` - Update state during acceptance
- `clearIncomingCall()` - Clear incoming call data
- `currentIncomingCall` - Current incoming call data

### CallRecordingService
**Purpose:** Call recording management  
**Features:**
- Recording state stream
- Duration tracking
- Recording pause/resume/stop

---

## 8. WebRTC Signaling Protocol

### Connection Flow

#### Outgoing Call
```
1. Connect WebSocket with query params
2. Create peer connection
3. Get local media (audio/video)
4. Create and send SDP offer
5. Send local ICE candidates
6. Receive remote SDP answer
7. Receive remote ICE candidates
8. Call established
```

#### Incoming Call
```
1. Dialog shown (IncomingCallOverlay)
2. User accepts
3. Connect WebSocket
4. Send accept-call command
5. Create peer connection
6. Get local media
7. Wait for remote SDP offer
8. Send SDP answer
9. Exchange ICE candidates
10. Call established
```

### WebSocket Query Parameters
```dart
'platform': 'WEB'
'appVersion': '1.1'
'version': '5'
'device': 'browser'
'capabilities': '2A03F'
'clientType': 'ONE_ME'  // CRITICAL
'tgt': 'start'
```

### SDP Exchange Format
```dart
{
  'command': 'transmit-data',
  'sequence': int,
  'participantId': int,  // INTERNAL ID
  'data': {
    'sdp': {
      'type': 'offer' | 'answer',
      'sdp': String
    }
  },
  'participantType': 'USER'
}
```

### ICE Candidate Format
```dart
{
  'command': 'transmit-data',
  'sequence': int,
  'participantId': int,
  'data': {
    'candidate': {
      'candidate': String,
      'sdpMid': String?,
      'sdpMLineIndex': int?
    }
  },
  'participantType': 'USER'
}
```

### Media Settings Exchange
```dart
{
  'command': 'change-media-settings' | 'accept-call',
  'sequence': int,
  'mediaSettings': {
    'isAudioEnabled': bool,
    'isVideoEnabled': bool,
    'isScreenSharingEnabled': false,
    'isFastScreenSharingEnabled': false,
    'isAudioSharingEnabled': false,
    'isAnimojiEnabled': false
  }
}
```

---

## 9. Key Technical Insights

### Call Minimization Flow
1. `CallScreen` renders normally
2. User initiates minimize gesture
3. `FloatingCallManager.startCall()` marks as minimized
4. `FloatingCallOverlay` detects change and shows `FloatingCallButton` or `FloatingCallPanel`
5. `CallScreen` still runs in background (WebRTC active)
6. User taps floating UI → `CallOverlayService.maximizeCall()`
7. `FloatingCallManager` changes state
8. `CallScreen` becomes visible again

### IP Address Tracking
- **Local IPs** extracted from local ICE candidates
- **Remote IPs** extracted from remote ICE candidates
- Priority: `srflx` (STUN reflected) > `host` (local network) > `relay` (TURN)
- Saved to SharedPreferences for last-used tracking

### Audio Level Monitoring
- **Remote:** Monitors `inbound-rtp` stats with `audioLevel` metric (0.0-1.0)
- **Local:** Monitors `media-source` stats for microphone level
- Threshold: 0.01 for detecting speech
- Updates every 200ms for remote, 100ms for local
- Triggers animation/indicator updates

### Network Statistics Collection
Sources:
1. **WebRTC Stats API** - Bitrate, packets, jitter, loss
2. **ICE Candidates** - Connection types and relay servers
3. **Signaling Messages** - STUN/TURN servers from server
4. **Analytics Events** - RTT, network type, geoip info

### DataChannel Implementation
- Created by outgoing call initiator only
- Received by incoming call if enabled
- Optional per call (checkbox in incoming dialog)
- Used for temporary encrypted chat
- Supports message encryption via `Encrypt` package

---

## 10. Error Handling & Edge Cases

| Scenario | Handling |
|----------|----------|
| WebSocket disconnect | Show error dialog, cleanup resources |
| Media permission denied | Fallback to audio-only if video denied |
| Camera unavailable | Continue with audio-only |
| Peer connection failed | 30-second grace period, then error |
| Remote hangup mid-call | Detect, close UI, cleanup resources |
| Widget disposal mid-call | Graceful cleanup with `_isCleaningUp` guard |
| Double cleanup trigger | Protected by `_isCleaningUp` flag |
| Missing remote participant ID | Fall back to contact ID |

---

## 11. Performance Considerations

- **Timer cleanup:** All timers cancelled in dispose
- **Stream subscriptions:** Signaling subscription cancelled in cleanup
- **Video renderers:** Properly disposed to prevent memory leaks
- **Audio player:** Disposed with call cleanup
- **Network stats:** Limited to 1-second updates during connected state
- **Audio level monitoring:** Stops when call ends or widget unmounts
- **Animation controllers:** All disposed in their respective widgets

---

## Summary

The Flutter call implementation is a sophisticated WebRTC-based system with:
- **Peer-to-peer audio/video** via WebSocket signaling
- **Minimize/maximize UI** with floating button and panel
- **Rich network diagnostics** (IPs, RTT, connection types)
- **Advanced features** (soundpad, recording, data channel, audio level monitoring)
- **Robust error handling** with graceful degradation
- **Smooth animations** for professional UX

The architecture is well-separated with dedicated services (`CallsService`, `CallOverlayService`, `FloatingCallManager`) managing different aspects of the call lifecycle.
