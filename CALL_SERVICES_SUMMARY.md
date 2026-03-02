# Flutter Call Services Architecture Summary

## Overview
The Flutter application implements a comprehensive call management system with multiple layers handling incoming calls, notifications, WebRTC signaling, UI overlays, and floating call panels. The architecture separates concerns into specialized services that work together to manage the complete call lifecycle.

---

## 1. CallsService (`lib/services/calls_service.dart`)

### Purpose
Central service for managing incoming calls. Handles reception, parsing, and routing of call notifications from the API WebSocket connection.

### Key Classes
- **CallsService**: Main service class (singleton)
- **IncomingCallData**: Data model for incoming call information

### Key Methods

#### Core Management
- `initialize()`: Sets up WebSocket message listener from ApiService
- `clearIncomingCall()`: Clears current incoming call and cancels notifications
- `markCallAsAccepted(String conversationId)`: Tracks accepted calls for 30 seconds to prevent duplicate cancellation handling

#### Call Handling
- `acceptCall(String conversationId, int callerId)`: Accepts incoming call by:
  - Sending `INCOMING_CALL_INIT` event
  - Initiating call via `ApiService.initiateCall()`
  - Returns `CallResponse` with WebRTC connection data
  
- `rejectCall(String conversationId, int callerId)`: Rejects incoming call by:
  - Initiating call to get WebSocket endpoint
  - Connecting to WebSocket signaling
  - Sending `hangup` command with `reason: REJECTED`
  - Falls back to REST API if WebSocket fails

#### Internal Message Handlers
- `_handleIncomingCall(Map payload)`: Processes opcode 78 (old format incoming calls)
  - Extracts conversationId, callerId, callerName, isVideo
  - Creates IncomingCallData object
  - Shows Android notification
  - Emits to incomingCalls stream
  
- `_handleIncomingCallV2(Map payload)`: Processes opcode 137 (new format with VCP)
  - Extracts conversationId, callerId, callType, VCP parameters
  - Fetches caller contact info from API
  - Handles video calls with video call parameters
  
- `_handleCallNotification(Map payload)`: Processes opcode 132
  - Detects call closure notifications (closed-conversation, hungup, canceled)
  - Clears incoming call if IDs match
  
- `_handleCallMessage(Map payload)`: Processes opcode 128
  - Handles CALL attachments in messages
  - Detects CANCELED hangup type
  - Prevents duplicate cancellations using `_acceptedCalls` set

### Properties
- `incomingCalls`: Stream<IncomingCallData> for listening to new incoming calls
- `currentIncomingCall`: IncomingCallData? - current active incoming call
- `_acceptedCalls`: Set<String> - tracks recently accepted calls (30s window)

### IncomingCallData Model
```dart
class IncomingCallData {
  final String conversationId;
  final int callerId;
  final String callerName;
  final String? callerAvatarUrl;
  final bool isVideo;
  final DateTime timestamp;
}
```

### Architecture
- Extends ChangeNotifier for state management
- Listens to ApiService.messages stream
- Emits events via StreamController
- Interacts with CallNotificationService for Android notifications

---

## 2. CallNotificationService (`lib/services/call_notification_service.dart`)

### Purpose
Handles native Android call notifications and receives user interactions (answer/decline) from the native notification UI.

### Key Classes
- **CallNotificationService**: Android call notification manager (singleton)

### Key Methods

#### Setup
- `_setupMethodCallHandler()`: Registers method channel handler to receive native callbacks
  - Listens for `onCallAnswered` method calls
  - Listens for `onCallDeclined` method calls

#### Notifications
- `showIncomingCallNotification({required String conversationId, required String callerName, required int callerId, String? avatarPath})`: 
  - Android-only (checks Platform.isAndroid)
  - Invokes native method to display call notification
  - Parameters passed to native layer for rich notification UI
  
- `cancelIncomingCallNotification()`: 
  - Cancels active call notification
  - Android-only

### Properties
- `onCallAnswered`: Callback function(String conversationId) - fired when user taps answer on notification
- `onCallDeclined`: Callback function(String conversationId) - fired when user taps decline on notification

### Implementation Details
- Uses MethodChannel: `'com.gwid.app/calls'`
- Singleton pattern with lazy initialization
- Platform-specific: Only operates on Android
- Two-way communication bridge with native layer

### Architecture
- Bridge pattern for native/Flutter communication
- Event-driven callbacks
- No direct Flutter UI responsibility

---

## 3. FloatingCallManager (`lib/services/floating_call_manager.dart`)

### Purpose
State management for minimized/floating call representation. Tracks call state, displays floating panel when minimized, floating button when in chat.

### Key Classes
- **FloatingCallManager**: State manager for floating call (singleton, extends ChangeNotifier)

