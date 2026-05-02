import 'package:flutter/material.dart';
import 'package:gwid/models/call_response.dart';

/// Менеджер для управления состоянием минимизированного звонка
class FloatingCallManager extends ChangeNotifier {
  static final FloatingCallManager instance = FloatingCallManager._();
  FloatingCallManager._();

  bool _isMinimized = false;
  bool _isInChatScreen = false;
  bool _hasActiveCall = false;
  
  // Call data
  String? _callerName;
  String? _callerAvatarUrl;
  int? _callerId;
  CallResponse? _callResponse;
  DateTime? _callStartTime;
  bool _isVideo = false;
  int? _contactId;
  String? _contactName;
  String? _contactAvatarUrl;
  bool _isOutgoing = true;

  bool get isMinimized => _isMinimized;
  bool get isInChatScreen => _isInChatScreen;
  bool get hasActiveCall => _hasActiveCall;
  
  String? get callerName => _callerName;
  String? get callerAvatarUrl => _callerAvatarUrl;
  int? get callerId => _callerId;
  CallResponse? get callResponse => _callResponse;
  DateTime? get callStartTime => _callStartTime;
  bool get isVideo => _isVideo;

  /// Показывать как панель внизу или как кружок
  bool get shouldShowAsPanel => _isMinimized && !_isInChatScreen;
  bool get shouldShowAsButton => _isMinimized && _isInChatScreen;
  
  // Callback для завершения звонка (вызывается из панели/кнопки)
  VoidCallback? onEndCall;

  /// Начать звонок (установить флаг активного звонка)
  void startCall() {
    _hasActiveCall = true;
    notifyListeners();
  }

  /// Минимизировать звонок
  void minimizeCall({
    required String callerName,
    String? callerAvatarUrl,
    required int callerId,
    required CallResponse callResponse,
    required DateTime callStartTime,
    bool isVideo = false,
  }) {
    _isMinimized = true;
    _hasActiveCall = true;
    _callerName = callerName;
    _callerAvatarUrl = callerAvatarUrl;
    _callerId = callerId;
    _callResponse = callResponse;
    _callStartTime = callStartTime;
    _isVideo = isVideo;
    
    notifyListeners();
  }

  /// Развернуть звонок обратно в полноэкранный режим
  void maximizeCall() {
    _isMinimized = false;
    notifyListeners();
  }

  /// Завершить звонок (очистить данные)
  void endCall() {
    _isMinimized = false;
    _hasActiveCall = false;
    _callerName = null;
    _callerAvatarUrl = null;
    _callerId = null;
    _callResponse = null;
    _callStartTime = null;
    _isVideo = false;
    onEndCall = null;
    
    notifyListeners();
  }

  /// Обновить статус - мы в чате или нет
  void setInChatScreen(bool inChat) {
    if (_isInChatScreen != inChat) {
      _isInChatScreen = inChat;
      notifyListeners();
    }
  }
}
