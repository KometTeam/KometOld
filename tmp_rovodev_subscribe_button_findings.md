# Channel Subscribe Button - Findings

## Summary
The subscribe button for channels is **NOT** shown directly in the chat screen itself. Instead, subscription is handled through a dialog that appears when users access a channel via a link.

## Key Locations

### 1. Subscribe Dialog Implementation
**File:** `lib/screens/home_screen.dart`

**Method:** `_showChannelSubscribeDialog()`

This dialog is shown when a user follows a channel link. The implementation includes:

```dart
void _showChannelSubscribeDialog(
  Map<String, dynamic> chatInfo,
  String linkToJoin,
) {
  final String title = chatInfo['title'] ?? 'Канал';
  final String? iconUrl =
      chatInfo['baseIconUrl'] ?? chatInfo['baseUrl'] ?? chatInfo['iconUrl'];

  int subscribeState = 0;  // 0: initial, 1: loading, 2: success, 3: error
  String? errorMessage;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          // ... content changes based on subscribeState
        },
      );
    },
  );
}
```

### 2. Subscribe States

The dialog manages three states:

1. **State 0 (Initial)**: Shows channel info with "Подписаться" (Subscribe) button
2. **State 1 (Loading)**: Shows "Подписка..." (Subscribing...) with loading spinner
3. **State 2 (Success)**: Shows success icon with "Вы подписались на канал!" (You subscribed!)
4. **State 3 (Error)**: Shows error icon with error message

### 3. Subscribe Button Code

```dart
} else {
  content = Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (iconUrl != null && iconUrl.isNotEmpty)
        CircleAvatar(
          radius: 60,
          backgroundImage: NetworkImage(iconUrl),
          onBackgroundImageError: (e, s) {
            print("Ошибка загрузки аватара канала: $e");
          },
          backgroundColor: Colors.grey.shade300,
        )
      else
        CircleAvatar(
          radius: 60,
          backgroundColor: Colors.grey.shade300,
          child: const Icon(
            Icons.campaign,
            size: 60,
            color: Colors.white,
          ),
        ),
      const SizedBox(height: 24),
      Text(
        title,
        style: Theme.of(context).textTheme.titleLarge,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      const Text(
        'Вы действительно хотите подписаться на этот канал?',
        textAlign: TextAlign.center,
      ),
    ],
  );
  actions = [
    TextButton(
      child: const Text('Отмена'),
      onPressed: () {
        Navigator.of(dialogContext).pop();
      },
    ),
    FilledButton(
      child: const Text('Подписаться'),
      onPressed: () async {
        setState(() {
          subscribeState = 1;
        });

        try {
          await ApiService.instance.subscribeToChannel(linkToJoin);

          setState(() {
            subscribeState = 2;
          });
        } catch (e) {
          setState(() {
            subscribeState = 3;
            errorMessage = e.toString();
          });
        }
      },
    ),
  ];
}
```

### 4. Visibility Conditions in Chat Screen

**File:** `lib/screens/chat_screen_ui.dart`

In the `_buildTextInput()` method (lines 841-854), for channels, the input field is **hidden** if the user is not an admin:

```dart
Widget _buildTextInput() {
  if (widget.isChannel) {
    bool amIAdmin = false;
    final currentChat = _getCurrentGroupChat();
    if (currentChat != null && _actualMyId != null) {
      final admins = currentChat['admins'] as List<dynamic>? ?? [];
      final owner = currentChat['owner'] as int?;
      amIAdmin = admins.contains(_actualMyId) || owner == _actualMyId;
    }

    if (!amIAdmin) {
      return const SizedBox.shrink();  // Input hidden for non-admins
    }
  }
  // ... rest of input UI
}
```

### 5. Channel Admin Settings Icon

**File:** `lib/screens/chat_screen_ui.dart` (lines 180-184)

Settings icon is only shown for channel admins:

```dart
// Иконка шестеренки для админов каналов
if (widget.isChannel && _isChannelAdmin())
  IconButton(
    onPressed: _openChannelSettings,
    icon: const Icon(Icons.settings),
    tooltip: 'Настройки канала',
  ),
```

### 6. Channel Model

**File:** `lib/models/channel.dart`

The Channel model does NOT have a subscription status field. It contains:

```dart
class Channel {
  final int id;
  final String name;
  final String? description;
  final String? photoBaseUrl;
  final String? link;
  final String? webApp;
  final List<String> options;  // Contains flags like 'OFFICIAL', 'JOIN_REQUEST', etc.
  final int updateTime;
}
```

The `options` list can contain `'JOIN_REQUEST'` which indicates if join request is required.

## Conclusion

- **There is NO "Subscribe" button shown in the chat screen UI itself**
- Subscription happens through a **dialog triggered when accessing a channel via link**
- The dialog shows the channel info and asks for confirmation with a "Подписаться" button
- Once subscribed, users are added to the channel with appropriate permissions based on whether they're admins
- Non-admins cannot send messages in channels (input field is hidden)
- The `Channel` model has an `options` field that can contain settings like `'JOIN_REQUEST'` for controlling join request requirements
