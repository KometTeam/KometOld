// master_key_manager.dart — менеджер мастер-ключа и обёрток ключей чатов.
//
// Архитектура (вариант B из меню):
//
//     [пользовательский пароль]
//            │ Argon2id(salt, 128 MiB, t=3) ← ОДИН РАЗ при unlock()
//            в–ј
//     [master_key (32 байта) — в RAM на сессию через SecretKey]
//            в"'
//            в"' AES-GCM(master_key, chat_key, AAD = "kometchat:v1:<chatId>")
//            │ — обёртка хранится в Secure Storage
//            в–ј
//     [chat_key (32 байта, случайный, уникальный на чат) — в RAM-кэше]
//            в"' AES-GCM(chat_key, plaintext)
//            в–ј
//     [ciphertext в формате CRPT]
//
// Что хранится в Secure Storage (flutter_secure_storage):
//   - komet_master_v2_salt:        16 байт случайной соли (hex)
//   - komet_master_v2_check:       blob CRPT (KDF_DIRECT) с фиксированным
//                                  plaintext "ok" — для проверки пароля
//                                  при unlock()
//   - komet_chat_wrapped_<chatId>: AES-GCM-обёрнутый chat_key (hex)
//   - komet_relock_seconds:        опциональный таймаут авто-релока (int)
//
// Что хранится в RAM (внутри этого синглтона):
//   - SecretKey master:            мастер-ключ (32 байта)
//   - Map<int, SecretKey> chatKeyCache: распакованные ключи чатов
//
// Безопасность:
//   - Если в Secure Storage нет соли → нужно вызвать setupMasterPassword()
//   - Если есть соль → нужно вызвать unlock(password); если пароль неверен,
//     AES-GCM проверочный blob не расшифруется → InvalidTag.
//   - При lock() весь master и все chat_key в кэше затираются нулями.
//   - Auto-relock: вызывающий код (App lifecycle observer) должен сам
//     вызывать lock() по таймеру — этот класс таймер не запускает (чтобы
//     не зависеть от Flutter SDK в крипто-слое).

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'crypt_format.dart';
import 'hex.dart';
import 'secret_key.dart';

/// Ошибка, которую бросает [MasterKeyManager] когда мастер-ключ не разблокирован.
class MasterLockedException implements Exception {
  final String message;
  MasterLockedException([this.message = 'Мастер-ключ не разблокирован']);
  @override
  String toString() => 'MasterLockedException: $message';
}

/// Ошибка неверного пароля при unlock().
class WrongMasterPasswordException implements Exception {
  final String message;
  WrongMasterPasswordException([this.message = 'Неверный пароль']);
  @override
  String toString() => 'WrongMasterPasswordException: $message';
}

/// Ошибка отсутствия мастер-пароля (нужно сначала setupMasterPassword()).
class MasterNotInitializedException implements Exception {
  final String message;
  MasterNotInitializedException([
    this.message = 'Мастер-пароль не настроен',
  ]);
  @override
  String toString() => 'MasterNotInitializedException: $message';
}

/// Глобальный держатель мастер-ключа и обёрток ключей чатов.
///
/// Типичный жизненный цикл:
///
/// ```dart
/// final mgr = MasterKeyManager.instance;
/// if (!await mgr.isInitialized()) {
///   await mgr.setupMasterPassword('user-password');
/// } else {
///   await mgr.unlock('user-password');
/// }
/// // далее: mgr.getOrCreateChatKey(chatId), mgr.getChatKey(chatId)
/// // при выходе: mgr.lock()
/// ```
class MasterKeyManager {
  MasterKeyManager._internal();

  /// Глобальный singleton.
  static final MasterKeyManager instance = MasterKeyManager._internal();

  // -- Storage keys -------------------------------------------------------- //

  static const String _kSalt = 'komet_master_v2_salt';
  static const String _kCheck = 'komet_master_v2_check';
  static const String _kWrappedPrefix = 'komet_chat_wrapped_';
  static const String _kRelockSeconds = 'komet_relock_seconds';
  static const String _kArgon2Profile = 'komet_master_v2_argon2_profile';

  /// Резерв старого salt/check во время changeMasterPassword. Если
  /// смена пароля упадёт между записью нового и перезаписью обёрток,
  /// эти ключи останутся и позволят recovery со старым паролем.
  static const String _kSaltPending = 'komet_master_v2_salt_pending';
  static const String _kCheckPending = 'komet_master_v2_check_pending';

  /// Маркер «миграция XOR→AES для старых чатов выполнена». Используется
  /// migration_v2.dart, не самим менеджером, но удобно держать ключ здесь.
  static const String kMigrationCompletedFlag = 'komet_migration_v2_completed';

  // -- AAD ---------------------------------------------------------------- //

  // AAD автоматически формируется из meta-блока CRPT-формата (packEncrypted
  // включает meta_bytes в associated data AES-GCM). Дополнительный binding
  // с chatId обеспечивается тем, что мы прописываем chat=<chatId> внутрь
  // meta при создании обёртки, а при разворачивании сверяем meta['chat']
  // с ожидаемым chatId — это защищает от перестановки имён storage-ключей.

