# FAIL_LOGIN_TOKEN Handling Analysis

## Overview
The token authentication system uses `invalid_token` as the primary error type, with special handling for `FAIL_WRONG_PASSWORD` server responses. There is NO explicit reference to `FAIL_LOGIN_TOKEN` in the codebase—the system uses a message-based event pattern instead.

---

## 1. Login/Token Authentication Flow

### File: `lib/api/api_service_auth.dart`

**How login works:**
- `ApiService` is a singleton managing authentication state
- Stores `authToken` (token string) and `userId` (user ID) as instance variables
- Uses `SharedPreferences` to persist the auth token locally
- Token validation happens during connection setup (handshake)

**Account switching logic (lines 262-295):**
```dart
Future<void> switchAccount(String accountId) async {
  // 1. Saves current token/userId
  // 2. Calls AccountManager.switchAccount() to change active account
  // 3. Loads new token from AccountManager.currentAccount.token
  // 4. Calls _resetSession() to clear cached data
  // 5. Listens for 'invalid_token' message type to detect if new token is bad
  // 6. If invalid_token received → triggers account switch to next available account
}
```

**Key constant:**
```dart
const invalidAccountError = 'invalid_token: Аккаунт недействителен';
```

---

## 2. Token Error Detection & Handling

### File: `lib/api/api_service_connection.dart`

**Primary token error handler - `_handleInvalidToken()` (lines 121-182):**

This is the core function triggered when server indicates token is invalid.

**What happens:**
1. **Session reset:**
   - Sets `_isSessionOnline = false`
   - Sets `_isSessionReady = false`
   - Stops health monitoring
   - Updates connection state to `ConnectionState.error` with message "Недействительный токен"

2. **Token cleanup:**
   - Clears `authToken = null`
   - Removes token from SharedPreferences: `prefs.remove('authToken')`
   - Clears all cached data: `clearAllCaches()`
   - Closes WebSocket: `_socket?.close()`

3. **Auto-account switching (if multiple accounts exist):**
   - Gets AccountManager instance
   - Finds first account with non-empty token that isn't the current invalid one
   - Switches to that account automatically
   - Emits `'auto_switched_account'` message
   - Calls `connect()` to reconnect with new token

4. **Fallback (if no other accounts available):**
   - Emits `'invalid_token'` message to UI
   - Message: `'Токен недействителен, требуется повторная авторизация'`
   - User must re-login

**Secondary detection - `FAIL_WRONG_PASSWORD` (lines 545-556):**
```dart
if (error != null && error['message'] == 'FAIL_WRONG_PASSWORD') {
  _clearAuthToken().then((_) {
    _chatsFetchedInThisSession = false;
    _messageController.add({
      'type': 'invalid_token',
      'message': 'Токен авторизации недействителен. Требуется повторная авторизация.',
    });
    _reconnect();
  });
}
```
This treats `FAIL_WRONG_PASSWORD` server response as an invalid token scenario.

**Health monitoring error reporting (line 125):**
```dart
_healthMonitor.onError('invalid_token');
```
Reports invalid token to health monitor for diagnostics/analytics.

---

## 3. Connection States

### File: `lib/connection/connection_state.dart`

**State enum:**
```dart
enum ConnectionState {
  disconnected,    // Not connected
  connecting,      // Attempting to connect
  connected,       // TCP connected, but session not ready
  ready,           // Session ready, can send messages
  reconnecting,    // Attempting to reconnect
  error,           // Connection error (including auth errors)
  disabled,        // Connection explicitly disabled
}
```

**ConnectionInfo metadata:**
- `state`: The ConnectionState
- `message`: Human-readable message (e.g., "Недействительный токен")
- `metadata`: Additional context (can include error details)
- `attemptNumber`: Reconnection attempt count
- `reconnectDelay`: Delay until next reconnection attempt

**Useful computed properties:**
```dart
bool get isActive => state == ConnectionState.ready || state == ConnectionState.connected;
bool get canSendMessages => state == ConnectionState.ready;
bool get hasError => state == ConnectionState.error;
```

---

## 4. Files That Handle Token Errors

### Search Results Summary

| File | Line | What It Does |
|------|------|------------|
| `lib/api/api_service_connection.dart` | 125 | Reports 'invalid_token' to health monitor |
| `lib/api/api_service_connection.dart` | 158 | Logs auto-account switch when token invalid |
| `lib/api/api_service_connection.dart` | 179-181 | Emits 'invalid_token' message (primary UI trigger) |
| `lib/api/api_service_connection.dart` | 549-551 | Treats FAIL_WRONG_PASSWORD as invalid_token |
| `lib/api/api_service_auth.dart` | 265 | References invalidAccountError constant |
| `lib/api/api_service_auth.dart` | 288-291 | Detects invalid_token in account switch flow |
| `lib/screens/home_screen.dart` | 61-62 | Listens for 'invalid_token' message and calls _handleInvalidToken() |
| `lib/screens/chat/handlers/message_handler.dart` | 222-229 | Shows dialog and redirects to login on invalid_token |

---

## 5. UI Response Flow

### HomeScreen (`lib/screens/home_screen.dart` lines 956-971)

When `'invalid_token'` message received:
```dart
void _handleInvalidToken(String message) {
  // Show red snackbar with error message
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Colors.red,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(10),
    ),
  );

  // Navigate back to login screen
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (context) => const PhoneEntryScreen()),
    (route) => false,
  );
}
```

### Chat Message Handler (`lib/screens/chat/handlers/message_handler.dart` lines 222-229)

```dart
if (message['type'] == 'invalid_token') {
  print('Получено событие недействительного токена, перенаправляем на вход');
  showTokenExpiredDialog(
    message['message'] ?? 'Токен авторизации недействителен',
  );
  return;
}
```

Shows a dialog and presumably also redirects to login.

---

## 6. Message-Based Error System

The system uses **message broadcasting** via `ApiService.messages` stream rather than explicit error codes:

**Message types emitted:**
- `'invalid_token'` - Token is invalid, user must re-login
- `'auto_switched_account'` - System automatically switched to another account
- `'session_terminated'` - Session was terminated by server
- Other opcodes like `'group_join_success'`, etc.

**Flow:**
1. Server sends error (via opcode/payload)
2. `_handleInvalidToken()` in api_service_connection detects and processes
3. Message with `type: 'invalid_token'` added to `_messageController`
4. UI screens listening on `ApiService.instance.messages` receive it
5. UI shows notification and redirects to login

---

## 7. Token Lifecycle Summary

1. **Initial Login:** Token obtained, stored in SharedPreferences
2. **Connection:** Token used in WebSocket handshake
3. **Server Rejection:** Server sends error response or closes connection
4. **Detection:** `_handleInvalidToken()` triggered
5. **Cleanup:** Token cleared, session reset, caches cleared
6. **Recovery Options:**
   - **If multi-account:** Auto-switch to next valid account, reconnect
   - **If single-account:** Emit 'invalid_token' message, user must re-login
7. **UI Notification:** Show error message and navigate to PhoneEntryScreen

---

## Key Observations

- **No `FAIL_LOGIN_TOKEN`:** The codebase doesn't use this literal string
- **Uses `invalid_token` type instead:** The standard error type for all token validation failures
- **Smart multi-account handling:** Automatically switches to another account if available
- **Graceful degradation:** Falls back to login screen if no alternative accounts
- **Health monitoring:** Invalid tokens are logged to health monitor for analytics
- **Stream-based:** Uses reactive streams (StreamController) for message broadcasting