### Key Methods

#### Call Control
- `startCall()`: Sets `_hasActiveCall = true` and notifies listeners
- `minimizeCall({...})`: Transitions to minimized state with caller info
  - Stores: callerName, callerAvatarUrl, callerId, callResponse, callStartTime, isVideo
  - Notifies listeners for UI update
  
- `maximizeCall()`: Transitions back to fullscreen
  - Sets `_isMinimized = false`
  - Notifies listeners to rebuild overlay
  
- `endCall()`: Clears all call data
  - Resets all fields to null/false
  - Clears onEndCall callback
  - Notifies listeners
  
- `setInChatScreen(bool inChat)`: Updates chat screen context
  - Notifies listeners only if state changes

### Properties
- `isMinimized`: bool - current minimization state
- `isInChatScreen`: bool - whether user is in chat screen
- `hasActiveCall`: bool - whether call is active
- `callerName`, `callerAvatarUrl`, `callerId`: Caller information
- `callResponse`: CallResponse object with WebRTC data
- `callStartTime`: DateTime for call duration calculation
- `isVideo`: bool - video vs audio call
- `shouldShowAsPanel`: bool - show bottom panel when minimized and not in chat
- `shouldShowAsButton`: bool - show floating button when minimized and in chat
- `onEndCall`: VoidCallback - callback when call ends from floating UI

### Architecture
- Pure state management with ChangeNotifier
- No UI rendering, only state tracking
- Observes chat screen navigation
- Provides computed properties for UI decision logic

---

## 4. CallOverlayService (`lib/services/call_overlay_service.dart`)

### Purpose
Manages the CallScreen display as a Flutter Overlay (fullscreen call UI). Handles minimize/maximize transitions with animations.

### Key Classes
- **CallOverlayService**: Overlay manager (singleton)
- **_CallOverlayWidget**: Stateful widget wrapping CallScreen in overlay
- **_CallOverlayWidgetState**: Animation controller for show/hide transitions

### Key Methods

#### Overlay Management
- `showCall(BuildContext? context, {...CallResponse callData, int contactId, String contactName, ...})`:
  - Creates OverlayEntry with CallScreen
  - Stores OverlayState for future manipulation
  - Sets call start time
  - Inserts entry into overlay stack
  - Parameters include: callData, contactId, contactName, contactAvatarUrl, isVideo, isOutgoing, enableDataChannel
  
- `_minimizeCall(String name, String? avatar, int id, CallResponse data, bool video)`:
  - Sets `_isMinimized = true`
  - Delegates to FloatingCallManager.minimizeCall()
  - Triggers widget rebuild
  
- `maximizeCall()`:
  - Sets `_isMinimized = false`
  - Delegates to FloatingCallManager.maximizeCall()
  - Marks overlay entry for rebuild
  
- `closeCall()`:
  - Removes OverlayEntry
  - Clears all state variables
  - Calls FloatingCallManager.endCall()
  - Complete cleanup

### Animation System
- `_CallOverlayWidgetState` implements SingleTickerProviderStateMixin
- AnimationController: 300ms duration
- Slide animation: Offset from (0, 0) to (0, 1) - slides down
- Fade animation: Opacity from 1.0 to 0.0 - fades out
- Uses CurvedAnimation with Curves.easeInOut
- Listens to FloatingCallManager changes via addListener

### Properties
- `_callOverlayEntry`: OverlayEntry - reference to displayed overlay
- `_overlayState`: OverlayState - context for overlay manipulation
- `_isMinimized`: bool - minimization state
- `_callStartTime`: DateTime? - call initiation time
- `isMinimized`: getter for minimization state
- `hasActiveCall`: getter - true if OverlayEntry exists

### UI Composition
- SlideTransition (animation based)
- FadeTransition (animation based)
- IgnorePointer (disables interaction when minimized)
- Material wrapper
- CallScreen child (the actual call UI)

### Architecture
- Wraps CallScreen in animated transitions
- Coordinates with FloatingCallManager for state
- Uses Overlay for z-order independence
- Provides smooth minimize/maximize UX

---

## 5. API Service Calls Extension (`lib/api/api_service_calls.dart`)

### Purpose
REST/WebSocket API layer for call operations. Provides high-level call initiation, termination, and event tracking.

### Key Methods

#### Call Initiation
- `initiateCall(int userId, {bool isVideo = false})`: **Outgoing Calls**
  - Creates CallRequest with userId (calleeId), deviceId, isVideo
  - Sends opcode 78 request
  - Validates cmd response (expects 0x100 or 256)
  - Returns CallResponse with WebRTC connection details
  - Logs event and handles errors
  
