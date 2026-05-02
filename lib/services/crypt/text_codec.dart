// text_codec.dart — обфускация зашифрованного blob под "случайный текст в чате".
//
// Назначение:
//     Заменяет base64-вывод на текст, имитирующий "залип на клавиатуре" —
//     кириллица, цифры, знаки препинания со случайными пробелами. Цель —
//     обойти простые regex-фильтры мессенджеров типа MAX, которые ловят
//     base64 как маркер шифрованного трафика.
//
// Профили по умолчанию (1-в-1 с Python utils/text_codec.py):
//     tiny     —  16 строчных букв (а-р),         4 бит/симв, расширение 2.00x
//     compact  —  32 (строчн+заглав+цифры),       5 бит/симв, расширение 1.60x
//     ru_full  —  64 (полный русский+цифры),      6 бит/симв, расширение 1.33x
//     ru_max   — 128 (всё+пунктуация),            7 бит/симв, расширение 1.14x
//     natural  —  33 чисто строчного русского, ~5.04 бит/симв, расширение 1.59x
//
// Регистрация своего профиля: registerProfile().
//
// ВНИМАНИЕ: это слой ОБФУСКАЦИИ, не криптографии. AES-GCM делает свою
// работу до этого. Здесь только меняем визуальную форму blob.
//
// Ограничение base_n-профилей: blob ≤ 255 байт (в первый байт payload
// записывается длина исходного blob). Для blob больше 255 байт используйте
// bits-профили (tiny / compact / ru_full / ru_max).

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Информация о зарегистрированном профиле обфускации.
class TextCodecProfile {
  final String name;
  final String alphabet;
  final int size;
  final double bitsPerChar;
  final String mode; // "bits" | "base_n"
  final int? bitsPerCharInt; // только для mode == "bits"

  const TextCodecProfile._({
    required this.name,
    required this.alphabet,
    required this.size,
    required this.bitsPerChar,
    required this.mode,
    this.bitsPerCharInt,
  });
}

// =========================================================================
//                   ВСТРОЕННЫЕ АЛФАВИТЫ (1-в-1 с Python)
// =========================================================================

const String _alphTiny = 'абвгдежзиклмнопр';

const String _alphCompact = 'абвгдеёжзийклмнопАБВГДЕЁЖ0123456';

// Python: первые 64 символа склейки трёх строк
const String _alphRuFullSrc =
    'абвгдеёжзийклмнопрстуфхцчшщъыьэюя'
    'АБВГДЕЖЗИЙКЛМНОПРСТУФХ'
    '0123456789';

// Python: первые 128 символов склейки нескольких строк (включая пунктуацию,
// валюты и спецсимволы)
const String _alphRuMaxSrc =
    'абвгдеёжзийклмнопрстуфхцчшщъыьэюя'
    'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ'
    '0123456789'
    ',.!?-:;"\'()[]{}@#\$%&*+='
    '/<>~^|`_§«»№…—–•†‡'
    '₽€£¥©®™°±×÷'
    '✓';

const String _alphNatural = 'абвгдеёжзийклмнопрстуфхцчшщъыьэюя';

/// Реестр профилей.
final Map<String, TextCodecProfile> _profiles = {};

/// ГСЧ для расстановки маскировочных пробелов.
/// Используется только для расстановки пробелов — не для секретов,
/// поэтому Random.secure() здесь избыточен, но и не вредит.
final Random _rng = Random.secure();

bool _builtinsRegistered = false;

void _ensureBuiltins() {
  if (_builtinsRegistered) return;
  if (!_profiles.containsKey('tiny')) {
    registerProfile('tiny', _alphTiny, bitsPerChar: 4, mode: 'bits');
  }
  if (!_profiles.containsKey('compact')) {
    registerProfile('compact', _alphCompact, bitsPerChar: 5, mode: 'bits');
  }
  if (!_profiles.containsKey('ru_full')) {
    registerProfile(
      'ru_full',
      String.fromCharCodes(_alphRuFullSrc.runes.take(64)),
      bitsPerChar: 6,
      mode: 'bits',
    );
  }
  if (!_profiles.containsKey('ru_max')) {
    registerProfile(
      'ru_max',
      String.fromCharCodes(_alphRuMaxSrc.runes.take(128)),
      bitsPerChar: 7,
      mode: 'bits',
    );
  }
  if (!_profiles.containsKey('natural')) {
    registerProfile('natural', _alphNatural, mode: 'base_n');
  }
  _builtinsRegistered = true;
}

