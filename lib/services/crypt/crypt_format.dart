// crypt_format.dart — единый формат зашифрованных blob'ов Crypt (порт
// utils/file_format.py).
//
// Используется для:
//   - Сообщений в чате (KDF_DIRECT, ключ деривирован один раз — sync)
//   - Экспорта ключа чата (KDF_PASSWORD, через Argon2id — async)
//
// Формат (бинарный):
//
//     Offset  Size  Field
//     ------  ----  -------------------------------------------
//     0       4     Magic:     "CRPT"
//     4       1     Version:   1
//     5       1     KDF mode:  0 = direct key, 1 = Argon2id(password)
//     6       2     Metadata length (big-endian uint16)
//     8       N     Metadata (JSON, UTF-8)
//     8+N     12    Nonce (random)
//     8+N+12  16    Tag (AES-GCM authenticator)
//     8+N+28  ...   Ciphertext
//
// Метаданные включаются в AAD (additional authenticated data) AES-GCM,
// поэтому их подмена обнаруживается по несошедшемуся tag.
//
// Реализация:
//   - AES-GCM: package:cryptography (AesGcm.encryptSync), pure-Dart
//     синхронный API. Это позволяет шифровать/дешифровать сообщения в
//     build()-функциях без асинхронности.
//   - Argon2id: package:cryptography (Argon2id). Асинхронный, тяжёлый
//     (1-3 секунды на телефоне для 128 MiB), вызывается ТОЛЬКО при
//     настройке мастер-пароля или при экспорте/импорте ключа.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as cg;
import 'package:cryptography/dart.dart' as cg_dart;

import 'hex.dart';
import 'secret_key.dart' show wipeBytes;

const List<int> _magic = [0x43, 0x52, 0x50, 0x54]; // "CRPT"
const int _version = 1;

/// KDF режимы.
const int kdfDirect = 0; // ключ передан напрямую
const int kdfPassword = 1; // ключ выводится из пароля через Argon2id

const int _nonceLen = 12;
const int _tagLen = 16;

// Argon2id параметры по умолчанию (OWASP 2024 second recommendation).
// Совпадают с Python (file_format.py: balanced профиль).
const int argon2DefaultTime = 3;
const int argon2DefaultMemoryKib = 131072; // 128 MiB
const int argon2DefaultParallel = 4;

/// Профили Argon2id (1-в-1 с Python ARGON2_PROFILES).
const Map<String, Map<String, int>> argon2Profiles = {
  'lite': {'time_cost': 3, 'memory_cost': 65536, 'parallelism': 4},
  'balanced': {'time_cost': 3, 'memory_cost': 131072, 'parallelism': 4},
  'strong': {'time_cost': 4, 'memory_cost': 262144, 'parallelism': 4},
};

/// L-5: верхние лимиты на параметры из meta (защита от DoS — кто-то
/// подсовывает blob с memory_cost=10^9).
const int argon2MaxTime = 1000;
const int argon2MaxMemoryKib = 1024 * 1024; // 1 GiB в KiB
const int argon2MaxParallel = 16;

/// Возвращает параметры Argon2id по имени профиля.
Map<String, int> getArgon2Params([String profile = 'balanced']) {
  final p = argon2Profiles[profile] ?? argon2Profiles['balanced']!;
  return Map<String, int>.from(p);
}

final Random _rng = Random.secure();

Uint8List _randomBytes(int n) {
  final out = Uint8List(n);
  for (int i = 0; i < n; i++) {
    out[i] = _rng.nextInt(256);
  }
  return out;
}

// =========================================================================
//                   ARGON2id ДЕРИВАЦИЯ (async)
// =========================================================================

