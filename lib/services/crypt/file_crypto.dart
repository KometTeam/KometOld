// file_crypto.dart — чанковое шифрование произвольных файлов (порт
// utils/file_crypto.py из Crypt v2.1.5).
//
// Используется для зашифрованных вложений в чате. Файл любого размера
// обрабатывается без загрузки целиком в память — чанками по 64 KB.
//
// Формат файла (бинарный):
//
//     [CRPT header: magic + version + kdf_mode + meta_len]
//     [public_meta JSON]
//     [base_nonce(12)]
//     [— ОПЦИОНАЛЬНО, если public_meta.private_meta == true: —]
//         priv_meta_len(2 BE)
//         priv_meta_nonce(12)
//         priv_meta_tag(16)
//         priv_meta_ct(...)         // AES-GCM(key, AAD = public_meta_bytes + base_nonce)
//                                    // → JSON с original_name, contact_name и т.п.
//     [Зашифрованный поток данных:]
//       Chunk 0:  size(4 BE) || tag(16) || ciphertext
//       Chunk 1:  ...
//       ...
//       Chunk N:  (может быть меньше chunk_size)
//
// Каждый чанк — независимый AES-GCM блок:
//   - nonce_i = base_nonce XOR (i как big-endian 12 байт)
//   - AAD = public_meta_bytes + (0x01 если последний, 0x00 иначе)
//
// Это стандартный подход (см. age, libsodium secretstream). Защищает от
// атак типа «отрезать конец файла» (последний чанк имеет другой AAD).
//
// Сравнение с Python-оригиналом: nonce-схема и AAD совпадают полностью,
// что даёт байт-в-байт совместимость зашифрованных файлов между Crypt и
// KometOld (если общий communication_key).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as cg;
import 'package:cryptography/dart.dart' as cg_dart;

import 'crypt_format.dart' show
    deriveArgon2id,
    argon2DefaultTime,
    argon2DefaultMemoryKib,
    argon2DefaultParallel;
import 'hex.dart';
import 'secret_key.dart' show constantTimeEquals, wipeBytes;

const int _chunkSize = 64 * 1024;
const int _nonceLen = 12;
const int _tagLen = 16;
const List<int> _magic = [0x43, 0x52, 0x50, 0x54]; // "CRPT"
const int _version = 1;
const int _kdfDirect = 0;

/// Колбэк прогресса: (обработано_байт, всего_байт). Вызывается после каждого
/// чанка.
typedef ProgressCallback = void Function(int processed, int total);

/// Параметры шифрования файла. Иммутабельный snapshot опций.
class EncryptFileOptions {
  /// Опциональный второй пароль. Если задан — chat_key оборачивается через
  /// Argon2id(password) и кладётся в meta. Для расшифровки требуется и ключ,
  /// и пароль. Используется для «защищённых вложений» в публичных чатах.
  final String? extraPassword;

  /// Если true — оригинальное имя файла прячется в зашифрованном priv_meta
  /// блоке вместо public meta. UI покажет «🔒 имя скрыто» до ввода ключа.
  final bool hideName;

  /// Опциональное имя контакта (для UI peek).
  final String? contactName;

  /// ID контакта/чата для public meta (нужен получателю для выбора ключа).
  final String? contactId;

  /// Размер чанка. Минимум 1 KiB, максимум 16 MiB.
  final int chunkSize;

  /// Параметры Argon2id для extra_password (если задан).
  final int argon2Time;
  final int argon2MemoryKib;
  final int argon2Parallel;

  const EncryptFileOptions({
    this.extraPassword,
    this.hideName = false,
    this.contactName,
    this.contactId,
    this.chunkSize = _chunkSize,
    this.argon2Time = argon2DefaultTime,
    this.argon2MemoryKib = argon2DefaultMemoryKib,
    this.argon2Parallel = argon2DefaultParallel,
  });
}

