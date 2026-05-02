// key_share_codec.dart — экспорт и импорт chat_key для двусторонней
// зашифрованной переписки.
//
// Сценарий:
//   Алиса включает шифрование в чате с Бобом.
//   - У Алисы создаётся случайный chat_key_AB (32 байта), обёрнут её мастером.
//   - Чтобы Боб мог расшифровывать сообщения Алисы — у него должен быть
//     ТОТ ЖЕ chat_key_AB.
//   - Алиса жмёт «Поделиться ключом» → выбирает «QR» или «QR + пароль».
//   - Боб сканирует QR (если есть пароль — вводит). У него теперь тот же
//     chat_key_AB, обёрнутый его мастером.
//
// Формат строки экспорта:
//   "kshare:v1:<base64url(crpt_blob)>"
//
// crpt_blob — это CRPT-формат:
//   - KDF_DIRECT (без пароля) — chat_key зашифрован случайным «общим
//     ключом» который встроен в blob? НЕТ — это бессмысленно.
//     Правильно: KDF_DIRECT означает «ключ передан в plain», но мы не
//     можем передать chat_key plain через QR без шифрования (хотя QR-
//     канал визуальный, риск утечки минимален, но всё же).
//   - KDF_PASSWORD — chat_key обёрнут паролем-фразой через Argon2id.
//
// Решение: ВСЕГДА используем KDF_PASSWORD. Если пользователь выбрал
// «без пароля» — мы генерим короткую passphrase (4 случайных слова) и
// показываем её ему рядом с QR. Получатель вводит passphrase. Это
// защищает от случайной утечки QR (например, фото в облаке).
//
// passphrase = 4 случайных слова из встроенного словаря (~100 слов
// русских существительных), пробелами:
//   "лампа дерево окно скала"
// Это ~26 бит энтропии, чего достаточно для краткосрочного канала
// (passphrase живёт минуты, не годы).
//
// Если пользователь выбирает СВОЙ пароль — он его вводит, а получателю
// сообщает (голосом, отдельным каналом).
//
// Параметры Argon2id для key-share — раньше были lite (64 MiB, t=2),
// что в сочетании с 28-битной passphrase давало слишком слабую защиту:
// passphrase из 4 слов перебирается за минуты на GPU. Усилили до
// balanced-эквивалента (128 MiB, t=3), а длина passphrase — 6 слов
// (~42 бит для 128-словного словаря, ~48 бит для 256-словного).

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'crypt_format.dart';

const String keyShareSchemePrefix = 'kshare:v1:';

/// Параметры Argon2id для key-share.
/// F-NEW fix: подняли с 64 MiB / t=2 до 128 MiB / t=3 — те же что balanced
/// для мастер-пароля. Argon2id занимает ~2 сек на телефоне, что приемлемо
/// для разовой операции импорта.
const Map<String, int> _kdfParams = {
  'time_cost': 3,
  'memory_cost': 131072, // 128 MiB
  'parallelism': 4,
};

/// Длина авто-passphrase в словах. 6 слов из 128-словного словаря дают
/// ~42 бит энтропии — этого достаточно для краткосрочного канала
/// при Argon2id ~2 сек/попытка (полный перебор > 100 лет на single-GPU).
const int _autoPassphraseWordCount = 6;

/// Метаданные общего ключа.
class KeyShareMeta {
  /// Произвольное имя, которое отправитель вписывает (например, своё имя
  /// или «Чат с Алисой»). Получатель увидит при импорте.
  final String? label;

  /// Числовой ID чата у отправителя. Получателю показывается, но не
  /// обязательно соответствует ID чата у получателя — он сам выбирает,
  /// в какой чат импортировать.
  final int? senderChatId;

  /// Профиль обфускации, который использует отправитель (получатель
  /// должен использовать тот же или совместимый — все встроенные
  /// профили взаимно совместимы при decode, потому что decode перебирает
  /// все).
  final String obfuscationProfile;

