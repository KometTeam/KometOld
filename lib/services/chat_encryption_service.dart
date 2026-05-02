// chat_encryption_service.dart — обновлённый публичный API шифрования чатов.
//
// КЛЮЧЕВОЕ ТРЕБОВАНИЕ: НЕ ИЗМЕНЯТЬ публичные сигнатуры — chat_screen.dart
// и chat_message_bubble.dart остаются нетронутыми.
//
// Старые сигнатуры:
//   - encryptWithPassword(String password, String plaintext) → String
//   - decryptWithPassword(String password, String text) → String?
//   - isEncryptedMessage(String text) → bool
//   - getConfigForChat(int chatId) → Future<ChatEncryptionConfig?>
//   - setPasswordForChat / setSendEncryptedForChat → Future<void>
//
// Что изменилось внутри:
//   1. ChatEncryptionConfig.password в новом формате содержит сериализо-
//      ванный chat_key: "kk2:<base64-32-байт>". chat_screen и bubble
//      работают с этим как с непрозрачной строкой.
//   2. encryptWithPassword распознаёт префикс "kk2:" → AES-GCM(chat_key, ...).
//      Если префикса нет — это plaintext-пароль из старого конфига, ещё не
//      мигрированного. В этом случае возвращаем plaintext без шифрования
//      (лучше не зашифровать совсем, чем выпустить XOR через слабую логику).
//   3. decryptWithPassword пробует:
//        a) если password в kk2-формате — пробует AES-GCM
//        b) если в конфиге чата есть legacyXorPassword — пробует XOR
//        c) иначе — возвращает null
//   4. getConfigForChat лениво докладывает legacyXorPassword из старого
//      JSON в новый, не запуская Argon2id (этот тяжёлый шаг — в migration_v2).
//
// Декомпозиция вызовов:
//   - chat_screen.encryptWithPassword(cfg.password, text)
//        → если cfg.password = "kk2:..." → шифрование AES-GCM
//        → если cfg.password = старый plaintext-пароль → НЕ шифруем
//          (значит мастер-пароль ещё не задан, чат в режиме «передача
//          plain до миграции»; UI должен показать предупреждение)
//   - bubble.decryptWithPassword(cfg.password, ciphertext)
//        → если text похож на legacy → decryptLegacy(legacyXorPassword)
//        → если text похож на новый формат → AES-GCM(chat_key из kk2)
//        → иначе null

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'crypt/crypt_format.dart';
import 'crypt/legacy_xor_codec.dart' as legacy;
import 'crypt/master_key_manager.dart';
import 'crypt/text_codec.dart' as tc;

/// Конфиг шифрования чата. Поле `password` сохраняет совместимость со старым
/// JSON: для нового формата хранит "kk2:base64key", для немигрированного —
/// старый plaintext-пароль.
///
/// Новое поле `legacyXorPassword` появилось в v2: это пароль, которым
/// читаются исторические XOR-сообщения (read-only).
class ChatEncryptionConfig {
  /// Содержит либо "kk2:<base64-32>" (новый формат, mapping на chat_key
  /// в Secure Storage), либо старый plaintext-пароль (немигрированный
  /// чат), либо пустую строку (шифрование не настроено).
  final String password;

  /// Должны ли отправляться сообщения зашифрованными.
  final bool sendEncrypted;

  /// Read-only legacy XOR-пароль для расшифровки СТАРЫХ сообщений.
  final String? legacyXorPassword;

  /// Имя профиля text_codec для исходящего шифрования.
  /// По умолчанию 'ru_full'.
  final String obfuscationProfile;

  /// Расширение зашифрованных файлов для этого чата.
  /// По умолчанию 'bin'. Может быть любым: 'txt', 'dat', 'log', 'kbak'
  /// или пользовательским. Без точки.
  final String encryptedFileExtension;

