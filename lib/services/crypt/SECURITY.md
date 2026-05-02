# SECURITY — Криптослой KometOld (Crypt → KometOld port)

Документ описывает модель угроз, защитные меры и известные ограничения
криптослоя `lib/services/crypt/`.

## Модель угроз

### От чего защищаемся

1. **Пассивный сетевой наблюдатель** (атака на трафик MAX-сервера).
   - Сообщения зашифрованы AES-256-GCM; tag даёт целостность.
   - text_codec обфускация скрывает факт шифрования от простых regex-фильтров.

2. **Скомпрометированный сервер MAX**.
   - Сервер видит только обфусцированный текст; ключи никогда не покидают
     устройство.
   - Метаданные (кто кому пишет) сервер всё равно видит — это вне нашей
     модели угроз.

3. **Кража физического устройства** при заблокированном экране.
   - Secure Storage защищён Keychain (iOS) / Android Keystore.
   - Без мастер-пароля приложения дешифровка невозможна.

4. **Подмена в Secure Storage** (rooted Android, jailbroken iOS).
   - Каждая обёртка `chat_key` имеет AAD-binding: `meta['chat'] = <chatId>`.
     Нельзя подсунуть обёртку чата 20 на место обёртки чата 10.
   - Любая модификация meta или ciphertext ломает GCM tag.

5. **Brute-force мастер-пароля**.
   - Argon2id 128 MiB, t=3, p=4 (OWASP balanced).
   - На современном GPU подбор 8-символьного случайного пароля займёт
     ≈10⁵ лет.

### От чего НЕ защищаемся

1. **Активный root/jailbreak с возможностью читать RAM работающего процесса**.
   Если злоумышленник может читать процесс — он увидит мастер-ключ и ключи
   чатов в открытом виде. См. F-03 ниже.

2. **Эвакуация ключей через GC** (ограничение Dart VM).
   Уничтожить все копии ключевых байтов после Argon2id невозможно — VM
   может оставить копии в young generation до следующего GC. См. F-03.

3. **Утечка через debug-логи**. Криптослой в production-сборке `flutter
   build` не логирует. В debug-сборках (`flutter run`) могут быть.

4. **Атаки по сторонним каналам** (timing, power analysis). DartAesGcm —
   pure Dart, не имеет защиты от cache-timing на shared CPU.

5. **Социальная инженерия** против пользователя.

## Защитные меры

| Угроза | Защита |
|---|---|
| Перебор пароля | Argon2id (128 MiB, t=3) |
| Подмена сообщения | AES-256-GCM tag (128 бит) |
| Подмена metadata | AAD = JSON metadata, любая модификация → InvalidTag |
| Перестановка обёрток ключей | meta['chat'] проверяется ДО unwrap |
| Truncation файла | AAD каждого чанка содержит is_last флаг |
| Reorder чанков | nonce_i = base_nonce XOR counter (BE 12 байт) |
| Reuse nonce | Random.secure() для base_nonce каждого файла |
| Время жизни ключа в RAM | SecretKey.dispose() с wipeBytes |
| Брутфорс мастера через storage | DoS-лимиты Argon2 параметров (max 1GiB, t=10) |

## Известные ограничения

### F-03 — копии ключей в RAM (Dart VM ограничение)

**Описание**: Dart VM не позволяет гарантированно уничтожить все копии
байтового буфера. После операции `cryptography.decryptSync()` plaintext
проходит через несколько слоёв: внутренние SecretBox-структуры, копии
List → Uint8List, GC young generation. Зачистка результирующего Uint8List
не гарантирует, что все промежуточные копии исчезли.

**Что мы делаем**:
- Mitigation 1: проверяем `meta['chat']` через `peekMeta()` ДО запуска
  AES-GCM. Если меньше совпадает — мы вообще не запускаем дешифровку,
  что исключает появление лишнего plaintext в RAM.
- Mitigation 2: SecretKey.dispose() вызывает wipe() на нашем буфере.
- Mitigation 3: master_key_manager.lock() очищает кэш всех ключей.

**Что не делаем (требует нативного кода)**:
- Хранить ключи в нативной памяти (mlock/SecKeyRef).
- Использовать iOS Secure Enclave / Android StrongBox для AES.

**Возможное улучшение для PR 3**: подключить `cryptography_flutter`,
который выполняет AES-GCM в нативном коде (Java/Swift). Тогда ключи
никогда не появляются в Dart heap, копий нет.

### F-06 (closed) — wipe XOR-ключа в legacy-декодере

XOR-ключ в `legacy_xor_codec.dart::decryptLegacy` теперь зачищается
через `wipeBytes()` в `finally`-блоке.

### Argon2id-параметры захардкожены

В `master_key_manager.dart` всегда используется `balanced` (128 MiB,
t=3, p=4). Профиль выбирается при `setupMasterPassword()` и сохраняется
в Secure Storage; меняется через настройки в PR 2.

## Аудит зависимостей

| Пакет | Версия | Использование | Статус |
|---|---|---|---|
| cryptography | ^2.7.0 | AES-GCM (sync DartAesGcm), Argon2id | активный |
| flutter_secure_storage | ^9.2.4 | хранение salt и обёрток | активный |
| shared_preferences | ^2.2.3 | конфиг чатов (НЕ ключевой материал) | активный |

Зависимость **package:encrypt** удалена из криптослоя (PR 1). Она
оставлена в pubspec.yaml только потому, что её всё ещё импортируют
несвязанные с шифрованием чатов файлы (token_auth_screen,
export_session_screen) — их миграция отдельным PR.

## Контакт для security-отчётов