/// Явная инициализация. Idempotent. Вызывается автоматически из encode/decode.
void initTextCodec() => _ensureBuiltins();

/// Регистрирует новый профиль обфускации.
///
/// [name] — уникальное имя для UI.
/// [alphabet] — все символы должны быть уникальны и не содержать пробела
///              (пробел зарезервирован для маскировочных вставок).
/// [bitsPerChar] — если len(alphabet) — степень двойки, можно явно указать
///                 log2(len) для битового кодирования. Если не указано или
///                 len не степень двойки — будет использовано base_n
///                 кодирование через BigInt (только для blob ≤ 255 байт).
/// [mode] — "bits" | "base_n" | null (auto).
///
/// Бросает [ArgumentError] при невалидных параметрах.
void registerProfile(
  String name,
  String alphabet, {
  int? bitsPerChar,
  String? mode,
}) {
  if (name.isEmpty) {
    throw ArgumentError('name должен быть непустой строкой');
  }
  if (alphabet.isEmpty) {
    throw ArgumentError('alphabet не может быть пустым');
  }
  if (alphabet.contains(' ')) {
    throw ArgumentError(
      'Пробел в алфавите запрещён (зарезервирован для маскировки)',
    );
  }

  // Уникальность по rune-кодпоинтам — корректно для эмодзи и кириллицы.
  final runes = alphabet.runes.toList();
  if (runes.toSet().length != runes.length) {
    throw ArgumentError('Алфавит содержит повторяющиеся символы');
  }
  if (runes.length < 2) {
    throw ArgumentError('Алфавит должен содержать минимум 2 символа');
  }
  if (runes.length > 1024) {
    throw ArgumentError('Алфавит слишком большой (>1024 символов)');
  }

  final n = runes.length;
  final isPow2 = (n & (n - 1)) == 0;

  String resolvedMode = mode ?? (isPow2 ? 'bits' : 'base_n');
  if (resolvedMode == 'bits' && !isPow2) {
    throw ArgumentError(
      'Режим "bits" требует размер алфавита степени двойки, получено $n',
    );
  }
  if (resolvedMode != 'bits' && resolvedMode != 'base_n') {
    throw ArgumentError('Неизвестный mode: $resolvedMode');
  }

  int? bitsInt;
  double bitsDouble;
  if (resolvedMode == 'bits') {
    bitsInt = bitsPerChar ?? _log2Int(n);
    if ((1 << bitsInt) != n) {
      throw ArgumentError(
        'bitsPerChar=$bitsInt не соответствует размеру $n',
      );
    }
    bitsDouble = bitsInt.toDouble();
  } else {
    bitsDouble = log(n) / ln2;
  }

  _profiles[name] = TextCodecProfile._(
    name: name,
    alphabet: alphabet,
    size: n,
    bitsPerChar: bitsDouble,
    mode: resolvedMode,
    bitsPerCharInt: bitsInt,
  );
  // Регистрация нового профиля → невалидация кэша union-алфавита.
  _unionAlphabetCache = null;
}

int _log2Int(int n) {
  // n гарантированно степень двойки и > 0.
  int k = 0;
  while ((1 << k) < n) {
    k++;
  }
  return k;
}

/// Информация обо всех профилях. Для UI.
Map<String, Map<String, dynamic>> listProfiles() {
  _ensureBuiltins();
  final result = <String, Map<String, dynamic>>{};
  for (final entry in _profiles.entries) {
    final p = entry.value;
    final preview = p.alphabet.runes.length > 20
        ? '${String.fromCharCodes(p.alphabet.runes.take(20))}...'
        : p.alphabet;
    result[entry.key] = {
      'alphabet_size': p.size,
      'bits_per_char': double.parse(p.bitsPerChar.toStringAsFixed(3)),
      'expansion_ratio': double.parse((8 / p.bitsPerChar).toStringAsFixed(2)),
      'mode': p.mode,
      'preview': preview,
    };
  }
  return result;
}

