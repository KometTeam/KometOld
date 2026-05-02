// encrypted_attachment_service.dart — обёртка над file_crypto.dart для
// шифрования вложений в чате.
//
// Использование:
//
//   // Отправитель:
//   final encrypted = await EncryptedAttachmentService.encryptForChat(
//     chatId: 42,
//     inputPath: '/storage/.../photo.jpg',
//   );
//   // → возвращает путь к зашифрованному файлу + метаданные.
//   // UI отправляет encrypted.encryptedPath по обычному pipeline MAX.
//
//   // Получатель:
//   final decrypted = await EncryptedAttachmentService.decryptForChat(
//     chatId: 42,
//     inputPath: '/cache/downloaded.crpt',
//   );
//   // → возвращает путь к расшифрованному файлу + оригинальное имя.
//
// Где хранятся файлы:
//   - Зашифрованные исходящие: <tempDir>/komet_enc/<chatId>/<uuid>.crpt
//     (отправляются и удаляются после успешной отправки)
//   - Расшифрованные входящие: <tempDir>/komet_dec/<chatId>/<originalName>
//     (хранятся пока пользователь смотрит, потом чистятся)

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'crypt/file_crypto.dart' as fc;
import 'crypt/master_key_manager.dart';
import 'crypt/safe_filename.dart';

/// Результат шифрования файла перед отправкой.
class EncryptedAttachment {
  /// Путь к зашифрованному .crpt файлу (готов к отправке).
  final String encryptedPath;

  /// Размер зашифрованного файла на диске.
  final int encryptedSize;

  /// Оригинальное имя (для UI).
  final String originalName;

  /// Размер оригинала.
  final int originalSize;

  EncryptedAttachment({
    required this.encryptedPath,
    required this.encryptedSize,
    required this.originalName,
    required this.originalSize,
  });
}

/// Результат расшифровки.
class DecryptedAttachment {
  final String decryptedPath;
  final String? originalName;
  final int? originalSize;

  DecryptedAttachment({
    required this.decryptedPath,
    this.originalName,
    this.originalSize,
  });
}

class EncryptedAttachmentService {
  static const _uuid = Uuid();

  /// Зашифровывает файл для чата [chatId].
  /// Если у чата нет ключа или мастер заблокирован — бросает.
  static Future<EncryptedAttachment> encryptForChat({
    required int chatId,
    required String inputPath,
    bool hideName = false,
    fc.ProgressCallback? progress,
  }) async {
    final mgr = MasterKeyManager.instance;
    if (!mgr.isUnlocked) {
      throw MasterLockedException(
        'Сначала разблокируйте приложение',
      );
    }

    final secret = await mgr.getOrCreateChatKey(chatId);
    final keyBytes = secret.exposeCopy();

    try {
      final tempRoot = await getTemporaryDirectory();
      final outDir = Directory(p.join(tempRoot.path, 'komet_enc', '$chatId'));
      await outDir.create(recursive: true);

      final outPath = p.join(outDir.path, '${_uuid.v4()}.crpt');
      final input = File(inputPath);
      final originalSize = await input.length();
      // Санитизируем имя — даже на отправке в meta (отправитель сам себя
      // не атакует, но если код когда-то начнёт принимать имена извне
      // через API — лучше пресечь сразу).
      final originalName = SafeFilename.sanitize(p.basename(inputPath));

      await fc.encryptFile(
        inputPath,
        outPath,
        keyBytes,
        options: fc.EncryptFileOptions(
          hideName: hideName,
          contactId: 'chat:$chatId',
        ),
        progress: progress,
      );

      final encryptedSize = await File(outPath).length();
      return EncryptedAttachment(
        encryptedPath: outPath,
        encryptedSize: encryptedSize,
        originalName: originalName,
        originalSize: originalSize,
      );
    } finally {
      // Затираем копию ключа.
      for (var i = 0; i < keyBytes.length; i++) {
        keyBytes[i] = 0;
      }
    }
  }

  /// Расшифровывает входящий файл для чата.
  static Future<DecryptedAttachment> decryptForChat({
    required int chatId,
    required String inputPath,
    String? extraPassword,
    fc.ProgressCallback? progress,
  }) async {
    final mgr = MasterKeyManager.instance;
    if (!mgr.isUnlocked) {
      throw MasterLockedException(
        'Сначала разблокируйте приложение',
      );
    }

    final secret = await mgr.getOrCreateChatKey(chatId);
    final keyBytes = secret.exposeCopy();

    try {
      final tempRoot = await getTemporaryDirectory();
      final outDir = Directory(p.join(tempRoot.path, 'komet_dec', '$chatId'));
      await outDir.create(recursive: true);

      // Узнаём оригинальное имя из meta (peek без расшифровки).
      // ВАЖНО: имя приходит из meta зашифрованного файла, который мог
      // прислать злоумышленник. Без санитизации `original_name` со
      // значением "../../etc/passwd" привёл бы к записи за пределами
      // outDir. SafeFilename.resolveWithin страхует двойной защитой:
      // сначала чистит имя, потом валидирует итоговый путь.
      String fallbackName = '${_uuid.v4()}.bin';
      try {
        final meta = await fc.peekFileMeta(inputPath);
        final n = meta['original_name'] as String?;
        if (n != null && n.isNotEmpty) {
          fallbackName = SafeFilename.sanitize(n, fallback: fallbackName);
        }
      } catch (_) {
        // Если peek упал — используем uuid имя.
      }

      final outPath = SafeFilename.resolveWithin(outDir.path, fallbackName);

      final decMeta = await fc.decryptFile(
        inputPath,
        outPath,
        keyBytes,
        extraPassword: extraPassword,
        progress: progress,
      );

      // Имя из private_meta (после расшифровки) — тоже из недоверенного
      // источника. Возвращаем санитизированное имя в UI, чтобы виджеты
      // ниже не использовали "сырой" original_name для построения путей.
      final returnedName = decMeta.originalName != null
          ? SafeFilename.sanitize(decMeta.originalName, fallback: fallbackName)
          : fallbackName;

      return DecryptedAttachment(
        decryptedPath: outPath,
        originalName: returnedName,
        originalSize: decMeta.originalSize,
      );
    } finally {
      for (var i = 0; i < keyBytes.length; i++) {
        keyBytes[i] = 0;
      }
    }
  }

  /// Чистит временные зашифрованные/расшифрованные файлы (например, при
  /// выходе из чата или закрытии приложения).
  static Future<void> cleanupTempFiles({int? chatId}) async {
    final tempRoot = await getTemporaryDirectory();
    for (final sub in const ['komet_enc', 'komet_dec']) {
      final root = Directory(p.join(tempRoot.path, sub));
      if (!await root.exists()) continue;
      if (chatId != null) {
        final chatDir = Directory(p.join(root.path, '$chatId'));
        if (await chatDir.exists()) {
          await chatDir.delete(recursive: true);
        }
      } else {
        await root.delete(recursive: true);
      }
    }
  }
}
