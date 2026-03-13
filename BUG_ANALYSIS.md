# Bug Analysis: Unnecessary 'auto_switched_account' Event with 2FA

## Problem Summary
When 2FA is enabled, the `auto_switched_account` event is being triggered unnecessarily. The issue is that when opcode 159 (profile push update) is received, it's being confused with an actual account switch scenario.

## Current Flow

### 1. In `lib/api/api_service_connection.dart` (lines 121-182)
The `_handleInvalidToken()` method triggers account auto-switch:
```dart
void _handleInvalidToken() async {
  // ... token invalidation logic ...
  
  // When switching to another account:
  _messageController.add({
    'type': 'auto_switched_account',
    'message': 'Автоматически переключились на другой аккаунт',
    'accountId': nextAccount.id,
  });
  
  // Reconnect with new account
  unawaited(connect());
}
```

**This is the CORRECT trigger for auto_switched_account** - it should only be sent when actually switching to a different account due to token invalidation.

### 2. In `lib/api/api_service_connection.dart` (lines 436-442)
Opcode 159 (profile push update) handling:
```dart
// Обновляем кэш профиля при получении push-уведомления opcode 159
if (opcode == 159 && payload != null) {
  final profileData = payload['profile'] as Map<String, dynamic>?;
  if (profileData != null && _lastChatsPayload != null) {
    _lastChatsPayload!['profile'] = profileData;
    print('🔄 Кэш профиля обновлён из push opcode 159');
  }
}
```

**This code just updates the profile cache - it should NOT trigger account switch events.**

### 3. In `lib/screens/chat/handlers/message_handler.dart` (lines 204-220)
The UI layer that shows the snackbar:
```dart
if (message['type'] == 'auto_switched_account') {
  // Автоматически переключились на другой аккаунт — перезагружаем UI
  print('🔄 Автопереключение аккаунта: ${message['accountId']}');
  if (getMounted()) {
    final ctx = getContext();
    ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(
        content: Text('Автоматически переключились на другой аккаунт'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ),
    );
    // Перезапускаем загрузку чатов
    refreshChats();
  }
}
```

## Root Cause Analysis

The bug likely occurs because:
1. During 2FA setup/validation, the server sends opcode 159 (profile update) to confirm the current session
2. If there's a disconnect/reconnect during 2FA, the system might be incorrectly treating the profile update as a signal to switch accounts
3. The `auto_switched_account` event is being emitted when it shouldn't be

## Solution

The fix should:
1. Add a flag to track whether an actual account switch occurred (not just a profile update)
2. Only emit `auto_switched_account` when `_handleInvalidToken()` actually switches to a different account
3. Ensure opcode 159 (profile push update) never triggers the snackbar

The snackbar in `message_handler.dart` should only show when there was an actual navigation change, not just a profile cache update.

## Code Sections to Review
- `lib/api/api_service_connection.dart`: Lines 121-182 (account switch logic)
- `lib/api/api_service_connection.dart`: Lines 436-442 (opcode 159 handling)
- `lib/screens/chat/handlers/message_handler.dart`: Lines 204-220 (snackbar display)