/// Шифрует файл [inputPath] в [outputPath] с ключом [key] (32 байта).
///
/// Async, потому что:
/// - Argon2id (если задан extra_password) тяжёлый.
/// - Файл может быть большим — стримим через File I/O.
Future<void> encryptFile(
  String inputPath,
  String outputPath,
  Uint8List key, {
  EncryptFileOptions options = const EncryptFileOptions(),
  ProgressCallback? progress,
}) async {
  if (key.length != 32) {
    throw ArgumentError('key must be 32 bytes (AES-256)');
  }
  final inputFile = File(inputPath);
  if (!await inputFile.exists()) {
    throw FileSystemException('Input file does not exist', inputPath);
  }

  final totalSize = await inputFile.length();
  final chunkSize = _validateChunkSize(options.chunkSize);
  final rng = Random.secure();

  // -- Опциональная KDF-обёртка extra_password ------------------------------ //
  Map<String, dynamic> kdfMeta = {};
  if (options.extraPassword != null) {
    final salt = _randomBytes(16, rng);
    final wrapperKey = await deriveArgon2id(
      password: options.extraPassword!,
      salt: salt,
      timeCost: options.argon2Time,
      memoryCostKib: options.argon2MemoryKib,
      parallelism: options.argon2Parallel,
    );

    try {
      // Оборачиваем сам communication_key (32 байта) AES-GCM-ом
      final wrapNonce = _randomBytes(_nonceLen, rng);
      final wrapped = _aesGcmEncryptShort(wrapperKey, wrapNonce, key, null);

      kdfMeta = {
        'password_wrapped': true,
        'wrap_salt': _hex(salt),
        'wrap_nonce': _hex(wrapNonce),
        'wrap_tag': _hex(wrapped.tag),
        'wrap_ct': _hex(wrapped.ciphertext),
        'time_cost': options.argon2Time,
        'memory_cost': options.argon2MemoryKib,
        'parallelism': options.argon2Parallel,
      };
    } finally {
      // F-NEW fix: затираем производный wrapper-ключ. Он деривирован
      // из extra_password, утечка = утечка пароля.
      wipeBytes(wrapperKey);
    }
  }

  // -- Public meta ---------------------------------------------------------- //
  final meta = <String, dynamic>{
    'type': 'file',
    'original_size': totalSize,
    'chunk_size': chunkSize,
    ...kdfMeta,
  };
  if (options.contactId != null) meta['contact_id'] = options.contactId;

  Map<String, dynamic> privateMeta = {};
  final inputName = inputPath.split(RegExp(r'[/\\]')).last;
  if (options.hideName) {
    meta['private_meta'] = true;
    privateMeta['original_name'] = inputName;
    if (options.contactName != null) {
      privateMeta['contact_name'] = options.contactName;
    }
  } else {
    meta['original_name'] = inputName;
    if (options.contactName != null) {
      meta['contact_name'] = options.contactName;
    }
  }

  final metaBytes = Uint8List.fromList(utf8.encode(jsonEncode(meta)));
  if (metaBytes.length > 65535) {
    throw ArgumentError('Metadata слишком большие (${metaBytes.length} байт)');
  }

  final baseNonce = _randomBytes(_nonceLen, rng);

  // -- Запись ---------------------------------------------------------------- //
  final outputFile = File(outputPath);
  await outputFile.parent.create(recursive: true);
  final out = outputFile.openWrite();

  try {
    // Header
    out.add([..._magic, _version, _kdfDirect]);
    out.add(_uint16Be(metaBytes.length));
    out.add(metaBytes);
    out.add(baseNonce);

    // private_meta blob (если hideName)
    if (options.hideName) {
      final privBlock = _encryptPrivateMeta(
        key: key,
        privateMeta: privateMeta,
        publicMetaBytes: metaBytes,
        baseNonce: baseNonce,
      );
      out.add(privBlock);
    }

    // Стриминг чанков. Логика как в Python:
    //   - Если в буфере есть chunkSize байт И ещё хоть что-то после них —
    //     значит эти chunkSize точно НЕ последний чанк (после есть данные).
    //   - Когда поток закрыт — то, что осталось в буфере (может быть < chunkSize,
    //     == chunkSize или 0 для пустого файла), это последний чанк.
    //   - Особый случай: ПУСТОЙ файл — пишем один пустой last-чанк, чтобы
    //     формат был валиден (соответствует Python-поведению).
    final aad = metaBytes;
    var counter = 0;
    var processed = 0;

    final stream = inputFile.openRead();
    final iter = _ChunkBuffer(chunkSize: chunkSize);
    await for (final piece in stream) {
      iter.add(piece);
      // Пишем только те чанки, после которых ГАРАНТИРОВАННО ещё есть данные
      // (буфер строго больше chunkSize → следующие байты будут).
      while (iter.bufferedBytes > chunkSize) {
        final chunk = iter.takeChunk();
        final encrypted = _encryptChunk(
          key: key,
          nonce: _chunkNonce(baseNonce, counter),
          data: chunk,
          isLast: false,
          aad: aad,
        );
        out.add(_uint32Be(encrypted.length));
        out.add(encrypted);
        counter++;
        processed += chunk.length;
        if (progress != null) progress(processed, totalSize);
      }
    }

    // Поток закончен. Всё что осталось в буфере — последний чанк.
    // Если буфер пуст И ни одного чанка ещё не было записано (counter == 0,
    // т.е. файл был полностью пустой) — пишем один пустой last-чанк.
    // Если counter > 0 и буфер пуст (файл кратен chunkSize) — НЕ пишем
    // лишний пустой чанк; вместо этого помечаем последний из уже записанных.
    //
    // Однако переписывать уже-записанный AAD-флаг нельзя без seek. Решение:
    // НИКОГДА не уходим в while (bufferedBytes > chunkSize) для последнего
    // чанка → по выходу из цикла в буфере всегда останется хотя бы 1..chunkSize
    // байт ИЛИ 0 для пустого файла. Берём оставшееся как last.
    final tail = iter.flush();
    if (tail.isNotEmpty || counter == 0) {
      final encryptedTail = _encryptChunk(
        key: key,
        nonce: _chunkNonce(baseNonce, counter),
        data: tail,
        isLast: true,
        aad: aad,
      );
      out.add(_uint32Be(encryptedTail.length));
      out.add(encryptedTail);
      processed += tail.length;
      if (progress != null) progress(processed, totalSize);
    } else {
      // tail.isEmpty && counter > 0 — невозможно с нашим инвариантом
      // bufferedBytes > chunkSize, но если случилось — fail-fast.
      throw StateError(
        'Внутренняя ошибка: пустой хвост при counter=$counter. '
        'Проверь логику _ChunkBuffer.',
      );
    }
  } finally {
    await out.close();
  }
}

