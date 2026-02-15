import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
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
import 'package:gwid/models/bot_command.dart';
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
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:gwid/widgets/message_bubble/models/message_read_status.dart';

import 'package:gwid/screens/group_settings_screen.dart';
import 'package:gwid/screens/settings/channel_settings_screen.dart';

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
import 'package:platform_info/platform_info.dart';

part 'chat_screen_widgets.dart';
part 'chat_screen_logic.dart';
part 'chat_screen_ui.dart';
part 'chat_screen_voice.dart';

bool get _isMobilePlatform =>
    Platform.instance.operatingSystem.iOS ||
    Platform.instance.operatingSystem.android;

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
  bool _isOpeningChannelSettings = false;
  final List<Message> _messages = [];
  List<ChatItem> _chatItems = [];
  final Set<String> _deletingMessageIds = {};
  final Set<String> _messagesToAnimate = {};

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
  int? _actualMyId;
  int? _oldestLoadedTime;
  int _maxViewedIndex = 0;

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
  OverlayEntry? _sparkleMenuOverlay;
  final GlobalKey _sparkleButtonKey = GlobalKey();
  final LayerLink _sparkleLayerLink = LayerLink();

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
  int get _optPage => _ultraOptimize
      ? AppLimits.historyLoadBatch
      : (_optimize ? 50 : _pageSize);

  @override
  void initState() {
    super.initState();
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

    _sendDragReturnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
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
    _isDisposed = true;
    _apiSubscription?.cancel();
    _typingTimer?.cancel();
    _voiceRecordingTimer?.cancel();
    _selectionCheckTimer?.cancel();
    _textController.removeListener(_onTextControllerChanged);
    _textFocusNode.removeListener(_onTextFocusChanged);
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
  Widget build(BuildContext context) {
    return Scaffold(appBar: _buildAppBar(), body: _buildBody());
  }

  // Helper method to show error snackbar
  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // Helper method to show info snackbar
  void _showInfoSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
            onChanged: (value) => setState(() => _enableDataChannel = value ?? false),
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
