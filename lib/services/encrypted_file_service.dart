// encrypted_file_service.dart — шифрование/расшифровка файлов и фото в чате.
//
// Стратегия:
//   ОТПРАВКА:
//     1. Берём оригинальный путь файла/фото.
//     2. Шифруем в temp-файл .<ext> через file_crypto.encryptFile.
//     3. Отдаём путь temp-файла в ApiService для upload.
//     4. После upload удаляем temp-файл.
//
//   ПОЛУЧЕНИЕ (авто-расшифровка):
//     1. После download читаем первые 4 байта — magic 'CRPT'.
//     2. Если совпало — пробуем расшифровать chat_key текущего чата.
//     3. Если расшифровалось — сохраняем расшифрованный файл рядом.
//     4. Bubble получает путь к расшифрованному файлу.
//
//   Если файл НЕ зашифрован (входящий от другого юзера без шифрования) —
//   работает как обычно.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'chat_encryption_service.dart';
import 'crypt/file_crypto.dart' as fc;
import 'crypt/master_key_manager.dart';
import 'crypt/safe_filename.dart';
import 'crypt/secret_key.dart';

/// Magic bytes формата CRPT.
const List<int> _crptMagic = [0x43, 0x52, 0x50, 0x54];

class EncryptedFileService {
  EncryptedFileService._();
  static final EncryptedFileService instance = EncryptedFileService._();

