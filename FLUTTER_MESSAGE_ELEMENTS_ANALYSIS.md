# Flutter Message Model & Elements/Formatting Analysis

## Overview
This document provides a comprehensive analysis of how message models and text formatting/elements are handled in the Flutter chat application.

---

## 1. Message Model Structure (`lib/models/message.dart`)

### Main Message Class

```dart
@immutable
class Message {
  final String id;
  final String text;
  final int time;
  final int senderId;
  final String? status;
  final int? updateTime;
  final List<Map<String, dynamic>> attaches;
  final int? cid;
  final Map<String, dynamic>? reactionInfo;
  final Map<String, dynamic>? link;
  final List<Map<String, dynamic>> elements;  // ← Text formatting elements
  final bool isDeleted;
  final String? originalText;

  const Message({
    required this.id,
    required this.text,
    required this.time,
    required this.senderId,
    this.status,
    this.updateTime,
    this.attaches = const [],
    this.cid,
    this.reactionInfo,
    this.link,
    this.elements = const [],
    this.isDeleted = false,
    this.originalText,
  });
```

### Key Properties

- **`elements`**: Core field for message formatting. Contains a list of formatting directives applied to the message text
- **`text`**: The raw text content of the message
- **`attaches`**: List of attachments (files, photos, videos, etc.)
- **`link`**: Used for replies and forwards (type: 'REPLY' or 'FORWARD')
- **`reactionInfo`**: Contains emoji reactions and counters
- **`originalText`**: Stores the original text before editing
- **`status`**: Message status ('EDITED', sending status, etc.)

### Getter Methods

```dart
bool get isEdited => status == 'EDITED';
bool get isReply => link != null && link!['type'] == 'REPLY';
bool get isForwarded => link != null && link!['type'] == 'FORWARD';
bool get hasFileAttach => attaches.any((a) => (a['_type'] ?? a['type']) == 'FILE');
```

### Message Deserialization

```dart
factory Message.fromJson(Map<String, dynamic> json) {
  final senderId = json['sender'] is int ? json['sender'] as int : 0;
  final time = json['time'] is int ? json['time'] as int : 0;
  final text = json['text']?.toString() ?? '';

  return Message(
    id: json['id']?.toString() ?? 'local_${DateTime.now().millisecondsSinceEpoch}',
    text: text,
    time: time,
    senderId: senderId,
    status: json['status'] as String?,
    updateTime: json['updateTime'] as int?,
    attaches: _parseList(json['attaches']),
    cid: json['cid'] as int?,
    reactionInfo: json['reactionInfo'] as Map<String, dynamic>?,
    link: json['link'] as Map<String, dynamic>?,
    elements: _parseList(json['elements']),  // ← Elements parsing
    isDeleted: json['isDeleted'] ?? false,
    originalText: json['originalText'] as String?,
  );
}

static List<Map<String, dynamic>> _parseList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}
```

---

## 2. Message Elements Structure

### Element Types (from `FormattedTextController`)

Message elements are stored as `List<Map<String, dynamic>>` with the following structure:

```dart
{
  'type': String,      // Formatting type (see below)
  'from': int,         // Start position in text
  'length': int,       // Length of formatted section
  'entityId': int?,    // For mentions: user ID
  'entityName': String? // For mentions: user name
}
```

### Supported Element Types

1. **`STRONG`** - Bold text
2. **`EMPHASIZED`** - Italic text
3. **`UNDERLINE`** - Underlined text
4. **`STRIKETHROUGH`** - Strike-through text
5. **`QUOTE`** - Block quote/quoted text
6. **`USER_MENTION`** - @user mentions with entityId and entityName

### Example Element Objects

```dart
// Bold text from position 5, length 10
{'type': 'STRONG', 'from': 5, 'length': 10}

// User mention
{
  'type': 'USER_MENTION',
  'from': 0,
  'length': 8,
  'entityId': 12345,
  'entityName': 'John Doe'
}

// Italic text
{'type': 'EMPHASIZED', 'from': 15, 'length': 7}
```

---

## 3. Text Formatting Controller (`lib/widgets/formatted_text_controller.dart`)

### Class Structure

```dart
class FormattedTextController extends TextEditingController {
  final List<Map<String, dynamic>> elements = [];

  FormattedTextController({super.text});

  void refresh() {
    notifyListeners();
  }
```

### Key Methods

#### Text Mutation Handling
Automatically adjusts element positions when text is edited:

```dart
void _handleTextMutation(String oldText, String newText) {
  // Detects changes and applies insertion/deletion logic
  // Maintains element position accuracy during text edits
}
```

#### Insertion & Deletion Logic
- `_applyInsertion()` - Shifts element positions when text is inserted
- `_applyDeletion()` - Removes or adjusts elements when text is deleted
- Special handling for QUOTE type (different adjustment logic)