/// Деривирует [hashLen]-байтный ключ из пароля через Argon2id.
///
/// Это тяжёлая операция (для 128 MiB — 1-3 секунды на телефоне).
/// Запускайте её только при первой настройке чата или при экспорте/импорте,
/// не на каждое сообщение.
Future<Uint8List> deriveArgon2id({
  required String password,
  required Uint8List salt,
  int timeCost = argon2DefaultTime,
  int memoryCostKib = argon2DefaultMemoryKib,
  int parallelism = argon2DefaultParallel,
  int hashLen = 32,
}) async {
  final algo = cg.Argon2id(
    memory: memoryCostKib,
    parallelism: parallelism,
    iterations: timeCost,
    hashLength: hashLen,
  );
  final key = await algo.deriveKeyFromPassword(
    password: password,
    nonce: salt,
  );
  final bytes = await key.extractBytes();
  return Uint8List.fromList(bytes);
}

// =========================================================================
//                AES-GCM (sync, через package:cryptography → AesGcm)
// =========================================================================
//
// Используем AesGcm — pure-Dart sync-реализация AES-GCM из
// package:cryptography. Этот вариант:
//   1. Не требует package:encrypt (архивирован в июне 2025).
//   2. Sync — работает в build()-методах виджетов.
//   3. Активно поддерживается, тот же пакет что и для Argon2id.
//
// На критическом пути (отрисовка чата) можно вместо нативного асинхронного
// AES-GCM (cryptography_flutter) использовать AesGcm — нагрузка на
// одно сообщение в чате (≤4KB) ничтожна.

final cg_dart.DartAesGcm _aesGcm = cg_dart.DartAesGcm.with256bits();

/// Шифрует [plaintext] sync через AES-256-GCM.
/// Возвращает (ciphertext, tag).
(Uint8List, Uint8List) _aesGcmEncrypt(
  Uint8List key,
  Uint8List nonce,
  Uint8List plaintext,
  Uint8List aad,
) {
  final secretKey = cg.SecretKeyData(key);
  final box = _aesGcm.encryptSync(
    plaintext,
    secretKeyData: secretKey,
    nonce: nonce,
    aad: aad,
  );
  final ct = Uint8List.fromList(box.cipherText);
  final tag = Uint8List.fromList(box.mac.bytes);
  if (tag.length != _tagLen) {
    throw StateError(
      'AES-GCM tag length: ${tag.length}, expected $_tagLen',
    );
  }
  return (ct, tag);
}

/// Расшифровывает sync через AES-256-GCM.
/// Бросает [cg.SecretBoxAuthenticationError] при несошедшемся tag.
Uint8List _aesGcmDecrypt(
  Uint8List key,
  Uint8List nonce,
  Uint8List ciphertext,
  Uint8List tag,
  Uint8List aad,
) {
  final secretKey = cg.SecretKeyData(key);
  final box = cg.SecretBox(
    ciphertext,
    nonce: nonce,
    mac: cg.Mac(tag),
  );
  final pt = _aesGcm.decryptSync(
    box,
    secretKeyData: secretKey,
    aad: aad,
  );
  return Uint8List.fromList(pt);
}

// =========================================================================
//                   PACK / UNPACK (KDF_DIRECT — sync)
// =========================================================================

/// Упаковывает [plaintext] в формат CRPT с KDF_DIRECT (ключ уже готов).
///
/// Sync — подходит для шифрования сообщений в чате на каждое отправление.
///
/// [publicMeta] — метаданные, которые нужны для разбора blob'а, но не
/// секретны. Они аутентифицируются GCM-тегом, но передаются открыто.
Uint8List packEncrypted({
  required Uint8List key,
  required Uint8List plaintext,
  Map<String, dynamic>? publicMeta,
}) {
  if (key.length != 32) {
    throw ArgumentError(
      'AES-256 ключ должен быть 32 байта, получено ${key.length}',
    );
  }
  final meta = publicMeta ?? <String, dynamic>{};
  final metaBytes = Uint8List.fromList(utf8.encode(_compactJson(meta)));
  if (metaBytes.length > 65535) {
    throw ArgumentError('Metadata слишком большие (>65535 байт)');
  }

  final nonce = _randomBytes(_nonceLen);
  final (ct, tag) = _aesGcmEncrypt(key, nonce, plaintext, metaBytes);

  return _assemble(kdfDirect, metaBytes, nonce, tag, ct);
}

