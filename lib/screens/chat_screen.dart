import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:gwid/consts.dart';
import 'package:gwid/utils/theme_provider.dart';
import 'package:gwid/theme/theme_enums.dart';

import 'package:gwid/api/api_service.dart';
import 'package:flutter/services.dart';
import 'package:gwid/models/chat.dart';
import 'package:gwid/models/contact.dart';
import 'package:gwid/models/message.dart';
import 'package:gwid/widgets/chat_message_bubble.dart';
import 'package:gwid/widgets/complaint_dialog.dart';
import 'package:gwid/widgets/pinned_message_widget.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gwid/services/chat_cache_service.dart';
import 'package:gwid/services/chat_read_settings_service.dart';
import 'package:gwid/services/floating_call_manager.dart';
import 'package:gwid/services/call_overlay_service.dart';
import 'package:gwid/services/contact_local_names_service.dart';
import 'package:gwid/services/notification_service.dart';
import 'package:gwid/services/message_queue_service.dart';
import 'package:gwid/services/message_read_status_service.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:gwid/widgets/message_bubble/models/message_read_status.dart';

import 'package:gwid/screens/group_settings_screen.dart';
import 'package:gwid/screens/group_call_screen.dart';
import 'package:gwid/screens/settings/channel_settings_screen.dart';

import 'package:gwid/screens/contact_selection_screen.dart';
import 'package:gwid/models/video_conference.dart';
import 'package:gwid/widgets/contact_name_widget.dart';
import 'package:gwid/widgets/contact_avatar_widget.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:gwid/screens/chat_encryption_settings_screen.dart';
import 'package:gwid/screens/chat_media_screen.dart';
import 'package:gwid/screens/settings/chat_notification_settings_dialog.dart';

import 'package:gwid/services/chat_encryption_service.dart';
import 'package:gwid/widgets/formatted_text_controller.dart';
import 'package:gwid/screens/chat/models/chat_item.dart';
import 'package:gwid/screens/chat/widgets/empty_chat_widget.dart';

import 'package:gwid/screens/chats_screen.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:platform_info/platform_info.dart';
import 'package:gwid/services/voice_upload_service.dart';
import 'package:gwid/widgets/yaznaytvoytelefon.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_compress/video_compress.dart';
import 'dart:math' show pi;

part 'chat_screen_widgets.dart';
part 'chat_screen_logic.dart';
part 'chat_screen_ui.dart';
part 'chat_screen_voice.dart';

bool get _isMobilePlatform =>
    Platform.instance.operatingSystem.iOS ||
    Platform.instance.operatingSystem.android;

// Настройки позиции mention панели
class MentionPanelPosition {
  static const double left = 20.0; // Отступ слева (можете изменить)
  static const double right = 20.0; // Отступ справа (можете изменить)
  static const double bottom = 70.0; // Высота над input bar (можете изменить)
}

// Intents для клавиатурных сочетаний в чате
class SendMessageIntent extends Intent {
  const SendMessageIntent();
}

class NewLineIntent extends Intent {
  const NewLineIntent();
}

class ChatDebugSettings {
  static bool showExactDate = false;

  static void toggleShowExactDate() {
    showExactDate = !showExactDate;
  }
}
// End of helper classes

class ChatScreen extends StatefulWidget {
  final int chatId;
  final Contact contact;
  final int myId;
  final Message? pinnedMessage;
  final VoidCallback? onChatUpdated;
  final Function(Message?)? onLastMessageChanged;
  final Function(int, Map<String, dynamic>?)? onDraftChanged;
  final VoidCallback? onChatRemoved;
  final bool isGroupChat;
  final bool isChannel;
  final int? participantCount;
  final bool isDesktopMode;
  final String? channelLink;
  final bool needBotStart;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.contact,
    required this.myId,
    this.pinnedMessage,
    this.onChatUpdated,
    this.onLastMessageChanged,
    this.onDraftChanged,
    this.onChatRemoved,
    this.isGroupChat = false,
    this.isChannel = false,
    this.participantCount,
    this.isDesktopMode = false,
    this.channelLink,
    this.needBotStart = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

// Helper classes
class Mention {
  final int from;
  final int length;
  final int entityId;
  final String entityName;
  final String type;

  Mention({
    required this.from,
    required this.length,
    required this.entityId,
    required this.entityName,
    this.type = 'USER_MENTION',
  });

