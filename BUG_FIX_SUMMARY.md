# Bug Fix Summary: Photos and GIFs Gallery Issues

## Issues Fixed

### Bug 12: Photo Opens Wrong Image
**Problem**: When tapping on a GIF or non-PHOTO attachment, the photo viewer was attempting to open it within the gallery context, causing index mismatches and opening wrong images.

**Root Cause**: The `_openPhotoViewer` method in `ChatMessageBubble` was not filtering attachments by type. When a GIF (or other non-PHOTO type) was tapped, it would try to find its index in `allPhotos` (which only contains PHOTO attachments), resulting in `initialIndex == -1`. The code then fell back to single image view, but the wrong image could be displayed due to stale state.

**Solution Applied**:
- Added type check at the beginning of `_openPhotoViewer` method
- If attachment type is not 'PHOTO', explicitly set `galleryPhotos = null`
- This ensures GIFs and other media types bypass gallery logic entirely and open as single images
- File: `lib/widgets/chat_message_bubble.dart` (lines 4357-4361)

### Bug 13: GIF Shows as Photo After Scroll
**Problem**: After scrolling through a chat, GIFs would render as static images instead of showing animation.

**Root Cause**: Related to Bug 11 (videos sent as GIF type). When the rendering system incorrectly treats GIFs as photos, they lose their animation state. Additionally, GIF widgets may lose their animation controller state during scroll/page transitions.

**Current Status**: 
- Partially addressed by Bug 12 fix (GIFs no longer open in photo gallery)
- Full fix depends on Bug 11 being resolved (proper VIDEO type assignment from backend)
- Once backend properly types videos as 'VIDEO' instead of 'GIF', this issue should resolve

## Code Changes

### File: `lib/widgets/chat_message_bubble.dart`

**Method**: `_openPhotoViewer` (starting line 4354)

**Added Code**:
```dart
// Don't use gallery for non-PHOTO attachments (e.g., GIFs, which have different _type)
final attachType = attach['_type'] as String?;
if (attachType != null && attachType != 'PHOTO') {
  galleryPhotos = null;
}
```

**Logic Flow**:
1. Extract the `_type` field from the attachment
2. If type exists and is not 'PHOTO', force `galleryPhotos` to null
3. This skips all gallery logic and opens the attachment as a single image view
4. Prevents index mismatch errors and ensures correct image is displayed

## Testing Recommendations

1. **Test Bug 12 Fix**:
   - Send mixed photo and GIF messages
   - Tap on each photo/GIF
   - Verify correct image opens each time
   - Verify photo gallery works for multi-photo messages

2. **Test Bug 13 Fix** (after Backend Bug 11 is deployed):
   - Send GIF/video messages
   - Scroll chat up and down
   - Verify GIFs continue to animate after scroll
   - Check that videos display with proper player controls

3. **Regression Testing**:
   - Multi-photo message gallery should still work normally
   - Photo gallery arrows and thumbnail previews should function
   - Single photo/GIF messages should open correctly

## Related Issues

- **Bug 11** (Backend): Videos must be typed as 'VIDEO' not 'GIF' for complete fix
- **Bug 7**: Audio playback issues (separate fix)
- **Bug 10**: Contact picker extras (pending server investigation)

## Implementation Notes

- The fix is minimal and surgical - only affects non-PHOTO types
- Photo gallery functionality remains completely intact
- No changes to FullScreenPhotoViewer class needed (the bypass prevents it from being called with wrong data)
- Safe to deploy independently - doesn't depend on other fixes
