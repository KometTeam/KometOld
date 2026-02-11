import 'package:flutter/material.dart';
import 'theme_enums.dart';

/// Пресет темы с полными настройками кастомизации
class CustomThemePreset {
  final String id;
  final String name;
  final AppTheme appTheme;
  final Color accentColor;

  // Chat wallpaper
  final bool useCustomChatWallpaper;
  final ChatWallpaperType chatWallpaperType;
  final Color chatWallpaperColor1;
  final Color chatWallpaperColor2;
  final String? chatWallpaperImagePath;
  final String? chatWallpaperVideoPath;
  final bool chatWallpaperBlur;
  final double chatWallpaperBlurSigma;
  final double chatWallpaperImageBlur;

  // Glass panels
  final bool useGlassPanels;
  final double topBarBlur;
  final double topBarOpacity;
  final double bottomBarBlur;
  final double bottomBarOpacity;

  // Dialog settings
  final double messageMenuOpacity;
  final double messageMenuBlur;
  final double profileDialogBlur;
  final double profileDialogOpacity;

  // UI settings
  final UIMode uiMode;
  final bool showSeconds;
  final bool showDeletedMessages;
  final bool viewRedactHistory;
  final double messageBubbleOpacity;
  final String messageStyle;
  final double messageBackgroundBlur;
  final double messageTextOpacity;
  final double messageShadowIntensity;
  final double messageBorderRadius;

  // Message settings
  final double messageFontSize;
  final Color? myBubbleColorLight;
  final Color? theirBubbleColorLight;
  final Color? myBubbleColorDark;
  final Color? theirBubbleColorDark;
  final MessageBubbleType messageBubbleType;
  final bool sendOnEnter;

  // Transitions
  final TransitionOption chatTransition;
  final TransitionOption tabTransition;
  final TransitionOption messageTransition;
  final TransitionOption extraTransition;
  final double messageSlideDistance;
  final double extraAnimationStrength;
  final bool animatePhotoMessages;
  final bool optimizeChats;
  final bool ultraOptimizeChats;
  final bool useDesktopLayout;
  final bool useAutoReplyColor;
  final Color? customReplyColor;

  // Gradient backgrounds
  final bool useGradientForChatsList;
  final ChatsListBackgroundType chatsListBackgroundType;
  final String? chatsListImagePath;
  final bool useGradientForDrawer;
  final DrawerBackgroundType drawerBackgroundType;
  final String? drawerImagePath;
  final bool useGradientForAddAccountButton;
  final bool useGradientForAppBar;
  final AppBarBackgroundType appBarBackgroundType;
  final String? appBarImagePath;
  final bool useGradientForFolderTabs;
  final FolderTabsBackgroundType folderTabsBackgroundType;
  final String? folderTabsImagePath;
  final Color chatsListGradientColor1;
  final Color chatsListGradientColor2;
  final Color drawerGradientColor1;
  final Color drawerGradientColor2;
  final Color addAccountButtonGradientColor1;
  final Color addAccountButtonGradientColor2;
  final Color appBarGradientColor1;
  final Color appBarGradientColor2;
  final Color folderTabsGradientColor1;
  final Color folderTabsGradientColor2;