  Map<String, dynamic> toJson() {
    return {
      'from': from,
      'length': length,
      'entityId': entityId,
      'entityName': entityName,
      'type': type,
    };
  }
}

class _PhotoPickerResult {
  final List<String> paths;
  final String? caption;
  final bool isVideo;

  _PhotoPickerResult({required this.paths, this.caption, this.isVideo = false});

  // Add getter for compatibility
  List<String> get images => paths;
}

class VoicePreviewItem extends ChatItem {
  final bool isUploading;
  final double progress;
  final bool isFailed;
  final VoidCallback? onRetry;

  VoicePreviewItem({
    required this.isUploading,
    required this.progress,
    required this.isFailed,
    this.onRetry,
  });
}

class VideoPreviewItem extends ChatItem {
  final bool isUploading;
  final double progress;
  final bool isFailed;
  final VoidCallback? onRetry;

  VideoPreviewItem({
    required this.isUploading,
    required this.progress,
    required this.isFailed,
    this.onRetry,
  });
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  // Core state fields
  bool _isDisposed = false;
  bool _isOpeningChannelSettings = false;
  bool _isSubscribedLocally = false;
  final List<Message> _messages = [];
  List<ChatItem> _chatItems = [];
  List<Map<String, dynamic>> _cachedAllPhotos = [];
  final Set<String> _deletingMessageIds = {};

  // Loading states
  bool _isLoadingHistory = true;
  Map<String, dynamic>? _emptyChatSticker;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  // Controllers
  final FormattedTextController _textController = FormattedTextController();
  final FocusNode _textFocusNode = FocusNode();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final ValueNotifier<bool> _showScrollToBottomNotifier = ValueNotifier(false);
  final ValueNotifier<Message?> _pinnedMessageNotifier = ValueNotifier(null);

  // Данные чата (загружаются через opcode 48)
  String? _chatLink;
  int? _chatParticipantsCount;
  int? _chatMessagesCount;
  String? _chatAccessType;
  DateTime? _chatCreatedAt;
  DateTime? _chatJoinedAt;
  bool? _chatIsOfficial;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Chat data
  late Contact _currentContact;
  Message? _pinnedMessage;
  Message? _replyingToMessage;
  final Map<int, Contact> _contactDetailsCache = {};
  int? _lastPeerReadMessageId;
  String? _lastPeerReadMessageIdStr;
  Map<String, dynamic>? _cachedCurrentGroupChat;

  // API & Connection
  StreamSubscription? _apiSubscription;
  StreamSubscription? _readStatusSubscription;
  int? _actualMyId;
  int? _oldestLoadedTime;
  int _maxViewedIndex = 0;

  // Swipe gesture tracking
  double _swipeStartX = 0.0;
  double _swipeCurrentX = 0.0;
  bool _isSwiping = false;

  // Queue for messages received during history loading
  final List<Message> _pendingMessagesDuringLoad = [];
  int _lastLoadedAtViewedIndex = 0;
  static const int _pageSize = 50;
  static const int _historyLoadBatch = AppLimits.historyLoadBatch;
  static const int _loadMoreThreshold = 20;

  // Mentions & Commands
  bool _showBotCommandsPanel = false;
  bool _isLoadingBotCommands = false;
  int? _botCommandsForBotId;
  List<BotCommand> _botCommands = const [];
  bool _showMentionDropdown = false;
  List<Contact> _mentionableUsers = [];
  List<Contact> _filteredMentionableUsers = [];
  String _mentionQuery = '';
  int? _mentionStartPosition;
  final LayerLink _mentionLayerLink = LayerLink();
  final List<Mention> _mentions = [];

  // Encryption
  bool _isEncryptionPasswordSetForCurrentChat = false;
  ChatEncryptionConfig? _encryptionConfigForCurrentChat;
  bool _sendEncryptedForCurrentChat = true;

  // UI States
  Timer? _selectionCheckTimer;
  OverlayEntry? _mentionOverlay;

  String? _highlightedMessageId;
  bool _isSearching = false;
  List<Message> _searchResults = [];
  int _currentResultIndex = -1;

  // Additional UI states
  Message? _editingMessage;
  final ValueNotifier<bool> _testAnimationTrigger = ValueNotifier(false);

  // Input field key and height notifier
  final GlobalKey _inputKey = GlobalKey();
  final ValueNotifier<double> _inputHeightNotifier = ValueNotifier<double>(
    56.0,
  );

