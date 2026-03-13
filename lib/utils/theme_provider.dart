import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/theme.dart';

/// Провайдер для управления темами приложения
class ThemeProvider with ChangeNotifier {
  // State
  CustomThemePreset _activeTheme = CustomThemePreset.createDefault();
  List<CustomThemePreset> _savedThemes = [];

  // Debounce timers
  final Map<String, Timer> _saveTimers = {};

  // Additional settings not in preset
  bool _showSeconds = false;
  Color? _myBubbleColorLight;
  Color? _theirBubbleColorLight;
  Color? _myBubbleColorDark;
  Color? _theirBubbleColorDark;
  final Map<int, String> _chatSpecificWallpapers = {};

  // Debug settings
  bool _debugShowPerformanceOverlay = false;
  bool _debugShowChatsRefreshPanel = false;
  bool _debugShowMessageCount = false;
  bool _debugReadOnEnter = true;
  bool _debugReadOnAction = true;

  // Feature flags
  bool _blockBypass = false;
  bool _highQualityPhotos = true;
  ChatPreviewMode _chatPreviewMode = ChatPreviewMode.twoLine;
  bool _optimization = false;
  bool _showFpsOverlay = false;
  int _maxFrameRate = 60;
  bool _chatCompactMode = false;

  // Cache
  CustomThemePreset? _savedThemeBeforeOptimization;
  AppTheme _lastNonSystemTheme = AppTheme.dark;

  // Komet features
  bool _kometAutoCompleteEnabled = false;
  bool _specialMessagesEnabled = true;
  bool _unlimitedPinnedChats = false;

  // Getters - Theme
  AppTheme get appTheme => _activeTheme.appTheme;
  AppTheme get lastNonSystemTheme => _lastNonSystemTheme;
  Color get accentColor => _activeTheme.accentColor;

  ThemeMode get themeMode => switch (_activeTheme.appTheme) {
    AppTheme.system => ThemeMode.system,
    AppTheme.light => ThemeMode.light,
    AppTheme.dark || AppTheme.black => ThemeMode.dark,
  };

  // Getters - Wallpaper
  bool get useCustomChatWallpaper => _activeTheme.useCustomChatWallpaper;
  ChatWallpaperType get chatWallpaperType => _activeTheme.chatWallpaperType;
  Color get chatWallpaperColor1 => _activeTheme.chatWallpaperColor1;
  Color get chatWallpaperColor2 => _activeTheme.chatWallpaperColor2;
  String? get chatWallpaperImagePath => _activeTheme.chatWallpaperImagePath;
  String? get chatWallpaperVideoPath => _activeTheme.chatWallpaperVideoPath;
  bool get chatWallpaperBlur => _activeTheme.chatWallpaperBlur;
  double get chatWallpaperBlurSigma => _activeTheme.chatWallpaperBlurSigma;
  double get chatWallpaperImageBlur => _activeTheme.chatWallpaperImageBlur;

  // Getters - Glass panels
  bool get useGlassPanels =>
      _optimization ? false : _activeTheme.useGlassPanels;
  double get topBarBlur => _activeTheme.topBarBlur;
  double get topBarOpacity => _activeTheme.topBarOpacity;
  double get bottomBarBlur => _activeTheme.bottomBarBlur;
  double get bottomBarOpacity => _activeTheme.bottomBarOpacity;

  // Getters - Dialog settings
  double get messageMenuOpacity => _activeTheme.messageMenuOpacity;
  double get messageMenuBlur => _activeTheme.messageMenuBlur;
  double get profileDialogBlur => _activeTheme.profileDialogBlur;
  double get profileDialogOpacity => _activeTheme.profileDialogOpacity;

  // Getters - UI
  UIMode get uiMode => _activeTheme.uiMode;
  bool get showSeconds => _showSeconds;
  bool get showDeletedMessages => _activeTheme.showDeletedMessages;
  bool get viewRedactHistory => _activeTheme.viewRedactHistory;
  double get messageBubbleOpacity => _activeTheme.messageBubbleOpacity;
  String get messageStyle => _activeTheme.messageStyle;
  double get messageBackgroundBlur => _activeTheme.messageBackgroundBlur;
  double get messageTextOpacity => _activeTheme.messageTextOpacity;
  double get messageShadowIntensity => _activeTheme.messageShadowIntensity;
  double get messageBorderRadius => _activeTheme.messageBorderRadius;

  // Getters - Message
  double get messageFontSize => _activeTheme.messageFontSize;
  bool get sendOnEnter => _activeTheme.sendOnEnter;
  MessageBubbleType get messageBubbleType => _activeTheme.messageBubbleType;
  Color? get myBubbleColorLight => _myBubbleColorLight;
  Color? get theirBubbleColorLight => _theirBubbleColorLight;
  Color? get myBubbleColorDark => _myBubbleColorDark;
  Color? get theirBubbleColorDark => _theirBubbleColorDark;

  Color? get myBubbleColor => switch (appTheme) {
    AppTheme.light => _myBubbleColorLight,
    AppTheme.dark || AppTheme.black => _myBubbleColorDark,
    _ => null,
  };