  // -- Storage ------------------------------------------------------------- //

  /// Storage для тестов можно подменить через [setStorageForTesting].
  FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Замена storage в тестах. Не использовать в production.
  void setStorageForTesting(FlutterSecureStorage storage) {
    _storage = storage;
  }

  // -- In-memory state ----------------------------------------------------- //

  SecretKey? _master;
  final Map<int, SecretKey> _chatKeyCache = {};

  // F-NEW fix: in-flight операции по получению/созданию chat_key. Раньше
  // две параллельные `getOrCreateChatKey(42)` для нового чата могли:
  //   1. Обе увидеть _chatKeyCache[42] == null
  //   2. Обе увидеть storage пустым
  //   3. Обе сгенерировать РАЗНЫЕ ключи
  //   4. Обе записать в storage (последняя выиграет)
  //   5. Сообщения, зашифрованные первым ключом — потеряны навсегда.
  //
  // Решение: общий Future для всех ожидающих один и тот же chatId. Если
  // кто-то уже начал getOrCreate — все остальные ждут его результат.
  final Map<int, Future<SecretKey>> _chatKeyInFlight = {};

  final Random _rng = Random.secure();

  /// True, если мастер-ключ загружен в RAM.
  bool get isUnlocked => _master != null && !_master!.isDisposed;

  /// Стрим, в который кидается событие при lock(). UI может слушать его,
  /// чтобы перейти на экран ввода пароля.
  final StreamController<void> _lockEventsController =
      StreamController<void>.broadcast();
  Stream<void> get lockEvents => _lockEventsController.stream;

  // ====================================================================== //
  //                            ИНИЦИАЛИЗАЦИЯ
  // ====================================================================== //

  /// True, если в Secure Storage уже есть мастер-пароль.
  Future<bool> isInitialized() async {
    final salt = await _storage.read(key: _kSalt);
    final check = await _storage.read(key: _kCheck);
    return salt != null && check != null;
  }

  /// Устанавливает мастер-пароль ПЕРВЫЙ раз. Если уже инициализирован —
  /// бросает [StateError]. Для смены пароля используй [changeMasterPassword].
  ///
  /// После успеха master_key загружен в RAM (isUnlocked == true).
  ///
  /// [argon2Profile] — профиль из [argon2Profiles] ('lite' | 'balanced' |
  /// 'strong'). По умолчанию 'balanced' (128 MiB, t=3, p=4 — OWASP).
  /// На слабых устройствах можно выбрать 'lite' (64 MiB), на сильных —
  /// 'strong' (256 MiB). Профиль сохраняется в Secure Storage и
  /// используется при последующих unlock().
  Future<void> setupMasterPassword(
    String password, {
    String argon2Profile = 'balanced',
  }) async {
    if (await isInitialized()) {
      throw StateError(
        'Мастер-пароль уже установлен. Используй changeMasterPassword.',
      );
    }
    if (password.isEmpty) {
      throw ArgumentError('Пароль не может быть пустым');
    }
    final params = getArgon2Params(argon2Profile);

    final salt = _randomBytes(16);
    final masterBytes = await deriveArgon2id(
      password: password,
      salt: salt,
      timeCost: params['time_cost']!,
      memoryCostKib: params['memory_cost']!,
      parallelism: params['parallelism']!,
    );

    // Создаём проверочный blob: AES-GCM(master, "ok") в формате CRPT.
    // Параметры Argon2id храним в meta — на случай если пользователь
    // удалит storage-ключ profile, мы всё равно знаем как пере-вывести
    // ключ (Argon2id-параметры включены в AAD → не подменяются).
    final check = packEncrypted(
      key: masterBytes,
      plaintext: Uint8List.fromList(utf8.encode('ok')),
      publicMeta: {
        'v': 2,
        'kind': 'check',
        'time_cost': params['time_cost'],
        'memory_cost': params['memory_cost'],
        'parallelism': params['parallelism'],
      },
    );

    await _storage.write(key: _kSalt, value: _hex(salt));
    await _storage.write(key: _kCheck, value: _hex(check));
    await _storage.write(key: _kArgon2Profile, value: argon2Profile);

    _master = SecretKey.takeOwnership(masterBytes);
  }

  /// Возвращает профиль Argon2id, выбранный при первой настройке.
  /// 'balanced' если не настроен.
  Future<String> getArgon2Profile() async {
    final stored = await _storage.read(key: _kArgon2Profile);
    return stored ?? 'balanced';
  }

