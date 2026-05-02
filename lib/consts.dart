export 'app_durations.dart';
export 'app_sizes.dart';
export 'app_urls.dart';
export 'app_colors.dart';

import 'package:flutter/material.dart';

const String appVersion = "0.4.2(119)";
const String appName = "Komet";

/// Windows Toast notifications require a stable AppUserModelID (AUMID)
const String windowsAppUserModelId = "KometTeam.Komet";

/// Stable GUID for toast activation callback on Windows
const String windowsNotificationGuid = "f30f0a4b-1a7f-4f74-8a86-6d241b5a78d0";

/// Лимиты и ограничения приложения
class AppLimits {
  AppLimits._();

  /// Через сколько часов нельзя редактировать сообщение
  static const int messageEditHours = 6969;

  /// Количество сообщений на страницу (стандарт)
  static const int pageSize = 30;

  /// Количество сообщений при оптимизированной загрузке
  static const int optimizedPageSize = 30;

  /// Количество сообщений при ультра-оптимизации
  static const int ultraOptimizedPageSize = 10;

  /// Размер пакета при подгрузке истории
  static const int historyLoadBatch = 30;

  /// Максимальное количество недавних эмодзи
  static const int maxRecentEmoji = 20;

  /// Максимальная длина payload для логирования
  static const int maxLogPayloadLength = 30000;
}

class AppSettings {
  AppSettings._();
  static const bool startFresh = false;
}

/// Значения анимаций
class AppAnimationValues {
  AppAnimationValues._();

  /// Смещение по Y для анимации нового сообщения
  static const double newMessageSlideOffset = 30.0;

  /// Начальная прозрачность подсветки при поиске
  static const double highlightOpacityStart = 0.3;

  /// Конечная прозрачность подсветки при поиске
  static const double highlightOpacityEnd = 0.6;
}

/// Цвета SVG иконок
class AppSvgColors {
  AppSvgColors._();

  static const Color kometSvgColor = Color(0xFFE1BEE7);
}