  /// Профиль маскировки имени зашифрованного файла. Возможные значения:
  /// - 'file_seq'         — file_<ts>_<rng>.<ext> (дефолт, обр. совместимость)
  /// - 'random_hex'       — <16-hex>.<ext>
  /// - 'random_alphanum'  — <12-[a-z0-9]>.<ext>
  /// - 'uuid'             — <uuid-v4>.<ext>
  /// - 'document'         — Document_<NNNN>.<ext>
  /// - 'photo'            — IMG_<YYYYMMDD>_<HHMMSS>.<ext>
  /// - 'screenshot'       — Screenshot_<YYYY-MM-DD>_<HH-MM-SS>.<ext>
  /// Реальная генерация происходит в EncryptedFileService.encryptedFileName.
  final String encryptedFileNameProfile;

  /// Шифровать ли отправляемые файлы и фото.
  final bool encryptFiles;

  ChatEncryptionConfig({
    required this.password,
    required this.sendEncrypted,
    this.legacyXorPassword,
    this.obfuscationProfile = 'ru_full',
    this.encryptedFileExtension = 'bin',
    this.encryptedFileNameProfile = 'file_seq',
    this.encryptFiles = true,
  });

  Map<String, dynamic> toJson() => {
        'password': password,
        'sendEncrypted': sendEncrypted,
        if (legacyXorPassword != null) 'legacyXorPassword': legacyXorPassword,
        'obfuscationProfile': obfuscationProfile,
        'encryptedFileExtension': encryptedFileExtension,
        'encryptedFileNameProfile': encryptedFileNameProfile,
        'encryptFiles': encryptFiles,
      };

  factory ChatEncryptionConfig.fromJson(Map<String, dynamic> json) {
    return ChatEncryptionConfig(
      password: (json['password'] as String?) ?? '',
      sendEncrypted: (json['sendEncrypted'] as bool?) ?? true,
      legacyXorPassword: json['legacyXorPassword'] as String?,
      obfuscationProfile:
          (json['obfuscationProfile'] as String?) ?? 'ru_full',
      encryptedFileExtension:
          (json['encryptedFileExtension'] as String?) ?? 'bin',
      encryptedFileNameProfile:
          (json['encryptedFileNameProfile'] as String?) ?? 'file_seq',
      encryptFiles: (json['encryptFiles'] as bool?) ?? true,
    );
  }

  ChatEncryptionConfig copyWith({
    String? password,
    bool? sendEncrypted,
    String? legacyXorPassword,
    String? obfuscationProfile,
    String? encryptedFileExtension,
    String? encryptedFileNameProfile,
    bool? encryptFiles,
  }) {
    return ChatEncryptionConfig(
      password: password ?? this.password,
      sendEncrypted: sendEncrypted ?? this.sendEncrypted,
      legacyXorPassword: legacyXorPassword ?? this.legacyXorPassword,
      obfuscationProfile: obfuscationProfile ?? this.obfuscationProfile,
      encryptedFileExtension:
          encryptedFileExtension ?? this.encryptedFileExtension,
      encryptedFileNameProfile:
          encryptedFileNameProfile ?? this.encryptedFileNameProfile,
      encryptFiles: encryptFiles ?? this.encryptFiles,
    );
  }
}

class ChatEncryptionService {
  // Префиксы Shared Preferences (старые остаются как были).
  // F-NEW: вынесены как `static const` (без подчёркивания), чтобы
  // migration_v2 и другие модули могли ссылаться на тот же источник
  // и не рассинхронизировать имена ключей при правках.
  static const String legacyPasswordKeyPrefix = 'encryption_pw_';
  static const String configKeyPrefix = 'encryption_chat_';

  // Внутренние алиасы для обратной совместимости со старыми ссылками
  // в этом же файле (чтобы не править десятки строк ниже).
  static const String _legacyPasswordKeyPrefix = legacyPasswordKeyPrefix;
  static const String _configKeyPrefix = configKeyPrefix;

  // Маркер reference: ключ хранится в Secure Storage MasterKeyManager,
  // в SharedPreferences кладём только ссылку kk2r:<chatId>. Это новый
  // безопасный формат с PR-fix.
  static const String _keyRefPrefix = 'kk2r:';

  // СТАРЫЙ маркер: ключ был base64-закодирован в SharedPreferences.
  // Это была дыра в безопасности — ключ лежал в незашифрованном
  // SharedPreferences. Оставлен только для чтения; при первом сохранении
  // конфига такие записи переписываются в kk2r:.
  static const String _keyPrefixLegacy = 'kk2:';