  /// Разблокирует мастер-ключ. Бросает [WrongMasterPasswordException] при
  /// неверном пароле, [MasterNotInitializedException] если мастер не настроен.
  Future<void> unlock(String password) async {
    final saltHex = await _storage.read(key: _kSalt);
    final checkHex = await _storage.read(key: _kCheck);
    if (saltHex == null || checkHex == null) {
      throw MasterNotInitializedException();
    }

    final salt = _unhex(saltHex);
    final check = _unhex(checkHex);

    // F-09 fix: Argon2-параметры берём из meta проверочного blob, а не из
    // дефолтов. Так пользователь, выбравший 'lite' при первичной настройке,
    // не упрётся в 128 MiB при unlock на слабом телефоне.
    //
    // Параметры из meta безопасны: meta участвует в AAD AES-GCM, любая
    // подмена ломает tag → unlock провалится с WrongMasterPasswordException.
    // Лимиты на параметры применяются в _validatedArgon2Params (DoS-защита).
    final checkMeta = peekMeta(check);
    final timeCost = (checkMeta['time_cost'] as num?)?.toInt() ??
        argon2DefaultTime;
    final memoryCost = (checkMeta['memory_cost'] as num?)?.toInt() ??
        argon2DefaultMemoryKib;
    final parallelism = (checkMeta['parallelism'] as num?)?.toInt() ??
        argon2DefaultParallel;

    // DoS-защита: не давать злоумышленнику запустить Argon2id на 100 GiB.
    if (memoryCost > argon2MaxMemoryKib || timeCost > argon2MaxTime) {
      throw const FormatException(
        'Argon2-параметры в check вне допустимых лимитов',
      );
    }

    final candidate = await deriveArgon2id(
      password: password,
      salt: salt,
      timeCost: timeCost,
      memoryCostKib: memoryCost,
      parallelism: parallelism,
    );

    // Пробуем расшифровать проверочный blob.
    try {
      final result = unpackDirect(key: candidate, blob: check);
      if (utf8.decode(result.plaintext) != 'ok') {
        // Маловероятно — но если кто-то подменил blob.
        wipeBytes(candidate);
        throw WrongMasterPasswordException('Проверочный blob повреждён');
      }
    } catch (e) {
      wipeBytes(candidate);
      if (e is WrongMasterPasswordException) rethrow;
      throw WrongMasterPasswordException();
    }

    // Если уже был разлочен (например, повторный unlock) — затираем старый.
    _master?.dispose();
    _master = SecretKey.takeOwnership(candidate);
  }

  /// Затирает мастер-ключ и все ключи чатов в RAM. Storage не трогается.
  /// После lock() нужно снова вызвать unlock() для шифрования/расшифровки.
  void lock() {
    _master?.dispose();
    _master = null;
    for (final ck in _chatKeyCache.values) {
      ck.dispose();
    }
    _chatKeyCache.clear();
    if (!_lockEventsController.isClosed) {
      _lockEventsController.add(null);
    }
  }

  /// Возвращает копию master_key. Используется ТОЛЬКО внутри
  /// BiometricLock.enable() для сохранения ключа в biometric storage.
  ///
  /// Вызывающий код ОБЯЗАН wipe-нуть возвращённый буфер сразу после
  /// использования, иначе ключ останется в RAM до GC.
  ///
  /// Бросает [MasterLockedException] если master не разблокирован.
  Uint8List masterKeyCopy() {
    _ensureUnlocked();
    return _master!.exposeCopy();
  }

  /// Загружает мастер-ключ напрямую из биометрического storage, минуя
  /// Argon2id. Используется только внутри BiometricLock.unlockWithBiometrics().
  ///
  /// Принимает ВЛАДЕНИЕ переданным буфером (не копирует) — буфер будет
  /// обнулён при lock().
  void installMasterFromBiometric(Uint8List masterBytes) {
    if (masterBytes.length != 32) {
      throw ArgumentError('master_key must be 32 bytes');
    }
    _master?.dispose();
    _master = SecretKey.takeOwnership(masterBytes);
  }