/// Получить алфавит профиля (для UI: показать пользователю какие символы).
String getProfileAlphabet(String name) {
  _ensureBuiltins();
  final p = _profiles[name];
  if (p == null) {
    throw ArgumentError('Неизвестный профиль: $name');
  }
  return p.alphabet;
}

/// Список доступных имён профилей. Геттер.
List<String> get profileNamesGetter {
  _ensureBuiltins();
  return List.unmodifiable(_profiles.keys);
}

/// Список доступных имён профилей. Функция для удобства вызова.
List<String> profileNames() {
  _ensureBuiltins();
  return List.unmodifiable(_profiles.keys);
}

bool hasProfile(String name) {
  _ensureBuiltins();
  return _profiles.containsKey(name);
}

/// Возвращает режим профиля: "bits" или "base_n".
/// Бросает [ArgumentError] если профиль не зарегистрирован.
String getProfileMode(String name) {
  _ensureBuiltins();
  final p = _profiles[name];
  if (p == null) throw ArgumentError('Unknown profile: $name');
  return p.mode;
}

/// Объединённый алфавит всех зарегистрированных профилей. Используется
/// эвристикой [ChatEncryptionService.isEncryptedMessage] для проверки,
/// все ли символы текста — из набора text_codec (т.е. это похоже на
/// обфусцированный blob).
///
/// Возвращает Set из rune codepoints для быстрого contains().
Set<int> unionAlphabet() {
  _ensureBuiltins();
  final cached = _unionAlphabetCache;
  if (cached != null) return cached;
  final union = <int>{};
  for (final p in _profiles.values) {
    union.addAll(p.alphabet.runes);
  }
  // Кэшируем — алфавиты не меняются часто, и хеш-сет 200+ элементов
  // дёшево пересоздать при registerProfile (см. ниже).
  _unionAlphabetCache = union;
  return union;
}

Set<int>? _unionAlphabetCache;

// =========================================================================
//                   БИТОВОЕ КОДИРОВАНИЕ (степени двойки)
// =========================================================================

String _encodeBits(Uint8List blob, List<int> alphabetRunes, int bitsPerChar) {
  final mask = (1 << bitsPerChar) - 1;
  int bits = 0;
  int count = 0;
  final out = <int>[];
  for (final byte in blob) {
    bits = (bits << 8) | byte;
    count += 8;
    while (count >= bitsPerChar) {
      count -= bitsPerChar;
      out.add(alphabetRunes[(bits >> count) & mask]);
    }
    bits &= (1 << count) - 1;
  }
  if (count > 0) {
    out.add(alphabetRunes[(bits << (bitsPerChar - count)) & mask]);
  }
  return String.fromCharCodes(out);
}

Uint8List _decodeBits(
  String text,
  Map<int, int> inverseAlphabet,
  int bitsPerChar,
) {
  // Инвариант: после полного декода `count` (количество накопленных,
  // но не выгруженных в out битов) всегда строго < 8. Это значит, что
  // если encode добавил трейлинг-символ для padding (см. _encodeBits),
  // его биты осядут в `count`, но не образуют байт — out не получит
  // лишний нулевой байт. Доказательство: каждый шаг bumpит count на
  // bitsPerChar (≤7) и при count>=8 уменьшает на 8. Значит count после
  // итерации входит в [0..bitsPerChar) ⊂ [0..7]. ⇒ длина out строго
  // равна floor(N * bitsPerChar / 8), где N — число валидных символов.
  // Это совпадает с длиной исходного blob в encode (потому что encode
  // выгружает ceil(blob.length * 8 / bitsPerChar) символов, и
  // floor(ceil(8L/B)*B/8) = L при B|8 или при правильно подобранных
  // комбинациях). Подтверждено fuzz-тестом для blob_len ∈ [1..34],
  // bpc ∈ {4,5,6,7}.
  int bits = 0;
  int count = 0;
  final out = <int>[];
  for (final rune in text.runes) {
    final idx = inverseAlphabet[rune];
    if (idx == null) continue; // пробелы и посторонние символы — игнорируем
    bits = (bits << bitsPerChar) | idx;
    count += bitsPerChar;
    while (count >= 8) {
      count -= 8;
      out.add((bits >> count) & 0xFF);
    }
    bits &= (1 << count) - 1;
  }
  return Uint8List.fromList(out);
}

