// migration_v2.dart — миграция со старого XOR-шифрования на новое
// AES-GCM + Argon2id (PR 1 → PR 2).
//
// Сценарий: пользователь обновил KometOld со старой версии. У него в
// SharedPreferences лежат:
//   - encryption_pw_<chatId>: <plaintext-пароль>      (legacy v0)
//   - encryption_chat_<chatId>: {"password": "...", ...} (legacy v1, JSON)
//
// После миграции должно стать:
//   1. У пользователя задан мастер-пароль (Argon2id → master_key в RAM).
//   2. Для каждого старого чата:
//      - Сгенерирован случайный chat_key (32 байта).
//      - chat_key обёрнут master_key и сохранён в Secure Storage.
//      - В JSON-конфиге чата:
//          password = "kk2:<base64-32>" (новый ключ)
//          legacyXorPassword = "<старый plaintext>" (для чтения архива)
//          sendEncrypted = true (как было)
//   3. В Secure Storage установлен флаг
//      MasterKeyManager.kMigrationCompletedFlag = "true".
//
// Детектор `needsMigration()` возвращает true, если:
//   - Есть хотя бы один SharedPreferences-ключ с префиксом
//     encryption_pw_ или encryption_chat_, И
//   - В Secure Storage НЕТ флага миграции.
//
// `migrate(masterPassword)`:
//   1. setupMasterPassword(masterPassword) → master_key в RAM.
//   2. Для каждого старого чата вызывает _migrateOneChat(chatId).
//   3. Ставит флаг миграции.
//
// Прогресс-колбэк: (current, total, chatId).
//
// Откат: если миграция упала на полпути — флаг не ставится. При повторном
// запуске уже обработанные чаты не трогаются (идемпотентность через
// проверку «есть ли уже kk2:» в конфиге).

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'chat_encryption_service.dart';
import 'crypt/master_key_manager.dart';

// F-NEW: префиксы перенесены в публичные статические поля
// ChatEncryptionService (см. ниже). Раньше здесь были свои копии
// `ChatEncryptionService.legacyPasswordKeyPrefix` и `ChatEncryptionService.configKeyPrefix`, которые могли
// рассинхронизироваться при правках в одном месте.

/// Колбэк прогресса миграции.
typedef MigrationProgress = void Function(
  int current,
  int total,
  int? currentChatId,
);

/// Результат миграции — для UI диагностики.
class MigrationResult {
  final int chatsTotal;
  final int chatsMigrated;
  final int chatsSkipped;
  final int chatsFailed;
  final List<String> errors;

  MigrationResult({
    required this.chatsTotal,
    required this.chatsMigrated,
    required this.chatsSkipped,
    required this.chatsFailed,
    required this.errors,
  });

  bool get hasErrors => chatsFailed > 0;
}

class MigrationV2 {
  /// True, если в SharedPreferences есть хотя бы один legacy-ключ И
  /// миграция не была завершена.
  static Future<bool> needsMigration() async {
    // Если флаг миграции стоит — больше ничего не нужно.
    final mgr = MasterKeyManager.instance;
    if (await mgr.isInitialized()) {
      // master_key установлен — это уже после миграции (или приложение
      // было установлено сразу с PR 1+, без legacy-чатов).
      return false;
    }

    // Проверяем есть ли хоть один legacy-ключ.
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (final k in keys) {
      if (k.startsWith(ChatEncryptionService.legacyPasswordKeyPrefix) ||
          k.startsWith(ChatEncryptionService.configKeyPrefix)) {
        return true;
      }
    }
    return false;
  }

