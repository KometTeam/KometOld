import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

class ContactLocalNamesService {
  static final ContactLocalNamesService _instance =
      ContactLocalNamesService._internal();
  factory ContactLocalNamesService() => _instance;
  ContactLocalNamesService._internal();
  final Map<int, Map<String, dynamic>> _cache = {};

  final _changesController = StreamController<int>.broadcast();
  Stream<int> get changes => _changesController.stream;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      for (final key in keys) {
        if (key.startsWith('contact_')) {
          final contactIdStr = key.replaceFirst('contact_', '');
          final contactId = int.tryParse(contactIdStr);

          if (contactId != null) {
            final data = prefs.getString(key);
            if (data != null) {
              try {
                final decoded = jsonDecode(data) as Map<String, dynamic>;
                final avatarPath = decoded['avatarPath'] as String?;
                if (avatarPath != null) {
                  final file = File(avatarPath);
                  if (!await file.exists()) {
                    decoded.remove('avatarPath');
                  }
                }
                _cache[contactId] = decoded;
              } catch (e) {
                print(
                  'Ошибка парсинга локальных данных для контакта $contactId: $e',
                );
              }
            }
          }
        }
      }

      _initialized = true;
    } catch (e) {
      print('Error initializing ContactLocalNamesService: $e');
    }
  }

  Map<String, dynamic>? getContactData(int contactId) {
    return _cache[contactId];
  }

  String getDisplayName({
    required int contactId,
    String? originalName,
    String? originalFirstName,
    String? originalLastName,
  }) {
    final localData = _cache[contactId];

    if (localData != null) {
      final nickname = localData['nickname'] as String?;
      if (nickname != null && nickname.isNotEmpty) {
        return nickname;
      }

      final firstName = localData['firstName'] as String?;
      final lastName = localData['lastName'] as String?;

      if (firstName != null && firstName.isNotEmpty ||
          lastName != null && lastName.isNotEmpty) {
        final fullName = '${firstName ?? ''} ${lastName ?? ''}'.trim();
        if (fullName.isNotEmpty) {
          return fullName;
        }
      }
    }

    if (originalFirstName != null || originalLastName != null) {
      final fullName = '${originalFirstName ?? ''} ${originalLastName ?? ''}'
          .trim();
      if (fullName.isNotEmpty) return fullName;
    }

    if (originalName != null && originalName.isNotEmpty) {
      return originalName;
    }

    return contactId.toString();
  }

  String? getDisplayDescription({
    required int contactId,
    String? originalDescription,
  }) {
    final localData = _cache[contactId];

    if (localData != null) {
      final notes = localData['notes'] as String?;
      if (notes != null && notes.isNotEmpty) {
        return notes;
      }
    }

    return originalDescription;
  }

  Future<String?> saveContactAvatar(File imageFile, int contactId) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final avatarDir = Directory('${directory.path}/contact_avatars');

      if (!await avatarDir.exists()) {
        await avatarDir.create(recursive: true);
      }

      final fileName = 'contact_$contactId.jpg';
      final savePath = '${avatarDir.path}/$fileName';

      await imageFile.copy(savePath);

      final localData = _cache[contactId] ?? {};
      localData['avatarPath'] = savePath;
      _cache[contactId] = localData;

      final prefs = await SharedPreferences.getInstance();
      final key = 'contact_$contactId';
      await prefs.setString(key, jsonEncode(localData));

      _changesController.add(contactId);

      print('✅ Локальный аватар контакта сохранен: $savePath');
      return savePath;
    } catch (e) {
      print('❌ Ошибка сохранения локального аватара контакта: $e');
      return null;
    }
  }

  String? getContactAvatarPath(int contactId) {
    final localData = _cache[contactId];
    if (localData != null) {
      return localData['avatarPath'] as String?;
    }
    return null;
  }

  String? getDisplayAvatar({
    required int contactId,
    String? originalAvatarUrl,
  }) {
    final localAvatarPath = getContactAvatarPath(contactId);
    if (localAvatarPath != null) {
      final file = File(localAvatarPath);
      if (file.existsSync()) {
        return 'file://$localAvatarPath';
      } else {
        final localData = _cache[contactId];
        if (localData != null) {
          localData.remove('avatarPath');
          _cache[contactId] = localData;
        }
      }
    }

    return originalAvatarUrl;
  }

  Future<void> removeContactAvatar(int contactId) async {
    try {
      final localData = _cache[contactId];
      if (localData != null) {
        final avatarPath = localData['avatarPath'] as String?;
        if (avatarPath != null) {
          final file = File(avatarPath);
          if (await file.exists()) {
            await file.delete();
          }
        }

        localData.remove('avatarPath');
        _cache[contactId] = localData;

        final prefs = await SharedPreferences.getInstance();
        final key = 'contact_$contactId';
        await prefs.setString(key, jsonEncode(localData));

        _changesController.add(contactId);

        print('✅ Локальный аватар контакта удален');
      }
    } catch (e) {
      print('❌ Ошибка удаления локального аватара контакта: $e');
    }
  }

  Future<void> saveContactData(int contactId, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'contact_$contactId';
      await prefs.setString(key, jsonEncode(data));

      _cache[contactId] = data;

      _changesController.add(contactId);

      print('✅ Сохранены локальные данные для контакта $contactId');
    } catch (e) {
      print('❌ Ошибка сохранения локальных данных контакта: $e');
    }
  }

  Future<void> clearContactData(int contactId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'contact_$contactId';
      await prefs.remove(key);

      _cache.remove(contactId);

      _changesController.add(contactId);

      print('✅ Очищены локальные данные для контакта $contactId');
    } catch (e) {
      print('❌ Ошибка очистки локальных данных контакта: $e');
    }
  }

  void clearCache() {
    _cache.clear();
  }

  void dispose() {
    _changesController.close();
  }
}