  // Scroll states
  bool _isUserAtBottom = true;
  bool _isScrollingToBottom = false;

  // Reactions
  final Set<String> _sendingReactions = {};
  final Map<int, String> _pendingReactionSeqs = {};

  // Voice recording
  bool _isVoiceRecordingUi = false;
  bool _isVideoRecordMode =
      false; // true = режим видеокружка, false = голосовое
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _currentRecordingPath;
  bool _isActuallyRecording = false;
  bool _isVoiceRecordingPaused = false;
  Duration _voiceRecordingDuration = Duration.zero;
  Timer? _voiceRecordingTimer;
  bool _isVoiceUploading = false;
  double _voiceUploadProgress = 0.0;
  String? _cachedVoicePath;
  bool _isVoiceUploadFailed = false;

  // Video message recording
  bool _isVideoRecordingUi = false;
  String? _currentVideoRecordingPath;
  bool _isActuallyVideoRecording = false;
  bool _isVideoRecordingPaused = false;
  Duration _videoRecordingDuration = Duration.zero;
  Timer? _videoRecordingTimer;
  bool _isVideoUploading = false;
  double _videoUploadProgress = 0.0;
  String? _cachedVideoPath;
  bool _isVideoUploadFailed = false;
  final int _videoWidth = 480;
  final int _videoHeight = 480;
  CameraController? _cameraController;

  static const double _recordCancelThreshold = 92.0;
  double _recordCancelDragDx = 0.0;
  late final AnimationController _recordCancelReturnController;

  static const double _recordSendButtonSpace = 40.0;
  static const double _recordPauseButtonSpace = 32.0;
  static const double _recordButtonGap = 4.0;

  // Typing indicators
  Timer? _typingTimer;
  DateTime _lastTypingSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Optimization getters
  bool get _optimize => context.read<ThemeProvider>().optimizeChats;
  bool get _ultraOptimize => context.read<ThemeProvider>().ultraOptimizeChats;
  bool get _anyOptimize => _optimize || _ultraOptimize;
  int get _optPage => _ultraOptimize
      ? AppLimits.historyLoadBatch
      : (_optimize ? 50 : _pageSize);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Set active chat as early as possible to keep notifications/unread in sync.
    ApiService.instance.currentActiveChatId = widget.chatId;

    // Уведомляем FloatingCallManager что мы в чате
    // Используем postFrameCallback чтобы избежать вызова notifyListeners во время build
    SchedulerBinding.instance.addPostFrameCallback((_) {
      FloatingCallManager.instance.setInChatScreen(true);
    });

    _currentContact = widget.contact;
    _pinnedMessage = widget.pinnedMessage;
    _pinnedMessageNotifier.value = widget.pinnedMessage;
    // Инициализируем статус подписки на канал
    if (widget.isChannel) {
      _isSubscribedLocally = ApiService.instance.myChatIds.contains(widget.chatId);
    }