  /// Метка времени создания (UTC unix seconds). Получатель может
  /// предупредить если код старее N часов.
  final int createdAt;

  const KeyShareMeta({
    this.label,
    this.senderChatId,
    this.obfuscationProfile = 'ru_full',
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        if (label != null) 'label': label,
        if (senderChatId != null) 'chat': senderChatId,
        'profile': obfuscationProfile,
        'created_at': createdAt,
        'kind': 'chatkey_share',
        'v': 1,
      };

  factory KeyShareMeta.fromJson(Map<String, dynamic> json) => KeyShareMeta(
        label: json['label'] as String?,
        senderChatId: (json['chat'] as num?)?.toInt(),
        obfuscationProfile:
            (json['profile'] as String?) ?? 'ru_full',
        createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      );
}

/// Результат построения экспорта.
class KeyShareExport {
  /// Закодированная строка для QR / клипборда.
  final String encoded;

  /// Passphrase для расшифровки. Если пользователь задал свой — это его
  /// строка. Если выбрал «авто» — это сгенерированная фраза, которую
  /// нужно показать пользователю.
  final String passphrase;

  /// True, если passphrase сгенерирована автоматически (нужно показать).
  /// False, если пользователь ввёл свою.
  final bool passphraseGenerated;

  KeyShareExport({
    required this.encoded,
    required this.passphrase,
    required this.passphraseGenerated,
  });
}

/// Результат импорта (до проверки пароля).
class KeyShareDecoded {
  /// Распакованный chat_key (32 байта).
  final Uint8List chatKey;

  /// Метаданные из публичной части.
  final KeyShareMeta meta;

