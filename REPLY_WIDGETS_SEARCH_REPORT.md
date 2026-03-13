# Flutter Reply-Related Widgets Search Report

## Summary
Search performed for reply-related widgets in the Flutter workspace using grep patterns:
- `replyWidget|ReplyWidget|reply_widget|replyPanel|ReplyPanel|replyMessage|ReplyMessage`

**Result**: No exact matches for the above patterns. However, comprehensive reply functionality is implemented using a generic `link` system with type checking.

---

## Key Findings

### 1. Reply Detection in Message Model
**File**: `lib/models/message.dart` (Line 116)

```dart
bool get isReply => link != null && link!['type'] == 'REPLY';
```

The reply detection uses a `link` property in the `Message` model where the type is checked against `'REPLY'`.

**Message class structure**:
- Property: `link` (Map<String, dynamic>?)
- Contains nested message data and metadata
- Used for both REPLY and FORWARD types

---

## Reply Preview Widgets Found

### 1. **_buildReplyPreview() Method**
**File**: `lib/widgets/chat_message_bubble.dart` (Lines 789-886)

**Purpose**: Renders a reply preview widget within the older chat message bubble implementation.

**Key Features**:
- Extracts reply message from `link['message']`
- Displays sender name with optional color coding
- Shows reply text preview (max 2 lines)
- Uses adaptive width based on text length (min: 120.0dp)
- Supports auto reply color based on sender ID via `getUserColor()`
- Custom reply colors supported via `customReplyColor` parameter
- Shows "Фото" placeholder when text is empty
- Clickable to navigate to original message

**Implementation Details**:
```dart
Widget _buildReplyPreview(
  BuildContext context,
  Map<String, dynamic> link,
  Color textColor,
  double messageTextOpacity,
  bool isUltraOptimized,
  double messageBorderRadius,
)
```

**Parameters Used from Message**:
- `link['message']['text']` - Reply message text
- `link['message']['sender']` - Sender ID for color/name lookup
- `link['message']['id']` - Message ID for navigation

**Styling Details**:
- Container with left border (2px width, accent color)
- Background color with transparency (0.15 in dark mode, 0.08 in light)
- Border radius: `messageBorderRadius * 0.3`
- Icon: `Icons.reply` (12px)
- Font sizes: sender name (10px, bold), reply text (11px)

**Navigation**: Callback `onReplyTap(messageId)` when tapped

---

### 2. **_ReplyPreview Class**
**File**: `lib/screens/chat/widgets/chat_message_item.dart` (Lines 352-412)

**Purpose**: Newer implementation for reply preview in the refactored chat message item.

**Key Features**:
- Simpler, cleaner widget structure
- Uses theme's surface and primary colors
- Displays reply icon with reply text
- Supports "Медиафайл" fallback text for media-only messages
- Stateless widget (pure presentation)
- MouseRegion for cursor feedback on web

**Implementation Details**:
```dart
class _ReplyPreview extends StatelessWidget {
  final Map<String, dynamic> link;
  final ThemeData theme;
  final VoidCallback? onTap;
}
```

**Styling Details**:
- Container with `surface.withValues(alpha: 0.5)`
- Left border with primary color (2px)
- Border radius: 8dp
- Icon: `Icons.reply` (14px, primary color with 0.8 opacity)
- Text: 13px, surface color with 0.7 opacity
- Padding: 8px horizontal, 4px vertical
- Max lines for text: 2

**Usage Location**: `lib/screens/chat/widgets/chat_message_item.dart:262`
```dart
if (message.isReply && message.link != null)
  _ReplyPreview(
    link: message.link!,
    theme: theme,
    onTap: () {
      final replyMessage = message.link!['message'] as Map<String, dynamic>?;
      final messageId = replyMessage?['id']?.toString();
      if (messageId != null && onReplyTap != null) {
        onReplyTap!(messageId);
      }
    },
  ),
```

---

## Reply Functionality Files

### Files Using Reply Features

1. **lib/models/message.dart**
   - `isReply` getter (line 116)
   - `isForwarded` getter (line 117) - Uses same link system
   - Message model definition

2. **lib/widgets/chat_message_bubble.dart**
   - `_buildReplyPreview()` method (lines 789-886)
   - Reference at line 4723
   - Constructor parameters:
     - `onReplyTap` callback
     - `useAutoReplyColor` (default: true)
     - `customReplyColor` (optional)
     - `contactDetailsCache` for sender lookup

3. **lib/screens/chat/widgets/chat_message_item.dart**
   - `_ReplyPreview` class (lines 352-412)
   - Used at line 262 in message building
   - Checks `message.isReply && message.link != null`

4. **lib/screens/chat/controllers/chat_input_controller.dart**
   - `replyToMessageId` parameter (lines 298-299)
   - `_replyingToMessage` state management

5. **lib/screens/chat_screen_logic.dart**
   - Reply sending logic (lines 52-53)
   - `replyToMessageId` parameter
   - `replyToMessage` parameter
   - Reply color assignment (line 1241)

6. **lib/screens/chat_screen_ui.dart**
   - `onReply` callback trigger (line 2023)
   - Links to `_replyToMessage(message)` method

7. **lib/api/api_service_chats.dart**
   - Message sending with reply (lines 1238-1257)
   - Builds link structure for API:
     ```dart
     if (replyToMessageId != null) {
       "link": {
         "type": "REPLY",
         "messageId": parsedReplyId ?? replyToMessageId,
         ...
       }
     }
     ```

---

## Link Structure Format

Based on code analysis, the reply link structure is:
```dart
Map<String, dynamic> link = {
  'type': 'REPLY',  // or 'FORWARD'
  'message': {
    'id': messageId,
    'text': messageText,
    'sender': senderId,
    'attaches': [...],
    'elements': [...],
  },
  'chatName': String?,
  'chatId': int?,
  'chatLink': String?,
  'chatIconUrl': String?,
}
```

---

## Key Observations

1. **No Dedicated Widget Names**: The reply functionality doesn't use specific naming patterns like `ReplyWidget` or `ReplyPanel`. Instead, it uses a generic `link` property with type discrimination.

2. **Two Implementations**: 
   - Old implementation: `_buildReplyPreview()` in `ChatMessageBubble` (for older UI)
   - New implementation: `_ReplyPreview` class in `chat_message_item.dart` (current/refactored UI)

3. **Color System**: Reply previews support both automatic color assignment (via `getUserColor()`) and custom colors.

4. **Callback Pattern**: Navigation to replied messages uses `onReplyTap(messageId)` callback pattern.

5. **Consistency**: Both reply preview implementations check for `message.isReply` and validate `message.link` before rendering.

---

## Files Summary Table

| File Path | Type | Lines | Component | Purpose |
|-----------|------|-------|-----------|---------|
| `lib/models/message.dart` | Model | 116 | `isReply` getter | Reply detection logic |
| `lib/widgets/chat_message_bubble.dart` | Widget | 789-886 | `_buildReplyPreview()` | Legacy reply preview rendering |
| `lib/screens/chat/widgets/chat_message_item.dart` | Widget | 352-412 | `_ReplyPreview` class | Current reply preview widget |
| `lib/screens/chat/controllers/chat_input_controller.dart` | Controller | 298-299 | Reply state | Input handling for replies |
| `lib/screens/chat_screen_logic.dart` | Logic | Multiple | Reply logic | Reply message sending |
| `lib/screens/chat_screen_ui.dart` | UI | 2023 | Reply callback | UI integration |
| `lib/api/api_service_chats.dart` | Service | 1238-1257 | API call builder | Server communication for replies |

