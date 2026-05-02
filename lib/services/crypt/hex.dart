// hex.dart — общий hex-кодер/декодер для криптослоя.
//
// Раньше каждый файл держал свою private пару `_hex`/`_unhex`. Это
// порождало мелкие расхождения (regex для валидации, обработка нечётной
// длины, регистр) и риск рассинхрона. Этот модуль — единая точка истины.
//
// Принципы:
//   - encode возвращает строго нижний регистр.
//   - decode принимает оба регистра.
//   - decode бросает FormatException на любых ошибках (нечётная длина,
//     невалидные символы) — а не возвращает null или мусор.

import 'dart:typed_data';

class Hex {
  static const String _digits = '0123456789abcdef';

  /// Кодирует байты в hex (нижний регистр, без разделителей).
  static String encode(Uint8List bytes) {
    final out = StringBuffer();
    for (final b in bytes) {
      out.write(_digits[(b >> 4) & 0xF]);
      out.write(_digits[b & 0xF]);
    }
    return out.toString();
  }

  /// Декодирует hex-строку в байты. Принимает upper/lower case.
  /// Бросает [FormatException] на нечётной длине или невалидных символах.
  static Uint8List decode(String s) {
    if (s.length.isOdd) {
      throw const FormatException('hex-строка нечётной длины');
    }
    final out = Uint8List(s.length ~/ 2);
    for (int i = 0; i < out.length; i++) {
      final hi = _nibble(s.codeUnitAt(i * 2));
      final lo = _nibble(s.codeUnitAt(i * 2 + 1));
      out[i] = (hi << 4) | lo;
    }
    return out;
  }

  static int _nibble(int code) {
    if (code >= 0x30 && code <= 0x39) return code - 0x30; // 0-9
    if (code >= 0x61 && code <= 0x66) return code - 0x61 + 10; // a-f
    if (code >= 0x41 && code <= 0x46) return code - 0x41 + 10; // A-F
    throw FormatException(
      'Невалидный hex-символ: ${String.fromCharCode(code)}',
    );
  }
}