  /// Старый префикс kometSM. оставлен для совместимости (legacy_xor_codec).
  static const String encryptedPrefix = legacy.legacyEncryptedPrefix;

  // Дефолтный профиль обфускации, если в конфиге не указан.
  static const String defaultObfuscationProfile = 'ru_full';

  // ====================================================================== //
  //                          isEncryptedMessage
  // ====================================================================== //

  /// Эвристика «похоже ли это на зашифрованное сообщение». Используется
  /// chat_screen.dart на ИСХОДЯЩИХ сообщениях (чтобы не дважды шифровать
  /// уже зашифрованный текст) и chat_message_bubble.dart на ВХОДЯЩИХ.
  ///
  /// Без префиксов в новом формате эвристика основана на:
  ///   1. Маркеры старого формата (kometSM. / digit-prefix+привет/незнаю/хм)
  ///   2. Длинная строка из символов алфавита text_codec без явного
  ///      пробельного шума читаемого текста.
  ///
  /// Если эвристика даёт false-positive — decryptWithPassword вернёт null
  /// (AES-GCM tag не сойдётся), и UI покажет оригинальный текст. Это
  /// безопасный режим деградации.
  static bool isEncryptedMessage(String text) {
    if (text.isEmpty) return false;
    if (legacy.looksLikeLegacy(text)) return true;
    return _looksLikeNewFormat(text);
  }

  /// Эвристика для нового формата (text_codec обфускация blob).
  ///
  /// Признаки:
  /// - Длина ≥ 30 символов (12-байтный nonce + 16-байтный tag + ≥1 байт
  ///   payload + JSON meta = минимум ~30 байт ≈ 40+ символов в ru_full).
  /// - Все runes — из объединённого алфавита всех профилей text_codec
  ///   плюс ASCII (для base64 как fallback).
  /// - Содержит хотя бы один пробел (маскировка) ИЛИ только base64 chars.
  static bool _looksLikeNewFormat(String text) {
    if (text.length < 30) return false;
    final stripped = text.replaceAll(' ', '');
    if (stripped.length < 30) return false;

    // Сначала проверяем — может это base64 (default_codec = base64)
    final b64 = RegExp(r'^[A-Za-z0-9+/=]+$');
    if (b64.hasMatch(stripped)) {
      // Слишком короткое для шифровки — не считаем
      return stripped.length >= 40;
    }

    // Проверяем алфавит text_codec
    final union = tc.unionAlphabet();
    for (final r in stripped.runes) {
      if (!union.contains(r)) return false;
    }
    // Если прошли проверку алфавита — должно быть достаточно длинным
    return true;
  }

  // ====================================================================== //
  //                         КОНФИГ ЧАТА (async)
  // ====================================================================== //

  static Future<ChatEncryptionConfig?> getConfigForChat(int chatId) async {
    final prefs = await SharedPreferences.getInstance();

    // Новый JSON-формат
    final configJson = prefs.getString('$_configKeyPrefix$chatId');
    if (configJson != null) {
      try {
        final data = jsonDecode(configJson) as Map<String, dynamic>;
        final cfg = ChatEncryptionConfig.fromJson(data);
        // Прогреваем кэш профиля для sync-вызовов encryptWithPassword.
        _obfuscationProfileCache[chatId] = cfg.obfuscationProfile;
        return cfg;
      } catch (_) {
        // Битый JSON — игнорируем, провалимся на legacy ниже.
      }
    }

    // Совсем старый формат: только plaintext-пароль в отдельном ключе.
    final legacyPassword = prefs.getString('$_legacyPasswordKeyPrefix$chatId');
    if (legacyPassword != null && legacyPassword.isNotEmpty) {
      final cfg = ChatEncryptionConfig(
        password: legacyPassword, // ещё не мигрировано
        sendEncrypted: true,
        legacyXorPassword: legacyPassword, // для чтения архива
      );
      await _saveConfig(chatId, cfg);
      return cfg;
    }

    return null;
  }