/// Расшифровка blob'а с KDF_DIRECT (sync).
/// Бросает [FormatException] / [Exception] при ошибках.
CrptUnpackResult unpackDirect({
  required Uint8List key,
  required Uint8List blob,
}) {
  if (key.length != 32) {
    throw ArgumentError(
      'AES-256 ключ должен быть 32 байта, получено ${key.length}',
    );
  }
  final h = parseHeader(blob);
  if (h.kdfMode != kdfDirect) {
    throw FormatException(
      'Файл защищён паролем (KDF=${h.kdfMode}). Используйте unpackPassword.',
    );
  }
  final nonce = Uint8List.fromList(
    blob.sublist(h.bodyOffset, h.bodyOffset + _nonceLen),
  );
  final tag = Uint8List.fromList(
    blob.sublist(h.bodyOffset + _nonceLen, h.bodyOffset + _nonceLen + _tagLen),
  );
  final ct = Uint8List.fromList(
    blob.sublist(h.bodyOffset + _nonceLen + _tagLen),
  );

  final pt = _aesGcmDecrypt(key, nonce, ct, tag, h.metaBytes);
  return CrptUnpackResult(pt, h.meta);
}

// =========================================================================
//                   PACK / UNPACK (KDF_PASSWORD — async)
// =========================================================================

/// Упаковывает [plaintext] с шифрованием по паролю (Argon2id+AES-GCM).
/// Async — Argon2id занимает 1-3 секунды.
///
/// [kdfParams] — словарь с time_cost / memory_cost / parallelism.
/// Если null — используется balanced-профиль (128 MiB, t=3, p=4).
Future<Uint8List> packPasswordEncrypted({
  required String password,
  required Uint8List plaintext,
  Map<String, dynamic>? publicMeta,
  Map<String, int>? kdfParams,
}) async {
  final params = kdfParams ?? getArgon2Params('balanced');
  final timeCost = params['time_cost'] ?? argon2DefaultTime;
  final memoryCost = params['memory_cost'] ?? argon2DefaultMemoryKib;
  final parallelism = params['parallelism'] ?? argon2DefaultParallel;

  final salt = _randomBytes(16);
  final meta = <String, dynamic>{
    ...?publicMeta,
    'kdf': 'argon2id',
    'salt': _hexEncode(salt),
    'time_cost': timeCost,
    'memory_cost': memoryCost,
    'parallelism': parallelism,
  };
  final metaBytes = Uint8List.fromList(utf8.encode(_compactJson(meta)));
  if (metaBytes.length > 65535) {
    throw ArgumentError('Metadata слишком большие (>65535 байт)');
  }

  final key = await deriveArgon2id(
    password: password,
    salt: salt,
    timeCost: timeCost,
    memoryCostKib: memoryCost,
    parallelism: parallelism,
  );

  try {
    final nonce = _randomBytes(_nonceLen);
    final (ct, tag) = _aesGcmEncrypt(key, nonce, plaintext, metaBytes);

    return _assemble(kdfPassword, metaBytes, nonce, tag, ct);
  } finally {
    // F-NEW fix: затираем производный ключ — он содержит результат
    // Argon2id над паролем, утечка которого равносильна утечке пароля.
    wipeBytes(key);
  }
}