/// Метаданные расшифровки.
class DecryptedFileMeta {
  final String? originalName;
  final String? contactName;
  final String? contactId;
  final int? originalSize;
  final Map<String, dynamic> publicMeta;

  const DecryptedFileMeta({
    this.originalName,
    this.contactName,
    this.contactId,
    this.originalSize,
    required this.publicMeta,
  });
}

/// Расшифровывает файл [inputPath] в [outputPath].
Future<DecryptedFileMeta> decryptFile(
  String inputPath,
  String outputPath,
  Uint8List key, {
  String? extraPassword,
  ProgressCallback? progress,
}) async {
  if (key.length != 32) {
    throw ArgumentError('key must be 32 bytes (AES-256)');
  }
  final inputFile = File(inputPath);
  final raf = await inputFile.open(mode: FileMode.read);

  try {
    // -- Header + meta ---------------------------------------------------- //
    final header = await raf.read(8);
    if (header.length != 8) {
      throw FormatException('File too small for CRPT header');
    }
    if (header[0] != _magic[0] ||
        header[1] != _magic[1] ||
        header[2] != _magic[2] ||
        header[3] != _magic[3]) {
      throw FormatException('Bad magic — not a CRPT file');
    }
    if (header[4] != _version) {
      throw FormatException('Unsupported CRPT version: ${header[4]}');
    }
    final metaLen = (header[6] << 8) | header[7];
    final metaBytes = await raf.read(metaLen);
    if (metaBytes.length != metaLen) {
      throw FormatException('Truncated metadata');
    }
    final meta = jsonDecode(utf8.decode(metaBytes)) as Map<String, dynamic>;

    // -- KDF unwrap (если нужно) ----------------------------------------- //
    var actualKey = key;
    if (meta['password_wrapped'] == true) {
      if (extraPassword == null || extraPassword.isEmpty) {
        throw ArgumentError(
          'Файл защищён дополнительным паролем — введите его',
        );
      }
      final unwrapped = await _unwrapKey(meta, extraPassword);
      // F-04 fix: проверяем, что распакованный ключ совпадает с тем,
      // который передал caller. Если нет — этот файл предназначен для
      // другого контакта/чата (или ключ контакта изменился). Бросаем
      // понятную ошибку вместо того чтобы тихо пройти, а потом упасть
      // на чанке с невнятным AES-GCM tag mismatch.
      //
      // Sub-case: extraPassword был верный, но ключ файла принадлежит
      // другому контакту. Это типичный кейс пересланных файлов между
      // чатами. Можно отдельным флагом разрешить такое — в PR 3.
      if (!constantTimeEquals(unwrapped, key)) {
        // Wipe лишний ключ перед бросанием.
        wipeBytes(unwrapped);
        throw const FormatException(
          'Файл защищён ключом другого контакта. Этот ключ не подходит '
          'для текущего чата.',
        );
      }
      actualKey = unwrapped;
    }

    // -- base_nonce ------------------------------------------------------ //
    final baseNonce = await raf.read(_nonceLen);
    if (baseNonce.length != _nonceLen) {
      throw FormatException('Truncated base_nonce');
    }

    // -- private_meta (если есть) ---------------------------------------- //
    Map<String, dynamic>? privateMeta;
    if (meta['private_meta'] == true) {
      final lenBytes = await raf.read(2);
      if (lenBytes.length != 2) {
        throw FormatException('Truncated private_meta length');
      }
      final privLen = (lenBytes[0] << 8) | lenBytes[1];
      if (privLen < _nonceLen + _tagLen) {
        throw FormatException('private_meta too short');
      }
      final privNonce = await raf.read(_nonceLen);
      final privTag = await raf.read(_tagLen);
      final privCt = await raf.read(privLen - _nonceLen - _tagLen);
      if (privCt.length != privLen - _nonceLen - _tagLen) {
        throw FormatException('Truncated private_meta ct');
      }

      final aadPriv = Uint8List(metaBytes.length + baseNonce.length)
        ..setRange(0, metaBytes.length, metaBytes)
        ..setRange(metaBytes.length, metaBytes.length + baseNonce.length, baseNonce);

      final pt = _aesGcmDecryptShort(
        actualKey,
        Uint8List.fromList(privNonce),
        Uint8List.fromList(privTag),
        Uint8List.fromList(privCt),
        aadPriv,
      );
      privateMeta = jsonDecode(utf8.decode(pt)) as Map<String, dynamic>;
    }

    // -- Чанки ------------------------------------------------------------ //
    final outputFile = File(outputPath);
    await outputFile.parent.create(recursive: true);
    final out = outputFile.openWrite();

    final aad = metaBytes;
    final totalSize = (meta['original_size'] as int?) ?? -1;
    var counter = 0;
    var processed = 0;
    var nextChunkLen = await _readUint32Be(raf);

    while (nextChunkLen != null) {
      // Прочитали длину следующего чанка. Чтобы понять, последний ли это
      // чанк — пробуем прочитать длину чанка ПОСЛЕ него. Если её нет —
      // текущий последний.
      if (nextChunkLen < _tagLen) {
        await out.close();
        throw FormatException(
          'Chunk $counter too small: $nextChunkLen < $_tagLen (tag size)',
        );
      }
      // DoS-защита: подложенный blob с chunk_len = 2 ГБ съест всю RAM
      // прежде чем мы поймём что tag не сходится. Лимит — 64 MiB на чанк
      // (макс. в нашем формате = 16 MiB по _validateChunkSize, но допускаем
      // 4-кратный запас для совместимости с возможными будущими версиями).
      const maxAcceptableChunk = 64 * 1024 * 1024;
      if (nextChunkLen > maxAcceptableChunk) {
        await out.close();
        throw FormatException(
          'Chunk $counter слишком большой: $nextChunkLen байт '
          '(лимит ${maxAcceptableChunk}). Подозрение на подделку.',
        );
      }
      final chunkBlob = await raf.read(nextChunkLen);
      if (chunkBlob.length != nextChunkLen) {
        await out.close();
        throw FormatException(
          'Truncated chunk $counter: expected $nextChunkLen, got ${chunkBlob.length}',
        );
      }
      final tag = chunkBlob.sublist(0, _tagLen);
      final ct = chunkBlob.sublist(_tagLen);

      final maybeNextLen = await _readUint32Be(raf);
      final isLast = maybeNextLen == null;

      try {
        final pt = _aesGcmDecryptShort(
          actualKey,
          _chunkNonce(Uint8List.fromList(baseNonce), counter),
          Uint8List.fromList(tag),
          Uint8List.fromList(ct),
          _aadWithLastFlag(aad, isLast),
        );
        out.add(pt);
        processed += pt.length;
        if (progress != null && totalSize > 0) {
          progress(processed, totalSize);
        }
      } catch (e) {
        await out.close();
        throw FormatException('Chunk $counter failed AES-GCM verify: $e');
      }

      counter++;
      nextChunkLen = maybeNextLen;
    }

    await out.close();

    return DecryptedFileMeta(
      originalName: privateMeta?['original_name'] as String? ??
          meta['original_name'] as String?,
      contactName: privateMeta?['contact_name'] as String? ??
          meta['contact_name'] as String?,
      contactId: meta['contact_id'] as String?,
      originalSize: meta['original_size'] as int?,
      publicMeta: meta,
    );
  } finally {
    await raf.close();
  }
}