  const CustomThemePreset({
    required this.id,
    required this.name,
    this.appTheme = AppTheme.dark,
    this.accentColor = Colors.blue,
    this.useCustomChatWallpaper = false,
    this.chatWallpaperType = ChatWallpaperType.komet,
    this.chatWallpaperColor1 = const Color(0xFF101010),
    this.chatWallpaperColor2 = const Color(0xFF202020),
    this.chatWallpaperImagePath,
    this.chatWallpaperVideoPath,
    this.chatWallpaperBlur = false,
    this.chatWallpaperBlurSigma = 12.0,
    this.chatWallpaperImageBlur = 0.0,
    this.useGlassPanels = true,
    this.topBarBlur = 10.0,
    this.topBarOpacity = 0.6,
    this.bottomBarBlur = 10.0,
    this.bottomBarOpacity = 0.7,
    this.messageMenuOpacity = 0.95,
    this.messageMenuBlur = 4.0,
    this.profileDialogBlur = 12.0,
    this.profileDialogOpacity = 0.26,
    this.uiMode = UIMode.both,
    this.showSeconds = false,
    this.showDeletedMessages = false,
    this.viewRedactHistory = false,
    this.messageBubbleOpacity = 0.12,
    this.messageStyle = 'glass',
    this.messageBackgroundBlur = 0.0,
    this.messageTextOpacity = 1.0,
    this.messageShadowIntensity = 0.1,
    this.messageBorderRadius = 20.0,
    this.messageFontSize = 16.0,
    this.myBubbleColorLight,
    this.theirBubbleColorLight,
    this.myBubbleColorDark,
    this.theirBubbleColorDark,
    this.messageBubbleType = MessageBubbleType.solid,
    this.sendOnEnter = false,
    this.chatTransition = TransitionOption.systemDefault,
    this.tabTransition = TransitionOption.systemDefault,
    this.messageTransition = TransitionOption.systemDefault,
    this.extraTransition = TransitionOption.systemDefault,
    this.messageSlideDistance = 96.0,
    this.extraAnimationStrength = 32.0,
    this.animatePhotoMessages = false,
    this.optimizeChats = false,
    this.ultraOptimizeChats = false,
    this.useDesktopLayout = true,
    this.useAutoReplyColor = true,
    this.customReplyColor,
    this.useGradientForChatsList = false,
    this.chatsListBackgroundType = ChatsListBackgroundType.none,
    this.chatsListImagePath,
    this.useGradientForDrawer = false,
    this.drawerBackgroundType = DrawerBackgroundType.none,
    this.drawerImagePath,
    this.useGradientForAddAccountButton = false,
    this.useGradientForAppBar = false,
    this.appBarBackgroundType = AppBarBackgroundType.none,
    this.appBarImagePath,
    this.useGradientForFolderTabs = false,
    this.folderTabsBackgroundType = FolderTabsBackgroundType.none,
    this.folderTabsImagePath,
    this.chatsListGradientColor1 = const Color(0xFF1E1E1E),
    this.chatsListGradientColor2 = const Color(0xFF2D2D2D),
    this.drawerGradientColor1 = const Color(0xFF1E1E1E),
    this.drawerGradientColor2 = const Color(0xFF2D2D2D),
    this.addAccountButtonGradientColor1 = const Color(0xFF1E1E1E),
    this.addAccountButtonGradientColor2 = const Color(0xFF2D2D2D),
    this.appBarGradientColor1 = const Color(0xFF1E1E1E),
    this.appBarGradientColor2 = const Color(0xFF2D2D2D),
    this.folderTabsGradientColor1 = const Color(0xFF1E1E1E),
    this.folderTabsGradientColor2 = const Color(0xFF2D2D2D),
  });

  factory CustomThemePreset.createDefault() {
    return const CustomThemePreset(
      id: 'default',
      name: 'По умолчанию',
      appTheme: AppTheme.system,
    );
  }