/// Расшифровка blob'а с KDF_PASSWORD (async).
Future<CrptUnpackResult> unpackPassword({
  required String password,
  required Uint8List blob,
}) async {
  final h = parseHeader(blob);
  if (h.kdfMode != kdfPassword) {
    throw FormatException(
      'Файл не защищён паролем (KDF=${h.kdfMode}). Используйте unpackDirect.',
    );
  }
  final saltHex = h.meta['salt'];
  if (saltHex is! String) {
    throw const FormatException('meta.salt отсутствует или невалидный');
  }
  final salt = _hexDecode(saltHex);
  final params = _validatedArgon2Params(h.meta);

  final key = await deriveArgon2id(
    password: password,
    salt: salt,
    timeCost: params.timeCost,
    memoryCostKib: params.memoryCost,
    parallelism: params.parallelism,
  );

  try {
    final nonce = Uint8List.fromList(
      blob.sublist(h.bodyOffset, h.bodyOffset + _nonceLen),
    );
    final tag = Uint8List.fromList(
      blob.sublist(h.bodyOffset + _nonceLen, h.bodyOffset + _nonceLen + _tagLen),
    );
    final ct = Uint8List.fromList(
      blob.sublist(h.bodyOffset + _nonceLen + _tagLen),
    );

    final pt = _aesGcmDecrypt(key, nonce, ct, tag, h.metaBytes);

    // Чистим публичные метаданные от KDF-полей.
    final publicMeta = <String, dynamic>{
      for (final entry in h.meta.entries)
        if (!_kdfMetaFields.contains(entry.key)) entry.key: entry.value,
    };
    return CrptUnpackResult(pt, publicMeta);
  } finally {
    // F-NEW fix: производный ключ из пароля больше не нужен.
    wipeBytes(key);
  }
}

// =========================================================================
//                   ЗАГОЛОВОК / ОБЩЕЕ
// =========================================================================

const Set<String> _kdfMetaFields = {
  'kdf', 'salt', 'time_cost', 'memory_cost', 'parallelism',
};

Uint8List _assemble(
  int kdfMode,
  Uint8List metaBytes,
  Uint8List nonce,
  Uint8List tag,
  Uint8List ct,
) {
  const headerLen = 4 + 1 + 1 + 2;
  final total =
      headerLen + metaBytes.length + nonce.length + tag.length + ct.length;
  final out = Uint8List(total);
  int off = 0;
  out.setRange(off, off + 4, _magic);
  off += 4;
  out[off++] = _version;
  out[off++] = kdfMode;
  // big-endian uint16
  out[off++] = (metaBytes.length >> 8) & 0xFF;
  out[off++] = metaBytes.length & 0xFF;
  out.setRange(off, off + metaBytes.length, metaBytes);
  off += metaBytes.length;
  out.setRange(off, off + nonce.length, nonce);
  off += nonce.length;
  out.setRange(off, off + tag.length, tag);
  off += tag.length;
  out.setRange(off, off + ct.length, ct);
  return out;
}

/// Разобранный заголовок CRPT-blob'а.
class CrptHeader {
  final int version;
  final int kdfMode;
  final Map<String, dynamic> meta;

  /// Сырые байты meta (нужны как AAD для AES-GCM).
  final Uint8List metaBytes;

  /// Смещение в blob'е, с которого начинается nonce.
  final int bodyOffset;

  CrptHeader({
    required this.version,
    required this.kdfMode,
    required this.meta,
    required this.metaBytes,
    required this.bodyOffset,
  });
}

/// Разбирает заголовок CRPT-blob'а.
/// Бросает [FormatException] при невалидных данных.
CrptHeader parseHeader(Uint8List blob) {
  if (blob.length < 8) {
    throw const FormatException('Файл слишком мал, не похож на CRPT формат');
  }
  for (int i = 0; i < 4; i++) {
    if (blob[i] != _magic[i]) {
      throw const FormatException('Неверный magic, ожидалось CRPT');
    }
  }
  final version = blob[4];
  final kdfMode = blob[5];
  final metaLen = (blob[6] << 8) | blob[7];

  if (version != _version) {
    throw FormatException('Неподдерживаемая версия формата: $version');
  }
  // F-07 fix: валидируем kdf_mode на белый список. Без этого peekKdfMode
  // и peekMeta могут «успешно» вернуть результат для blob с произвольным
  // байтом в позиции 5, что вводит в заблуждение вызывающий код.
  if (kdfMode != kdfDirect && kdfMode != kdfPassword) {
    throw FormatException('Неизвестный KDF mode: $kdfMode');
  }
  if (blob.length < 8 + metaLen + _nonceLen + _tagLen) {
    throw const FormatException('CRPT-blob обрезан');
  }

  final metaBytes = Uint8List.fromList(blob.sublist(8, 8 + metaLen));
  Map<String, dynamic> meta;
  try {
    meta = jsonDecode(utf8.decode(metaBytes)) as Map<String, dynamic>;
  } catch (e) {
    throw FormatException('Повреждённые метаданные: $e');
  }

  return CrptHeader(
    version: version,
    kdfMode: kdfMode,
    meta: meta,
    metaBytes: metaBytes,
    bodyOffset: 8 + metaLen,
  );
}

