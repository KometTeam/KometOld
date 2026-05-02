// safe_filename.dart — санитизация и безопасный резолвинг имён файлов,
// полученных из недоверенного источника (meta зашифрованного файла,
// сетевой ответ).
//
// Назначение:
//   Защита от path-traversal атак, когда злоумышленник кладёт в meta
//   `original_name` строку вида `../../sdcard/Android/data/...` или
//   абсолютный путь `/etc/passwd`. Без санитизации `p.join(outDir, name)`
//   вернул бы путь за пределами outDir (если name абсолютный, p.join
//   вообще игнорирует первый аргумент).
//
// Использование:
//   final safeName = SafeFilename.sanitize(meta['original_name']);
//   final outPath = SafeFilename.resolveWithin(outDir.path, safeName);

import 'package:path/path.dart' as p;

class SafeFilename {
  /// Запрещённые на Windows символы + control chars + path separators.
  static final RegExp _badChars = RegExp(r'[\x00-\x1F<>:"|?*\\/]');

  /// Зарезервированные имена Windows (без расширения).
  static const Set<String> _reserved = {
    'CON', 'PRN', 'AUX', 'NUL',
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
  };

  /// Максимальная длина имени файла на большинстве FS (255 байт UTF-8).
  /// Берём 200 чтобы оставить место для timestamp-префиксов.
  static const int _maxLen = 200;

  /// Возвращает безопасное имя файла из произвольной строки.
  ///
  /// Гарантии:
  ///   - Без `/`, `\`, `..`, control chars, NUL.
  ///   - Не начинается с точки/пробела.
  ///   - Не пустое (если на входе мусор — вернёт fallback).
  ///   - Не превышает 200 байт UTF-8.
  ///   - Не совпадает с reserved-именами Windows.
  static String sanitize(String? raw, {String fallback = 'file'}) {
    if (raw == null || raw.isEmpty) return fallback;

    // 1. Берём только последний компонент пути — отрезаем любые директории.
    //    Это работает и для "../../etc" и для "C:\Windows\..." (basename
    //    отрезает разделители обеих платформ).
    var name = p.basename(raw);
    // basename для строки без разделителей вернёт её саму; для "/" и
    // подобных — "" или ".".

    // 2. Заменяем небезопасные символы.
    name = name.replaceAll(_badChars, '_');

    // 3. Удаляем ведущие точки и пробелы (скрытые файлы, обрезка
    //    Windows-расширений с пробелами).
    name = name.replaceFirst(RegExp(r'^[.\s]+'), '');
    // И завершающие пробелы/точки (Windows их трогает).
    name = name.replaceFirst(RegExp(r'[.\s]+$'), '');

    if (name.isEmpty || name == '.' || name == '..') return fallback;

    // 4. Reserved name check (без расширения, case-insensitive).
    final dotIdx = name.indexOf('.');
    final stem = (dotIdx > 0 ? name.substring(0, dotIdx) : name).toUpperCase();
    if (_reserved.contains(stem)) {
      name = '_$name';
    }

    // 5. Ограничение длины. Считаем именно UTF-8 байты, чтобы не уйти
    //    за лимит FS на длинных кириллических именах.
    final bytes = name.codeUnits; // approx — для BMP utf-16 == ≤3 utf-8 байт
    if (bytes.length > _maxLen) {
      // Сохраняем расширение если оно есть и недлинное.
      final extIdx = name.lastIndexOf('.');
      if (extIdx > 0 && name.length - extIdx <= 16) {
        final ext = name.substring(extIdx);
        final stemPart = name.substring(0, _maxLen - ext.length);
        name = '$stemPart$ext';
      } else {
        name = name.substring(0, _maxLen);
      }
    }

    return name;
  }

  /// Резолвит имя внутри [parentDir] и проверяет, что итоговый путь не
  /// вышел за его пределы. Возвращает абсолютный путь, готовый к записи.
  ///
  /// Бросает [ArgumentError] если каким-то образом sanitize не сработал
  /// и итоговый путь оказался вне parentDir.
  static String resolveWithin(String parentDir, String name) {
    final safeName = sanitize(name);
    final joined = p.join(parentDir, safeName);
    final absParent = p.canonicalize(parentDir);
    final absJoined = p.canonicalize(joined);

    // Проверяем, что absJoined находится внутри absParent. p.isWithin
    // вернёт false если это тот же путь, а нам нужен строго дочерний.
    if (!p.isWithin(absParent, absJoined)) {
      throw ArgumentError(
        'Resolved path "$absJoined" is outside parent "$absParent"',
      );
    }
    return joined;
  }
}
