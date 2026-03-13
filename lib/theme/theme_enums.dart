/// Перечисления для системы тем

enum AppTheme { system, light, dark, black }

enum ChatWallpaperType { komet, solid, gradient, image, video }

enum FolderTabsBackgroundType { none, gradient, image }

enum DrawerBackgroundType { none, gradient, image }

enum ChatsListBackgroundType { none, gradient, image }

enum AppBarBackgroundType { none, gradient, image }

enum TransitionOption { systemDefault, slide }

enum UIMode { both, burgerOnly, panelOnly }

enum MessageBubbleType { solid }

enum ChatPreviewMode { twoLine, threeLine, noNicknames }

extension MessageBubbleTypeExtension on MessageBubbleType {
  String get displayName {
    switch (this) {
      case MessageBubbleType.solid:
        return 'Цвет';
    }
  }
}

extension TransitionOptionExtension on TransitionOption {
  String get displayName {
    switch (this) {
      case TransitionOption.systemDefault:
        return 'Default';
      case TransitionOption.slide:
        return 'Slide';
    }
  }
}

extension ChatWallpaperTypeExtension on ChatWallpaperType {
  String get displayName {
    switch (this) {
      case ChatWallpaperType.komet:
        return 'Komet';
      case ChatWallpaperType.solid:
        return 'Цвет';
      case ChatWallpaperType.gradient:
        return 'Градиент';
      case ChatWallpaperType.image:
        return 'Фото';
      case ChatWallpaperType.video:
        return 'Видео';
    }
  }
}

extension FolderTabsBackgroundTypeExtension on FolderTabsBackgroundType {
  String get displayName {
    switch (this) {
      case FolderTabsBackgroundType.none:
        return 'Нет';
      case FolderTabsBackgroundType.gradient:
        return 'Градиент';
      case FolderTabsBackgroundType.image:
        return 'Фото';
    }
  }
}

extension DrawerBackgroundTypeExtension on DrawerBackgroundType {
  String get displayName {
    switch (this) {
      case DrawerBackgroundType.none:
        return 'Нет';
      case DrawerBackgroundType.gradient:
        return 'Градиент';
      case DrawerBackgroundType.image:
        return 'Фото';
    }
  }
}

extension ChatsListBackgroundTypeExtension on ChatsListBackgroundType {
  String get displayName {
    switch (this) {
      case ChatsListBackgroundType.none:
        return 'Нет';
      case ChatsListBackgroundType.gradient:
        return 'Градиент';
      case ChatsListBackgroundType.image:
        return 'Фото';
    }
  }
}

extension AppBarBackgroundTypeExtension on AppBarBackgroundType {
  String get displayName {
    switch (this) {
      case AppBarBackgroundType.none:
        return 'Нет';
      case AppBarBackgroundType.gradient:
        return 'Градиент';
      case AppBarBackgroundType.image:
        return 'Фото';
    }
  }
}