  /// Меняет мастер-пароль. Требует знания старого.
  ///
  /// Алгоритм (восстанавливаемый при сбое):
  ///   1. unlock(oldPassword) — проверяем что старый пароль верен.
  ///   2. Argon2id(newPassword) — деривируем новый master.
  ///   3. Читаем все chat_key из Secure Storage в RAM (через старый master).
  ///   4. Пишем НОВЫЙ check-blob и НОВЫЙ salt в storage. ← точка коммита.
  ///   5. После этого пере-оборачиваем chat_keys новым master, затирая
  ///      старые обёртки. Если процесс упадёт здесь — после перезапуска
  ///      unlock с новым паролем сработает (check валиден), но часть
  ///      чатов окажутся «потеряны» (старые обёртки нечитаемы новым master).
  ///      Решается повторным запуском [recoverChangePassword] (TODO PR 3).
  ///
  /// Бросает [WrongMasterPasswordException] если oldPassword неверен.
  Future<void> changeMasterPassword(
    String oldPassword,
    String newPassword,
  ) async {
    if (newPassword.isEmpty) {
      throw ArgumentError('Новый пароль не может быть пустым');
    }

    // 1. Проверяем oldPassword.
    //
    // ВАЖНО: чисто доверять _master в RAM нельзя — кто-то с физическим
    // доступом к разблокированному устройству мог бы сменить мастер-пароль
    // не зная старого. Поэтому ВСЕГДА верифицируем oldPassword через
    // Argon2id+проверочный blob (та же логика что и в unlock()).
    final saltHex = await _storage.read(key: _kSalt);
    final checkHex = await _storage.read(key: _kCheck);
    if (saltHex == null || checkHex == null) {
      throw MasterNotInitializedException();
    }
    final salt = _unhex(saltHex);
    final check = _unhex(checkHex);
    final checkMeta = peekMeta(check);
    final timeCostOld =
        (checkMeta['time_cost'] as num?)?.toInt() ?? argon2DefaultTime;
    final memoryCostOld = (checkMeta['memory_cost'] as num?)?.toInt() ??
        argon2DefaultMemoryKib;
    final parallelismOld = (checkMeta['parallelism'] as num?)?.toInt() ??
        argon2DefaultParallel;
    if (memoryCostOld > argon2MaxMemoryKib || timeCostOld > argon2MaxTime) {
      throw const FormatException(
        'Argon2-параметры в check вне допустимых лимитов',
      );
    }
    final oldMasterCandidate = await deriveArgon2id(
      password: oldPassword,
      salt: salt,
      timeCost: timeCostOld,
      memoryCostKib: memoryCostOld,
      parallelism: parallelismOld,
    );
    try {
      final r = unpackDirect(key: oldMasterCandidate, blob: check);
      if (utf8.decode(r.plaintext) != 'ok') {
        wipeBytes(oldMasterCandidate);
        throw WrongMasterPasswordException();
      }
    } catch (e) {
      wipeBytes(oldMasterCandidate);
      if (e is WrongMasterPasswordException) rethrow;
      throw WrongMasterPasswordException();
    }
    // Если до этого был locked — устанавливаем master в RAM (избегаем
    // повторного запуска unlock() и ещё одного Argon2id).
    if (!isUnlocked) {
      _master = SecretKey.takeOwnership(oldMasterCandidate);
    } else {
      // Уже был unlocked — кандидат больше не нужен.
      wipeBytes(oldMasterCandidate);
    }

    // 2. Считываем профиль Argon2 (тот же что и при setup).
    final argon2Profile = await getArgon2Profile();
    final params = getArgon2Params(argon2Profile);

    // 3. Считываем ВСЕ обёртки в RAM (через текущий master).
    //
    // Важно: не используем getOrCreateChatKey, т.к. он кеширует ключи в
    // _chatKeyCache на постоянной основе. После changeMasterPassword мы
    // не хотим оставлять в кэше ключи всех чатов (которые пользователь
    // мог никогда не открывать в этой сессии) — это расширяет окно
    // утечки в RAM. Запоминаем какие ключи УЖЕ были в кэше до операции,
    // чтобы в конце оставить только их.
    final keysAlreadyInCache = _chatKeyCache.keys.toSet();
    final all = await _storage.readAll();
    final wrappedKeys = <int, Uint8List>{};
    for (final entry in all.entries) {
      if (!entry.key.startsWith(_kWrappedPrefix)) continue;
      final chatIdStr = entry.key.substring(_kWrappedPrefix.length);
      final chatId = int.tryParse(chatIdStr);
      if (chatId == null) continue;

      // Если ключ уже в кэше — берём оттуда, иначе разворачиваем напрямую.
      final cached = _chatKeyCache[chatId];
      if (cached != null && !cached.isDisposed) {
        wrappedKeys[chatId] = cached.exposeCopy();
        continue;
      }

      try {
        final wrappedBlob = _unhex(entry.value);
        final peekedMeta = peekMeta(wrappedBlob);
        if (peekedMeta['chat'] != chatId) {
          // AAD-binding нарушен — пропускаем этот чат, переоборачивать
          // нечего (либо повреждение, либо подмена). При следующем
          // getOrCreateChatKey он провалится с ошибкой и пользователь
          // увидит broken-state в recovery.
          continue;
        }
        final result = unpackDirect(
          key: _master!.unsafeView(),
          blob: wrappedBlob,
        );
        if (result.plaintext.length != 32) {
          wipeBytes(result.plaintext);
          continue;
        }
        wrappedKeys[chatId] = result.plaintext;
      } catch (_) {
        // Битая обёртка — пропускаем. После смены пароля попадёт в
        // scanForCorruptedChatKeys.
        continue;
      }
    }

    // 4. Деривируем новый master.
    final newSalt = _randomBytes(16);
    final newMasterBytes = await deriveArgon2id(
      password: newPassword,
      salt: newSalt,
      timeCost: params['time_cost']!,
      memoryCostKib: params['memory_cost']!,
      parallelism: params['parallelism']!,
    );
    final newCheck = packEncrypted(
      key: newMasterBytes,
      plaintext: Uint8List.fromList(utf8.encode('ok')),
      publicMeta: {
        'v': 2,
        'kind': 'check',
        'time_cost': params['time_cost'],
        'memory_cost': params['memory_cost'],
        'parallelism': params['parallelism'],
      },
    );

    // RECOVERY: сохраняем старый salt+check в pending-слот ПЕРЕД записью
    // нового. Если смена пароля упадёт между шагом 4 и шагом 5, при
    // следующем unlock можно восстановиться со старым паролем через
    // recoverWithOldPassword().
    final oldSaltHex = await _storage.read(key: _kSalt);
    final oldCheckHex = await _storage.read(key: _kCheck);
    if (oldSaltHex != null && oldCheckHex != null) {
      await _storage.write(key: _kSaltPending, value: oldSaltHex);
      await _storage.write(key: _kCheckPending, value: oldCheckHex);
    }

    // ТОЧКА КОММИТА: пишем новый salt+check. С этого момента unlock()
    // примет только новый пароль (старый идёт через recovery).
    await _storage.write(key: _kSalt, value: _hex(newSalt));
    await _storage.write(key: _kCheck, value: _hex(newCheck));

    // Подменяем мастер в RAM.
    _master?.dispose();
    _master = SecretKey.takeOwnership(newMasterBytes);

    // 5. Пере-оборачиваем все chat_keys новым master.
    for (final entry in wrappedKeys.entries) {
      final chatId = entry.key;
      final keyBytes = entry.value;
      final newWrapped = packEncrypted(
        key: _master!.unsafeView(),
        plaintext: keyBytes,
        publicMeta: {'v': 2, 'kind': 'chatkey', 'chat': chatId},
      );
      await _storage.write(
        key: '$_kWrappedPrefix$chatId',
        value: _hex(newWrapped),
      );
      wipeBytes(keyBytes);
    }

    // 6. Сбрасываем из кэша те ключи, которых там не было до операции.
    // Те, что были — могут оставаться: пользователь явно их использовал.
    // Note: после переоборачивания кешированные SecretKey всё ещё валидны
    // (мы их не пересоздавали), сами 32-байтные ключи чатов не менялись.
    final toEvict = _chatKeyCache.keys
        .where((id) => !keysAlreadyInCache.contains(id))
        .toList();
    for (final id in toEvict) {
      _chatKeyCache[id]?.dispose();
      _chatKeyCache.remove(id);
    }

    // 7. Все обёртки перезаписаны — pending-резерв больше не нужен.
    await _storage.delete(key: _kSaltPending);
    await _storage.delete(key: _kCheckPending);
  }