  Color? get theirBubbleColor => switch (appTheme) {
    AppTheme.light => _theirBubbleColorLight,
    AppTheme.dark || AppTheme.black => _theirBubbleColorDark,
    _ => null,
  };

  // Getters - Debug
  bool get debugShowBottomBar =>
      uiMode == UIMode.both || uiMode == UIMode.panelOnly;
  bool get debugShowBurgerMenu =>
      uiMode == UIMode.both || uiMode == UIMode.burgerOnly;
  bool get debugShowPerformanceOverlay => _debugShowPerformanceOverlay;
  bool get debugShowChatsRefreshPanel => _debugShowChatsRefreshPanel;
  bool get debugShowMessageCount => _debugShowMessageCount;
  bool get debugReadOnEnter => _debugReadOnEnter;
  bool get debugReadOnAction => _debugReadOnAction;

  // Getters - Transitions (optimization aware)
  TransitionOption get chatTransition =>
      (_optimization || _activeTheme.ultraOptimizeChats)
      ? TransitionOption.systemDefault
      : _activeTheme.chatTransition;
  TransitionOption get tabTransition =>
      (_optimization || _activeTheme.ultraOptimizeChats)
      ? TransitionOption.systemDefault
      : _activeTheme.tabTransition;
  TransitionOption get messageTransition =>
      (_optimization || _activeTheme.ultraOptimizeChats)
      ? TransitionOption.systemDefault
      : _activeTheme.messageTransition;
  TransitionOption get extraTransition =>
      (_optimization || _activeTheme.ultraOptimizeChats)
      ? TransitionOption.systemDefault
      : _activeTheme.extraTransition;
  double get messageSlideDistance => _activeTheme.messageSlideDistance;
  double get extraAnimationStrength => _activeTheme.extraAnimationStrength;
  bool get animatePhotoMessages =>
      (_optimization || _activeTheme.ultraOptimizeChats)
      ? false
      : _activeTheme.animatePhotoMessages;

  // Getters - Optimization
  bool get optimizeChats => _activeTheme.optimizeChats;
  bool get ultraOptimizeChats => _activeTheme.ultraOptimizeChats;
  bool get useDesktopLayout => _activeTheme.useDesktopLayout;
  bool get useAutoReplyColor => _activeTheme.useAutoReplyColor;
  Color? get customReplyColor => _activeTheme.customReplyColor;
  bool get optimization => _optimization;

  // Getters - Gradients
  bool get useGradientForChatsList => _activeTheme.useGradientForChatsList;
  ChatsListBackgroundType get chatsListBackgroundType =>
      _activeTheme.chatsListBackgroundType;
  String? get chatsListImagePath => _activeTheme.chatsListImagePath;
  bool get useGradientForDrawer => _activeTheme.useGradientForDrawer;
  DrawerBackgroundType get drawerBackgroundType =>
      _activeTheme.drawerBackgroundType;
  String? get drawerImagePath => _activeTheme.drawerImagePath;
  bool get useGradientForAddAccountButton =>
      _activeTheme.useGradientForAddAccountButton;
  bool get useGradientForAppBar => _activeTheme.useGradientForAppBar;
  AppBarBackgroundType get appBarBackgroundType =>
      _activeTheme.appBarBackgroundType;
  String? get appBarImagePath => _activeTheme.appBarImagePath;
  bool get useGradientForFolderTabs => _activeTheme.useGradientForFolderTabs;
  FolderTabsBackgroundType get folderTabsBackgroundType =>
      _activeTheme.folderTabsBackgroundType;
  String? get folderTabsImagePath => _activeTheme.folderTabsImagePath;
  Color get chatsListGradientColor1 => _activeTheme.chatsListGradientColor1;
  Color get chatsListGradientColor2 => _activeTheme.chatsListGradientColor2;
  Color get drawerGradientColor1 => _activeTheme.drawerGradientColor1;
  Color get drawerGradientColor2 => _activeTheme.drawerGradientColor2;
  Color get addAccountButtonGradientColor1 =>
      _activeTheme.addAccountButtonGradientColor1;
  Color get addAccountButtonGradientColor2 =>
      _activeTheme.addAccountButtonGradientColor2;
  Color get appBarGradientColor1 => _activeTheme.appBarGradientColor1;
  Color get appBarGradientColor2 => _activeTheme.appBarGradientColor2;
  Color get folderTabsGradientColor1 => _activeTheme.folderTabsGradientColor1;
  Color get folderTabsGradientColor2 => _activeTheme.folderTabsGradientColor2;

  // Getters - Misc
  bool get highQualityPhotos => _highQualityPhotos;
  bool get blockBypass => _blockBypass;
  ChatPreviewMode get chatPreviewMode => _chatPreviewMode;
  bool get showFpsOverlay => _showFpsOverlay;
  int get maxFrameRate => _maxFrameRate;
  List<CustomThemePreset> get savedThemes => _savedThemes;
  CustomThemePreset get activeTheme => _activeTheme;
  bool get materialYouEnabled => _activeTheme.appTheme == AppTheme.system;
  bool get chatCompactMode => _chatCompactMode;
  bool get kometAutoCompleteEnabled => _kometAutoCompleteEnabled;
  bool get specialMessagesEnabled => _specialMessagesEnabled;
  bool get unlimitedPinnedChats => _unlimitedPinnedChats;