#### Style Clearing
```dart
void clearStylesForSelection(TextSelection selection) {
  // Removes all elements that overlap with selected text
  elements.removeWhere((el) {
    final elFrom = (el['from'] as int?) ?? 0;
    final elLen = (el['length'] as int?) ?? 0;
    final elEnd = elFrom + elLen;
    return (elFrom < end && elEnd > start);
  });
}
```

#### Text Span Building
Converts elements into styled `TextSpan`:

```dart
TextSpan buildTextSpan({
  required BuildContext context,
  TextStyle? style,
  bool withComposing = false,
}) {
  // Builds visual representation with applied styles
  // Handles overlapping styles intelligently
  return _buildSpanWithoutQuote(context, text, baseStyle, elements);
}
```

### Style Application Logic

The controller creates style arrays for each character position:
```dart
final bold = List<bool>.filled(text.length, false);
final italic = List<bool>.filled(text.length, false);
final underline = List<bool>.filled(text.length, false);
final strike = List<bool>.filled(text.length, false);
final quote = List<bool>.filled(text.length, false);
final mention = List<bool>.filled(text.length, false);
```

Then applies styles per character type and combines them.

---

## 4. Message Bubble Rendering (`lib/widgets/chat_message_bubble.dart`)

### Message Display Flow

```
Message received
    ↓
ChatMessageBubble widget receives message
    ↓
Determines message type (normal, reply, forward, media-only, etc.)
    ↓
_buildMixedMessageContent() called
    ↓
_parseMixedMessageSegments() - splits text by komet formatting
    ↓
Elements sliced per segment
    ↓
_buildFormattedRichText() - applies formatting
    ↓
RichText or Linkify displayed
```

### Key Method: _buildMixedMessageContent

```dart
Widget _buildMixedMessageContent(
  BuildContext context,
  String text,
  TextStyle baseStyle,
  TextStyle linkStyle,
  Future<void> Function(LinkableElement) onOpenLink, {
  List<Map<String, dynamic>> elements = const [],
}) {
  // Limits text size (10KB)
  const int maxTextLength = 10000;
  
  // Parses text into segments (normal, colored, galaxy, pulse)
  final segments = _segmentsCache[message] ??= _parseMixedMessageSegments(text);
  
  // For each segment:
  // 1. Slice elements that apply to this segment's content range
  // 2. Render with appropriate formatting based on segment type
  // 3. Apply link styles and formatting elements
}
```

### Element Slicing Logic

```dart
// For each segment, find overlapping elements
for (final el in elements) {
  final from = (el['from'] as int?) ?? 0;
  final length = (el['length'] as int?) ?? 0;
  final end = from + length;
  
  // Calculate overlap between segment [contentStart, contentEnd] and element [from, end]
  final overlapStart = from < contentStart ? contentStart : from;
  final overlapEnd = end > contentEnd ? contentEnd : end;
  
  if (overlapEnd > overlapStart) {
    final mapped = Map<String, dynamic>.from(el);
    // Translate to segment-relative positions
    mapped['from'] = overlapStart - contentStart;
    mapped['length'] = overlapEnd - overlapStart;
    slicedElements.add(mapped);
  }
}
```

### Segment Types

From `lib/widgets/message_bubble/models/komet_segment.dart`:

```dart
enum KometSegmentType { normal, colored, galaxy, pulse }

class KometSegment {
  final String text;
  final KometSegmentType type;
  final Color? color;
  final int absStart;
  final int absEnd;
  final int contentStart;
  
  KometSegment(
    this.text,
    this.type, {
    this.color,
    required this.absStart,
    required this.absEnd,
    required this.contentStart,
  });
}
```

- **`normal`** - Plain text, applies elements normally
- **`colored`** - Colored text (Komet cosmetic)
- **`galaxy`** - Galaxy animation effect
- **`pulse`** - Pulse animation effect

---

## 5. Message Creation & Sending

### Chat Input Controller (`lib/screens/chat/controllers/chat_input_controller.dart`)

Elements are managed in the input controller:

```dart
class ChatInputController extends ChangeNotifier {
  final FormattedTextController textController = FormattedTextController();
  // ...
  
  void toggleStyle(String type) {
    final selection = textController.selection;
    
    // Find and remove existing style
    bool found = false;
    for (int i = 0; i < textController.elements.length; i++) {
      final el = textController.elements[i];
      if (el['type'] == type && 
          el['from'] == from && 
          el['length'] == length) {
        textController.elements.removeAt(i);
        found = true;
        break;
      }
    }
    
    // Add new style if not found
    if (!found) {
      textController.elements.add({
        'type': type,
        'from': from,
        'length': length,
      });
    }
    
    textController.notifyListeners();
  }
}
```

