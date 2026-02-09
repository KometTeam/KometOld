import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../models/message.dart';
import '../../../services/chat_cache_service.dart';

/// Состояние отправки сообщения
enum SendState {
  idle,
  sending,
  sent,
  error,
}

/// Состояние записи голосового сообщения
enum VoiceRecordingState {
  idle,
  recording,
  paused,
  sending,
  error,
}

/// Контроллер для управления вводом сообщений
class ChatInputController extends ChangeNotifier {
  final int chatId;
  
  ChatInputController({required this.chatId}) {
    _loadDraft();
  }

  // Text editing
  final TextEditingController textController = TextEditingController();
  final FocusNode focusNode = FocusNode();
  
  // Reply state
  Message? _replyingToMessage;
  Message? get replyingToMessage => _replyingToMessage;
  
  // Send state
  SendState _sendState = SendState.idle;
  SendState get sendState => _sendState;
  bool get isSending => _sendState == SendState.sending;
  
  // Voice recording
  VoiceRecordingState _voiceState = VoiceRecordingState.idle;
  VoiceRecordingState get voiceState => _voiceState;
  bool get isRecording => _voiceState == VoiceRecordingState.recording;
  
  Duration _recordingDuration = Duration.zero;
  Duration get recordingDuration => _recordingDuration;
  
  Timer? _recordingTimer;
  
  // Mentions
  final List<MentionDraft> _mentions = [];
  List<MentionDraft> get mentions => List.unmodifiable(_mentions);
  
  bool _showMentionDropdown = false;
  bool get showMentionDropdown => _showMentionDropdown;
  
  String _mentionQuery = '';
  String get mentionQuery => _mentionQuery;
  
  // Subscriptions
  bool _isDisposed = false;

  // Getters
  String get text => textController.text;
  bool get hasText => text.trim().isNotEmpty;
  bool get canSend => hasText && !isSending;

  /// Установить сообщение для ответа
  void setReplyTo(Message? message) {
    _replyingToMessage = message;
    focusNode.requestFocus();
    _notifyListenersSafe();
  }
  
  /// Отменить ответ
  void clearReply() {
    _replyingToMessage = null;
    _notifyListenersSafe();
  }
  
  /// Добавить упоминание
  void addMention(int userId, String name, {int? position, int? length}) {
    final from = position ?? textController.selection.start;
    final len = length ?? name.length;
    
    _mentions.add(MentionDraft(
      userId: userId,
      name: name,
      from: from,
      length: len,
    ));
    
    _showMentionDropdown = false;
    _notifyListenersSafe();
  }
  
  /// Показать dropdown с упоминаниями
  void showMentions(String query) {
    _mentionQuery = query;
    _showMentionDropdown = true;
    _notifyListenersSafe();
  }
  
  /// Скрыть dropdown упоминаний
  void hideMentions() {
    _showMentionDropdown = false;
    _notifyListenersSafe();
  }
  
  /// Начать запись голоса
  Future<void> startVoiceRecording() async {
    if (_voiceState != VoiceRecordingState.idle) return;
    
    _voiceState = VoiceRecordingState.recording;
    _recordingDuration = Duration.zero;
    _notifyListenersSafe();
    
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _recordingDuration += const Duration(seconds: 1);
      _notifyListenersSafe();
    });
    
    try {
      // TODO: Инициализация записи
    } catch (e) {
      _voiceState = VoiceRecordingState.error;
      _recordingTimer?.cancel();
      _notifyListenersSafe();
    }
  }
  
  /// Приостановить/возобновить запись
  void togglePauseRecording() {
    if (_voiceState == VoiceRecordingState.recording) {
      _voiceState = VoiceRecordingState.paused;
      _recordingTimer?.cancel();
    } else if (_voiceState == VoiceRecordingState.paused) {
      _voiceState = VoiceRecordingState.recording;
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _recordingDuration += const Duration(seconds: 1);
        _notifyListenersSafe();
      });
    }
    _notifyListenersSafe();
  }
  
  /// Отменить запись
  void cancelVoiceRecording() {
    _recordingTimer?.cancel();
    _voiceState = VoiceRecordingState.idle;
    _recordingDuration = Duration.zero;
    _notifyListenersSafe();
  }
  
  /// Отправить голосовое сообщение
  Future<void> sendVoiceRecording() async {
    if (_voiceState != VoiceRecordingState.recording && 
        _voiceState != VoiceRecordingState.paused) {
      return;
    }
    
    _recordingTimer?.cancel();
    _voiceState = VoiceRecordingState.sending;
    _notifyListenersSafe();
    
    try {
      // TODO: Отправка голосового сообщения
      await Future.delayed(const Duration(seconds: 1));
      
      _voiceState = VoiceRecordingState.idle;
      _recordingDuration = Duration.zero;
    } catch (e) {
      _voiceState = VoiceRecordingState.error;
    } finally {
      _notifyListenersSafe();
    }
  }
  
  /// Отправить текстовое сообщение
  Future<void> sendMessage() async {
    if (!canSend) return;
    
    _sendState = SendState.sending;
    _notifyListenersSafe();
    
    try {
      // TODO: Отправка сообщения через API
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Очистка после отправки
      textController.clear();
      _mentions.clear();
      _replyingToMessage = null;
      _saveDraft();
      
      _sendState = SendState.sent;
    } catch (e) {
      _sendState = SendState.error;
    } finally {
      _notifyListenersSafe();
      
      // Сброс состояния через задержку
      if (_sendState == SendState.sent || _sendState == SendState.error) {
        Future.delayed(const Duration(seconds: 1), () {
          _sendState = SendState.idle;
          _notifyListenersSafe();
        });
      }
    }
  }
  
  /// Сохранить черновик
  Future<void> _saveDraft() async {
    if (textController.text.isNotEmpty) {
      await ChatCacheService().saveChatInputState(
        chatId,
        text: textController.text,
        elements: _mentions.map((m) => m.toJson()).toList(),
        replyingToMessage: _replyingToMessage != null ? {
          'id': _replyingToMessage!.id,
          'text': _replyingToMessage!.text,
        } : null,
      );
    } else {
      await ChatCacheService().clearChatInputState(chatId);
    }
  }
  
  /// Загрузить черновик
  Future<void> _loadDraft() async {
    try {
      final draft = await ChatCacheService().getChatInputState(chatId);
      if (draft != null) {
        final text = draft['text'] as String?;
        if (text != null && text.isNotEmpty) {
          textController.text = text;
        }
      }
    } catch (e) {
      print('⚠️ Ошибка загрузки черновика: $e');
    }
  }
  
  /// Применить шифрование к тексту
  String applyEncryption(String text, String? password) {
    if (password == null || password.isEmpty) return text;
    // TODO: Шифрование
    return text;
  }
  
  void _notifyListenersSafe() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }
  
  @override
  void dispose() {
    _isDisposed = true;
    _recordingTimer?.cancel();
    textController.dispose();
    focusNode.dispose();
    super.dispose();
  }
}

/// Черновик упоминания
class MentionDraft {
  final int userId;
  final String name;
  final int from;
  final int length;
  
  MentionDraft({
    required this.userId,
    required this.name,
    required this.from,
    required this.length,
  });
  
  Map<String, dynamic> toJson() => {
    'entityId': userId,
    'entityName': name,
    'from': from,
    'length': length,
    'type': 'USER_MENTION',
  };
}