// =========================================================================
//                   BASE-N КОДИРОВАНИЕ (через BigInt)
// =========================================================================

/// Максимальная длина blob для base_n-кодирования (1 байт длины в payload).
const int maxBaseNBlobLen = 255;

String _encodeBaseN(Uint8List blob, List<int> alphabetRunes) {
  if (blob.isEmpty) return '';
  if (blob.length > maxBaseNBlobLen) {
    throw ArgumentError(
      'base_n кодирование рассчитано на blob ≤ $maxBaseNBlobLen байт '
      '(получено ${blob.length}). Используйте bits-профиль для длинных '
      'данных.',
    );
  }
  final base = BigInt.from(alphabetRunes.length);
  // payload = [len(blob)] + blob, как в Python
  final payload = Uint8List(blob.length + 1);
  payload[0] = blob.length;
  payload.setRange(1, payload.length, blob);

  BigInt n = _bytesToBigInt(payload);
  final digits = <int>[];
  if (n == BigInt.zero) {
    digits.add(0);
  }
  while (n > BigInt.zero) {
    final rem = n % base;
    digits.add(rem.toInt());
    n = n ~/ base;
  }
  final out = <int>[];
  for (final d in digits.reversed) {
    out.add(alphabetRunes[d]);
  }
  return String.fromCharCodes(out);
}

Uint8List _decodeBaseN(
  String text,
  Map<int, int> inverseAlphabet,
  int alphabetSize,
) {
  final chars = <int>[];
  for (final rune in text.runes) {
    final idx = inverseAlphabet[rune];
    if (idx != null) chars.add(idx);
  }
  if (chars.isEmpty) return Uint8List(0);

  final base = BigInt.from(alphabetSize);
  BigInt n = BigInt.zero;
  for (final c in chars) {
    n = n * base + BigInt.from(c);
  }
  final byteLen = max(1, (n.bitLength + 7) ~/ 8);
  Uint8List payload = _bigIntToBytes(n, byteLen);

  if (payload.isEmpty) return Uint8List(0);
  final expectedLen = payload[0];
  Uint8List blobPart = Uint8List.fromList(payload.sublist(1));
  if (blobPart.length < expectedLen) {
    final padded = Uint8List(expectedLen);
    padded.setRange(expectedLen - blobPart.length, expectedLen, blobPart);
    blobPart = padded;
  }
  if (blobPart.length > expectedLen) {
    blobPart = Uint8List.fromList(blobPart.sublist(0, expectedLen));
  }
  return blobPart;
}

BigInt _bytesToBigInt(Uint8List bytes) {
  BigInt result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b);
  }
  return result;
}

Uint8List _bigIntToBytes(BigInt n, int length) {
  final out = Uint8List(length);
  BigInt cur = n;
  final mask = BigInt.from(0xFF);
  for (int i = length - 1; i >= 0; i--) {
    out[i] = (cur & mask).toInt();
    cur = cur >> 8;
  }
  return out;
}

// =========================================================================
//                   МАСКИРОВОЧНЫЕ ПРОБЕЛЫ
// =========================================================================

String _addSpaces(String text, {int minBlock = 1, int maxBlock = 22}) {
  if (text.isEmpty) return '';
  final runes = text.runes.toList();
  final n = runes.length;
  final out = <String>[];
  int i = 0;
  while (i < n) {
    final blockLen = minBlock + _rng.nextInt(maxBlock - minBlock + 1);
    final end = (i + blockLen) > n ? n : (i + blockLen);
    out.add(String.fromCharCodes(runes.sublist(i, end)));
    i = end;
  }
  return out.join(' ');
}