### Message Sending Process (`lib/screens/chat_screen_logic.dart`)

```dart
Future<void> _sendMessage() async {
  final originalText = _textController.text.trim();
  
  // Combine mentions with user-applied formatting
  final List<Map<String, dynamic>> elements = [
    ..._captureMentions(),  // Auto-detected @mentions
    ..._textController.elements,  // User-applied styles
  ];
  
  // Validate mentions
  if (!_validateMentions(elements)) {
    elements.removeWhere((e) => e['type'] == 'USER_MENTION');
  }
  
  // Create temporary message for optimistic UI
  final tempMessage = _createTempMessage(
    text: textToSend,
    cid: tempCid,
    elements: elements,  // ← Include formatted elements
  );
  
  // Send to server
  _sendToServer(
    text: textToSend,
    cid: tempCid,
    elements: elements,  // ← Include formatted elements
    replyToMessageId: replyIdForServer,
    replyToMessage: replyMsgForLocal,
  );
}

bool _validateMentions(List<Map<String, dynamic>> elements) {
  for (final element in elements) {
    if (element['type'] == 'USER_MENTION') {
      final entityId = element['entityId'];
      final entityName = element['entityName'];
      // Must have valid entityId (int > 0) OR entityName
      if ((entityId == null || entityId is! int || entityId <= 0) &&
          (entityName == null || entityName.toString().isEmpty)) {
        return false;
      }
    }
  }
  return true;
}
```

---

## 6. Mention Handling

### Mention Class

```dart
@immutable
class Mention {
  final int from;
  final int length;
  final int entityId;
  final String entityName;

  const Mention({
    required this.from,
    required this.length,
    required this.entityId,
    required this.entityName,
  });

  Map<String, dynamic> toJson() => {
    'type': 'USER_MENTION',
    'from': from,
    'length': length,
    'entityId': entityId,
  };
}
```

### Mention Parsing

Auto-detects and parses `@username` patterns from text:
```dart
// Парсим @username из текста и добавляем USER_MENTION elements
List<Map<String, dynamic>> _captureMentions() {
  // Regex pattern for @username
  // Creates USER_MENTION element with proper from/length
}
```

---

## 7. Message Draft Persistence

Elements are saved and restored when drafts are loaded:

```dart
// Save draft
ChatCacheService().saveChatInputState(chatId, {
  'text': _textController.text,
  'elements': _textController.elements,
  'replyingToMessage': replyingData,
});

// Restore draft
final state = ChatCacheService().getChatInputState(chatId);
if (state != null && mounted) {
  final text = state['text'] as String? ?? '';
  final elements = (state['elements'] as List<dynamic>?)
      ?.map((e) => e as Map<String, dynamic>)
      .toList() ?? [];
  
  _textController.text = text;
  _textController.elements.addAll(elements);
}
```

---

## 8. Display in Chat Media Screen

Elements are used to extract mentions from messages:

```dart
// lib/screens/chat_media_screen.dart
for (final element in message.elements) {
  // Process elements to extract mentions, etc.
}
```

---

## 9. Komet Animated Text Support

The app supports animated text effects via Komet cosmetics:

```dart
case KometSegmentType.galaxy:
  return GalaxyAnimatedText(text: seg.text);

case KometSegmentType.pulse:
  final hexStr = seg.color!.toARGB32()
      .toRadixString(16)
      .padLeft(8, '0')
      .substring(2)
      .toUpperCase();
  return PulseAnimatedText(
    text: "komet.cosmetic.pulse#$hexStr'${seg.text}'",
  );
```

---

## Summary

### Element Structure
- **Type**: Formatting type (STRONG, EMPHASIZED, UNDERLINE, STRIKETHROUGH, QUOTE, USER_MENTION)
- **From/Length**: Position in text (character indices)
- **Optional**: entityId/entityName for mentions

### Processing Pipeline
1. **Input**: Elements managed in `FormattedTextController` during typing
2. **Creation**: Elements combined with auto-detected mentions before sending
3. **Transmission**: Elements sent to server along with message text
4. **Reception**: Elements parsed from JSON in `Message.fromJson()`
5. **Display**: Elements sliced per segment and applied as styles in `_buildMixedMessageContent()`
6. **Rendering**: Text rendered with applied formatting using `Linkify`, `RichText`, or animations

### Key Design Patterns
- **Position-based formatting**: Elements reference positions (from, length) rather than text markers
- **Text-agnostic**: Positions adjusted automatically when text changes
- **Layered rendering**: Multiple styles can overlap on same characters
- **Segment-based**: Text split into segments (normal, colored, animated) before rendering
- **Smart caching**: Segment parsing cached to avoid recomputation