- `startGroupCall(int chatId, {bool isVideo = false})`: **Group Calls**
  - Sends opcode 77 with chatId, operation: 'START', callType
  - Returns ConversationConnection
  - Validates response code
  
- `joinGroupCallByConferenceId({required String conferenceId, required int chatId})`: **Join Existing Call**
  - Sends opcode 80 with conferenceId, chatId
  - Returns ConversationConnection for existing call
  - Validates response

#### Call Termination
- `hangupCall({required String conversationId, required String hangupType, int duration = 0})`:
  - Sends opcode 79 with conversationId, hangupType (CANCELED/HUNGUP/DECLINED), duration
  - hangupType values:
    - CANCELED: Call was rejected/declined
    - HUNGUP: Normal call termination
    - DECLINED: Incoming call rejected
  - Non-critical error handling (doesn't throw)

#### Events/Analytics
- `sendCallEvent({required String eventType, required String conversationId})`:
  - Sends opcode 5 (events)
  - eventType values: START_CALL, INCOMING_CALL_INIT, etc.
  - Includes userId, sessionId, timestamp
  - Non-critical (doesn't throw on error)

### Request/Response Models
- **CallRequest**: Outgoing call request
  - Fields: calleeId, deviceId, isVideo, conversationId
  - Factory method: CallRequest.create()
  
- **CallResponse**: API response for call initiation
  - Contains: conversationId, internalCallerParams (with endpoint for WebSocket)
  - Parsed from opcode 78 response payload
  
- **ConversationConnection**: Group call response
  - Contains: conversation data, connection parameters
  - Parsed from opcode 77/80 response payloads

### Opcodes
- **78**: Initiate call (1-to-1)
- **79**: Hangup call
- **77**: Start group call
- **80**: Join group call
- **5**: Send events

### Architecture
- Part of ApiService main class (extension)
- Assumes online connectivity (waitUntilOnline)
- Uses SharedPreferences for device ID and user info
- Comprehensive logging with _log()
- Error handling with stack traces

---

## Interconnection Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    WebSocket/API Messages                    │
│                                                               │
│  Opcode 78 (call init)  →  Opcode 137 (incoming call v2)    │
│  Opcode 132 (call notification)  →  Opcode 128 (messages)   │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   CallsService                               │
│  • Listens to API messages via ApiService.messages stream   │
│  • Parses incoming call opcodes (78, 137, 132, 128)        │
│  • Emits IncomingCallData via incomingCalls stream          │
│  • Tracks currentIncomingCall                               │
│  • Coordinates acceptCall() / rejectCall()                  │
└──────────────────────────┬──────────────────────────────────┘
                           │
                    ┌──────┴──────┐
                    ▼             ▼
        ┌──────────────────┐  ┌─────────────────────────┐
        │CallNotification  │  │  API Service Calls      │
        │Service           │  │  • initiateCall()       │
        │                  │  │  • hangupCall()         │
        │• Android native  │  │  • sendCallEvent()      │
        │  notifications   │  │  • startGroupCall()     │
        │• User interactions│  │  • joinGroupCall()      │
        │  (answer/decline)│  │                         │
        └────────┬─────────┘  └────────┬────────────────┘
                 │                     │
                 │         ┌───────────┘
                 │         │
                 │         ▼
                 │    CallResponse
                 │    (WebRTC data)
                 │         │
                 │         ▼
┌────────────────────────────────────────────────────┐
│         CallOverlayService                         │
│  • showCall() with CallResponse                    │
│  • Creates Overlay with CallScreen                │
│  • Manages minimize/maximize animations           │
│  • Coordinates with FloatingCallManager            │
└────────┬─────────────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────────────────┐
│    FloatingCallManager (ChangeNotifier)            │
│  • Tracks minimization state                       │
│  • Stores call data (caller, avatar, etc.)        │
│  • Determines UI display logic (panel vs button)  │
│  • Observes chat screen navigation                │
│  • Provides callbacks (onEndCall)                 │
└────────────────────────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────────────────┐
│           UI Layer                                 │
│  • CallScreen (fullscreen)                        │
│  • FloatingPanel (minimized, not in chat)         │
│  • FloatingButton (minimized, in chat)            │
│  • FloatingCallManager notifies listeners         │
└────────────────────────────────────────────────────┘
```

---

## Call Lifecycle: Incoming Call Example

### 1. **Reception**
   - WebSocket message arrives with opcode 78 or 137
   - CallsService._handleIncomingCall() or _handleIncomingCallV2() invoked
   - IncomingCallData object created

### 2. **Notification**
   - CallNotificationService.showIncomingCallNotification() called
   - Android native notification displayed with caller info
   - User can tap "Answer" or "Decline" on notification

### 3. **User Action**
   - If answered: Native layer calls CallNotificationService.onCallAnswered callback
   - Callback triggers CallsService.acceptCall()
   - acceptCall() sends INCOMING_CALL_INIT event + initiateCall() API call
   
   - If declined: Native layer calls CallNotificationService.onCallDeclined callback
   - Callback triggers CallsService.rejectCall()
   - rejectCall() initiates WebSocket + sends hangup command

### 4. **Call Response**
   - ApiService.initiateCall() returns CallResponse with WebRTC endpoint
   - CallOverlayService.showCall() displays CallScreen in overlay

### 5. **Call Active**
   - CallOverlayService creates animated overlay entry
   - FloatingCallManager.startCall() marks call active
   - CallScreen handles WebRTC signaling/connection

### 6. **Minimize**
   - User taps minimize button in CallScreen
   - CallOverlayService._minimizeCall() called
   - FloatingCallManager.minimizeCall() stores call data
   - Overlay animates: slide down + fade out
   - FloatingPanel or FloatingButton displayed based on chat context

### 7. **Maximize**
   - User taps floating panel/button
   - CallOverlayService.maximizeCall() called
   - FloatingCallManager.maximizeCall() resets minimized flag
   - Overlay animates: slide up + fade in
   - Full CallScreen restored

### 8. **Termination**
   - Either party hangs up
   - ApiService.hangupCall() sends opcode 79
   - CallOverlayService.closeCall() removes overlay
   - FloatingCallManager.endCall() clears all data
   - CallNotificationService.cancelIncomingCallNotification() cleanup

---

## Call Lifecycle: Outgoing Call Example

### 1. **Initiation**
   - User starts call from chat/contact screen
   - UI calls ApiService.initiateCall(userId, isVideo: true/false)
   - Sends opcode 78 with CallRequest (calleeId, deviceId, isVideo)

### 2. **Response**
   - API returns CallResponse with WebRTC endpoint and connection data
   - sendCallEvent(START_CALL) sent for analytics

### 3. **Display**
   - CallOverlayService.showCall() displays CallScreen
   - CallScreen handles WebRTC signaling to establish peer connection
   - Calling state shown until recipient answers

### 4. **Connected**
   - Remote party answers (or WebRTC establishes)
   - Audio/Video streams active
   - Call timer running

### 5. **Minimize/Maximize**
   - Same as incoming call lifecycle
   - FloatingCallManager manages state
   - CallOverlayService manages animations

### 6. **Termination**
   - User or remote party ends call
   - ApiService.hangupCall() with duration sent
   - Complete cleanup cascade

---

## Key Design Patterns

### 1. **Singleton Pattern**
   - All services: CallsService, CallNotificationService, FloatingCallManager, CallOverlayService
   - Ensures single instance across app

### 2. **Stream Pattern**
   - CallsService.incomingCalls: Stream<IncomingCallData>
   - Allows multiple listeners
   - Broadcast stream for simultaneous subscribers

### 3. **ChangeNotifier Pattern**
   - CallsService, FloatingCallManager extend ChangeNotifier
   - Integrates with Provider/Consumer for reactive UI updates

### 4. **Bridge Pattern**
   - CallNotificationService bridges native Android and Flutter
   - MethodChannel for two-way communication

### 5. **Observer Pattern**
   - FloatingCallManager observed by CallOverlayWidget
   - CallOverlayWidget listens for state changes
   - Triggers animations and rebuilds

### 6. **Extension Pattern**
   - ApiServiceCalls extends ApiService
   - Modular organization of call-related API methods

---

## Error Handling Strategy

### Critical Errors (Rethrow)
- initiateCall() failures: Rethrows to caller
- Call initiation failures prevent UI display

### Non-Critical Errors (Silent)
- hangupCall(): Doesn't throw (call already ending)
- sendCallEvent(): Doesn't throw (analytics non-critical)
- Notification display failures: Catch and log only

### Fallback Mechanisms
- rejectCall(): Primary WebSocket method, fallbacks to REST API (opcode 79)
- CallOverlayService: Handles null overlay state gracefully
- Contact fetching: Defaults to "Неизвестный" if fetch fails

---

## Summary

The call management system is architecturally sound with clear separation of concerns:

1. **CallsService**: Logic layer - parses API messages, manages call state
2. **CallNotificationService**: Platform bridge - Android native notifications
3. **ApiServiceCalls**: API layer - REST/WebSocket communication
4. **FloatingCallManager**: State management - minimization/chat context
5. **CallOverlayService**: UI orchestration - overlay display and animations

Services interact through well-defined interfaces and are loosely coupled. The system elegantly handles:
- Incoming and outgoing calls
- Group calls
- Call notifications
- Minimize/maximize transitions
- Native Android integration
- WebRTC signaling and data exchange