  ThemeProvider() {
    loadSettings();
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Load themes
    final themesJson = prefs.getStringList('saved_themes') ?? [];
    _savedThemes = themesJson
        .map((jsonString) {
          try {
            return CustomThemePreset.fromJson(jsonDecode(jsonString));
          } catch (e) {
            return null;
          }
        })
        .whereType<CustomThemePreset>()
        .toList();

    if (_savedThemes.isEmpty) {
      _savedThemes.add(CustomThemePreset.createDefault());
    }

    final activeId =
        prefs.getString('active_theme_id') ?? _savedThemes.first.id;
    _activeTheme = _savedThemes.firstWhere(
      (t) => t.id == activeId,
      orElse: () => _savedThemes.first,
    );

    // Default to system theme if needed
    if (_savedThemes.length == 1 &&
        _activeTheme.id == 'default' &&
        _activeTheme.appTheme != AppTheme.system) {
      _activeTheme = _activeTheme.copyWith(appTheme: AppTheme.system);
      await _saveActiveTheme();
    }

    // Load last non-system theme
    final storedLastNonSystemIndex =
        prefs.getInt('last_non_system_theme') ?? AppTheme.dark.index;
    _lastNonSystemTheme = _getValidTheme(
      storedLastNonSystemIndex,
      AppTheme.dark,
    );
    if (_lastNonSystemTheme == AppTheme.system) {
      _lastNonSystemTheme = AppTheme.dark;
    }

    if (_activeTheme.appTheme != AppTheme.system) {
      _lastNonSystemTheme = _activeTheme.appTheme;
      await prefs.setInt('last_non_system_theme', _lastNonSystemTheme.index);
    }

    // Initialize bubble colors
    _initializeBubbleColors(prefs);

    // Load debug settings
    _debugShowPerformanceOverlay = prefs.getBool('debug_perf_overlay') ?? false;
    _debugShowChatsRefreshPanel =
        prefs.getBool('debug_show_chats_refresh_panel') ?? false;
    _debugShowMessageCount = prefs.getBool('debug_show_message_count') ?? false;
    _debugReadOnEnter = prefs.getBool('debug_read_on_enter') ?? true;
    _debugReadOnAction = prefs.getBool('debug_read_on_action') ?? true;

    // Load feature flags
    _highQualityPhotos = prefs.getBool('high_quality_photos') ?? true;
    _blockBypass = prefs.getBool('block_bypass') ?? false;
    _chatPreviewMode = _getValidChatPreviewMode(
      prefs.getInt('chat_preview_mode'),
    );
    _optimization = prefs.getBool('optimization') ?? false;
    _showFpsOverlay = prefs.getBool('show_fps_overlay') ?? false;
    _maxFrameRate = prefs.getInt('max_frame_rate') ?? 60;
    _showSeconds = prefs.getBool('show_seconds') ?? false;
    _chatCompactMode = prefs.getBool('chat_compact_mode') ?? false;
    _kometAutoCompleteEnabled =
        prefs.getBool('komet_auto_complete_enabled') ?? false;
    _specialMessagesEnabled = prefs.getBool('special_messages_enabled') ?? true;
    _unlimitedPinnedChats = prefs.getBool('unlimited_pinned_chats') ?? false;

    await loadChatSpecificWallpapers();
    notifyListeners();
  }

  void _initializeBubbleColors(SharedPreferences prefs) {
    if (_activeTheme.myBubbleColorLight == null ||
        _activeTheme.theirBubbleColorLight == null ||
        _activeTheme.myBubbleColorDark == null ||
        _activeTheme.theirBubbleColorDark == null) {
      _updateBubbleColorsFromAccent(_activeTheme.accentColor);
      _activeTheme = _activeTheme.copyWith(
        myBubbleColorLight: _myBubbleColorLight,
        theirBubbleColorLight: _theirBubbleColorLight,
        myBubbleColorDark: _myBubbleColorDark,
        theirBubbleColorDark: _theirBubbleColorDark,
      );
      _saveActiveTheme();
    } else {
      _myBubbleColorLight = _activeTheme.myBubbleColorLight;
      _theirBubbleColorLight = _activeTheme.theirBubbleColorLight;
      _myBubbleColorDark = _activeTheme.myBubbleColorDark;
      _theirBubbleColorDark = _activeTheme.theirBubbleColorDark;
    }
  }

  AppTheme _getValidTheme(int index, AppTheme fallback) {
    if (index >= 0 && index < AppTheme.values.length) {
      return AppTheme.values[index];
    }
    return fallback;
  }

