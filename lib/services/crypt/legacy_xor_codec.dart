// legacy_xor_codec.dart — READ-ONLY декодер старого формата XOR-шифрования.
//
// Этот модуль используется ТОЛЬКО для расшифровки исторических сообщений,
// зашифрованных предыдущей версией KometOld до миграции на AES-GCM.
// Шифровать новый трафик этим кодом ЗАПРЕЩЕНО — XOR над повторяющимся
// ключом ломается тривиально (Vigenère).
//
// Формат старых сообщений:
//   - Маркер 1: префикс `kometSM.` + base64(payload) с заменой
//     `+/=` → `привет/незнаю/хм`
//   - Маркер 2: digit-prefix + base64(payload) с заменой английских букв на
//     русские по карте + замена спецсимволов
//
// payload — JSON {"s": base64(salt[8]), "c": base64(xor(plain, password+salt))}
//
// Логика 1-в-1 с lib/services/chat_encryption_service.dart версии до миграции
// (см. /KometOld-main/lib/services/chat_encryption_service.dart, метод
// decryptWithPassword).
//
// EncryptionCharMapping остаётся в проекте как есть и используется отсюда.

import 'dart:convert';
import 'dart:typed_data';

import 'package:gwid/services/encryption_char_mapping.dart';

/// Префикс старых сообщений «нового» XOR-формата (после kometSM-фазы).
const String legacyEncryptedPrefix = 'kometSM.';

/// Расшифровывает legacy XOR-сообщение указанным паролем. Возвращает
/// plaintext или null если не удалось (неверный пароль / повреждённое /
/// не наш формат).
///
/// **НЕ ИСПОЛЬЗУЕТСЯ ДЛЯ НОВЫХ СООБЩЕНИЙ** — только для чтения архива.
String? decryptLegacy(String password, String text) {
  if (text.isEmpty) return null;

  String payloadB64;

  if (text.startsWith(legacyEncryptedPrefix)) {
    payloadB64 = text.substring(legacyEncryptedPrefix.length);
    payloadB64 = EncryptionCharMapping.restoreBase64SpecialChars(payloadB64);
  } else {
    // digit-prefix format: цифры в начале — это контрольная сумма+шум.
    var prefixLength = 0;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (int.tryParse(ch) != null) {
        prefixLength++;
      } else {
        break;
      }
    }

    if (prefixLength == 0) return null;
    if (text.length <= prefixLength) return null;

    payloadB64 = text.substring(prefixLength);
    payloadB64 = EncryptionCharMapping.restoreBase64SpecialChars(payloadB64);
    payloadB64 = EncryptionCharMapping.replaceRussianWithEnglish(payloadB64);
  }

  try {
    final decodedBytes = base64Decode(payloadB64);
    final payloadJson = utf8.decode(decodedBytes);
    final data = jsonDecode(payloadJson) as Map<String, dynamic>;

    final salt = base64Decode(data['s'] as String);
    final cipherBytes = base64Decode(data['c'] as String);

    final key = Uint8List.fromList([...utf8.encode(password), ...salt]);
    try {
      final plainBytes = _xor(cipherBytes, key);
      return utf8.decode(plainBytes);
    } finally {
      // F-06 fix: затираем XOR-ключ (содержит пароль) сразу после
      // использования, чтобы он не висел в RAM до GC.
      _wipe(key);
    }
  } catch (_) {
    return null;
  }
}

/// Локальная функция wipe (не импортируем secret_key.dart, чтобы не
/// тащить в legacy-модуль зависимости — он самодостаточен).
void _wipe(Uint8List buf) {
  for (var i = 0; i < buf.length; i++) {
    buf[i] = 0;
  }
}

/// Эвристика: похоже ли это на legacy-зашифрованное сообщение.
/// Legacy XOR формат:
///   - "kometSM." префикс (явный маркер старых версий), ИЛИ
///   - Числовой префикс (длина) + кириллический payload БЕЗ ПРОБЕЛОВ
///     (XOR над UTF-8 кириллицы даёт кириллицу). Внутри часто "хм" / "хмхм"
///     как XOR-padding.
///
/// Отличие от нового формата (text_codec): новый ВСЕГДА содержит пробелы
/// (маскировка), legacy — никогда. Это надёжный разделитель.
bool looksLikeLegacy(String text) {
  if (text.isEmpty) return false;
  if (text.startsWith(legacyEncryptedPrefix)) return true;

  // Содержит пробелы — это новый text_codec формат, не legacy.
  if (text.contains(' ')) return false;

  // Legacy всегда начинается с числового префикса (длина payload).
  var prefixLength = 0;
  for (var i = 0; i < text.length; i++) {
    if (int.tryParse(text[i]) != null) {
      prefixLength++;
    } else {
      break;
    }
  }
  if (prefixLength == 0) return false;
  if (text.length <= prefixLength) return false;

  final payloadPart = text.substring(prefixLength);
  if (payloadPart.length < 20) return false;

  // Допустимые символы legacy payload (кириллица + латиница + цифры/_/-)
  final validChars = RegExp(r'^[А-Яа-яA-Za-z0-9_-]+$');
  if (!validChars.hasMatch(payloadPart)) return false;

  // Должна быть кириллица или специфические маркеры старого формата
  final hasRussian = RegExp(r'[А-Яа-я]').hasMatch(payloadPart);
  final hasMarkers = payloadPart.contains('хм') ||
      payloadPart.contains('привет') ||
      payloadPart.contains('незнаю');

  return hasRussian || hasMarkers;
}

Uint8List _xor(Uint8List data, Uint8List key) {
  // F-NEW fix: пустой ключ привёл бы к `% 0` → ArithmeticError. Хотя на
  // практике key всегда непуст (password+salt), guard снимает риск
  // регрессии при изменениях вокруг.
  if (key.isEmpty) {
    throw ArgumentError('XOR key must be non-empty');
  }
  final out = Uint8List(data.length);
  for (var i = 0; i < data.length; i++) {
    out[i] = data[i] ^ key[i % key.length];
  }
  return out;
}