  // ====================================================================== //
  //                         КЛЮЧИ ЧАТОВ — ОБЁРТКИ
  // ====================================================================== //

  /// Возвращает chat_key для чата. Если обёртка существует в Secure Storage,
  /// разворачивает её мастер-ключом. Если нет — генерирует новый случайный
  /// chat_key, оборачивает мастер-ключом, кладёт в Secure Storage.
  ///
  /// Бросает [MasterLockedException] если master не загружен.
  ///
  /// F-NEW fix: безопасен для concurrent вызовов с одинаковым chatId.
  /// Все ожидающие получат тот же ключ; storage не будет перезаписан
  /// разными ключами разных параллельных вызовов.
  Future<SecretKey> getOrCreateChatKey(int chatId) async {
    _ensureUnlocked();

    // Кэш в RAM
    final cached = _chatKeyCache[chatId];
    if (cached != null && !cached.isDisposed) return cached;

    // Если кто-то уже начал получать ключ для этого чата — ждём его.
    final inFlight = _chatKeyInFlight[chatId];
    if (inFlight != null) {
      return inFlight;
    }

    // Стартуем новую операцию. Сохраняем Future ДО запуска — если кто-то
    // зайдёт между первым `await` ниже и завершением, он увидит наш
    // Future и подождёт.
    final future = _doGetOrCreateChatKey(chatId);
    _chatKeyInFlight[chatId] = future;
    try {
      return await future;
    } finally {
      _chatKeyInFlight.remove(chatId);
    }
  }