  ChatPreviewMode _getValidChatPreviewMode(int? index) {
    if (index != null && index >= 0 && index < ChatPreviewMode.values.length) {
      return ChatPreviewMode.values[index];
    }
    return ChatPreviewMode.twoLine;
  }

  Future<void> _saveThemeListToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final themesJson = _savedThemes.map((t) => jsonEncode(t.toJson())).toList();
    await prefs.setStringList('saved_themes', themesJson);
  }

  Future<void> _saveActiveTheme() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_theme_id', _activeTheme.id);
    final index = _savedThemes.indexWhere((t) => t.id == _activeTheme.id);
    if (index != -1) {
      _savedThemes[index] = _activeTheme;
    } else {
      // Если темы нет в списке - добавляем её
      _savedThemes.add(_activeTheme);
    }
    await _saveThemeListToPrefs();
  }

  void _debouncedSave(String key, void Function() saveAction) {
    _saveTimers[key]?.cancel();
    _saveTimers[key] = Timer(const Duration(milliseconds: 500), saveAction);
  }

  // ==================== THEME MANAGEMENT ====================

  void toggleTheme() {
    final newTheme = switch (_activeTheme.appTheme) {
      AppTheme.light => AppTheme.dark,
      AppTheme.dark => AppTheme.light,
      AppTheme.black => AppTheme.light,
      AppTheme.system =>
        _lastNonSystemTheme == AppTheme.light ? AppTheme.dark : AppTheme.light,
    };
    setTheme(newTheme);
  }

  void setTheme(AppTheme theme) {
    if (theme == _activeTheme.appTheme) return;

    if (theme != AppTheme.system) {
      _lastNonSystemTheme = theme;
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt('last_non_system_theme', theme.index);
      });
    }

    _activeTheme = _activeTheme.copyWith(appTheme: theme);
    _saveActiveTheme();
    notifyListeners();
  }

  void setAccentColor(Color color) {
    if (color == _activeTheme.accentColor) return;

    _activeTheme = _activeTheme.copyWith(accentColor: color);
    _updateBubbleColorsFromAccent(color);
    _activeTheme = _activeTheme.copyWith(
      myBubbleColorLight: _myBubbleColorLight,
      theirBubbleColorLight: _theirBubbleColorLight,
      myBubbleColorDark: _myBubbleColorDark,
      theirBubbleColorDark: _theirBubbleColorDark,
    );
    _saveActiveTheme();
    notifyListeners();
  }

  void setMaterialYouEnabled(bool enabled) {
    setTheme(enabled ? AppTheme.system : _lastNonSystemTheme);
  }

  void _updateBubbleColorsFromAccent(Color accent) {
    final hsl = HSLColor.fromColor(accent);
    _myBubbleColorLight = hsl.withLightness(0.92).toColor();
    _theirBubbleColorLight = const Color(0xFFFFFFFF);
    _myBubbleColorDark = hsl.withLightness(0.25).withSaturation(0.6).toColor();
    _theirBubbleColorDark = const Color(0xFF2D2D2D);
  }

  // ==================== PRESET MANAGEMENT ====================

  Future<void> saveCurrentThemeAs(String name) async {
    await saveCurrentAsPreset(name);
  }

  Future<void> saveCurrentAsPreset(String name) async {
    final newPreset = _activeTheme.copyWith(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
    );
    _savedThemes.add(newPreset);
    _activeTheme = newPreset;
    await _saveActiveTheme();
    notifyListeners();
  }

  Future<void> loadPreset(String presetId) async {
    await applyTheme(presetId);
  }

  Future<void> applyTheme(String presetId) async {
    final preset = _savedThemes.firstWhere(
      (t) => t.id == presetId,
      orElse: () => _savedThemes.first,
    );
    _activeTheme = preset;

    _myBubbleColorLight = preset.myBubbleColorLight;
    _theirBubbleColorLight = preset.theirBubbleColorLight;
    _myBubbleColorDark = preset.myBubbleColorDark;
    _theirBubbleColorDark = preset.theirBubbleColorDark;

    await _saveActiveTheme();
    notifyListeners();
  }

  Future<void> deleteTheme(String presetId) async {
    await deletePreset(presetId);
  }

  Future<void> deletePreset(String presetId) async {
    if (_savedThemes.length <= 1) return;
    _savedThemes.removeWhere((t) => t.id == presetId);
    if (_activeTheme.id == presetId) {
      _activeTheme = _savedThemes.first;
    }
    await _saveActiveTheme();
    notifyListeners();
  }

  Future<void> renameTheme(String presetId, String newName) async {
    final index = _savedThemes.indexWhere((t) => t.id == presetId);
    if (index != -1) {
      _savedThemes[index] = _savedThemes[index].copyWith(name: newName);
      if (_activeTheme.id == presetId) {
        _activeTheme = _savedThemes[index];
      }
      await _saveThemeListToPrefs();
      notifyListeners();
    }
  }

  Future<void> importThemeFromJson(String jsonString) async {
    try {
      final json = jsonDecode(jsonString);
      final preset = CustomThemePreset.fromJson(json);
      _savedThemes.add(preset);
      await _saveThemeListToPrefs();
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  // ==================== QUICK TOGGLES ====================

  void toggleOptimization() {
    setOptimization(!_optimization);
  }

  void setOptimization(bool value) {
    _optimization = value;
    if (_optimization) {
      _savedThemeBeforeOptimization = _activeTheme;
    } else if (_savedThemeBeforeOptimization != null) {
      _activeTheme = _savedThemeBeforeOptimization!;
      _savedThemeBeforeOptimization = null;
    }
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('optimization', _optimization);
    });
    notifyListeners();
  }

  void toggleShowSeconds() {
    setShowSeconds(!_showSeconds);
  }

  void setShowSeconds(bool value) {
    _showSeconds = value;
    _debouncedSave('showSeconds', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('show_seconds', _showSeconds);
    });
    notifyListeners();
  }

  void toggleShowDeletedMessages() {
    setShowDeletedMessages(!_activeTheme.showDeletedMessages);
  }

  void setShowDeletedMessages(bool value) {
    _activeTheme = _activeTheme.copyWith(showDeletedMessages: value);
    _saveActiveTheme();
    notifyListeners();
  }

  void toggleViewRedactHistory() {
    setViewRedactHistory(!_activeTheme.viewRedactHistory);
  }

  void setViewRedactHistory(bool value) {
    _activeTheme = _activeTheme.copyWith(viewRedactHistory: value);
    _saveActiveTheme();
    notifyListeners();
  }

  void toggleUseGlassPanels() {
    setUseGlassPanels(!_activeTheme.useGlassPanels);
  }

  void setUseGlassPanels(bool value) {
    _activeTheme = _activeTheme.copyWith(useGlassPanels: value);
    _debouncedSave('useGlassPanels', _saveActiveTheme);
    notifyListeners();
  }

  void toggleSendOnEnter() {
    setSendOnEnter(!_activeTheme.sendOnEnter);
  }

  void setSendOnEnter(bool value) {
    _activeTheme = _activeTheme.copyWith(sendOnEnter: value);
    _saveActiveTheme();
    notifyListeners();
  }

  // ==================== DEBUG SETTINGS ====================

  void toggleDebugPerformanceOverlay() {
    setDebugShowPerformanceOverlay(!_debugShowPerformanceOverlay);
  }

  void setDebugShowPerformanceOverlay(bool value) {
    _debugShowPerformanceOverlay = value;
    SharedPreferences.getInstance().then(
      (p) => p.setBool('debug_perf_overlay', _debugShowPerformanceOverlay),
    );
    notifyListeners();
  }

  void toggleDebugChatsRefreshPanel() {
    setDebugShowChatsRefreshPanel(!_debugShowChatsRefreshPanel);
  }

  void setDebugShowChatsRefreshPanel(bool value) {
    _debugShowChatsRefreshPanel = value;
    SharedPreferences.getInstance().then(
      (p) => p.setBool(
        'debug_show_chats_refresh_panel',
        _debugShowChatsRefreshPanel,
      ),
    );
    notifyListeners();
  }

  void toggleDebugShowMessageCount() {
    setDebugShowMessageCount(!_debugShowMessageCount);
  }

  void setDebugShowMessageCount(bool value) {
    _debugShowMessageCount = value;
    SharedPreferences.getInstance().then(
      (p) => p.setBool('debug_show_message_count', _debugShowMessageCount),
    );
    notifyListeners();
  }

  void toggleDebugReadOnEnter() {
    setDebugReadOnEnter(!_debugReadOnEnter);
  }

  void setDebugReadOnEnter(bool value) {
    _debugReadOnEnter = value;
    SharedPreferences.getInstance().then(
      (p) => p.setBool('debug_read_on_enter', _debugReadOnEnter),
    );
    notifyListeners();
  }

  void toggleDebugReadOnAction() {
    setDebugReadOnAction(!_debugReadOnAction);
  }

  void setDebugReadOnAction(bool value) {
    _debugReadOnAction = value;
    SharedPreferences.getInstance().then(
      (p) => p.setBool('debug_read_on_action', _debugReadOnAction),
    );
    notifyListeners();
  }

  // ==================== FEATURE FLAGS ====================

  void toggleHighQualityPhotos() {
    setHighQualityPhotos(!_highQualityPhotos);
  }

  void setHighQualityPhotos(bool value) {
    _highQualityPhotos = value;
    SharedPreferences.getInstance().then(
      (p) => p.setBool('high_quality_photos', _highQualityPhotos),
    );
    notifyListeners();
  }

  void toggleBlockBypass() {
    setBlockBypass(!_blockBypass);
  }

  void setBlockBypass(bool value) {
    _blockBypass = value;
    SharedPreferences.getInstance().then(
      (p) => p.setBool('block_bypass', _blockBypass),
    );
    notifyListeners();
  }

  void toggleFpsOverlay() {
    setShowFpsOverlay(!_showFpsOverlay);
  }

  void setShowFpsOverlay(bool value) {
    _showFpsOverlay = value;
    SharedPreferences.getInstance().then(
      (p) => p.setBool('show_fps_overlay', _showFpsOverlay),
    );
    notifyListeners();
  }

  void setMaxFrameRate(int rate) {
    _maxFrameRate = rate.clamp(30, 144);
    SharedPreferences.getInstance().then(
      (p) => p.setInt('max_frame_rate', _maxFrameRate),
    );
    notifyListeners();
  }

  void setChatPreviewMode(ChatPreviewMode mode) {
    _chatPreviewMode = mode;
    SharedPreferences.getInstance().then(
      (p) => p.setInt('chat_preview_mode', mode.index),
    );
    notifyListeners();
  }

  void setChatCompactMode(bool value) {
    _chatCompactMode = value;
    SharedPreferences.getInstance().then(
      (p) => p.setBool('chat_compact_mode', value),
    );
    notifyListeners();
  }

  void setKometAutoCompleteEnabled(bool value) {
    _kometAutoCompleteEnabled = value;
    _debouncedSave('komet_auto_complete_enabled', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('komet_auto_complete_enabled', value);
    });
    notifyListeners();
  }

  void setSpecialMessagesEnabled(bool value) {
    _specialMessagesEnabled = value;
    _debouncedSave('special_messages_enabled', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('special_messages_enabled', value);
    });
    notifyListeners();
  }

  void setUnlimitedPinnedChats(bool value) {
    _unlimitedPinnedChats = value;
    _debouncedSave('unlimited_pinned_chats', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('unlimited_pinned_chats', value);
    });
    notifyListeners();
  }

  // ==================== BUBBLE COLORS ====================

  void setMyBubbleColorLight(Color? color) {
    _myBubbleColorLight = color;
    _activeTheme = _activeTheme.copyWith(myBubbleColorLight: color);
    _saveActiveTheme();
    notifyListeners();
  }

  void setMyBubbleColorDark(Color? color) {
    _myBubbleColorDark = color;
    _activeTheme = _activeTheme.copyWith(myBubbleColorDark: color);
    _saveActiveTheme();
    notifyListeners();
  }

  void setTheirBubbleColorLight(Color? color) {
    _theirBubbleColorLight = color;
    _activeTheme = _activeTheme.copyWith(theirBubbleColorLight: color);
    _saveActiveTheme();
    notifyListeners();
  }

  void setTheirBubbleColorDark(Color? color) {
    _theirBubbleColorDark = color;
    _activeTheme = _activeTheme.copyWith(theirBubbleColorDark: color);
    _saveActiveTheme();
    notifyListeners();
  }

  // ==================== WALLPAPER SETTINGS ====================

  void setUseCustomChatWallpaper(bool value) {
    _activeTheme = _activeTheme.copyWith(useCustomChatWallpaper: value);
    _saveActiveTheme();
    notifyListeners();
  }

  void setChatWallpaperType(ChatWallpaperType type) {
    _activeTheme = _activeTheme.copyWith(chatWallpaperType: type);
    _saveActiveTheme();
    notifyListeners();
  }

  void setChatWallpaperColor1(Color color) {
    _activeTheme = _activeTheme.copyWith(chatWallpaperColor1: color);
    _saveActiveTheme();
    notifyListeners();
  }

  void setChatWallpaperColor2(Color color) {
    _activeTheme = _activeTheme.copyWith(chatWallpaperColor2: color);
    _saveActiveTheme();
    notifyListeners();
  }

  void setChatWallpaperImagePath(String? path) {
    _activeTheme = _activeTheme.copyWith(chatWallpaperImagePath: path);
    _saveActiveTheme();
    notifyListeners();
  }

  void setChatWallpaperVideoPath(String? path) {
    _activeTheme = _activeTheme.copyWith(chatWallpaperVideoPath: path);
    _saveActiveTheme();
    notifyListeners();
  }

  void setChatWallpaperImageBlur(double value) {
    _activeTheme = _activeTheme.copyWith(chatWallpaperImageBlur: value);
    _saveActiveTheme();
    notifyListeners();
  }

  // ==================== MESSAGE SETTINGS ====================

  void setMessageTextOpacity(double value) {
    _activeTheme = _activeTheme.copyWith(messageTextOpacity: value);
    _saveActiveTheme();
    notifyListeners();
  }

  void setMessageShadowIntensity(double value) {
    _activeTheme = _activeTheme.copyWith(messageShadowIntensity: value);
    _saveActiveTheme();
    notifyListeners();
  }

  void setMessageMenuOpacity(double value) {
    _activeTheme = _activeTheme.copyWith(messageMenuOpacity: value);
    _saveActiveTheme();
    notifyListeners();
  }

  void setMessageMenuBlur(double value) {
    _activeTheme = _activeTheme.copyWith(messageMenuBlur: value);
    _saveActiveTheme();
    notifyListeners();
  }

  void setMessageBubbleOpacity(double value) {
    _activeTheme = _activeTheme.copyWith(messageBubbleOpacity: value);
    _saveActiveTheme();
    notifyListeners();
  }

  void setMessageBorderRadius(double value) {
    _activeTheme = _activeTheme.copyWith(messageBorderRadius: value);
    _saveActiveTheme();
    notifyListeners();
  }

  void setMessageBubbleType(MessageBubbleType type) {
    _activeTheme = _activeTheme.copyWith(messageBubbleType: type);
    _saveActiveTheme();
    notifyListeners();
  }

  void setUseAutoReplyColor(bool value) {
    _activeTheme = _activeTheme.copyWith(useAutoReplyColor: value);
    _saveActiveTheme();
    notifyListeners();
  }

  void setCustomReplyColor(Color? color) {
    _activeTheme = _activeTheme.copyWith(customReplyColor: color);
    _saveActiveTheme();
    notifyListeners();
  }

  // ==================== PROFILE DIALOG SETTINGS ====================

  void setProfileDialogOpacity(double value) {
    _activeTheme = _activeTheme.copyWith(profileDialogOpacity: value);
    _saveActiveTheme();
    notifyListeners();
  }

  void setProfileDialogBlur(double value) {
    _activeTheme = _activeTheme.copyWith(profileDialogBlur: value);
    _saveActiveTheme();
    notifyListeners();
  }

  // ==================== GLASS PANELS SETTINGS ====================

  void setTopBarOpacity(double value) {
    _activeTheme = _activeTheme.copyWith(topBarOpacity: value);
    _saveActiveTheme();
    notifyListeners();
  }

  void setTopBarBlur(double value) {
    _activeTheme = _activeTheme.copyWith(topBarBlur: value);
    _saveActiveTheme();
    notifyListeners();
  }

  void setBottomBarOpacity(double value) {
    _activeTheme = _activeTheme.copyWith(bottomBarOpacity: value);
    _saveActiveTheme();
    notifyListeners();
  }

  void setBottomBarBlur(double value) {
    _activeTheme = _activeTheme.copyWith(bottomBarBlur: value);
    _saveActiveTheme();
    notifyListeners();
  }

  // ==================== CHATS LIST SETTINGS ====================

  void setUseGradientForChatsList(bool value) {
    _activeTheme = _activeTheme.copyWith(useGradientForChatsList: value);
    _saveActiveTheme();
    notifyListeners();
  }

  void setChatsListBackgroundType(ChatsListBackgroundType type) {
    _activeTheme = _activeTheme.copyWith(chatsListBackgroundType: type);
    _saveActiveTheme();
    notifyListeners();
  }

  void setChatsListGradientColor1(Color color) {
    _activeTheme = _activeTheme.copyWith(chatsListGradientColor1: color);
    _saveActiveTheme();
    notifyListeners();
  }

  void setChatsListGradientColor2(Color color) {
    _activeTheme = _activeTheme.copyWith(chatsListGradientColor2: color);
    _saveActiveTheme();
    notifyListeners();
  }

  void setChatsListImagePath(String? path) {
    _activeTheme = _activeTheme.copyWith(chatsListImagePath: path);
    _saveActiveTheme();
    notifyListeners();
  }

  // ==================== DRAWER SETTINGS ====================

  void setUseGradientForDrawer(bool value) {
    _activeTheme = _activeTheme.copyWith(useGradientForDrawer: value);
    _saveActiveTheme();
    notifyListeners();
  }

  void setDrawerBackgroundType(DrawerBackgroundType type) {
    _activeTheme = _activeTheme.copyWith(drawerBackgroundType: type);
    _saveActiveTheme();
    notifyListeners();
  }

  void setDrawerGradientColor1(Color color) {
    _activeTheme = _activeTheme.copyWith(drawerGradientColor1: color);
    _saveActiveTheme();
    notifyListeners();
  }

  void setDrawerGradientColor2(Color color) {
    _activeTheme = _activeTheme.copyWith(drawerGradientColor2: color);
    _saveActiveTheme();
    notifyListeners();
  }

  void setDrawerImagePath(String? path) {
    _activeTheme = _activeTheme.copyWith(drawerImagePath: path);
    _saveActiveTheme();
    notifyListeners();
  }

  // ==================== ADD ACCOUNT BUTTON SETTINGS ====================

  void setUseGradientForAddAccountButton(bool value) {
    _activeTheme = _activeTheme.copyWith(useGradientForAddAccountButton: value);
    _saveActiveTheme();
    notifyListeners();
  }

  void setAddAccountButtonGradientColor1(Color color) {
    _activeTheme = _activeTheme.copyWith(addAccountButtonGradientColor1: color);
    _saveActiveTheme();
    notifyListeners();
  }

  void setAddAccountButtonGradientColor2(Color color) {
    _activeTheme = _activeTheme.copyWith(addAccountButtonGradientColor2: color);
    _saveActiveTheme();
    notifyListeners();
  }

  // ==================== APP BAR SETTINGS ====================

  void setUseGradientForAppBar(bool value) {
    _activeTheme = _activeTheme.copyWith(useGradientForAppBar: value);
    _saveActiveTheme();
    notifyListeners();
  }

  void setAppBarBackgroundType(AppBarBackgroundType type) {
    _activeTheme = _activeTheme.copyWith(appBarBackgroundType: type);
    _saveActiveTheme();
    notifyListeners();
  }

  void setAppBarGradientColor1(Color color) {
    _activeTheme = _activeTheme.copyWith(appBarGradientColor1: color);
    _saveActiveTheme();
    notifyListeners();
  }

  void setAppBarGradientColor2(Color color) {
    _activeTheme = _activeTheme.copyWith(appBarGradientColor2: color);
    _saveActiveTheme();
    notifyListeners();
  }

  void setAppBarImagePath(String? path) {
    _activeTheme = _activeTheme.copyWith(appBarImagePath: path);
    _saveActiveTheme();
    notifyListeners();
  }

  // ==================== FOLDER TABS SETTINGS ====================

  void setUseGradientForFolderTabs(bool value) {
    _activeTheme = _activeTheme.copyWith(useGradientForFolderTabs: value);
    _saveActiveTheme();
    notifyListeners();
  }

  void setFolderTabsBackgroundType(FolderTabsBackgroundType type) {
    _activeTheme = _activeTheme.copyWith(folderTabsBackgroundType: type);
    _saveActiveTheme();
    notifyListeners();
  }

  void setFolderTabsGradientColor1(Color color) {
    _activeTheme = _activeTheme.copyWith(folderTabsGradientColor1: color);
    _saveActiveTheme();
    notifyListeners();
  }

  void setFolderTabsGradientColor2(Color color) {
    _activeTheme = _activeTheme.copyWith(folderTabsGradientColor2: color);
    _saveActiveTheme();
    notifyListeners();
  }

  void setFolderTabsImagePath(String? path) {
    _activeTheme = _activeTheme.copyWith(folderTabsImagePath: path);
    _saveActiveTheme();
    notifyListeners();
  }

  // ==================== TRANSITION SETTINGS ====================

  void setMessageTransition(TransitionOption option) {
    _activeTheme = _activeTheme.copyWith(messageTransition: option);
    _saveActiveTheme();
    notifyListeners();
  }

  void setAnimatePhotoMessages(bool value) {
    _activeTheme = _activeTheme.copyWith(animatePhotoMessages: value);
    _saveActiveTheme();
    notifyListeners();
  }

  void setMessageSlideDistance(double value) {
    _activeTheme = _activeTheme.copyWith(messageSlideDistance: value);
    _saveActiveTheme();
    notifyListeners();
  }

  void setChatTransition(TransitionOption option) {
    _activeTheme = _activeTheme.copyWith(chatTransition: option);
    _saveActiveTheme();
    notifyListeners();
  }

  void setExtraTransition(TransitionOption option) {
    _activeTheme = _activeTheme.copyWith(extraTransition: option);
    _saveActiveTheme();
    notifyListeners();
  }

  void setExtraAnimationStrength(double value) {
    _activeTheme = _activeTheme.copyWith(extraAnimationStrength: value);
    _saveActiveTheme();
    notifyListeners();
  }

  void setTabTransition(TransitionOption option) {
    _activeTheme = _activeTheme.copyWith(tabTransition: option);
    _saveActiveTheme();
    notifyListeners();
  }

  void resetAnimationsToDefault() {
    _activeTheme = _activeTheme.copyWith(
      chatTransition: TransitionOption.systemDefault,
      tabTransition: TransitionOption.systemDefault,
      messageTransition: TransitionOption.systemDefault,
      extraTransition: TransitionOption.systemDefault,
      messageSlideDistance: 96.0,
      extraAnimationStrength: 32.0,
      animatePhotoMessages: false,
    );
    _saveActiveTheme();
    notifyListeners();
  }

  // ==================== DESKTOP LAYOUT ====================

  void setUseDesktopLayout(bool value) {
    _activeTheme = _activeTheme.copyWith(useDesktopLayout: value);
    _saveActiveTheme();
    notifyListeners();
  }

  // ==================== CHAT-SPECIFIC WALLPAPERS ====================

  Future<void> setChatSpecificWallpaper(int chatId, String? path) async {
    await setChatWallpaper(chatId, path);
  }

  Future<void> loadChatSpecificWallpapers() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('chat_specific_wallpapers');
    if (data != null) {
      final decoded = jsonDecode(data) as Map<String, dynamic>;
      _chatSpecificWallpapers.clear();
      decoded.forEach((key, value) {
        _chatSpecificWallpapers[int.tryParse(key) ?? 0] = value as String;
      });
    }
  }

  String? getChatWallpaper(int chatId) => _chatSpecificWallpapers[chatId];

  Future<void> setChatWallpaper(int chatId, String? path) async {
    if (path == null) {
      _chatSpecificWallpapers.remove(chatId);
    } else {
      _chatSpecificWallpapers[chatId] = path;
    }
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _chatSpecificWallpapers.map((k, v) => MapEntry(k.toString(), v)),
    );
    await prefs.setString('chat_specific_wallpapers', encoded);
    notifyListeners();
  }

  @override
  void dispose() {
    for (final timer in _saveTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }
}
