import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:gwid/utils/theme_provider.dart';
import 'package:gwid/api/api_service.dart';
import 'package:flutter/services.dart';
import 'package:gwid/models/chat.dart';
import 'package:gwid/models/contact.dart';
import 'package:gwid/models/message.dart';
import 'package:gwid/models/bot_command.dart';
import 'package:gwid/widgets/chat_message_bubble.dart';
import 'package:gwid/widgets/complaint_dialog.dart';
import 'package:gwid/widgets/pinned_message_widget.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gwid/services/chat_cache_service.dart';
import 'package:gwid/services/chat_read_settings_service.dart';
import 'package:gwid/services/contact_local_names_service.dart';
import 'package:gwid/services/notification_service.dart';
import 'package:gwid/services/message_queue_service.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:file_picker/file_picker.dart';
import 'package:gwid/screens/group_settings_screen.dart';

import 'package:gwid/screens/contact_selection_screen.dart';
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

part 'chat_screen_widgets.dart';
part 'chat_screen_logic.dart';
part 'chat_screen_ui.dart';
part 'chat_screen_voice.dart';

class ChatDebugSettings {
  static bool showExactDate = false;
  
  static void toggleShowExactDate() {
    showExactDate = !showExactDate;
  }
}

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

  _PhotoPickerResult({required this.paths, this.caption});

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

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  // Core state fields
  bool _isDisposed = false;
  final List<Message> _messages = [];
  List<ChatItem> _chatItems = [];
  final Set<String> _deletingMessageIds = {};
  final Set<String> _messagesToAnimate = {};
  List<Map<String, dynamic>> _cachedAllPhotos = [];
  String? _highlightedMessageId;

  // Loading states
  bool _isLoadingHistory = true;
  Map<String, dynamic>? _emptyChatSticker;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  // Controllers
  final FormattedTextController _textController = FormattedTextController();
  final FocusNode _textFocusNode = FocusNode();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();
  final ValueNotifier<bool> _showScrollToBottomNotifier = ValueNotifier(false);
  final ValueNotifier<Message?> _pinnedMessageNotifier = ValueNotifier(null);
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Chat data
  late Contact _currentContact;
  Message? _pinnedMessage;
  Message? _replyingToMessage;
  final Map<int, Contact> _contactDetailsCache = {};
  final Set<int> _loadingContactIds = {};
  int? _lastPeerReadMessageId;
  String? _lastPeerReadMessageIdStr;
  Map<String, dynamic>? _cachedCurrentGroupChat;

  // API & Connection
  StreamSubscription? _apiSubscription;
  StreamSubscription<String>? _connectionStatusSub;
  String _connectionStatus = 'connecting';
  int? _actualMyId;
  bool _isIdReady = false;
  int? _oldestLoadedTime;
  int _maxViewedIndex = 0;
  int _lastLoadedAtViewedIndex = 0;
  static const int _pageSize = 50;
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
  List<Mention> _mentions = [];

  // Encryption
  bool _isEncryptionPasswordSetForCurrentChat = false;
  ChatEncryptionConfig? _encryptionConfigForCurrentChat;
  bool _sendEncryptedForCurrentChat = true;

  // UI States
  bool _specialMessagesEnabled = true;
  bool _hasTextSelection = false;
  Timer? _selectionCheckTimer;
  bool _showKometColorPicker = false;
  String? _currentKometColorPrefix;
  bool _isSearching = false;
  List<Message> _searchResults = [];
  int _currentResultIndex = -1;

  // Additional UI states
  Message? _editingMessage;
  bool _isSendingMessage = false;
  int? _mentionQueryStart;
  Color? _kometColor;
  bool _showSpecialMessagesPanelState = false;
  final ValueNotifier<bool> _testAnimationTrigger = ValueNotifier(false);

  // Scroll states
  bool _isUserAtBottom = true;
  bool _isScrollingToBottom = false;

  // Reactions
  final Set<String> _sendingReactions = {};
  final Map<int, String> _pendingReactionSeqs = {};

  // Send drag
  static const double _sendDragThreshold = 52.0;
  static const double _sendDragVisualThreshold = 88.0;
  double _sendDragDy = 0.0;
  double _sendDragPullDy = 0.0;
  bool _isSendDragging = false;
  late final AnimationController _sendDragReturnController;

  // Voice recording
  bool _isVoiceRecordingUi = false;
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
  int get _optPage => _ultraOptimize ? 10 : (_optimize ? 50 : _pageSize);

  @override
  void initState() {
    super.initState();
    print('🔘 ChatScreen.initState: chatId=${widget.chatId}');
    _currentContact = widget.contact;
    _pinnedMessage = widget.pinnedMessage;
    _pinnedMessageNotifier.value = widget.pinnedMessage;

    _sendDragReturnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _recordCancelReturnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    print('🔘 initState: scheduling _init() via addPostFrameCallback');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('🔘 PostFrameCallback: вызываем _init()');
      _init();
    });
  }

  // Initialize method referenced in initState
  Future<void> _init() async {
    print('🔘 _init: начало для chatId=${widget.chatId}');
    print('🔘 _init: this.runtimeType = ${this.runtimeType}');
    
    print('🔘 _init: ПРЯМО ПЕРЕД вызовом _initializeChat');
    final stopwatch = Stopwatch()..start();
    try {
      print('🔘 _init: вызываю await _initializeChat()');
      await _initializeChat();
      stopwatch.stop();
      print('🔘 _init: _initializeChat завершился за ${stopwatch.elapsedMilliseconds}ms');
    } catch (e, st) {
      stopwatch.stop();
      print('🔘 _init: ОШИБКА в _initializeChat после ${stopwatch.elapsedMilliseconds}ms: $e');
      print(st);
    }
    
    print('🔘 _init: вызываем _loadEncryptionConfig...');
    _loadEncryptionConfig();
    _loadSpecialMessagesSetting();

    ApiService.instance.currentActiveChatId = widget.chatId;
    NotificationService().clearNotificationMessagesForChat(widget.chatId);

    _textController.addListener(() {
      _handleTextChangedForKometColor();
      _updateTextSelectionState();
      _handleMentionFiltering(_textController.text);
    });

    _textFocusNode.addListener(() {
      if (_textFocusNode.hasFocus) {
        _startSelectionCheck();
      } else {
        _stopSelectionCheck();
        if (!mounted) return;
        setState(() {
          _hasTextSelection = false;
        });
        _saveInputState();

        if (_showMentionDropdown) {
          setState(() {
            _showMentionDropdown = false;
          });
        }
      }
    });

    _itemPositionsListener.itemPositions.addListener(_onScrollUpdate);

    _connectionStatus = ApiService.instance.isOnline &&
            ApiService.instance.isSessionReady &&
            ApiService.instance.isActuallyConnected
        ? 'connected'
        : 'connecting';

    _connectionStatusSub = ApiService.instance.connectionStatus.listen((status) {
      if (!mounted) return;
      setState(() {
        _connectionStatus = status;
      });
    });

    _loadInputState();
  }

  // Handle scroll update
  void _onScrollUpdate() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      final bottomItemPosition = positions.firstWhere(
            (p) => p.index == 0,
        orElse: () => positions.first,
      );

      final isBottomItemVisible = bottomItemPosition.index == 0;
      final isAtBottom =
          isBottomItemVisible && bottomItemPosition.itemLeadingEdge <= 0.25;

      if (_isUserAtBottom != isAtBottom && mounted) {
        setState(() {
          _isUserAtBottom = isAtBottom;
          _showScrollToBottomNotifier.value = !isAtBottom;
        });
      }

      final maxVisibleIndex = positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);
      if (maxVisibleIndex > _maxViewedIndex) {
        _maxViewedIndex = maxVisibleIndex;
      }

      final shouldLoadMore = positions.any((p) => p.index >= _chatItems.length - _loadMoreThreshold);
      if (shouldLoadMore && !_isLoadingMore && _hasMore) {
        _loadMore();
      }
    }
  }

  // Handle API event - implemented in logic file via extension

  @override
  void dispose() {
    _isDisposed = true;
    _apiSubscription?.cancel();
    _connectionStatusSub?.cancel();
    _typingTimer?.cancel();
    _voiceRecordingTimer?.cancel();
    _selectionCheckTimer?.cancel();
    _textController.dispose();
    _textFocusNode.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _showScrollToBottomNotifier.dispose();
    _pinnedMessageNotifier.dispose();
    _testAnimationTrigger.dispose();
    _sendDragReturnController.dispose();
    _recordCancelReturnController.dispose();
    _audioRecorder.dispose();

    ApiService.instance.currentActiveChatId = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('🔘 ChatScreen.build: chatId=${widget.chatId}');
    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  // Copy message method
  Future<void> _copyMessage(Message message) async {
    await Clipboard.setData(ClipboardData(text: message.text ?? ''));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message copied to clipboard')),
      );
    }
  }

  // Helper method to show error snackbar
  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  // Helper method to show info snackbar
  void _showInfoSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // Placeholder methods that will be implemented in part files
  void _handleTextChangedForKometColor() {
    // Implemented in logic file
  }

  void _updateTextSelectionState() {
    // Implemented in logic file
  }

  void _handleMentionFiltering(String text) {
    // Implemented in logic file
  }

  void _startSelectionCheck() {
    // Implemented in logic file
  }

  void _stopSelectionCheck() {
    // Implemented in logic file
  }

  void _saveInputState() {
    // Implemented in logic file
  }

  // Методы _initializeChat, _loadEncryptionConfig, _loadSpecialMessagesSetting, _loadMore
  // реализованы в chat_screen_logic.dart как part of этого файла
}
