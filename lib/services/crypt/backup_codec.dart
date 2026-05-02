// backup_codec.dart — экспорт/импорт ВСЕХ chat_keys пользователя в
// один резервный файл, защищённый отдельным паролем.
//
// Назначение: позволить пользователю сделать backup перед сменой
// устройства / переустановкой / nuclearReset.
//
// Формат backup-файла (бинарный, .kbak):
//
//   CRPT(KDF_PASSWORD, plaintext = JSON{
//     "v": 1,
//     "kind": "kometold_keys_backup",
//     "created_at": <unix_seconds>,
//     "keys": [
//       {"chat_id": 42, "key": "<hex 32 bytes>", "profile": "ru_full"},
//       ...
//     ]
//   })
//
// Защищён Argon2id(backup_password) — отдельный пароль на backup, не
// мастер-пароль. Это позволяет хранить backup в облаке (Google Drive,
// iCloud) без риска: даже если backup утечёт, без backup_password он
// бесполезен.

import 'dart:convert';
import 'dart:typed_data';

import 'crypt_format.dart';
import 'hex.dart';

const String backupKindMarker = 'kometold_keys_backup';
const int backupCurrentVersion = 1;

/// Параметры Argon2id для backup. Сильнее чем для key-share (backup живёт
/// долго, у злоумышленника много времени на подбор).
const Map<String, int> _backupKdfParams = {
  'time_cost': 4,
  'memory_cost': 262144, // 256 MiB — strong
  'parallelism': 4,
};

/// Один ключ внутри backup.
class BackupChatKey {
  final int chatId;
  final Uint8List key;
  final String? profile;
  final String? legacyXorPassword;

  BackupChatKey({
    required this.chatId,
    required this.key,
    this.profile,
    this.legacyXorPassword,
  });

  Map<String, dynamic> toJson() => {
        'chat_id': chatId,
        'key': _hex(key),
        if (profile != null) 'profile': profile,
        if (legacyXorPassword != null) 'legacy_xor': legacyXorPassword,
      };

  factory BackupChatKey.fromJson(Map<String, dynamic> j) => BackupChatKey(
        chatId: (j['chat_id'] as num).toInt(),
        key: _unhex(j['key'] as String),
        profile: j['profile'] as String?,
        legacyXorPassword: j['legacy_xor'] as String?,
      );
}

/// Создаёт backup-blob с заданным паролем.
/// [keys] копируются — caller может wipe-ать после возврата.
Future<Uint8List> packBackup({
  required String backupPassword,
  required List<BackupChatKey> keys,
}) async {
  if (backupPassword.length < 8) {
    throw ArgumentError('Пароль backup минимум 8 символов');
  }
  final body = jsonEncode({
    'v': backupCurrentVersion,
    'kind': backupKindMarker,
    'created_at': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
    'keys': keys.map((k) => k.toJson()).toList(),
  });

  return packPasswordEncrypted(
    password: backupPassword,
    plaintext: Uint8List.fromList(utf8.encode(body)),
    publicMeta: {
      'kind': backupKindMarker,
      'v': backupCurrentVersion,
    },
    kdfParams: _backupKdfParams,
  );
}

/// Распаковывает backup-blob.
/// Бросает [Exception] при неверном пароле или повреждённом blob.
Future<List<BackupChatKey>> unpackBackup({
  required String backupPassword,
  required Uint8List blob,
}) async {
  final result = await unpackPassword(
    password: backupPassword,
    blob: blob,
  );
  final body = jsonDecode(utf8.decode(result.plaintext))
      as Map<String, dynamic>;
  if (body['kind'] != backupKindMarker) {
    throw const FormatException('Не KometOld backup');
  }
  if (body['v'] != backupCurrentVersion) {
    throw FormatException('Неподдерживаемая версия backup: ${body['v']}');
  }
  final keys = (body['keys'] as List)
      .map((j) => BackupChatKey.fromJson(j as Map<String, dynamic>))
      .toList();
  return keys;
}

String _hex(Uint8List b) => Hex.encode(b);
Uint8List _unhex(String s) => Hex.decode(s);
