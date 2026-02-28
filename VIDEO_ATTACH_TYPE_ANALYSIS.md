# Video Gallery Picking and Sending - Attach Type Analysis

## Overview
This document shows where video from gallery is picked and sent in the chat screen, and where the video attach type is set.

---

## 1. VIDEO PICKING FROM GALLERY (UI Layer)

**File:** `lib/screens/chat_screen_ui.dart`

**Location:** Lines 2257-2662 in `_onAttachPressed()` and `_pickPhotosFlow()` functions

### Where user selects video from gallery (lines 2589-2591):
```dart
ListTile(
  leading: const Icon(Icons.video_library),
  title: const Text('Выбрать видео из галереи'),
  onTap: () => Navigator.pop(context, 'video'),
),
```

### Where ImagePicker picks video from gallery (lines 2614-2616):
```dart
} else if (choice == 'video') {
  final file = await picker.pickVideo(source: ImageSource.gallery);
  if (file != null) pickedFiles = [file];
  isVideoChoice = true;
```

### Where video is sent after selection (lines 2318-2328):
```dart
if (result != null && result.paths.isNotEmpty) {
  if (result.isVideo) {
    for (final path in result.paths) {
      await ApiService.instance.sendGalleryVideoMessage(
        widget.chatId,
        localPath: path,
        caption: result.caption,
        senderId: _actualMyId,
      );
    }
  } else {
    // ... photo sending code
  }
}
```

---

## 2. VIDEO ATTACH TYPE SET WHEN SENDING (API Layer)

**File:** `lib/api/api_service_chats.dart`

**Function:** `sendGalleryVideoMessage()` (lines 1785-1900)

### Where attach type is set for LOCAL MESSAGE PREVIEW (lines 1812-1814):
```dart
'attaches': [
  {'_type': 'VIDEO', 'url': 'file://$localPath', 'videoType': 0},
],
```

**Key Details:**
- `_type`: `'VIDEO'` ← **This is the attach type**
- `videoType`: `0` ← Standard video type (not a round video)
- `url`: `'file://$localPath'` ← Local file path for preview

### Where attach type is set for FINAL SENDING (lines 1859-1865):
```dart
final attachment = {
  'videoType': 0,
  '_type': 'VIDEO',
  'token': token,
  'size': fileSize,
  'videoId': videoId,
  'sender': senderId ?? 0,
};
```

**Key Details:**
- `_type`: `'VIDEO'` ← **This is the attach type for sending**
- `videoType`: `0` ← Standard video (not ROUNDVIDEO)
- `token`: Upload token from server
- `videoId`: ID from server's opcode 82 response
- `size`: File size in bytes
- `sender`: Sender ID

### Full payload sent to server (lines 1867-1877):
```dart
final payload = {
  'chatId': chatId,
  'message': {
    'isLive': false,
    'detectShare': false,
    'elements': [],
    'text': caption?.trim() ?? '',
    'cid': cid,
    'attaches': [attachment],  // ← Video attachment with _type: 'VIDEO'
  },
  'notify': true,
};

final resp64 = await sendRequest(64, payload);
```

---

## 3. FLOW SUMMARY

```
User selects "Выбрать видео из галереи" (Pick video from gallery)
    ↓
ImagePicker.pickVideo(source: ImageSource.gallery)
    ↓
_PhotoPickerResult created with isVideo: true
    ↓
ApiService.instance.sendGalleryVideoMessage()
    ↓
Emit local message with: {'_type': 'VIDEO', 'videoType': 0, 'url': 'file://...'}
    ↓
Upload video to server (opcode 82)
    ↓
Create final attachment with: {'_type': 'VIDEO', 'videoType': 0, 'token': ...}
    ↓
Send via opcode 64 with payload containing 'attaches': [attachment]
```

---

## 4. KEY FINDINGS

| Aspect | Value | Location |
|--------|-------|----------|
| **Attach Type** | `'VIDEO'` | `_type` field in attachment object |
| **Video Type Value** | `0` | `videoType` field (0 = standard, not round) |
| **ImagePicker Source** | `ImageSource.gallery` | Line 2614 in chat_screen_ui.dart |
| **Send Function** | `sendGalleryVideoMessage()` | Line 1785 in api_service_chats.dart |
| **Upload Opcode** | `82` | Line 1819 in api_service_chats.dart |
| **Send Opcode** | `64` | Line 1875 in api_service_chats.dart |
| **Local Preview Type** | `VIDEO` | Line 1813 in api_service_chats.dart |
| **Final Send Type** | `VIDEO` | Line 1862 in api_service_chats.dart |

---

## 5. VIDEO TYPE VALUES

Based on the code structure:
- `videoType: 0` = Standard video (used for gallery videos)
- No mention of `ROUNDVIDEO` in the gallery video sending flow
- Round video (if it exists) would likely use a different `videoType` value or `_type` field

---

## 6. NOTES

- The video is uploaded to a server URL obtained from opcode 82 response
- A token is returned after successful upload and used in the final message
- The `videoType: 0` is consistent in both local preview and final send
- Caption is optional and sent with the message
- The system uses `_type` field (with underscore prefix) for attach type classification