  KeyShareDecoded({required this.chatKey, required this.meta});
}

/// Экспортирует chat_key в строку.
///
/// [chatKey] — 32 байта, ключ чата.
/// [userPassphrase] — если задан, используется как пароль.
///                    Если null — генерируется случайная фраза из словаря.
/// [meta] — публичные метаданные.
Future<KeyShareExport> exportChatKey({
  required Uint8List chatKey,
  required KeyShareMeta meta,
  String? userPassphrase,
}) async {
  if (chatKey.length != 32) {
    throw ArgumentError('chat_key must be 32 bytes');
  }

  String passphrase;
  bool generated;
  if (userPassphrase == null || userPassphrase.isEmpty) {
    passphrase = _generatePassphrase(_autoPassphraseWordCount);
    generated = true;
  } else {
    // F-NEW fix: подняли минимум с 6 до 8 — 6-символьная random ASCII даёт
    // только ~36 бит, что слабее даже автоматической фразы. 8 символов —
    // приемлемый минимум, и UI должен поощрять длиннее (см. экран).
    if (userPassphrase.length < 8) {
      throw ArgumentError('Свой пароль должен быть минимум 8 символов');
    }
    passphrase = userPassphrase;
    generated = false;
  }

  // Шифруем chat_key passphrase'ой через KDF_PASSWORD.
  final blob = await packPasswordEncrypted(
    password: passphrase,
    plaintext: chatKey,
    publicMeta: meta.toJson(),
    kdfParams: _kdfParams,
  );

  // base64url для безопасного включения в QR без проблем с экранированием.
  final encoded = '$keyShareSchemePrefix${base64UrlEncode(blob)}';
  return KeyShareExport(
    encoded: encoded,
    passphrase: passphrase,
    passphraseGenerated: generated,
  );
}

/// Возвращает только метаданные из закодированной строки (без passphrase).
/// Полезно чтобы показать «откуда» и «когда» до того как пользователь
/// введёт пароль.
KeyShareMeta peekShareMeta(String encoded) {
  if (!encoded.startsWith(keyShareSchemePrefix)) {
    throw const FormatException(
      'Неподдерживаемая схема экспорта ключа',
    );
  }
  final blob = base64Url.decode(encoded.substring(keyShareSchemePrefix.length));
  final pub = peekMeta(blob);
  return KeyShareMeta.fromJson(pub);
}

/// Расшифровывает экспорт с заданной passphrase.
/// Бросает [Exception] при неверной passphrase или повреждённой строке.
Future<KeyShareDecoded> importChatKey({
  required String encoded,
  required String passphrase,
}) async {
  if (!encoded.startsWith(keyShareSchemePrefix)) {
    throw const FormatException(
      'Неподдерживаемая схема экспорта ключа',
    );
  }
  final Uint8List blob;
  try {
    blob = base64Url.decode(encoded.substring(keyShareSchemePrefix.length));
  } catch (_) {
    throw const FormatException('Битая base64-кодировка');
  }

  final result = await unpackPassword(password: passphrase, blob: blob);
  if (result.plaintext.length != 32) {
    throw FormatException(
      'Неверная длина ключа: ${result.plaintext.length}, ожидалось 32',
    );
  }
  return KeyShareDecoded(
    chatKey: result.plaintext,
    meta: KeyShareMeta.fromJson(result.publicMeta),
  );
}

// ========================================================================== //
//                        ГЕНЕРАЦИЯ PASSPHRASE
// ========================================================================== //

/// Словарь русских существительных для авто-passphrase.
/// 128 уникальных слов = 7 бит/слово. 6 слов = 42 бит энтропии (~4.4×10^12
/// комбинаций). При Argon2id с балансом 128 MiB / t=3 (~2 сек/попытка)
/// полный перебор займёт > 100 лет на single-GPU, что достаточно даже
/// для долгоживущего канала.
const List<String> _wordlist = [
  'апрель', 'башня', 'волна', 'гора', 'дом', 'ель', 'жук', 'звезда',
  'игла', 'йога', 'кот', 'лес', 'мост', 'небо', 'окно', 'пар',
  'река', 'снег', 'трава', 'улей', 'факел', 'хлеб', 'цветок', 'чай',
  'шар', 'щука', 'ягода', 'аист', 'буря', 'ветер', 'голос', 'дождь',
  'енот', 'жасмин', 'заря', 'игра', 'камень', 'лето', 'мечта', 'нота',
  'остров', 'парус', 'роща', 'свеча', 'тайна', 'утро', 'фонарь', 'холм',
  'циркуль', 'часы', 'шёлк', 'эхо', 'якорь', 'арка', 'берёза', 'вечер',
  'грусть', 'дерево', 'ёлка', 'жатва', 'зима', 'имя', 'клён', 'луна',
  'море', 'нить', 'обруч', 'путь', 'радуга', 'свет', 'тень', 'улыбка',
  'фея', 'хвоя', 'цапля', 'черта', 'шорох', 'эра', 'юг', 'ясень',
  'арена', 'бриз', 'волк', 'грань', 'дюна', 'дельта', 'жёлудь', 'зерно',
  'ива', 'круг', 'липа', 'мак', 'нерпа', 'олень', 'почка', 'роса',
  'степь', 'тополь', 'утка', 'фиалка', 'хор', 'хвостик', 'чага', 'шалфей',
  'эфир', 'юла', 'якут', 'ангел', 'бубен', 'верба', 'гавань', 'дрозд',
  'ермак', 'жираф', 'зефир', 'индиго', 'кедр', 'ландыш', 'мята', 'нарцисс',
  'омут', 'пион', 'рябина', 'сирень', 'туман', 'ушанка', 'фрегат', 'хмель',
];

String _generatePassphrase(int wordCount) {
  // F-NEW: assert проверяет инвариант словаря на этапе разработки.
  // В release-сборке assert выпиливается, но если кто-то редактирует
  // _wordlist и случайно вставит дубликат — энтропия упадёт ниже
  // заявленной. Эта проверка ловит такие правки в debug.
  assert(_wordlist.toSet().length == _wordlist.length,
      '_wordlist contains duplicates — entropy claim is wrong');
  final rng = Random.secure();
  final words = <String>[];
  for (var i = 0; i < wordCount; i++) {
    words.add(_wordlist[rng.nextInt(_wordlist.length)]);
  }
  return words.join(' ');
}