/// Читает только public meta файла без расшифровки. Для UI «информация о
/// зашифрованном файле».
Future<Map<String, dynamic>> peekFileMeta(String inputPath) async {
  final raf = await File(inputPath).open(mode: FileMode.read);
  try {
    final header = await raf.read(8);
    if (header.length != 8) {
      throw FormatException('File too small for CRPT header');
    }
    if (header[0] != _magic[0] ||
        header[1] != _magic[1] ||
        header[2] != _magic[2] ||
        header[3] != _magic[3]) {
      throw FormatException('Bad magic — not a CRPT file');
    }
    // F-NEW fix: peekFileMeta раньше пропускал проверку version, поэтому
    // UI мог показать meta файла будущей версии формата, а потом decryptFile
    // упал бы с другой ошибкой. Симметрично с decryptFile проверяем здесь.
    if (header[4] != _version) {
      throw FormatException('Unsupported CRPT version: ${header[4]}');
    }
    final metaLen = (header[6] << 8) | header[7];
    final metaBytes = await raf.read(metaLen);
    return jsonDecode(utf8.decode(metaBytes)) as Map<String, dynamic>;
  } finally {
    await raf.close();
  }
}

// ========================================================================== //
//                              ВНУТРЕННЯЯ КУХНЯ
// ========================================================================== //