  Future<SecretKey> _doGetOrCreateChatKey(int chatId) async {
    final wrappedHex = await _storage.read(
      key: '$_kWrappedPrefix$chatId',
    );

    Uint8List chatKeyBytes;
    if (wrappedHex == null) {
      // Новый чат — генерируем ключ, оборачиваем, сохраняем.
      // Делаем две копии: одна уйдёт в packEncrypted и будет затёрта,
      // вторая останется в SecretKey-кэше. Не зависим от того,
      // модифицирует ли AES-реализация входной буфер.
      chatKeyBytes = _randomBytes(32);
      final packCopy = Uint8List.fromList(chatKeyBytes);
      final wrapped = packEncrypted(
        key: _master!.unsafeView(),
        plaintext: packCopy,
        publicMeta: {
          'v': 2,
          'kind': 'chatkey',
          'chat': chatId,
        },
      );
      wipeBytes(packCopy);
      await _storage.write(
        key: '$_kWrappedPrefix$chatId',
        value: _hex(wrapped),
      );
    } else {
      // Существующая обёртка — разворачиваем.
      try {
        final wrappedBlob = _unhex(wrappedHex);

        // F-03 fix: проверяем meta['chat'] ДО разворачивания.
        // Если chat_id в meta не совпадает с запрошенным — мы НИКОГДА
        // не запускаем AES-GCM, ключ другого чата вообще не появляется
        // в RAM. Это самая сильная защита из возможных в Dart, где
        // нельзя строго контролировать копии буферов в GC.
        //
        // Даже если злоумышленник подделает meta (поставит туда нужный
        // chat_id), AAD при unpackDirect не сойдётся — meta включена в
        // AAD AES-GCM, любая подмена ломает tag.
        final peekedMeta = peekMeta(wrappedBlob);
        final metaChat = peekedMeta['chat'];
        if (metaChat != chatId) {
          throw StateError(
            'AAD-binding нарушен: обёртка предназначена для чата $metaChat, '
            'а запрошен $chatId. Подозрение на подмену storage.',
          );
        }

        // Сейчас meta совпала. Разворачиваем — если AAD расходится
        // (мета подделана), AES-GCM бросит SecretBoxAuthenticationError.
        final result = unpackDirect(
          key: _master!.unsafeView(),
          blob: wrappedBlob,
        );
        if (result.plaintext.length != 32) {
          // Зачищаем перед бросанием — но это best-effort, см. F-03 в
          // SECURITY.md (буферы могли быть скопированы внутри cryptography).
          wipeBytes(result.plaintext);
          throw StateError(
            'Обёртка повреждена: ожидался ключ 32 байта, получено '
            '${result.plaintext.length}',
          );
        }
        chatKeyBytes = result.plaintext;
      } catch (e) {
        throw StateError('Не удалось развернуть chat_key для $chatId: $e');
      }
    }

    // F-NEW fix: дополнительная защита от race. Между нашим первым
    // прочтением кэша и достижением этой точки кто-то мог положить ключ
    // в кэш через другой путь (например, importChatKey). Если так —
    // используем уже существующий, чтобы не плодить копии.
    final existingNow = _chatKeyCache[chatId];
    if (existingNow != null && !existingNow.isDisposed) {
      // Затираем нашу копию — она больше не нужна.
      wipeBytes(chatKeyBytes);
      return existingNow;
    }

    final secret = SecretKey.takeOwnership(chatKeyBytes);
    _chatKeyCache[chatId] = secret;
    return secret;
  }

  /// Импортирует УЖЕ существующий chat_key (например, при миграции XOR→AES
  /// или при импорте экспортированного ключа). Если в Secure Storage уже
  /// есть обёртка — перезаписывает её.
  ///
  /// Передаваемый [keyBytes] должен быть длиной 32. Этот метод копирует его
  /// внутренне, исходный буфер вызывающий код может wipe-ать после возврата.
  ///
  /// F-NEW fix: если параллельно идёт getOrCreateChatKey для того же чата —
  /// сначала дождёмся его (чтобы не было race "create заполнил storage,
  /// import читает старую запись и импортирует поверх"), затем импортируем.
  Future<void> importChatKey(int chatId, Uint8List keyBytes) async {
    _ensureUnlocked();
    if (keyBytes.length != 32) {
      throw ArgumentError('chat_key должен быть длиной 32 байта');
    }

    // Дожидаемся любого in-flight getOrCreate, чтобы не пересечься.
    final inFlight = _chatKeyInFlight[chatId];
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {
        // Если та операция упала — нам всё равно, мы перепишем.
      }
    }

    // Делаем ДВЕ независимые копии:
    //   - packCopy идёт в packEncrypted как plaintext. Большинство
    //     реализаций AES-GCM не модифицируют входной plaintext, но
    //     cryptography_flutter (нативный) может работать иначе. Лучше
    //     не зависеть от деталей реализации.
    //   - cacheCopy остаётся в RAM-кэше через SecretKey.
    final packCopy = Uint8List.fromList(keyBytes);
    final cacheCopy = Uint8List.fromList(keyBytes);
    final wrapped = packEncrypted(
      key: _master!.unsafeView(),
      plaintext: packCopy,
      publicMeta: {
        'v': 2,
        'kind': 'chatkey',
        'chat': chatId,
      },
    );
    // packCopy больше не нужен — затираем как одноразовый.
    wipeBytes(packCopy);

    await _storage.write(
      key: '$_kWrappedPrefix$chatId',
      value: _hex(wrapped),
    );