    _recordCancelReturnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _init();
    });
  }

  // Initialize method referenced in initState
  Future<void> _init() async {
    try {
      await _initializeChat();
    } catch (e, st) {
      print('[ChatScreen] Ошибка инициализации чата ${widget.chatId}: $e');
      print(st);
    }

    _loadEncryptionConfig();

    // Initial height calculation for drafts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _handleChatInputChanged(_textController.text);
        // Capture initial input height
        final renderBox =
            _inputKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          _inputHeightNotifier.value = renderBox.size.height;
        }
      }
    });

    NotificationService().clearNotificationMessagesForChat(widget.chatId);

    _textController.addListener(_onTextControllerChanged);
    _textFocusNode.addListener(_onTextFocusChanged);

    // Подписываемся на обновления статусов прочитанности
    _readStatusSubscription = MessageReadStatusService().statusUpdates.listen((
      update,
    ) {
      if (update.chatId == widget.chatId && mounted) {
        print(
          '✨ [opcode 130] Обновление статуса в UI для чата ${widget.chatId}',
        );
      }
    });

    unawaited(_loadInputState());
  }

  // Text controller change handler
  void _onTextControllerChanged() {
    _handleChatInputChanged(_textController.text);
  }

  void _onTextFocusChanged() {
    if (_textFocusNode.hasFocus) {
      _startSelectionCheck();
      return;
    }

    _stopSelectionCheck();
    if (!mounted) return;
    _saveInputState();

    if (_showMentionDropdown) {
      setState(() {
        _showMentionDropdown = false;
      });
    }
  }

  // Handle API event - implemented in logic file via extension

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(ChatCacheService().flushPendingCache(widget.chatId));
    print('🗑️ dispose() вызван для чата ${widget.chatId}');
    print('📝 Текст перед dispose: "${_textController.text}"');

    // Всегда вызываем onDraftChanged - либо с данными, либо с null для очистки
    final textTrimmed = _textController.text.trim();

    if (textTrimmed.isNotEmpty) {
      print('💾 Сохраняем черновик в dispose()');
      // Синхронное сохранение
      ChatCacheService().saveChatInputState(
        widget.chatId,
        text: _textController.text,
        elements: _textController.elements,
        replyingToMessage: _replyingToMessage != null
            ? {
                'id': _replyingToMessage!.id,
                'sender': _replyingToMessage!.senderId,
                'text': _replyingToMessage!.text,
                'time': _replyingToMessage!.time,
                'type': 'USER',
                'cid': _replyingToMessage!.cid,
                'attaches': _replyingToMessage!.attaches,
              }
            : null,
      );

      final draftData = {
        'text': _textController.text,
        'elements': _textController.elements,
        'replyingToMessage': _replyingToMessage != null
            ? {
                'id': _replyingToMessage!.id,
                'sender': _replyingToMessage!.senderId,
                'text': _replyingToMessage!.text,
                'time': _replyingToMessage!.time,
                'type': 'USER',
                'cid': _replyingToMessage!.cid,
                'attaches': _replyingToMessage!.attaches,
              }
            : null,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      // Вызываем callback через microtask чтобы UI успел обновиться
      Future.microtask(() {
        widget.onDraftChanged?.call(widget.chatId, draftData);
      });
      print('✅ Черновик сохранён в dispose()');
    } else {
      print('🗑️ Очищаем черновик в dispose()');
      // Очищаем черновик если текст пустой
      ChatCacheService().saveChatInputState(
        widget.chatId,
        text: '',
        elements: [],
        replyingToMessage: null,
      );
      // Вызываем callback с null чтобы удалить черновик из UI
      Future.microtask(() {
        widget.onDraftChanged?.call(widget.chatId, null);
      });
      print('✅ Черновик очищен в dispose()');
    }

    _isDisposed = true;
    _apiSubscription?.cancel();
    _readStatusSubscription?.cancel();
    _typingTimer?.cancel();
    _voiceRecordingTimer?.cancel();
    _selectionCheckTimer?.cancel();
    _removeMentionOverlay();
    _textController.removeListener(_onTextControllerChanged);
    _textFocusNode.removeListener(_onTextFocusChanged);
    _textController.dispose();
    _textFocusNode.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _showScrollToBottomNotifier.dispose();
    _pinnedMessageNotifier.dispose();
    _testAnimationTrigger.dispose();
    _recordCancelReturnController.dispose();
    _audioRecorder.dispose();
    _cameraController?.dispose();
    _pendingMessagesDuringLoad.clear();

    if (ApiService.instance.currentActiveChatId == widget.chatId) {
      ApiService.instance.currentActiveChatId = null;
    }

    // Уведомляем FloatingCallManager что мы вышли из чата
    // Используем postFrameCallback чтобы избежать вызова notifyListeners во время dispose
    SchedulerBinding.instance.addPostFrameCallback((_) {
      FloatingCallManager.instance.setInChatScreen(false);
    });

    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _mentionOverlay?.markNeedsBuild();
  }

  // Helper method to show error snackbar
  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 8, right: 8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          print('🔄 PopScope: выход из чата ${widget.chatId}');
          print('📝 Текущий текст: "${_textController.text}"');

          // Сохраняем черновик перед выходом
          _saveInputState();

          // Проверяем секретный текст после выхода
          if (_textController.text.trim() == 'ЯЗНАЮТВОЙТЕЛЕФОН') {
            print('🎬 Обнаружен секретный текст!');
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _checkSecretText();
            });
          }
        }
      },
      child: GestureDetector(
        // Свайп слева направо для возврата назад (работает от любой точки экрана!)
        onHorizontalDragStart: _handleSwipeStart,
        onHorizontalDragUpdate: _handleSwipeUpdate,
        onHorizontalDragEnd: _handleSwipeEnd,
        child: Scaffold(appBar: _buildAppBar(), body: _buildBody()),
      ),
    );
  }

  // Обработчики свайпа для возврата назад
  void _handleSwipeStart(DragStartDetails details) {
    _swipeStartX = details.globalPosition.dx;
    _swipeCurrentX = details.globalPosition.dx;
    _isSwiping = true;
  }

  void _handleSwipeUpdate(DragUpdateDetails details) {
    if (!_isSwiping) return;
    _swipeCurrentX = details.globalPosition.dx;

    // Можно добавить визуальную обратную связь здесь
    // Например, setState для анимации свайпа
  }

  void _handleSwipeEnd(DragEndDetails details) {
    if (!_isSwiping) return;

    final swipeDistance = _swipeCurrentX - _swipeStartX;
    final screenWidth = MediaQuery.of(context).size.width;

    // Если свайп больше 30% ширины экрана ИЛИ скорость достаточная - возвращаемся
    final threshold = screenWidth * 0.3;
    final velocity = details.velocity.pixelsPerSecond.dx;

    if (swipeDistance > threshold || velocity > 500) {
      print('👈 Свайп назад: distance=$swipeDistance, velocity=$velocity');
      Navigator.of(context).pop();
    }

    _isSwiping = false;
    _swipeStartX = 0.0;
    _swipeCurrentX = 0.0;
  }

  // Проверка секретного текста и показ видео
  void _checkSecretText() {
    if (!mounted) return;

    // Мгновенный переход без анимации
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const YAZNAYTVOYTELEFON(videoPath: 'ЯЗНАЮТВОЙТЕЛЕФОН.mp4'),
        transitionDuration: Duration.zero, // Без анимации
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  // Placeholder methods that will be implemented in part files
  // These methods are implemented in chat_screen_logic.dart via extension

  void _startSelectionCheck() {
    // Implemented in logic file
  }

  void _stopSelectionCheck() {
    // Implemented in logic file
  }

  void _saveInputState() {
    // Implemented in logic file
  }

  List<Map<String, dynamic>> _buildAllPhotos() {
    final result = <Map<String, dynamic>>[];
    for (final msg in _messages) {
      for (final attach in msg.attaches) {
        final type = (attach['_type'] ?? attach['type']) as String?;
        if (type == 'PHOTO' || type == 'IMAGE') {
          result.add({...attach, '_messageId': msg.id});
        }
      }
    }
    return result;
  }

  // Методы _initializeChat, _loadEncryptionConfig, _loadMore
  // реализованы в chat_screen_logic.dart как part of этого файла
}