class _AesShortResult {
  final Uint8List ciphertext;
  final Uint8List tag;
  _AesShortResult(this.ciphertext, this.tag);
}

/// Sync AesGcm для всех чанков (потокобезопасный, переиспользуемый).
final cg_dart.DartAesGcm _aesGcm = cg_dart.DartAesGcm.with256bits();

/// AES-GCM шифрование короткого блока (≤ chunk size). Возвращает (ct, tag)
/// раздельно. Использует package:cryptography (AesGcm.encryptSync).
///
/// F-NEW: AAD теперь обязательный non-nullable Uint8List. Раньше принимали
/// `Uint8List?` и кодировали null как пустой list — это рисково: если
/// encrypt передаст `null`, а decrypt где-то передаст `Uint8List(0)`,
/// итоговое поведение совпадёт (оба = пустой список), но смешение null/[]
/// в API ведёт к багам при копи-пасте. Если AAD не нужен, передавайте
/// явно `Uint8List(0)` (или используйте константу `_emptyAad`).
final Uint8List _emptyAad = Uint8List(0);

_AesShortResult _aesGcmEncryptShort(
  Uint8List key,
  Uint8List nonce,
  Uint8List plaintext,
  Uint8List? aad,
) {
  final secretKey = cg.SecretKeyData(key);
  final box = _aesGcm.encryptSync(
    plaintext,
    secretKeyData: secretKey,
    nonce: nonce,
    aad: aad ?? _emptyAad,
  );
  return _AesShortResult(
    Uint8List.fromList(box.cipherText),
    Uint8List.fromList(box.mac.bytes),
  );
}

/// AES-GCM расшифровка короткого блока с раздельными ct и tag.
/// Бросает [cg.SecretBoxAuthenticationError] при несошедшемся tag.
Uint8List _aesGcmDecryptShort(
  Uint8List key,
  Uint8List nonce,
  Uint8List tag,
  Uint8List ct,
  Uint8List? aad,
) {
  final secretKey = cg.SecretKeyData(key);
  final box = cg.SecretBox(ct, nonce: nonce, mac: cg.Mac(tag));
  final pt = _aesGcm.decryptSync(
    box,
    secretKeyData: secretKey,
    aad: aad ?? _emptyAad,
  );
  return Uint8List.fromList(pt);
}