  /// Перечисляет все chatId, которые требуют миграции (есть legacy-конфиг,
  /// но нет нового kk2-ключа).
  static Future<List<int>> _findLegacyChatIds() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = <int>{};
    for (final k in prefs.getKeys()) {
      if (k.startsWith(ChatEncryptionService.legacyPasswordKeyPrefix)) {
        final s = k.substring(ChatEncryptionService.legacyPasswordKeyPrefix.length);
        final id = int.tryParse(s);
        if (id != null) ids.add(id);
      } else if (k.startsWith(ChatEncryptionService.configKeyPrefix)) {
        final s = k.substring(ChatEncryptionService.configKeyPrefix.length);
        final id = int.tryParse(s);
        if (id != null) ids.add(id);
      }
    }
    return ids.toList()..sort();
  }

  /// Главная процедура миграции. Должна вызываться ОДИН раз при первом
  /// запуске после обновления.
  ///
  /// Если мастер-пароль уже установлен — бросает [StateError] (используй
  /// [migrateAfterMasterReady] для случая когда master уже unlocked).
  static Future<MigrationResult> migrate(
    String masterPassword, {
    String argon2Profile = 'balanced',
    MigrationProgress? onProgress,
  }) async {
    final mgr = MasterKeyManager.instance;
    if (await mgr.isInitialized()) {
      throw StateError(
        'Мастер-пароль уже установлен — используй migrateAfterMasterReady',
      );
    }

    // 1. Настраиваем мастер-пароль.
    await mgr.setupMasterPassword(
      masterPassword,
      argon2Profile: argon2Profile,
    );

    // 2. Запускаем фактическую миграцию.
    return _migrateAllChats(onProgress: onProgress);
  }

  /// Миграция, когда мастер уже разблокирован (например, пользователь
  /// в настройках выбрал «мигрировать остальные старые чаты»).
  static Future<MigrationResult> migrateAfterMasterReady({
    MigrationProgress? onProgress,
  }) async {
    final mgr = MasterKeyManager.instance;
    if (!mgr.isUnlocked) {
      throw MasterLockedException(
        'Мастер должен быть разблокирован для миграции',
      );
    }
    return _migrateAllChats(onProgress: onProgress);
  }

  static Future<MigrationResult> _migrateAllChats({
    MigrationProgress? onProgress,
  }) async {
    final ids = await _findLegacyChatIds();

    var migrated = 0;
    var skipped = 0;
    var failed = 0;
    final errors = <String>[];

    for (var i = 0; i < ids.length; i++) {
      final id = ids[i];
      onProgress?.call(i + 1, ids.length, id);
      try {
        final result = await _migrateOneChat(id);
        if (result == _ChatMigrationOutcome.migrated) migrated++;
        if (result == _ChatMigrationOutcome.alreadyMigrated) skipped++;
      } catch (e) {
        failed++;
        // Сохраняем только тип ошибки и сообщение, БЕЗ stack trace —
        // stack может содержать пути к ключам в Secure Storage и другие
        // sensitive данные. См. SECURITY.md.
        errors.add('chat $id: ${e.runtimeType}: $e');
        // Не прерываем всю миграцию из-за одного чата — продолжаем с
        // остальными. Этот чат можно мигрировать позже из настроек.
      }
    }

    // Помечаем миграцию завершённой только если ВСЕ чаты прошли (или
    // были уже мигрированы). Если есть failed — пользователь сам решит,
    // что делать дальше через UI «Зашифрованные чаты с проблемами».
    if (failed == 0) {
      await _markCompleted();
    }

    return MigrationResult(
      chatsTotal: ids.length,
      chatsMigrated: migrated,
      chatsSkipped: skipped,
      chatsFailed: failed,
      errors: errors,
    );
  }

  static Future<_ChatMigrationOutcome> _migrateOneChat(int chatId) async {
    final prefs = await SharedPreferences.getInstance();

    // Считываем существующий конфиг (или эмулируем legacy v0).
    ChatEncryptionConfig? cfg;
    final configJson = prefs.getString('${ChatEncryptionService.configKeyPrefix}$chatId');
    if (configJson != null) {
      try {
        cfg = ChatEncryptionConfig.fromJson(
          jsonDecode(configJson) as Map<String, dynamic>,
        );
      } catch (_) {
        cfg = null;
      }
    }
    if (cfg == null) {
      // Очень старый формат — отдельный SharedPreferences-ключ с паролем.
      final pw = prefs.getString('${ChatEncryptionService.legacyPasswordKeyPrefix}$chatId');
      if (pw != null && pw.isNotEmpty) {
        cfg = ChatEncryptionConfig(
          password: pw,
          sendEncrypted: true,
          legacyXorPassword: pw,
        );
      }
    }
    if (cfg == null) {
      // Этого не должно быть, но если случилось — пропускаем.
      return _ChatMigrationOutcome.skippedNoConfig;
    }

    // Идемпотентность: если уже мигрирован — пропускаем.
    if (ChatEncryptionService.hasNewKey(cfg)) {
      return _ChatMigrationOutcome.alreadyMigrated;
    }

    // Сохраняем старый XOR-пароль (если был).
    final legacyXor = cfg.legacyXorPassword ?? cfg.password;

    // Создаём новый chat_key через MasterKeyManager. Сам ключ остаётся
    // в Secure Storage; в JSON-конфиге кладём только ссылку kk2r:<chatId>.
    final mgr = MasterKeyManager.instance;
    await mgr.getOrCreateChatKey(chatId);
    final serialized = ChatEncryptionService.serializeChatKey(chatId);

    final newCfg = ChatEncryptionConfig(
      password: serialized,
      sendEncrypted: cfg.sendEncrypted,
      legacyXorPassword: legacyXor,
      obfuscationProfile: cfg.obfuscationProfile,
    );
    await prefs.setString(
      '${ChatEncryptionService.configKeyPrefix}$chatId',
      jsonEncode(newCfg.toJson()),
    );

    // Старый отдельный ключ encryption_pw_<chatId> можно удалить —
    // пароль теперь хранится в новом JSON под legacyXorPassword.
    await prefs.remove('${ChatEncryptionService.legacyPasswordKeyPrefix}$chatId');

    return _ChatMigrationOutcome.migrated;
  }

  /// Помечает миграцию завершённой.
  static Future<void> _markCompleted() async {
    final mgr = MasterKeyManager.instance;
    // Используем то же storage, что и MasterKeyManager — Secure Storage.
    // Для простоты тут обращаемся через SharedPreferences (не критично
    // для безопасности — это просто флаг «прошла ли миграция», его
    // подделка не даёт никакой выгоды злоумышленнику).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(MasterKeyManager.kMigrationCompletedFlag, true);
  }

  /// True, если миграция уже была завершена.
  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(MasterKeyManager.kMigrationCompletedFlag) ?? false;
  }
}

enum _ChatMigrationOutcome {
  migrated,
  alreadyMigrated,
  skippedNoConfig,
}