/// Диалог для исходящего звонка с опцией DATA_CHANNEL
class _OutgoingCallDialog extends StatefulWidget {
  final String contactName;

  const _OutgoingCallDialog({required this.contactName});

  @override
  State<_OutgoingCallDialog> createState() => _OutgoingCallDialogState();
}

class _OutgoingCallDialogState extends State<_OutgoingCallDialog> {
  bool _enableDataChannel = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Звонок: ${widget.contactName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CheckboxListTile(
            value: _enableDataChannel,
            onChanged: (value) =>
                setState(() => _enableDataChannel = value ?? false),
            title: const Text('Enable DATA_CHANNEL'),
            subtitle: const Text('Для temporary chat и других функций'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_enableDataChannel),
          icon: const Icon(Icons.call),
          label: const Text('Позвонить'),
        ),
      ],
    );
  }
}

class _WebAppScreen extends StatefulWidget {
  final String url;
  final String title;

  const _WebAppScreen({required this.url, required this.title});

  @override
  State<_WebAppScreen> createState() => _WebAppScreenState();
}

class _WebAppScreenState extends State<_WebAppScreen> {
  InAppWebViewController? _webViewController;
  bool _isLoading = true;

  bool get _supportsWebView =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (!_supportsWebView) {
      // На Linux/Windows открываем в браузере и закрываем экран
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final uri = Uri.tryParse(widget.url);
        if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_supportsWebView) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _webViewController?.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(widget.url),
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
            ),
            onWebViewCreated: (controller) {
              _webViewController = controller;
            },
            onLoadStart: (controller, url) {
              setState(() => _isLoading = true);
            },
            onLoadStop: (controller, url) {
              setState(() => _isLoading = false);
            },
          ),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