/// Шифрует один чанк потокового формата. Возвращает [tag || ct].
Uint8List _encryptChunk({
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List data,
  required bool isLast,
  required Uint8List aad,
}) {
  final result = _aesGcmEncryptShort(
    key,
    nonce,
    data,
    _aadWithLastFlag(aad, isLast),
  );
  // Формат чанка на диске — [tag][ct], как в Python (enc.tag + ct)
  final out = Uint8List(_tagLen + result.ciphertext.length)
    ..setRange(0, _tagLen, result.tag)
    ..setRange(_tagLen, _tagLen + result.ciphertext.length, result.ciphertext);
  return out;
}

/// Шифрует priv_meta блок. Возвращает [len(2) || nonce(12) || tag(16) || ct].
Uint8List _encryptPrivateMeta({
  required Uint8List key,
  required Map<String, dynamic> privateMeta,
  required Uint8List publicMetaBytes,
  required Uint8List baseNonce,
}) {
  final ptBytes = Uint8List.fromList(utf8.encode(jsonEncode(privateMeta)));
  final nonce = _randomBytes(_nonceLen, Random.secure());

  final aad = Uint8List(publicMetaBytes.length + baseNonce.length)
    ..setRange(0, publicMetaBytes.length, publicMetaBytes)
    ..setRange(publicMetaBytes.length, publicMetaBytes.length + baseNonce.length, baseNonce);

  final result = _aesGcmEncryptShort(key, nonce, ptBytes, aad);

  final body = Uint8List(_nonceLen + _tagLen + result.ciphertext.length)
    ..setRange(0, _nonceLen, nonce)
    ..setRange(_nonceLen, _nonceLen + _tagLen, result.tag)
    ..setRange(_nonceLen + _tagLen,
        _nonceLen + _tagLen + result.ciphertext.length, result.ciphertext);

  final lenBytes = _uint16Be(body.length);
  return Uint8List(lenBytes.length + body.length)
    ..setRange(0, lenBytes.length, lenBytes)
    ..setRange(lenBytes.length, lenBytes.length + body.length, body);
}

/// Разворачивает chat_key из meta[password_wrapped] через Argon2id+AES-GCM.
/// Возвращает РАЗВЁРНУТЫЙ ключ.
Future<Uint8List> _unwrapKey(
  Map<String, dynamic> meta,
  String password,
) async {
  final salt = _unhex(meta['wrap_salt'] as String);
  // F-NEW fix: используем `as num?` + toInt() вместо `as int?`. Если
  // meta пришло из JSON, числа могут быть double (например, 3.0) — старый
  // cast выкинет TypeError ещё до fallback.
  final timeCost = (meta['time_cost'] as num?)?.toInt() ?? argon2DefaultTime;
  final memoryCost = (meta['memory_cost'] as num?)?.toInt() ?? argon2DefaultMemoryKib;
  final parallelism = (meta['parallelism'] as num?)?.toInt() ?? argon2DefaultParallel;

  // F-NEW fix: валидация параметров. Без неё подделанный файл с
  // `memory_cost = 10^9` мог заставить устройство Argon2id-нуть гигабайт
  // памяти и упасть. Лимиты совпадают с теми, что в crypt_format.
  if (timeCost < 1 || timeCost > 1000) {
    throw FormatException(
      'wrap.time_cost вне допустимого диапазона: $timeCost',
    );
  }
  if (memoryCost < 8 || memoryCost > 1024 * 1024) {
    throw FormatException(
      'wrap.memory_cost вне допустимого диапазона: $memoryCost KiB',
    );
  }
  if (parallelism < 1 || parallelism > 16) {
    throw FormatException(
      'wrap.parallelism вне допустимого диапазона: $parallelism',
    );
  }

  final wrapperKey = await deriveArgon2id(
    password: password,
    salt: salt,
    timeCost: timeCost,
    memoryCostKib: memoryCost,
    parallelism: parallelism,
  );
  try {
    final wrapNonce = _unhex(meta['wrap_nonce'] as String);
    final wrapTag = _unhex(meta['wrap_tag'] as String);
    final wrapCt = _unhex(meta['wrap_ct'] as String);

    final unwrapped = _aesGcmDecryptShort(
      wrapperKey,
      wrapNonce,
      wrapTag,
      wrapCt,
      null,
    );
    // Если расшифровка прошла — пароль верен. Возвращаем именно тот ключ,
    // которым зашифрован файл (он может отличаться от ключа текущего чата,
    // что нормально для файлов, пересланных между чатами).
    return unwrapped;
  } finally {
    // F-NEW fix: производный wrapper-ключ больше не нужен.
    wipeBytes(wrapperKey);
  }
}