  static Future<void> _saveConfig(
    int chatId,
    ChatEncryptionConfig config,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_configKeyPrefix$chatId',
      jsonEncode(config.toJson()),
    );
    _obfuscationProfileCache[chatId] = config.obfuscationProfile;
  }

  /// Публичная обёртка для атомарной перезаписи всего конфига чата.
  /// Используется при импорте ключа (key_share_import_screen).
  static Future<void> saveRawConfigForChat(
    int chatId,
    ChatEncryptionConfig config,
  ) async {
    await _saveConfig(chatId, config);
  }

  /// Удалить конфиг чата (например, при выключении шифрования). НЕ удаляет
  /// legacyXorPassword из storage сам по себе — этим занимается
  /// MasterKeyManager.removeChatKey() через migration_v2.
  static Future<void> deleteConfig(int chatId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_configKeyPrefix$chatId');
    await prefs.remove('$_legacyPasswordKeyPrefix$chatId');
    _obfuscationProfileCache.remove(chatId);
  }

  /// СТАРАЯ сигнатура: задать пароль чата. В новой архитектуре пароль чата
  /// как сущность не существует — есть только chat_key (случайный, обёрнут
  /// мастер-паролем). Этот метод оставлен ради совместимости с UI (если
  /// chat_encryption_settings_screen.dart вызывает его), но реальная
  /// работа делается так:
  ///
  ///   - Если master разблокирован → создаётся/перезатягивается chat_key,
  ///     поле `password` в конфиге становится "kk2:<base64>".
  ///   - Если master НЕ разблокирован → бросаем [MasterLockedException].
  ///
  /// **Параметр `password`** в новой архитектуре игнорируется (chat_key
  /// случайный). Этот параметр оставлен только из совместимости.
  static Future<void> setPasswordForChat(int chatId, String password) async {
    // ignore: unused_parameter
    // ^ password игнорируется в новой архитектуре. Оставлен ради
    // совместимости с местами, которые передают его.
    final mgr = MasterKeyManager.instance;
    if (!mgr.isUnlocked) {
      throw MasterLockedException(
        'Сначала разблокируйте мастер-пароль',
      );
    }

    // Создаём ключ в Secure Storage (если его ещё нет) — но НЕ копируем
    // его в JSON. В конфиге храним только reference kk2r:<chatId>.
    await mgr.getOrCreateChatKey(chatId);
    final serialized = '$_keyRefPrefix$chatId';

    final current = await getConfigForChat(chatId);
    // F-NEW fix: при создании нового конфига сохраняем все поля с
    // дефолтами. Раньше передавался только {password, sendEncrypted},
    // что молча сбрасывало legacyXorPassword, obfuscationProfile,
    // encryptedFileExtension и encryptFiles при первом включении
    // шифрования из чата без существующего конфига.
    final updated = current != null
        ? current.copyWith(password: serialized)
        : ChatEncryptionConfig(
            password: serialized,
            sendEncrypted: true,
            // legacyXorPassword: null — этого ключа просто не было.
            // Дальше ChatEncryptionConfig применит свои дефолты для
            // obfuscationProfile, encryptedFileExtension, encryptFiles.
          );
    await _saveConfig(chatId, updated);
  }

  static Future<void> setSendEncryptedForChat(int chatId, bool enabled) async {
    final current = await getConfigForChat(chatId);
    // F-NEW fix: при создании нового конфига (current == null) — сохраняем
    // дефолтные значения других полей через конструктор. Раньше явно
    // передавалось только {password: '', sendEncrypted}, что выглядело
    // одинаково, но было fragile при добавлении новых полей в конфиг.
    final updated = current != null
        ? current.copyWith(sendEncrypted: enabled)
        : ChatEncryptionConfig(
            password: '',
            sendEncrypted: enabled,
          );
    await _saveConfig(chatId, updated);
  }

  static Future<String?> getPasswordForChat(int chatId) async {
    final cfg = await getConfigForChat(chatId);
    return cfg?.password;
  }

  static Future<bool> isSendEncryptedEnabled(int chatId) async {
    final cfg = await getConfigForChat(chatId);
    return cfg?.sendEncrypted ?? true;
  }

  // ====================================================================== //
  //                         ШИФРОВАНИЕ (sync)
  // ====================================================================== //

  /// Шифрует [plaintext] с помощью [keyOrPassword].
  ///
  /// - Если [keyOrPassword] начинается с "kk2r:<chatId>" (новый безопасный
  ///   формат) → берёт chat_key из RAM-кэша MasterKeyManager.
  /// - Если "kk2:<base64-32>" (старый небезопасный формат, будет вычищен)
  ///   → AES-GCM(chat_key из base64, ...).
  /// - Иначе (старый plaintext-пароль) → возвращает [plaintext] БЕЗ
  ///   шифрования. Безопасное поведение для немигрированного состояния:
  ///   лучше не шифровать совсем, чем использовать сломанный XOR.
  ///
  /// [profileName] — профиль обфускации (из ChatEncryptionConfig.obfuscationProfile).
  /// Если не передан — используется [defaultObfuscationProfile].
  static String encryptWithPassword(
    String keyOrPassword,
    String plaintext, {
    String profileName = defaultObfuscationProfile,
  }) {
    // Новый безопасный формат: reference на ключ в Secure Storage.
    if (keyOrPassword.startsWith(_keyRefPrefix)) {
      final chatId =
          int.tryParse(keyOrPassword.substring(_keyRefPrefix.length));
      if (chatId == null) return plaintext;
      final secret = MasterKeyManager.instance.getCachedChatKey(chatId);
      if (secret == null) {
        // Ключ не в кэше — возвращаем plaintext (caller должен был prefetch'нуть).
        return plaintext;
      }
      return _encryptWithKey(
        secret.unsafeView(),
        plaintext,
        profileName: profileName,
      );
    }

    // Legacy: ключ в открытом виде в строке (небезопасно, но читаем).
    if (keyOrPassword.startsWith(_keyPrefixLegacy)) {
      final keyBytes = _parseLegacyKey(keyOrPassword);
      if (keyBytes == null) return plaintext;
      return _encryptWithKey(keyBytes, plaintext, profileName: profileName);
    }

    // Немигрированный конфиг. UI должен был перевести пользователя через
    // экран миграции до этой точки — значит, тут что-то пошло не так.
    // Безопасный фолбэк: возвращаем plaintext.
    return plaintext;
  }

  /// Шифрование с явным [chatKey] (32 байта) и опциональным выбором профиля.
  /// Используется migration_v2 и тестами.
  static String encryptForChatKey(
    Uint8List chatKey,
    String plaintext, {
    String profileName = defaultObfuscationProfile,
  }) {
    return _encryptWithKey(chatKey, plaintext, profileName: profileName);
  }

  // Кэш профилей обфускации по chatId — заполняется в getConfigForChat()
  // и сбрасывается в deleteConfig(). Нужен потому что encryptWithPassword
  // sync, а SharedPreferences async.
  static final Map<int, String> _obfuscationProfileCache = {};

  /// Возвращает профиль обфускации для чата из кэша, или дефолт.
  static String getCachedObfuscationProfile(int chatId) {
    return _obfuscationProfileCache[chatId] ?? defaultObfuscationProfile;
  }

  /// Шифрует с профилем обфускации из кэша по chatId.
  static String encryptForChat(
    int chatId,
    String keyOrPassword,
    String plaintext,
  ) {
    return encryptWithPassword(
      keyOrPassword,
      plaintext,
      profileName: getCachedObfuscationProfile(chatId),
    );
  }

  static String _encryptWithKey(
    Uint8List chatKey,
    String plaintext, {
    String profileName = defaultObfuscationProfile,
  }) {
    if (chatKey.length != 32) {
      throw ArgumentError('chat_key must be 32 bytes');
    }

    final blob = packEncrypted(
      key: chatKey,
      plaintext: Uint8List.fromList(utf8.encode(plaintext)),
      publicMeta: {'v': 2},
    );

    // Выбор профиля: для длинных blob → ru_full (bits-режим), для коротких
    // — выбранный пользователем (включая base_n). Если запрошенный профиль
    // не поддерживает blob такого размера (base_n > 255 байт), молча
    // переключаемся на ru_full (как договаривались).
    final profile = _resolveProfileForBlob(profileName, blob.length);
    return tc.encode(blob, profile: profile);
  }

  static String _resolveProfileForBlob(String requested, int blobLen) {
    if (!tc.hasProfile(requested)) {
      // F-NEW fix: fallback порядок детерминированный — берём
      // первый доступный из приоритетного списка. Раньше
      // `tc.profileNames().first` зависел от порядка вставки в Map,
      // что могло выдавать любой профиль.
      const fallbackOrder = ['ru_full', 'compact', 'ru_max', 'tiny'];
      for (final name in fallbackOrder) {
        if (tc.hasProfile(name)) return name;
      }
      // Если совсем ничего нет — берём первый что есть (теоретически
      // невозможно, но не падаем).
      final all = tc.profileNames();
      if (all.isEmpty) {
        throw StateError('No text_codec profiles registered');
      }
      return all.first;
    }
    final mode = tc.getProfileMode(requested);
    if (mode == 'base_n' && blobLen > tc.maxBaseNBlobLen) {
      // Слишком длинный blob для base_n — переключаемся на ru_full.
      return 'ru_full';
    }
    return requested;
  }

  // ====================================================================== //
  //                         РАСШИФРОВКА (sync)
  // ====================================================================== //

  /// Расшифровывает [text] с помощью [keyOrPassword].
  ///
  /// Алгоритм:
  ///   1. Если [text] похож на legacy XOR → пробуем legacy_xor_codec.decryptLegacy.
  ///   2. Если [keyOrPassword] = "kk2r:<chatId>" → берём ключ из RAM-кэша
  ///      MasterKeyManager и пробуем AES-GCM.
  ///   3. Если [keyOrPassword] = "kk2:<base64>" (legacy) → AES-GCM напрямую.
  ///   4. Если ничего не подошло → null.
  static String? decryptWithPassword(String keyOrPassword, String text) {
    if (text.isEmpty) return null;

    final isRefKey = keyOrPassword.startsWith(_keyRefPrefix);
    final isLegacyKey = keyOrPassword.startsWith(_keyPrefixLegacy);

    // 1. Legacy XOR ветка — пробуем первой по специфическим маркерам.
    if (legacy.looksLikeLegacy(text)) {
      // Если keyOrPassword — старый plaintext-пароль, используем его напрямую.
      // Если "kk2..." — у нас нет XOR-пароля в этой sync-функции, только
      // через конфиг чата. См. decryptForChat для async-варианта.
      if (!isRefKey && !isLegacyKey) {
        final result = legacy.decryptLegacy(keyOrPassword, text);
        if (result != null) return result;
      }
    }

    // 2. Новый безопасный формат через RAM-кэш.
    if (isRefKey) {
      final chatId =
          int.tryParse(keyOrPassword.substring(_keyRefPrefix.length));
      if (chatId == null) return null;
      final secret = MasterKeyManager.instance.getCachedChatKey(chatId);
      if (secret == null) {
        // Ключ не разблокирован в RAM. Sync не может выполнить I/O —
        // используйте decryptForChat (async) для прозрачного prefetch.
        return null;
      }
      return _decryptWithKey(secret.unsafeView(), text);
    }

    // 3. Legacy формат с встроенным base64-ключом (миграция в kk2r на лету
    // невозможна без chatId, поэтому просто читаем).
    if (isLegacyKey) {
      final chatKey = _parseLegacyKey(keyOrPassword);
      if (chatKey != null) {
        final result = _decryptWithKey(chatKey, text);
        if (result != null) return result;
      }
    }

    // Если мы здесь — это либо legacy XOR без legacyXorPassword в этой
    // sync-функции, либо старый plaintext-пароль для не-legacy-текста,
    // либо повреждённый формат. Возвращаем null — UI покажет оригинал.
    return null;
  }

  /// Sync-версия которая пробует оба варианта: новый ключ И legacy XOR.
  /// Используется bubble/chat_screen которые не могут быть async.
  /// Возвращает первый успешный результат или null.
  static String? decryptWithBothSync(
    String keyOrPassword,
    String? legacyXorPassword,
    String text,
  ) {
    if (text.isEmpty) return null;

    // 1. Legacy XOR — если пароль задан и текст похож на legacy
    if (legacyXorPassword != null &&
        legacyXorPassword.isNotEmpty &&
        legacy.looksLikeLegacy(text)) {
      try {
        final r = legacy.decryptLegacy(legacyXorPassword, text);
        if (r != null && r.isNotEmpty) return r;
      } catch (_) {}
    }

    // 2. Новый формат
    final r = decryptWithPassword(keyOrPassword, text);
    if (r != null) return r;

    // 3. Если новый ключ дал null а legacy XOR пароль есть — попробуем
    // ещё раз без looksLikeLegacy (на случай если эвристика не сработала)
    if (legacyXorPassword != null && legacyXorPassword.isNotEmpty) {
      try {
        final r2 = legacy.decryptLegacy(legacyXorPassword, text);
        if (r2 != null && r2.isNotEmpty) return r2;
      } catch (_) {}
    }

    return null;
  }

  /// Async-версия для UI: пробует и новый формат, и legacy. Возвращает
  /// расшифрованный текст или null. Использует MasterKeyManager + конфиг
  /// чата, чтобы найти и chat_key, и legacyXorPassword.
  ///
  /// Используется в migration_v2 и в новом UI. chat_screen/bubble всё ещё
  /// могут вызывать sync decryptWithPassword.
  static Future<String?> decryptForChat(int chatId, String text) async {
    if (text.isEmpty) return null;

    final cfg = await getConfigForChat(chatId);

    // 1. Legacy ветка
    if (legacy.looksLikeLegacy(text) && cfg?.legacyXorPassword != null) {
      final r = legacy.decryptLegacy(cfg!.legacyXorPassword!, text);
      if (r != null) return r;
    }

    // 2. Новый формат через MasterKeyManager — ключ в Secure Storage.
    final mgr = MasterKeyManager.instance;
    if (mgr.isUnlocked && await mgr.hasChatKey(chatId)) {
      final secret = await mgr.getOrCreateChatKey(chatId);
      final r = _decryptWithKey(secret.unsafeView(), text);
      if (r != null) return r;
    }

    // 3. Совсем легаси — base64-ключ в конфиге (небезопасный формат, но
    //    читаем для совместимости с не-мигрированными конфигами).
    if (cfg != null && cfg.password.startsWith(_keyPrefixLegacy)) {
      final inlineKey = _parseLegacyKey(cfg.password);
      if (inlineKey != null) {
        final r = _decryptWithKey(inlineKey, text);
        if (r != null) {
          // Опортунистическая миграция конфига: переписываем в kk2r при
          // условии что master_key разблокирован и storage готов.
          if (mgr.isUnlocked) {
            // Импортируем ключ в Secure Storage и обновляем конфиг.
            unawaited(_migrateInlineKeyToReference(chatId, inlineKey, cfg));
          }
          return r;
        }
      }
    }

    return null;
  }

  /// Опортунистическая миграция legacy `kk2:<base64>` → `kk2r:<chatId>`.
  /// Импортирует inlineKey в Secure Storage MasterKeyManager и
  /// переписывает конфиг чата на ссылку. На ошибки не реагируем —
  /// при следующем сообщении попробуем снова.
  ///
  /// F-NEW fix: in-flight Map предотвращает дублирующие миграции при
  /// быстром поступлении нескольких сообщений в один чат. Раньше
  /// `unawaited(_migrate...)` мог запускаться 5+ раз параллельно для
  /// одного chatId, каждый звал `importChatKey` (что dispose-ит
  /// SecretKey в кеше) и `_saveConfig` — гонка приводила к временному
  /// сбою расшифровки следующих сообщений.
  static final Map<int, Future<void>> _inlineMigrationInFlight = {};

  static Future<void> _migrateInlineKeyToReference(
    int chatId,
    Uint8List inlineKey,
    ChatEncryptionConfig cfg,
  ) async {
    // Если миграция этого чата уже идёт — ничего не делаем (тот вызов
    // отработает за всех). Конфиг уже будет обновлён к моменту следующего
    // _decryptWithKey, и if-условие выше его не пропустит сюда.
    if (_inlineMigrationInFlight.containsKey(chatId)) return;

    final future = _doMigrateInlineKey(chatId, inlineKey, cfg);
    _inlineMigrationInFlight[chatId] = future;
    try {
      await future;
    } finally {
      _inlineMigrationInFlight.remove(chatId);
    }
  }

  static Future<void> _doMigrateInlineKey(
    int chatId,
    Uint8List inlineKey,
    ChatEncryptionConfig cfg,
  ) async {
    try {
      final mgr = MasterKeyManager.instance;
      if (!mgr.isUnlocked) return;
      // F-NEW: ещё одна проверка — между постановкой в очередь и
      // выполнением кто-то мог уже завершить миграцию (через явный
      // setPasswordForChat или другой путь). Если ключ уже переехал
      // в Secure Storage и конфиг обновлён — нечего делать.
      final fresh = await getConfigForChat(chatId);
      if (fresh != null && fresh.password.startsWith(_keyRefPrefix)) {
        return;
      }
      await mgr.importChatKey(chatId, inlineKey);
      // Перечитываем cfg ещё раз — с момента получения параметра
      // настройки могли измениться (пользователь переключил профиль и т.п.).
      final latest = await getConfigForChat(chatId) ?? cfg;
      final updated = latest.copyWith(password: '$_keyRefPrefix$chatId');
      await _saveConfig(chatId, updated);
    } catch (_) {
      // best-effort
    }
  }

  static String? _decryptWithKey(Uint8List chatKey, String text) {
    try {
      final result = tc.smartDecodeAndVerify<String>(
        text,
        (blob) {
          // unpackDirect бросает исключение при InvalidTag — это сигнал
          // smartDecodeAndVerify попробовать следующий профиль.
          final r = unpackDirect(key: chatKey, blob: blob);
          return utf8.decode(r.plaintext);
        },
      );
      return result.value;
    } catch (_) {
      return null;
    }
  }

  // ====================================================================== //
  //                              УТИЛИТЫ
  // ====================================================================== //

  /// Парсит legacy-формат `kk2:<base64-32>` (ключ в открытом виде).
  /// Используется только для совместимости со старым конфигом.
  static Uint8List? _parseLegacyKey(String s) {
    if (!s.startsWith(_keyPrefixLegacy)) return null;
    try {
      final raw = base64Decode(s.substring(_keyPrefixLegacy.length));
      if (raw.length != 32) return null;
      return Uint8List.fromList(raw);
    } catch (_) {
      return null;
    }
  }

  /// Сериализует ссылку на chat_key в безопасном формате `kk2r:<chatId>`.
  /// Сам ключ остаётся в Secure Storage, в конфиг кладём только ссылку.
  /// Используется migration_v2 и saveRawConfigForChat.
  static String serializeChatKey(int chatId) {
    return '$_keyRefPrefix$chatId';
  }

  /// Считывает chat_key из RAM-кэша MasterKeyManager (для kk2r-ссылок) или
  /// из inline base64 (для legacy kk2-ключей). Возвращает null, если ключ
  /// недоступен (master locked, нет в кэше, повреждённый формат).
  ///
  /// Возвращаемый буфер — НЕ владелец, не нужно wipe-ать (для kk2r это вид
  /// внутри SecretKey, для kk2 — отдельная копия в RAM, GC её соберёт).
  static Uint8List? extractChatKey(ChatEncryptionConfig? cfg, {int? chatId}) {
    if (cfg == null) return null;
    if (cfg.password.startsWith(_keyRefPrefix)) {
      final id = chatId ??
          int.tryParse(cfg.password.substring(_keyRefPrefix.length));
      if (id == null) return null;
      final secret = MasterKeyManager.instance.getCachedChatKey(id);
      return secret?.unsafeView();
    }
    return _parseLegacyKey(cfg.password);
  }

  /// True, если конфиг хранит ссылку на ключ (kk2r) или inline-ключ (kk2).
  static bool hasNewKey(ChatEncryptionConfig? cfg) {
    if (cfg == null) return false;
    return cfg.password.startsWith(_keyRefPrefix) ||
        cfg.password.startsWith(_keyPrefixLegacy);
  }
}
