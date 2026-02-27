# Flutter Video Playback Error Analysis Report

## Error Message Location
**Error Text**: "Проверьте подключение к интернету\nили попробуйте позже" (Check your internet connection or try again later)

---

## 1. Where Video Player is Initialized

### Location 1: `lib/widgets/full_screen_video_player.dart`

**File**: `lib/widgets/full_screen_video_player.dart`
**Method**: `_initializePlayer()`
**Lines**: 58-91

```dart
Future<void> _initializePlayer() async {
  try {
    _videoPlayerController = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
      httpHeaders: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    );

    _videoPlayerController!.addListener(_videoListener);
    await _videoPlayerController!.initialize();
    _videoPlayerController!.play();

    if (mounted) {
      setState(() {
        _isLoading = false;
        _isPlaying = true;
        _totalDuration = _videoPlayerController!.value.duration;
        _currentPosition = _videoPlayerController!.value.position;
      });
      _startHideControlsTimer();
      _startPositionTimer();
    }
  } catch (e) {
    print('❌ [FullScreenVideoPlayer] Error initializing player: $e');
    if (mounted) {
      setState(() {
        _hasError = true;          // Line 86
        _isLoading = false;         // Line 87
      });
    }
  }
}
```

### Location 2: `lib/widgets/chat_message_bubble.dart`

**File**: `lib/widgets/chat_message_bubble.dart`
**Class**: `_VideoCirclePlayerState`
**Method**: `_loadVideo()`
**Lines**: 8746-8792

```dart
Future<void> _loadVideo() async {
  try {
    final videoUrl = await ApiService.instance.getVideoUrl(
      widget.videoId,
      widget.chatId,
      widget.messageId,
    );

    if (!mounted) return;

    _controller = VideoPlayerController.networkUrl(
      Uri.parse(videoUrl),                              // Line 8757
      httpHeaders: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    );

    await _controller!.initialize();                    // Line 8764

    if (!mounted) return;

    _controller!.setLooping(true);
    _controller!.setVolume(0.0);
    _controller!.play();

    setState(() {
      _isLoading = false;
      _isPlaying = true;
      _isUserTapped = false;
    });
  } catch (e) {
    print('❌ [VideoCirclePlayer] Error loading video: $e');
    if (e is UnimplementedError &&
        e.message?.contains('init() has not been implemented') == true) {
      print(
        '⚠️ [VideoCirclePlayer] Video playback not supported on this platform',
      );
    }
    if (mounted) {
      setState(() {
        _hasError = true;                               // Line 8787
        _isLoading = false;                             // Line 8788
      });
    }
  }
}
```

---

## 2. Error Handling - What Shows This Message

### Error Widget Definition
**File**: `lib/widgets/full_screen_video_player.dart`
**Class**: `_ErrorWidget`
**Lines**: 937-982

```dart
class _ErrorWidget extends StatelessWidget {
  final ColorScheme colorScheme;

  const _ErrorWidget({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                color: colorScheme.onErrorContainer,
                size: 48,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Не удалось загрузить видео',                              // Line 964
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Проверьте подключение к интернету\nили попробуйте позже',  // Line 973
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
```

### Error Display Logic
**File**: `lib/widgets/full_screen_video_player.dart`
**Lines**: 267-271

The error widget is displayed when `_hasError` flag is set to true:

```dart
_isLoading
    ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
    : _hasError                                         // Line 269
    ? Center(child: _ErrorWidget(colorScheme: colorScheme))  // Line 270
    : _videoPlayerController != null &&
          _videoPlayerController!.value.isInitialized
    ? InteractiveViewer(...)
```

### What Causes the Error
The error is triggered when:
1. **VideoPlayerController.networkUrl()** initialization fails (line 60-66)
2. **await _videoPlayerController!.initialize()** throws an exception (line 69)
3. Any exception in the try-catch block sets `_hasError = true` (line 86)

Common causes:
- Network connectivity issues (no internet)
- Invalid video URL
- Server errors (HTTP errors)
- Cleartext traffic blocked (HTTP URLs on Android 9+)
- CORS/SSL certificate issues

---

## 3. Network Security Configuration

### Android Cleartext Traffic Setting
**File**: `android/app/src/main/AndroidManifest.xml`
**Line**: 43

```xml
<application
  android:label="Komet"
  android:name="${applicationName}"
  android:icon="@mipmap/ic_launcher"
  android:requestLegacyExternalStorage="true"
  android:preserveLegacyExternalStorage="true"
  android:usesCleartextTraffic="true">
```

**Finding**: `android:usesCleartextTraffic="true"` is enabled at the application level.

### Network Security Configuration Files
**Status**: No dedicated `network_security_config.xml` file found in the project.

### Implications
- **Cleartext (HTTP) traffic is explicitly allowed** for the entire application
- This means the app can load videos from both HTTP and HTTPS URLs
- Without a more granular `network_security_config.xml`, all domains can use cleartext traffic
- This is less secure but necessary if video URLs are served over HTTP

### Recommended Network Security File (if needed)
If you want to restrict cleartext to specific domains only, create:
`android/app/src/main/res/xml/network_security_config.xml`

Example to allow cleartext only for specific domains:
```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="true">example.com</domain>
    </domain-config>
    <domain-config cleartextTrafficPermitted="false">
        <domain includeSubdomains="true">*</domain>
    </domain-config>
</network-security-config>
```

Then reference it in AndroidManifest.xml:
```xml
<application
  ...
  android:networkSecurityConfig="@xml/network_security_config">
```

---

## Summary

| Item | Location | Details |
|------|----------|---------|
| **Error Message** | `lib/widgets/full_screen_video_player.dart:973` | "Проверьте подключение к интернету\nили попробуйте позже" |
| **Error Widget** | `lib/widgets/full_screen_video_player.dart:937-982` | `_ErrorWidget` class |
| **Display Logic** | `lib/widgets/full_screen_video_player.dart:269-270` | Conditional rendering when `_hasError == true` |
| **Full Screen Player Init** | `lib/widgets/full_screen_video_player.dart:58-91` | `_initializePlayer()` method |
| **Chat Message Player Init** | `lib/widgets/chat_message_bubble.dart:8746-8792` | `_VideoCirclePlayerState._loadVideo()` method |
| **Video Controller** | Both files above | `VideoPlayerController.networkUrl()` with User-Agent header |
| **Cleartext Traffic** | `android/app/src/main/AndroidManifest.xml:43` | `android:usesCleartextTraffic="true"` |
| **Network Security Config** | Not present | No dedicated XML configuration file found |

---

## Error Flow
1. User plays a video → `_initializePlayer()` or `_loadVideo()` is called
2. `VideoPlayerController.networkUrl()` is created
3. `await controller.initialize()` is awaited
4. If any exception occurs → `_hasError = true` is set in catch block
5. UI rebuilds and displays `_ErrorWidget` with the error message
6. User sees: "Не удалось загрузить видео" + "Проверьте подключение к интернету..."