Uint8List _chunkNonce(Uint8List baseNonce, int counter) {
  final out = Uint8List(_nonceLen);
  // big-endian counter в 12 байт.
  //
  // На Dart-VM (mobile/desktop) `int` 64-битный — counter влезает целиком.
  // На dart2js `>>>` ограничен 32 битами, что для counter > 2^32 даст
  // некорректный nonce. Реалистичных файлов размером >2^32 чанков по 64KB
  // (~256 ТБ) не бывает, но защищаемся явно: бросаем при выходе за uint32.
  if (counter < 0 || counter > 0xFFFFFFFF) {
    throw ArgumentError(
      'chunk counter $counter вне допустимого диапазона [0..2^32-1]',
    );
  }
  var c = counter;
  for (var i = _nonceLen - 1; i >= 0; i--) {
    out[i] = c & 0xFF;
    c = (c >>> 8) & 0xFFFFFFFF; // маска для dart2js
  }
  for (var i = 0; i < _nonceLen; i++) {
    out[i] ^= baseNonce[i];
  }
  return out;
}

Uint8List _aadWithLastFlag(Uint8List aad, bool isLast) {
  final out = Uint8List(aad.length + 1);
  out.setRange(0, aad.length, aad);
  out[aad.length] = isLast ? 0x01 : 0x00;
  return out;
}

int _validateChunkSize(int v) {
  if (v < 1024) return 1024;
  if (v > 16 * 1024 * 1024) return 16 * 1024 * 1024;
  return v;
}

Uint8List _randomBytes(int n, Random rng) {
  final out = Uint8List(n);
  for (var i = 0; i < n; i++) {
    out[i] = rng.nextInt(256);
  }
  return out;
}

List<int> _uint16Be(int v) => [(v >> 8) & 0xFF, v & 0xFF];
List<int> _uint32Be(int v) => [
      (v >> 24) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 8) & 0xFF,
      v & 0xFF,
    ];

Future<int?> _readUint32Be(RandomAccessFile raf) async {
  final b = await raf.read(4);
  if (b.length != 4) return null;
  // На Dart-VM (mobile/desktop) сдвиги работают на 64-битных int — OK.
  // На dart2js bitwise ограничены 32-bit signed, поэтому при MSB=1 (длина
  // ≥ 2 ГБ) результат будет отрицательным. Маска `& 0xFFFFFFFF` приводит
  // к корректному unsigned значению на обеих платформах.
  return ((b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]) & 0xFFFFFFFF;
}

// F-NEW: убраны дубликаты hex-функций — используем общий Hex utility.
String _hex(Uint8List b) => Hex.encode(b);
Uint8List _unhex(String s) => Hex.decode(s);

/// Буфер для накопления чанков из стрима произвольных кусков.
class _ChunkBuffer {
  final int chunkSize;
  final BytesBuilder _buf = BytesBuilder(copy: false);
  _ChunkBuffer({required this.chunkSize});

  void add(List<int> piece) => _buf.add(piece);

  /// Текущее количество байт в буфере.
  int get bufferedBytes => _buf.length;

  /// True, если в буфере есть как минимум полный чанк.
  bool get hasFullChunk => _buf.length >= chunkSize;

  Uint8List takeChunk() {
    final all = _buf.takeBytes();
    if (all.length == chunkSize) return all;
    // Возвращаем ровно chunkSize, остальное обратно в буфер.
    _buf.add(all.sublist(chunkSize));
    return all.sublist(0, chunkSize);
  }

  Uint8List flush() => _buf.takeBytes();
}