  /// Проверяет, выглядит ли файл как зашифрованный CRPT-блоб.
  Future<bool> looksEncrypted(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;
      final bytes = await file.openRead(0, 4).expand((x) => x).toList();
      if (bytes.length < 4) return false;
      for (var i = 0; i < 4; i++) {
        if (bytes[i] != _crptMagic[i]) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Шифрует файл для отправки в чат [chatId].
  /// Возвращает путь к временному зашифрованному файлу.
  /// Расширение — из конфига чата (по умолчанию 'bin').
  /// Caller обязан удалить temp-файл после upload.
  Future<String?> encryptForUpload({
    required int chatId,
    required String originalPath,
  }) async {
    final mgr = MasterKeyManager.instance;
    if (!mgr.isUnlocked) return null;

    final cfg = await ChatEncryptionService.getConfigForChat(chatId);
    if (cfg == null || !ChatEncryptionService.hasNewKey(cfg)) return null;
    if (!cfg.encryptFiles) return null;

    final chatKey = await mgr.getOrCreateChatKey(chatId);
    final keyBytes = chatKey.exposeCopy();

    final ext = cfg.encryptedFileExtension.replaceAll('.', '');
    final originalName = p.basename(originalPath);

    final tmpDir = await getTemporaryDirectory();
    final tmpPath = '${tmpDir.path}/komet_enc_${DateTime.now().millisecondsSinceEpoch}.$ext';

    try {
      await fc.encryptFile(
        originalPath,
        tmpPath,
        keyBytes,
        options: fc.EncryptFileOptions(
          contactName: 'chat_$chatId',
          hideName: false,
        ),
      );
      wipeBytes(keyBytes);
      return tmpPath;
    } catch (e) {
      wipeBytes(keyBytes);
      // Если шифрование упало — возвращаем null, отправим оригинал.
      return null;
    }
  }

  /// Пытается расшифровать файл по [filePath] ключом чата [chatId].
  /// Если файл не зашифрован или ключ не подходит — возвращает null.
  /// Если расшифровалось — возвращает путь к расшифрованному файлу.
  Future<String?> tryDecrypt({
    required int chatId,
    required String filePath,
    String? originalFileName,
  }) async {
    final mgr = MasterKeyManager.instance;
    if (!mgr.isUnlocked) return null;

    if (!await looksEncrypted(filePath)) return null;

    // Проверяем что у чата вообще есть ключ.
    if (!await mgr.hasChatKey(chatId)) return null;

    final chatKey = await mgr.getOrCreateChatKey(chatId);
    final keyBytes = chatKey.exposeCopy();

    String? decPath;
    String? finalPath;
    try {
      final tmpDir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      // Имя расшифрованного файла: strip enc-extension, оставить оригинал.
      // ВАЖНО: и [originalFileName], и [filePath] могут содержать данные
      // из недоверенного источника. Санитизируем оба варианта, чтобы
      // путь не вышел за пределы tmpDir.
      final rawName = originalFileName ?? p.basenameWithoutExtension(filePath);
      final decName = SafeFilename.sanitize(rawName, fallback: 'decrypted');
      decPath = SafeFilename.resolveWithin(tmpDir.path, 'komet_dec_${ts}_$decName');

      final meta = await fc.decryptFile(filePath, decPath, keyBytes);

      // Вернём путь с правильным именем (из meta если есть). meta.originalName
      // — это plaintext, но всё равно из недоверенного источника, поэтому
      // санитизируем перед использованием в имени файла.
      final metaName = meta.originalName != null
          ? SafeFilename.sanitize(meta.originalName, fallback: decName)
          : decName;
      finalPath = SafeFilename.resolveWithin(tmpDir.path, '${ts}_$metaName');
      await File(decPath).rename(finalPath);
      decPath = null; // переименован → больше не наш для cleanup

      return finalPath;
    } catch (_) {
      // Чистим оба возможных temp-файла.
      if (decPath != null) {
        try { await File(decPath).delete(); } catch (_) {}
      }
      if (finalPath != null) {
        try { await File(finalPath).delete(); } catch (_) {}
      }
      return null;
    } finally {
      wipeBytes(keyBytes);
    }
  }

  /// Результат [tryDecryptToBytes] с явной семантикой.
  /// Заменяет старый ambiguous-null контракт.
  ///
  /// Состояния:
  ///   - [bytes] != null → успешно расшифровано.
  ///   - [bytes] == null && [notEncrypted] → файл не был зашифрован
  ///     (caller должен показать оригинал).
  ///   - [bytes] == null && [error] != null → ошибка расшифровки или
  ///     чтения. Caller может логировать [error] или показать заглушку.
  ///
  /// Старый код `await tryDecryptToBytes(...) == null` нужно мигрировать
  /// на проверку `result.bytes` или `result.notEncrypted`.
  Future<DecryptToBytesResult> tryDecryptToBytesResult({
    required int chatId,
    required String filePath,
  }) async {
    final mgr = MasterKeyManager.instance;
    if (!mgr.isUnlocked) {
      return DecryptToBytesResult(
        bytes: null,
        notEncrypted: false,
        error: 'master_locked',
      );
    }
    if (!await looksEncrypted(filePath)) {
      return DecryptToBytesResult(bytes: null, notEncrypted: true);
    }
    final decPath = await tryDecrypt(chatId: chatId, filePath: filePath);
    if (decPath == null) {
      return DecryptToBytesResult(
        bytes: null,
        notEncrypted: false,
        error: 'decrypt_failed',
      );
    }
    Uint8List? bytes;
    String? error;
    try {
      bytes = await File(decPath).readAsBytes();
    } catch (e) {
      bytes = null;
      error = 'read_failed: $e';
    } finally {
      // Удаляем временный расшифрованный файл независимо от успеха чтения.
      try { await File(decPath).delete(); } catch (_) {}
    }
    return DecryptToBytesResult(
      bytes: bytes,
      notEncrypted: false,
      error: error,
    );
  }

  /// Расшифровывает фото из файла → возвращает байты для отображения.
  /// Если файл не зашифрован — возвращает null.
  ///
  /// **Deprecated**: эта функция не различает «не зашифровано» и «ошибка
  /// расшифровки» — оба случая возвращают null. Используйте
  /// [tryDecryptToBytesResult] для явной семантики. Оставлено для
  /// совместимости с существующими call-сайтами.
  Future<Uint8List?> tryDecryptToBytes({
    required int chatId,
    required String filePath,
  }) async {
    final r = await tryDecryptToBytesResult(chatId: chatId, filePath: filePath);
    return r.bytes;
  }

  /// Генерирует маскированное имя файла для зашифрованного вложения.
  ///
  /// Оригинальное имя серверу не передаётся — оно сохраняется внутри
  /// CRPT-blob и восстанавливается при расшифровке у получателя.
  ///
  /// [profile] задаётся из [ChatEncryptionConfig.encryptedFileNameProfile].
  /// Неизвестный профиль сваливается на 'file_seq'.
  String encryptedFileName(
    String originalName,
    String ext, {
    String profile = 'file_seq',
  }) {
    return _generateName(profile, ext);
  }

  /// Список профилей маскировки имени файла для UI.
  static const List<({String id, String label, String example})>
      fileNameProfiles = [
    (
      id: 'file_seq',
      label: 'file_seq — стандартный (file_..._...)',
      example: 'file_1730551234567_42.bin',
    ),
    (
      id: 'random_hex',
      label: 'random_hex — случайный hex',
      example: 'a3f7b2c801d4e5f6.bin',
    ),
    (
      id: 'random_alphanum',
      label: 'random_alphanum — буквы+цифры',
      example: 'k7m3p9q2x1w8.bin',
    ),
    (
      id: 'uuid',
      label: 'uuid — UUID v4',
      example: '550e8400-e29b-41d4-a716-446655440000.bin',
    ),
    (
      id: 'document',
      label: 'document — под обычный документ',
      example: 'Document_4827.bin',
    ),
    (
      id: 'photo',
      label: 'photo — под фото с камеры',
      example: 'IMG_20260315_142233.bin',
    ),
    (
      id: 'screenshot',
      label: 'screenshot — под скриншот',
      example: 'Screenshot_2026-03-15_14-22-33.bin',
    ),
  ];

  // ----------- Внутренние генераторы -----------

  static final Random _rng = Random.secure();
  static const _hexChars = '0123456789abcdef';
  static const _alphanumChars = 'abcdefghijklmnopqrstuvwxyz0123456789';

  String _generateName(String profile, String ext) {
    switch (profile) {
      case 'random_hex':
        return '${_randomString(_hexChars, 16)}.$ext';

      case 'random_alphanum':
        return '${_randomString(_alphanumChars, 12)}.$ext';

      case 'uuid':
        return '${const Uuid().v4()}.$ext';

      case 'document':
        // 4-значный номер от 0001 до 9999
        final n = (_rng.nextInt(9999) + 1).toString().padLeft(4, '0');
        return 'Document_$n.$ext';

      case 'photo':
        // IMG_YYYYMMDD_HHMMSS — формат, в котором Android camera
        // сохраняет снимки.
        final now = DateTime.now();
        final stamp = '${now.year.toString().padLeft(4, '0')}'
            '${now.month.toString().padLeft(2, '0')}'
            '${now.day.toString().padLeft(2, '0')}'
            '_'
            '${now.hour.toString().padLeft(2, '0')}'
            '${now.minute.toString().padLeft(2, '0')}'
            '${now.second.toString().padLeft(2, '0')}';
        return 'IMG_$stamp.$ext';

      case 'screenshot':
        // Screenshot_YYYY-MM-DD_HH-MM-SS — формат, в котором Linux/macOS
        // сохраняют скриншоты.
        final now = DateTime.now();
        final stamp = '${now.year.toString().padLeft(4, '0')}-'
            '${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')}'
            '_'
            '${now.hour.toString().padLeft(2, '0')}-'
            '${now.minute.toString().padLeft(2, '0')}-'
            '${now.second.toString().padLeft(2, '0')}';
        return 'Screenshot_$stamp.$ext';

      case 'file_seq':
      default:
        // Дефолт + безопасный фолбэк для неизвестных профилей.
        final ts = DateTime.now().millisecondsSinceEpoch;
        final rng = DateTime.now().microsecondsSinceEpoch & 0xFFFF;
        return 'file_${ts}_$rng.$ext';
    }
  }

  String _randomString(String alphabet, int length) {
    final sb = StringBuffer();
    for (int i = 0; i < length; i++) {
      sb.write(alphabet[_rng.nextInt(alphabet.length)]);
    }
    return sb.toString();
  }
}

/// Результат [EncryptedFileService.tryDecryptToBytesResult] с явной
/// семантикой (взамен ambiguous-null контракта tryDecryptToBytes).
class DecryptToBytesResult {
  /// Расшифрованные байты, или null если расшифровка не удалась/не
  /// требовалась.
  final Uint8List? bytes;

  /// True, если файл не был зашифрован (нет CRPT-magic). В этом случае
  /// caller должен показать оригинальный файл как есть.
  final bool notEncrypted;

  /// Текстовый код ошибки (или null при успехе/нешифрованном файле).
  /// Возможные значения: 'master_locked', 'decrypt_failed',
  /// 'read_failed: <msg>'.
  final String? error;

  const DecryptToBytesResult({
    required this.bytes,
    this.notEncrypted = false,
    this.error,
  });

  /// True, если результат содержит расшифрованные байты.
  bool get isSuccess => bytes != null;
}