/// Результат расшифровки: сам plaintext + публичные метаданные.
class CrptUnpackResult {
  final Uint8List plaintext;
  final Map<String, dynamic> publicMeta;
  CrptUnpackResult(this.plaintext, this.publicMeta);
}

/// L-5: безопасное чтение Argon2-параметров из meta с верхним лимитом.
({int timeCost, int memoryCost, int parallelism}) _validatedArgon2Params(
  Map<String, dynamic> meta,
) {
  final timeCost = (meta['time_cost'] as num?)?.toInt() ?? argon2DefaultTime;
  final memoryCost =
      (meta['memory_cost'] as num?)?.toInt() ?? argon2DefaultMemoryKib;
  final parallelism =
      (meta['parallelism'] as num?)?.toInt() ?? argon2DefaultParallel;

  if (timeCost < 1 || timeCost > argon2MaxTime) {
    throw FormatException(
      'Argon2 time_cost вне допустимого диапазона '
      '[1..$argon2MaxTime]: $timeCost. Файл повреждён или подделан.',
    );
  }
  if (memoryCost < 8 || memoryCost > argon2MaxMemoryKib) {
    throw FormatException(
      'Argon2 memory_cost вне допустимого диапазона '
      '[8..$argon2MaxMemoryKib] KiB: $memoryCost. Файл повреждён или подделан.',
    );
  }
  if (parallelism < 1 || parallelism > argon2MaxParallel) {
    throw FormatException(
      'Argon2 parallelism вне допустимого диапазона '
      '[1..$argon2MaxParallel]: $parallelism. Файл повреждён или подделан.',
    );
  }
  return (
    timeCost: timeCost,
    memoryCost: memoryCost,
    parallelism: parallelism,
  );
}

/// Узнать, защищён ли blob паролем, не расшифровывая его.
int peekKdfMode(Uint8List blob) => parseHeader(blob).kdfMode;

/// Прочитать публичные метаданные без расшифровки.
Map<String, dynamic> peekMeta(Uint8List blob) {
  final h = parseHeader(blob);
  return <String, dynamic>{
    for (final entry in h.meta.entries)
      if (!_kdfMetaFields.contains(entry.key)) entry.key: entry.value,
  };
}

/// Быстрая проверка: похож ли buffer на CRPT-blob (по magic).
bool isCrptBlob(Uint8List blob) {
  if (blob.length < 4) return false;
  for (int i = 0; i < 4; i++) {
    if (blob[i] != _magic[i]) return false;
  }
  return true;
}

// =========================================================================
//                   ВСПОМОГАТЕЛЬНЫЕ
// =========================================================================

/// JSON в "компактном" формате, совместимом с Python
/// `json.dumps(..., separators=(",", ":"), ensure_ascii=False)`.
///
/// `dart:convert.jsonEncode` по умолчанию даёт ровно такой же результат
/// (без пробелов между разделителями, не-ASCII не экранируется).
String _compactJson(Map<String, dynamic> meta) => jsonEncode(meta);

// F-NEW: убраны дубликаты hex-функций — используем общий Hex utility.
String _hexEncode(Uint8List bytes) => Hex.encode(bytes);
Uint8List _hexDecode(String s) => Hex.decode(s);