    // Обновляем RAM-кэш — SecretKey забирает владение cacheCopy.
    _chatKeyCache[chatId]?.dispose();
    _chatKeyCache[chatId] = SecretKey.takeOwnership(cacheCopy);
  }

  /// Удаляет ключ чата (и обёртку из Secure Storage).
  Future<void> removeChatKey(int chatId) async {
    await _storage.delete(key: '$_kWrappedPrefix$chatId');
    _chatKeyCache[chatId]?.dispose();
    _chatKeyCache.remove(chatId);
  }

  /// True, если для чата есть сохранённая обёртка ключа.
  Future<bool> hasChatKey(int chatId) async {
    final v = await _storage.read(key: '$_kWrappedPrefix$chatId');
    return v != null;
  }

  /// Sync-проверка: есть ли ключ чата в RAM-кэше. Полезно из sync-методов
  /// типа [encryptWithPassword].
  bool hasChatKeyCached(int chatId) {
    final c = _chatKeyCache[chatId];
    return c != null && !c.isDisposed;
  }

  /// Sync-доступ к ключу чата из RAM-кэша. Если ключа нет в кэше —
  /// возвращает null (sync контекст не может вызвать async I/O).
  /// Вызывающий код должен предварительно вызвать [getOrCreateChatKey].
  SecretKey? getCachedChatKey(int chatId) {
    final c = _chatKeyCache[chatId];
    if (c == null || c.isDisposed) return null;
    return c;
  }

  // ====================================================================== //
  //                            АВТО-РЕЛОК
  // ====================================================================== //

  /// Возвращает таймаут авто-релока в секундах, или null если выключен.
  Future<int?> getRelockSeconds() async {
    final raw = await _storage.read(key: _kRelockSeconds);
    if (raw == null) return null;
    return int.tryParse(raw);
  }

  /// Устанавливает таймаут авто-релока. null = никогда (по умолчанию).
  Future<void> setRelockSeconds(int? seconds) async {
    if (seconds == null) {
      await _storage.delete(key: _kRelockSeconds);
    } else {
      if (seconds < 30) {
        throw ArgumentError('Минимальный таймаут — 30 секунд');
      }
      await _storage.write(key: _kRelockSeconds, value: seconds.toString());
    }
  }

  // ====================================================================== //
  //                         СБРОС (ТОЛЬКО ДЛЯ ТЕСТОВ)
  // ====================================================================== //

  /// Полностью удаляет всё из storage и затирает RAM. Используется в тестах
  /// и при сценарии «забыл пароль» (после явного подтверждения, что все
  /// зашифрованные данные будут потеряны).
  /// Хуки, которые вызываются при nuclearReset перед удалением ключей
  /// мастера. Используется BiometricLock для затирания биометрического
  /// ключа из своего отдельного storage.
  final List<Future<void> Function()> _resetHooks = [];

  /// Регистрирует callback на nuclearReset. Вызывается до удаления
  /// мастер-ключа из storage.
  void registerResetHook(Future<void> Function() hook) {
    _resetHooks.add(hook);
  }

  Future<void> nuclearReset() async {
    lock();
    // Вызываем хуки (например, BiometricLock.wipeOnReset).
    for (final hook in _resetHooks) {
      try {
        await hook();
      } catch (_) {
        // Если хук упал, продолжаем — главное удалить мастер.
      }
    }
    final all = await _storage.readAll();
    for (final k in all.keys) {
      if (k == _kSalt ||
          k == _kCheck ||
          k == _kSaltPending ||
          k == _kCheckPending ||
          k == _kRelockSeconds ||
          k == _kArgon2Profile ||
          k.startsWith(_kWrappedPrefix)) {
        await _storage.delete(key: k);
      }
    }
  }

  // ====================================================================== //
  //                            HELPERS
  // ====================================================================== //

  /// Сканирует все обёртки chat_key и возвращает список chatId, которые
  /// не разворачиваются текущим master_key. Это типичный признак
  /// прерванной changeMasterPassword: часть обёрток уже перезаписана новым
  /// master, часть осталась со старым.
  ///
  /// Master должен быть unlocked.
  Future<List<int>> scanForCorruptedChatKeys() async {
    _ensureUnlocked();
    final all = await _storage.readAll();
    final corrupted = <int>[];

    for (final entry in all.entries) {
      if (!entry.key.startsWith(_kWrappedPrefix)) continue;
      final chatIdStr = entry.key.substring(_kWrappedPrefix.length);
      final chatId = int.tryParse(chatIdStr);
      if (chatId == null) continue;

      try {
        final blob = _unhex(entry.value);
        // Сначала проверяем meta — не должно совпадать → битый
        final meta = peekMeta(blob);
        if (meta['chat'] != chatId) {
          corrupted.add(chatId);
          continue;
        }
        // Пробуем развернуть.
        final result = unpackDirect(
          key: _master!.unsafeView(),
          blob: blob,
        );
        if (result.plaintext.length != 32) {
          wipeBytes(result.plaintext);
          corrupted.add(chatId);
        }
      } catch (_) {
        // Любое исключение — обёртка нечитаема текущим master.
        corrupted.add(chatId);
      }
    }
    return corrupted..sort();
  }

  /// True, если в storage есть незавершённая changeMasterPassword
  /// (есть pending salt+check). Это означает, что часть chat_key обёрток
  /// может быть нечитаема текущим master.
  Future<bool> hasPendingPasswordChange() async {
    final salt = await _storage.read(key: _kSaltPending);
    final check = await _storage.read(key: _kCheckPending);
    return salt != null && check != null;
  }

  /// Восстанавливает обёртки chat_key с помощью СТАРОГО пароля.
  /// Используется ТОЛЬКО когда [hasPendingPasswordChange] == true,
  /// т.е. предыдущая changeMasterPassword не завершилась.
  ///
  /// Алгоритм:
  ///   1. Argon2id(oldPassword, pending_salt) → старый master_key.
  ///   2. Проверяем через pending_check — если совпало, пароль верен.
  ///   3. Для каждого chatId в [corruptedChatIds]:
  ///      - Разворачиваем обёртку старым master.
  ///      - Заново оборачиваем текущим master.
  ///   4. Удаляем pending_salt + pending_check (recovery завершён).
  ///
  /// Возвращает количество восстановленных чатов.
  /// Бросает [WrongMasterPasswordException] если oldPassword неверен.
  Future<int> recoverWithOldPassword({
    required String oldPassword,
    required List<int> corruptedChatIds,
  }) async {
    _ensureUnlocked();

    final pendingSaltHex = await _storage.read(key: _kSaltPending);
    final pendingCheckHex = await _storage.read(key: _kCheckPending);
    if (pendingSaltHex == null || pendingCheckHex == null) {
      throw StateError(
        'Нет незавершённой смены пароля — recovery не нужен',
      );
    }

    final pendingSalt = _unhex(pendingSaltHex);
    final pendingCheck = _unhex(pendingCheckHex);

    // Argon2-параметры из pending_check meta.
    final pendingMeta = peekMeta(pendingCheck);
    final timeCost =
        (pendingMeta['time_cost'] as num?)?.toInt() ?? argon2DefaultTime;
    final memoryCost = (pendingMeta['memory_cost'] as num?)?.toInt() ??
        argon2DefaultMemoryKib;
    final parallelism = (pendingMeta['parallelism'] as num?)?.toInt() ??
        argon2DefaultParallel;

    final oldMasterBytes = await deriveArgon2id(
      password: oldPassword,
      salt: pendingSalt,
      timeCost: timeCost,
      memoryCostKib: memoryCost,
      parallelism: parallelism,
    );

    // Проверяем pending_check.
    try {
      final r = unpackDirect(key: oldMasterBytes, blob: pendingCheck);
      if (utf8.decode(r.plaintext) != 'ok') {
        wipeBytes(oldMasterBytes);
        throw WrongMasterPasswordException();
      }
    } catch (e) {
      wipeBytes(oldMasterBytes);
      if (e is WrongMasterPasswordException) rethrow;
      throw WrongMasterPasswordException();
    }

    var recovered = 0;
    for (final chatId in corruptedChatIds) {
      final wrappedHex = await _storage.read(key: '$_kWrappedPrefix$chatId');
      if (wrappedHex == null) continue;
      try {
        final wrapped = _unhex(wrappedHex);
        final result = unpackDirect(key: oldMasterBytes, blob: wrapped);
        if (result.plaintext.length != 32) {
          wipeBytes(result.plaintext);
          continue;
        }

        // Заново оборачиваем текущим (новым) master.
        final newWrapped = packEncrypted(
          key: _master!.unsafeView(),
          plaintext: result.plaintext,
          publicMeta: {'v': 2, 'kind': 'chatkey', 'chat': chatId},
        );
        await _storage.write(
          key: '$_kWrappedPrefix$chatId',
          value: _hex(newWrapped),
        );
        wipeBytes(result.plaintext);
        recovered++;
      } catch (_) {
        // Пропускаем чаты, которые не разворачиваются ни старым, ни новым.
      }
    }

    wipeBytes(oldMasterBytes);

    // Если все corrupted восстановлены — удаляем pending.
    if (recovered == corruptedChatIds.length) {
      await _storage.delete(key: _kSaltPending);
      await _storage.delete(key: _kCheckPending);
    }
    return recovered;
  }

  /// Принудительно удаляет pending salt+check (если пользователь решил
  /// что recovery невозможно и хочет «забыть»). После этого старый
  /// пароль больше нельзя использовать для recovery.
  Future<void> dismissPendingPasswordChange() async {
    await _storage.delete(key: _kSaltPending);
    await _storage.delete(key: _kCheckPending);
  }

  /// Удаляет битые обёртки chat_key (для чатов из [chatIds]).
  /// Используется когда recovery невозможен и пользователь готов
  /// принять потерю ключей этих чатов.
  Future<void> dropCorruptedChatKeys(List<int> chatIds) async {
    for (final id in chatIds) {
      await _storage.delete(key: '$_kWrappedPrefix$id');
      _chatKeyCache[id]?.dispose();
      _chatKeyCache.remove(id);
    }
  }

  // ====================================================================== //

  void _ensureUnlocked() {
    if (!isUnlocked) throw MasterLockedException();
  }

  Uint8List _randomBytes(int n) {
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = _rng.nextInt(256);
    }
    return out;
  }

  // F-NEW: убраны дубликаты _hex/_unhex — используем общий Hex utility.
  String _hex(Uint8List b) => Hex.encode(b);
  Uint8List _unhex(String s) => Hex.decode(s);
}