// =========================================================================
//                   ПУБЛИЧНОЕ API
// =========================================================================

/// Кодирует blob в обфусцированный текст.
///
/// [profile] — имя зарегистрированного профиля.
/// [spaces] — вставлять ли маскировочные пробелы.
String encode(
  Uint8List blob, {
  String profile = 'compact',
  bool spaces = true,
}) {
  _ensureBuiltins();
  final p = _profiles[profile];
  if (p == null) {
    throw ArgumentError(
      'Неизвестный профиль: "$profile". '
      'Доступные: ${_profiles.keys.toList()}',
    );
  }
  final runes = p.alphabet.runes.toList();
  String encoded;
  if (p.mode == 'bits') {
    encoded = _encodeBits(blob, runes, p.bitsPerCharInt!);
  } else {
    encoded = _encodeBaseN(blob, runes);
  }
  return spaces ? _addSpaces(encoded) : encoded;
}

/// Декодирует обфусцированный текст в blob. Профиль должен совпадать.
Uint8List decode(String text, {String profile = 'compact'}) {
  _ensureBuiltins();
  final p = _profiles[profile];
  if (p == null) {
    throw ArgumentError('Неизвестный профиль: "$profile"');
  }
  final runes = p.alphabet.runes.toList();
  final inv = <int, int>{};
  for (int i = 0; i < runes.length; i++) {
    inv[runes[i]] = i;
  }
  if (p.mode == 'bits') {
    return _decodeBits(text, inv, p.bitsPerCharInt!);
  } else {
    return _decodeBaseN(text, inv, p.size);
  }
}

// =========================================================================
//                   АВТООПРЕДЕЛЕНИЕ ПРОФИЛЯ ЧЕРЕЗ ПЕРЕБОР
// =========================================================================

/// Порядок перебора при smartDecodeAndVerify.
/// Совпадает с Python DEFAULT_DECODE_ORDER.
const List<String> defaultDecodeOrder = [
  'base64',
  'compact',
  'natural',
  'ru_full',
  'ru_max',
  'tiny',
];

/// Результат [smartDecodeAndVerify].
class SmartDecodeResult<T> {
  final T value;
  final String profile;
  SmartDecodeResult(this.value, this.profile);
}

/// Перебирает все профили, для каждого зовёт [verify].
/// Возвращает результат первого профиля, на котором [verify] не выбросил
/// исключение (то есть AES-GCM tag сошёлся).
///
/// Минимум 28 байт после декода: 12 (nonce) + 16 (GCM tag). Меньше — точно
/// не наш blob, профиль пропускается.
///
/// Бросает [FormatException] если ни один профиль не сработал.
SmartDecodeResult<T> smartDecodeAndVerify<T>(
  String text,
  T Function(Uint8List blob) verify, {
  List<String>? profilesOrder,
}) {
  _ensureBuiltins();
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Пустой текст');
  }
  final order = profilesOrder ?? defaultDecodeOrder;

  for (final profile in order) {
    Uint8List blob;
    try {
      if (profile == 'base64') {
        blob = _tryBase64(trimmed);
      } else {
        if (!_profiles.containsKey(profile)) continue;
        blob = decode(trimmed, profile: profile);
      }
    } catch (_) {
      continue;
    }
    // Минимум 28 байт: 12 (nonce) + 16 (GCM tag).
    if (blob.length < 28) continue;
    try {
      final result = verify(blob);
      return SmartDecodeResult(result, profile);
    } catch (_) {
      continue;
    }
  }

  throw FormatException(
    'Не удалось расшифровать ни одним из ${order.length} профилей. '
    'Возможные причины: ключ не совпадает, сообщение повреждено, '
    'или формат не поддерживается.',
  );
}

Uint8List _tryBase64(String text) {
  final cleaned = text.replaceAll(RegExp(r'\s+'), '');
  if (cleaned.isEmpty) return Uint8List(0);
  final padNeeded = (4 - cleaned.length % 4) % 4;
  final padded = cleaned + ('=' * padNeeded);
  return Uint8List.fromList(base64.decode(padded));
}