  CustomThemePreset copyWith({
    String? id,
    String? name,
    AppTheme? appTheme,
    Color? accentColor,
    bool? useCustomChatWallpaper,
    ChatWallpaperType? chatWallpaperType,
    Color? chatWallpaperColor1,
    Color? chatWallpaperColor2,
    String? chatWallpaperImagePath,
    String? chatWallpaperVideoPath,
    bool? chatWallpaperBlur,
    double? chatWallpaperBlurSigma,
    double? chatWallpaperImageBlur,
    bool? useGlassPanels,
    double? topBarBlur,
    double? topBarOpacity,
    double? bottomBarBlur,
    double? bottomBarOpacity,
    double? messageMenuOpacity,
    double? messageMenuBlur,
    double? profileDialogBlur,
    double? profileDialogOpacity,
    UIMode? uiMode,
    bool? showSeconds,
    bool? showDeletedMessages,
    bool? viewRedactHistory,
    double? messageBubbleOpacity,
    String? messageStyle,
    double? messageBackgroundBlur,
    double? messageTextOpacity,
    double? messageShadowIntensity,
    double? messageBorderRadius,
    double? messageFontSize,
    Color? myBubbleColorLight,
    Color? theirBubbleColorLight,
    Color? myBubbleColorDark,
    Color? theirBubbleColorDark,
    MessageBubbleType? messageBubbleType,
    bool? sendOnEnter,
    TransitionOption? chatTransition,
    TransitionOption? tabTransition,
    TransitionOption? messageTransition,
    TransitionOption? extraTransition,
    double? messageSlideDistance,
    double? extraAnimationStrength,
    bool? animatePhotoMessages,
    bool? optimizeChats,
    bool? ultraOptimizeChats,
    bool? useDesktopLayout,
    bool? useAutoReplyColor,
    Color? customReplyColor,
    bool? useGradientForChatsList,
    ChatsListBackgroundType? chatsListBackgroundType,
    String? chatsListImagePath,
    bool? useGradientForDrawer,
    DrawerBackgroundType? drawerBackgroundType,
    String? drawerImagePath,
    bool? useGradientForAddAccountButton,
    bool? useGradientForAppBar,
    AppBarBackgroundType? appBarBackgroundType,
    String? appBarImagePath,
    bool? useGradientForFolderTabs,
    FolderTabsBackgroundType? folderTabsBackgroundType,
    String? folderTabsImagePath,
    Color? chatsListGradientColor1,
    Color? chatsListGradientColor2,
    Color? drawerGradientColor1,
    Color? drawerGradientColor2,
    Color? addAccountButtonGradientColor1,
    Color? addAccountButtonGradientColor2,
    Color? appBarGradientColor1,
    Color? appBarGradientColor2,
    Color? folderTabsGradientColor1,
    Color? folderTabsGradientColor2,
  }) {
    return CustomThemePreset(
      id: id ?? this.id,
      name: name ?? this.name,
      appTheme: appTheme ?? this.appTheme,
      accentColor: accentColor ?? this.accentColor,
      useCustomChatWallpaper: useCustomChatWallpaper ?? this.useCustomChatWallpaper,
      chatWallpaperType: chatWallpaperType ?? this.chatWallpaperType,
      chatWallpaperColor1: chatWallpaperColor1 ?? this.chatWallpaperColor1,
      chatWallpaperColor2: chatWallpaperColor2 ?? this.chatWallpaperColor2,
      chatWallpaperImagePath: chatWallpaperImagePath ?? this.chatWallpaperImagePath,
      chatWallpaperVideoPath: chatWallpaperVideoPath ?? this.chatWallpaperVideoPath,
      chatWallpaperBlur: chatWallpaperBlur ?? this.chatWallpaperBlur,
      chatWallpaperBlurSigma: chatWallpaperBlurSigma ?? this.chatWallpaperBlurSigma,
      chatWallpaperImageBlur: chatWallpaperImageBlur ?? this.chatWallpaperImageBlur,
      useGlassPanels: useGlassPanels ?? this.useGlassPanels,
      topBarBlur: topBarBlur ?? this.topBarBlur,
      topBarOpacity: topBarOpacity ?? this.topBarOpacity,
      bottomBarBlur: bottomBarBlur ?? this.bottomBarBlur,
      bottomBarOpacity: bottomBarOpacity ?? this.bottomBarOpacity,
      messageMenuOpacity: messageMenuOpacity ?? this.messageMenuOpacity,
      messageMenuBlur: messageMenuBlur ?? this.messageMenuBlur,
      profileDialogBlur: profileDialogBlur ?? this.profileDialogBlur,
      profileDialogOpacity: profileDialogOpacity ?? this.profileDialogOpacity,
      uiMode: uiMode ?? this.uiMode,
      showSeconds: showSeconds ?? this.showSeconds,
      showDeletedMessages: showDeletedMessages ?? this.showDeletedMessages,
      viewRedactHistory: viewRedactHistory ?? this.viewRedactHistory,
      messageBubbleOpacity: messageBubbleOpacity ?? this.messageBubbleOpacity,
      messageStyle: messageStyle ?? this.messageStyle,
      messageBackgroundBlur: messageBackgroundBlur ?? this.messageBackgroundBlur,
      messageTextOpacity: messageTextOpacity ?? this.messageTextOpacity,
      messageShadowIntensity: messageShadowIntensity ?? this.messageShadowIntensity,
      messageBorderRadius: messageBorderRadius ?? this.messageBorderRadius,
      messageFontSize: messageFontSize ?? this.messageFontSize,
      myBubbleColorLight: myBubbleColorLight ?? this.myBubbleColorLight,
      theirBubbleColorLight: theirBubbleColorLight ?? this.theirBubbleColorLight,
      myBubbleColorDark: myBubbleColorDark ?? this.myBubbleColorDark,
      theirBubbleColorDark: theirBubbleColorDark ?? this.theirBubbleColorDark,
      messageBubbleType: messageBubbleType ?? this.messageBubbleType,
      sendOnEnter: sendOnEnter ?? this.sendOnEnter,
      chatTransition: chatTransition ?? this.chatTransition,
      tabTransition: tabTransition ?? this.tabTransition,
      messageTransition: messageTransition ?? this.messageTransition,
      extraTransition: extraTransition ?? this.extraTransition,
      messageSlideDistance: messageSlideDistance ?? this.messageSlideDistance,
      extraAnimationStrength: extraAnimationStrength ?? this.extraAnimationStrength,
      animatePhotoMessages: animatePhotoMessages ?? this.animatePhotoMessages,
      optimizeChats: optimizeChats ?? this.optimizeChats,
      ultraOptimizeChats: ultraOptimizeChats ?? this.ultraOptimizeChats,
      useDesktopLayout: useDesktopLayout ?? this.useDesktopLayout,
      useAutoReplyColor: useAutoReplyColor ?? this.useAutoReplyColor,
      customReplyColor: customReplyColor ?? this.customReplyColor,
      useGradientForChatsList: useGradientForChatsList ?? this.useGradientForChatsList,
      chatsListBackgroundType: chatsListBackgroundType ?? this.chatsListBackgroundType,
      chatsListImagePath: chatsListImagePath ?? this.chatsListImagePath,
      useGradientForDrawer: useGradientForDrawer ?? this.useGradientForDrawer,
      drawerBackgroundType: drawerBackgroundType ?? this.drawerBackgroundType,
      drawerImagePath: drawerImagePath ?? this.drawerImagePath,
      useGradientForAddAccountButton: useGradientForAddAccountButton ?? this.useGradientForAddAccountButton,
      useGradientForAppBar: useGradientForAppBar ?? this.useGradientForAppBar,
      appBarBackgroundType: appBarBackgroundType ?? this.appBarBackgroundType,
      appBarImagePath: appBarImagePath ?? this.appBarImagePath,
      useGradientForFolderTabs: useGradientForFolderTabs ?? this.useGradientForFolderTabs,
      folderTabsBackgroundType: folderTabsBackgroundType ?? this.folderTabsBackgroundType,
      folderTabsImagePath: folderTabsImagePath ?? this.folderTabsImagePath,
      chatsListGradientColor1: chatsListGradientColor1 ?? this.chatsListGradientColor1,
      chatsListGradientColor2: chatsListGradientColor2 ?? this.chatsListGradientColor2,
      drawerGradientColor1: drawerGradientColor1 ?? this.drawerGradientColor1,
      drawerGradientColor2: drawerGradientColor2 ?? this.drawerGradientColor2,
      addAccountButtonGradientColor1: addAccountButtonGradientColor1 ?? this.addAccountButtonGradientColor1,
      addAccountButtonGradientColor2: addAccountButtonGradientColor2 ?? this.addAccountButtonGradientColor2,
      appBarGradientColor1: appBarGradientColor1 ?? this.appBarGradientColor1,
      appBarGradientColor2: appBarGradientColor2 ?? this.appBarGradientColor2,
      folderTabsGradientColor1: folderTabsGradientColor1 ?? this.folderTabsGradientColor1,
      folderTabsGradientColor2: folderTabsGradientColor2 ?? this.folderTabsGradientColor2,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'appTheme': appTheme.index,
    'accentColor': accentColor.toARGB32(),
    'useCustomChatWallpaper': useCustomChatWallpaper,
    'chatWallpaperType': chatWallpaperType.index,
    'chatWallpaperColor1': chatWallpaperColor1.toARGB32(),
    'chatWallpaperColor2': chatWallpaperColor2.toARGB32(),
    'chatWallpaperImagePath': chatWallpaperImagePath,
    'chatWallpaperVideoPath': chatWallpaperVideoPath,
    'chatWallpaperBlur': chatWallpaperBlur,
    'chatWallpaperBlurSigma': chatWallpaperBlurSigma,
    'chatWallpaperImageBlur': chatWallpaperImageBlur,
    'useGlassPanels': useGlassPanels,
    'topBarBlur': topBarBlur,
    'topBarOpacity': topBarOpacity,
    'bottomBarBlur': bottomBarBlur,
    'bottomBarOpacity': bottomBarOpacity,
    'messageMenuOpacity': messageMenuOpacity,
    'messageMenuBlur': messageMenuBlur,
    'profileDialogBlur': profileDialogBlur,
    'profileDialogOpacity': profileDialogOpacity,
    'uiMode': uiMode.index,
    'showSeconds': showSeconds,
    'showDeletedMessages': showDeletedMessages,
    'viewRedactHistory': viewRedactHistory,
    'messageBubbleOpacity': messageBubbleOpacity,
    'messageStyle': messageStyle,
    'messageBackgroundBlur': messageBackgroundBlur,
    'messageTextOpacity': messageTextOpacity,
    'messageShadowIntensity': messageShadowIntensity,
    'messageBorderRadius': messageBorderRadius,
    'messageFontSize': messageFontSize,
    'myBubbleColorLight': myBubbleColorLight?.toARGB32(),
    'theirBubbleColorLight': theirBubbleColorLight?.toARGB32(),
    'myBubbleColorDark': myBubbleColorDark?.toARGB32(),
    'theirBubbleColorDark': theirBubbleColorDark?.toARGB32(),
    'messageBubbleType': messageBubbleType.index,
    'sendOnEnter': sendOnEnter,
    'chatTransition': chatTransition.index,
    'tabTransition': tabTransition.index,
    'messageTransition': messageTransition.index,
    'extraTransition': extraTransition.index,
    'messageSlideDistance': messageSlideDistance,
    'extraAnimationStrength': extraAnimationStrength,
    'animatePhotoMessages': animatePhotoMessages,
    'optimizeChats': optimizeChats,
    'ultraOptimizeChats': ultraOptimizeChats,
    'useDesktopLayout': useDesktopLayout,
    'useAutoReplyColor': useAutoReplyColor,
    'customReplyColor': customReplyColor?.toARGB32(),
    'useGradientForChatsList': useGradientForChatsList,
    'chatsListBackgroundType': chatsListBackgroundType.index,
    'chatsListImagePath': chatsListImagePath,
    'useGradientForDrawer': useGradientForDrawer,
    'drawerBackgroundType': drawerBackgroundType.index,
    'drawerImagePath': drawerImagePath,
    'useGradientForAddAccountButton': useGradientForAddAccountButton,
    'useGradientForAppBar': useGradientForAppBar,
    'appBarBackgroundType': appBarBackgroundType.index,
    'appBarImagePath': appBarImagePath,
    'useGradientForFolderTabs': useGradientForFolderTabs,
    'folderTabsBackgroundType': folderTabsBackgroundType.index,
    'folderTabsImagePath': folderTabsImagePath,
    'chatsListGradientColor1': chatsListGradientColor1.toARGB32(),
    'chatsListGradientColor2': chatsListGradientColor2.toARGB32(),
    'drawerGradientColor1': drawerGradientColor1.toARGB32(),
    'drawerGradientColor2': drawerGradientColor2.toARGB32(),
    'addAccountButtonGradientColor1': addAccountButtonGradientColor1.toARGB32(),
    'addAccountButtonGradientColor2': addAccountButtonGradientColor2.toARGB32(),
    'appBarGradientColor1': appBarGradientColor1.toARGB32(),
    'appBarGradientColor2': appBarGradientColor2.toARGB32(),
    'folderTabsGradientColor1': folderTabsGradientColor1.toARGB32(),
    'folderTabsGradientColor2': folderTabsGradientColor2.toARGB32(),
  };

  factory CustomThemePreset.fromJson(Map<String, dynamic> json) {
    int appThemeIndex = json['appTheme'] as int? ?? AppTheme.system.index;
    AppTheme parsedTheme = (appThemeIndex >= 0 && appThemeIndex < AppTheme.values.length)
        ? AppTheme.values[appThemeIndex]
        : AppTheme.system;
    
    return CustomThemePreset(
      id: json['id'] as String,
      name: json['name'] as String,
      appTheme: parsedTheme,
      accentColor: Color(json['accentColor'] as int? ?? Colors.blue.toARGB32()),
      useCustomChatWallpaper: json['useCustomChatWallpaper'] as bool? ?? false,
      chatWallpaperType: _parseChatWallpaperType(json['chatWallpaperType']),
      chatWallpaperColor1: _parseColor(json['chatWallpaperColor1'], const Color(0xFF101010)),
      chatWallpaperColor2: _parseColor(json['chatWallpaperColor2'], const Color(0xFF202020)),
      chatWallpaperImagePath: json['chatWallpaperImagePath'] as String?,
      chatWallpaperVideoPath: json['chatWallpaperVideoPath'] as String?,
      chatWallpaperBlur: json['chatWallpaperBlur'] as bool? ?? false,
      chatWallpaperBlurSigma: (json['chatWallpaperBlurSigma'] as double? ?? 12.0).clamp(0.0, 20.0),
      chatWallpaperImageBlur: (json['chatWallpaperImageBlur'] as double? ?? 0.0).clamp(0.0, 10.0),
      useGlassPanels: json['useGlassPanels'] as bool? ?? true,
      topBarBlur: json['topBarBlur'] as double? ?? 10.0,
      topBarOpacity: json['topBarOpacity'] as double? ?? 0.6,
      bottomBarBlur: json['bottomBarBlur'] as double? ?? 10.0,
      bottomBarOpacity: json['bottomBarOpacity'] as double? ?? 0.7,
      messageMenuOpacity: json['messageMenuOpacity'] as double? ?? 0.95,
      messageMenuBlur: json['messageMenuBlur'] as double? ?? 4.0,
      profileDialogBlur: (json['profileDialogBlur'] as double? ?? 12.0).clamp(0.0, 30.0),
      profileDialogOpacity: (json['profileDialogOpacity'] as double? ?? 0.26).clamp(0.0, 1.0),
      uiMode: _parseUIMode(json['uiMode']),
      showSeconds: json['showSeconds'] as bool? ?? false,
      showDeletedMessages: json['showDeletedMessages'] as bool? ?? false,
      viewRedactHistory: json['viewRedactHistory'] as bool? ?? false,
      messageBubbleOpacity: (json['messageBubbleOpacity'] as double? ?? 0.12).clamp(0.0, 1.0),
      messageStyle: json['messageStyle'] as String? ?? 'glass',
      messageBackgroundBlur: (json['messageBackgroundBlur'] as double? ?? 0.0).clamp(0.0, 10.0),
      messageTextOpacity: (json['messageTextOpacity'] as double? ?? 1.0).clamp(0.1, 1.0),
      messageShadowIntensity: (json['messageShadowIntensity'] as double? ?? 0.1).clamp(0.0, 0.5),
      messageBorderRadius: (json['messageBorderRadius'] as double? ?? 20.0).clamp(4.0, 50.0),
      messageFontSize: json['messageFontSize'] as double? ?? 16.0,
      myBubbleColorLight: _parseOptionalColor(json['myBubbleColorLight']),
      theirBubbleColorLight: _parseOptionalColor(json['theirBubbleColorLight']),
      myBubbleColorDark: _parseOptionalColor(json['myBubbleColorDark']),
      theirBubbleColorDark: _parseOptionalColor(json['theirBubbleColorDark']),
      messageBubbleType: _parseMessageBubbleType(json['messageBubbleType']),
      sendOnEnter: json['sendOnEnter'] as bool? ?? false,
      chatTransition: _parseTransitionOption(json['chatTransition']),
      tabTransition: _parseTransitionOption(json['tabTransition']),
      messageTransition: _parseTransitionOption(json['messageTransition']),
      extraTransition: _parseTransitionOption(json['extraTransition']),
      messageSlideDistance: (json['messageSlideDistance'] as double? ?? 96.0).clamp(1.0, 200.0),
      extraAnimationStrength: (json['extraAnimationStrength'] as double? ?? 32.0).clamp(1.0, 400.0),
      animatePhotoMessages: json['animatePhotoMessages'] as bool? ?? false,
      optimizeChats: json['optimizeChats'] as bool? ?? false,
      ultraOptimizeChats: json['ultraOptimizeChats'] as bool? ?? false,
      useDesktopLayout: json['useDesktopLayout'] as bool? ?? false,
      useAutoReplyColor: json['useAutoReplyColor'] as bool? ?? true,
      customReplyColor: _parseOptionalColor(json['customReplyColor']),
      useGradientForChatsList: json['useGradientForChatsList'] as bool? ?? false,
      chatsListBackgroundType: _parseChatsListBackgroundType(json['chatsListBackgroundType']),
      chatsListImagePath: json['chatsListImagePath'] as String?,
      useGradientForDrawer: json['useGradientForDrawer'] as bool? ?? false,
      drawerBackgroundType: _parseDrawerBackgroundType(json['drawerBackgroundType']),
      drawerImagePath: json['drawerImagePath'] as String?,
      useGradientForAddAccountButton: json['useGradientForAddAccountButton'] as bool? ?? false,
      useGradientForAppBar: json['useGradientForAppBar'] as bool? ?? false,
      appBarBackgroundType: _parseAppBarBackgroundType(json['appBarBackgroundType']),
      appBarImagePath: json['appBarImagePath'] as String?,
      useGradientForFolderTabs: json['useGradientForFolderTabs'] as bool? ?? false,
      folderTabsBackgroundType: _parseFolderTabsBackgroundType(json['folderTabsBackgroundType']),
      folderTabsImagePath: json['folderTabsImagePath'] as String?,
      chatsListGradientColor1: _parseColor(json['chatsListGradientColor1'], const Color(0xFF1E1E1E)),
      chatsListGradientColor2: _parseColor(json['chatsListGradientColor2'], const Color(0xFF2D2D2D)),
      drawerGradientColor1: _parseColor(json['drawerGradientColor1'], const Color(0xFF1E1E1E)),
      drawerGradientColor2: _parseColor(json['drawerGradientColor2'], const Color(0xFF2D2D2D)),
      addAccountButtonGradientColor1: _parseColor(json['addAccountButtonGradientColor1'], const Color(0xFF1E1E1E)),
      addAccountButtonGradientColor2: _parseColor(json['addAccountButtonGradientColor2'], const Color(0xFF2D2D2D)),
      appBarGradientColor1: _parseColor(json['appBarGradientColor1'], const Color(0xFF1E1E1E)),
      appBarGradientColor2: _parseColor(json['appBarGradientColor2'], const Color(0xFF2D2D2D)),
      folderTabsGradientColor1: _parseColor(json['folderTabsGradientColor1'], const Color(0xFF1E1E1E)),
      folderTabsGradientColor2: _parseColor(json['folderTabsGradientColor2'], const Color(0xFF2D2D2D)),
    );
  }

  // Helper methods for parsing
  static Color _parseColor(dynamic value, Color defaultColor) {
    if (value == null) return defaultColor;
    return Color(value as int);
  }

  static Color? _parseOptionalColor(dynamic value) {
    if (value == null) return null;
    return Color(value as int);
  }

  static ChatWallpaperType _parseChatWallpaperType(dynamic value) {
    final index = value as int? ?? 0;
    if (index >= 0 && index < ChatWallpaperType.values.length) {
      return ChatWallpaperType.values[index];
    }
    return ChatWallpaperType.komet;
  }

  static UIMode _parseUIMode(dynamic value) {
    final index = value as int? ?? 0;
    if (index >= 0 && index < UIMode.values.length) {
      return UIMode.values[index];
    }
    return UIMode.both;
  }

  static MessageBubbleType _parseMessageBubbleType(dynamic value) {
    final index = value as int? ?? 0;
    if (index >= 0 && index < MessageBubbleType.values.length) {
      return MessageBubbleType.values[index];
    }
    return MessageBubbleType.solid;
  }

  static TransitionOption _parseTransitionOption(dynamic value) {
    final index = value as int? ?? 0;
    if (index >= 0 && index < TransitionOption.values.length) {
      return TransitionOption.values[index];
    }
    return TransitionOption.systemDefault;
  }

  static ChatsListBackgroundType _parseChatsListBackgroundType(dynamic value) {
    final index = value as int? ?? 0;
    if (index >= 0 && index < ChatsListBackgroundType.values.length) {
      return ChatsListBackgroundType.values[index];
    }
    return ChatsListBackgroundType.none;
  }

  static DrawerBackgroundType _parseDrawerBackgroundType(dynamic value) {
    final index = value as int? ?? 0;
    if (index >= 0 && index < DrawerBackgroundType.values.length) {
      return DrawerBackgroundType.values[index];
    }
    return DrawerBackgroundType.none;
  }

  static AppBarBackgroundType _parseAppBarBackgroundType(dynamic value) {
    final index = value as int? ?? 0;
    if (index >= 0 && index < AppBarBackgroundType.values.length) {
      return AppBarBackgroundType.values[index];
    }
    return AppBarBackgroundType.none;
  }

  static FolderTabsBackgroundType _parseFolderTabsBackgroundType(dynamic value) {
    final index = value as int? ?? 0;
    if (index >= 0 && index < FolderTabsBackgroundType.values.length) {
      return FolderTabsBackgroundType.values[index];
    }
    return FolderTabsBackgroundType.none;
  }
}