Если вы нашли уязвимость — НЕ открывайте публичный issue. Свяжитесь
напрямую с командой через [TODO: добавить email/PGP-ключ].

## Changelog (security-relevant)

### Раунд аудита: исправления

- **F-PT-1: Path traversal при расшифровке файлов**.
  `original_name` из meta зашифрованного вложения шёл напрямую в
  `p.join(outDir, name)`. Если злоумышленник прописывал `"../../..."`
  или абсолютный путь, расшифрованный файл писался за пределы tempDir.
  Введён модуль `safe_filename.dart` с двухступенчатой защитой:
  `SafeFilename.sanitize` чистит имя, `SafeFilename.resolveWithin`
  валидирует итоговый канонический путь относительно parentDir.
  Применено в `EncryptedAttachmentService` и `EncryptedFileService`.

- **F-WP-1: Утечка ключей после Argon2id**. `packPasswordEncrypted`,
  `unpackPassword`, `_unwrapKey` и `encryptFile` (extra_password ветка)
  держали 32-байтный wrapper-ключ в памяти до GC, не вызывая `wipeBytes`.
  Теперь все эти функции зачищают деривированный ключ в `finally`-блоке.

- **F-DOS-2: Argon2id-параметры в _unwrapKey без валидации**.
  Подложенный файл с `memory_cost = 10^9` мог заставить устройство
  выделить ~гигабайт памяти. Добавлена та же валидация лимитов, что и
  в `_validatedArgon2Params` (max 1 GiB / t=1000 / parallelism=16).
  Заодно исправлен type-cast: `as int?` менялся на `(... as num?)?.toInt()`,
  чтобы JSON-double’ы (например, `3.0`) не выкидывали TypeError.

- **F-RACE-1: Гонка в `getOrCreateChatKey`**. Две параллельные сессии
  (например, из двух чат-окон) для нового chatId могли сгенерировать
  два разных ключа, оба записать в storage и потерять сообщения,
  зашифрованные первым ключом. Введён `_chatKeyInFlight` Map с общим
  Future для всех ожидающих. `importChatKey` теперь дожидается
  in-flight `getOrCreate`, прежде чем перезаписывать.

- **F-RACE-2: Гонка в `_migrateInlineKeyToReference`**. При быстром
  поступлении нескольких сообщений в один legacy-чат `unawaited`-
  миграция запускалась дублирующе, что приводило к временному сбою
  расшифровки последующих сообщений. Добавлен per-chatId in-flight
  Map с проверкой свежести конфига.

- **F-QR-1: QR-сканер не останавливался**. `MobileScanner.onDetect`
  стрелял каждым кадром, спамя `_onCodeAcquired` и `setState`. Добавлен
  флаг `_scannerHandled` и явный `controller.stop()` при первом успешном
  декодировании. Сам контроллер теперь создаётся один раз (а не в
  каждом `build`) — устранена утечка камеры.

- **F-KE-1: Усиление key-share энтропии и KDF**. Авто-passphrase: 4 слова
  → 6 слов из 128-словного словаря (~28 бит → ~42 бита). Argon2id-
  параметры: `lite (64MiB, t=2)` → `balanced (128MiB, t=3)`. Минимальная
  длина user-passphrase: 6 → 8 символов. Полный перебор автоматической
  6-словной фразы при balanced-Argon2 занимает >100 лет на single-GPU.

- **F-RT-1: Rate limiting на unlock**. Прогрессивный cooldown после 5
  неудачных попыток (5/10/20/40/60 сек), после 10 — 5 минут. Счётчик
  попыток и время cooldown персистятся в SharedPreferences (выживают
  перезапуск приложения). Авто-биометрия не запускается во время
  cooldown. После успеха или nuclearReset счётчик сбрасывается.

- **F-LB-1: Персистенция времени ухода в фон**. `_lastBackgroundedAt`
  раньше жил только в RAM — если ОС убивала процесс в фоне, таймер
  auto-relock сбрасывался. Теперь время сохраняется в SharedPreferences
  и проверяется после холодного старта. Добавлена обработка
  `AppLifecycleState.detached` (iOS app extension shutdown).

- **F-CFG-1: setPasswordForChat / setSendEncryptedForChat теряли
  настройки**. При создании нового конфига (current == null) функции
  передавали только `{password, sendEncrypted}`, что молча сбрасывало
  legacyXorPassword, obfuscationProfile, encryptedFileExtension и
  encryptFiles. Теперь полагаемся на дефолты конструктора
  `ChatEncryptionConfig`, что защищает от регрессий при добавлении
  новых полей.

- **F-MISC: Мелочи**.
  - `peekFileMeta` теперь валидирует CRPT version (раньше пропускал).
  - `_xor` в legacy-кодеке защищён от пустого ключа.
  - AAD в `_aesGcmEncryptShort/Decrypt` использует именованную пустую
    константу (избавились от `null` vs `[]` смешивания).
  - Детерминированный fallback при выборе профиля text_codec.
  - Очистка `TextEditingController` после успешного setup/change/unlock.
  - Удаление temp-файла с экспортированным ключом сразу после share.
  - Санитизация расширения зашифрованных файлов (только `[a-z0-9]`,
    не более 10 символов).
  - Hex-энкодинг вынесен в общий `Hex` utility — устранены 4 дубликата.
  - Префиксы SharedPreferences вынесены в публичные константы
    `ChatEncryptionService.{config,legacyPassword}KeyPrefix` —
    `migration_v2` теперь не держит свои копии.
  - Явный `DecryptToBytesResult` с разделёнными состояниями
    "не зашифровано" / "ошибка расшифровки" / "ошибка чтения".

