import 'dart:io';
import 'package:gwid/services/cache_service.dart';
import 'package:gwid/services/cache_settings_service.dart';
import 'package:gwid/models/profile.dart';
import 'package:path_provider/path_provider.dart';

class ProfileCacheService {
  static final ProfileCacheService _instance = ProfileCacheService._internal();
  factory ProfileCacheService() => _instance;
  ProfileCacheService._internal();

  final CacheService _cacheService = CacheService();
  final CacheSettingsService _settingsService = CacheSettingsService();

  static const String _profileKey = 'my_profile_data';
  static const String _profileAvatarKey = 'my_profile_avatar';

  // TTL берется из настроек
  Duration get _profileTTL => _settingsService.currentSettings.profileTTL;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    await _cacheService.initialize();
    await _settingsService.initialize();
    _initialized = true;
    print('✅ ProfileCacheService инициализирован');
  }

  Future<void> saveProfileData({
    required int userId,
    required String firstName,
    required String lastName,
    String? description,
    String? photoBaseUrl,
    int? photoId,
  }) async {
    try {
      final profileData = {
        'userId': userId,
        'firstName': firstName,
        'lastName': lastName,
        'description': description,
        'photoBaseUrl': photoBaseUrl,
        'photoId': photoId,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      await _cacheService.set(_profileKey, profileData, ttl: _profileTTL);
      print('✅ Данные профиля сохранены в кэш: $firstName $lastName');
    } catch (e) {
      print('❌ Ошибка сохранения профиля в кэш: $e');
    }
  }

  Future<Map<String, dynamic>?> getProfileData() async {
    try {
      final cached = await _cacheService.get<Map<String, dynamic>>(
        _profileKey,
        ttl: _profileTTL,
      );

      if (cached != null) {
        print('✅ Данные профиля загружены из кэша');
        return cached;
      }
    } catch (e) {
      print('❌ Ошибка загрузки профиля из кэша: $e');
    }
    return null;
  }

  Future<String?> saveAvatar(File imageFile, int userId) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final avatarDir = Directory('${directory.path}/avatars');

      if (!await avatarDir.exists()) {
        await avatarDir.create(recursive: true);
      }

      final fileName = 'profile_$userId.jpg';
      final savePath = '${avatarDir.path}/$fileName';

      await imageFile.copy(savePath);

      await _cacheService.set(_profileAvatarKey, savePath, ttl: _profileTTL);

      print('✅ Аватар сохранен локально: $savePath');
      return savePath;
    } catch (e) {
      print('❌ Ошибка сохранения аватара: $e');
      return null;
    }
  }

  Future<String?> getLocalAvatarPath() async {
    try {
      final path = await _cacheService.get<String>(
        _profileAvatarKey,
        ttl: _profileTTL,
      );

      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          print('✅ Локальный аватар найден: $path');
          return path;
        } else {
          await _cacheService.remove(_profileAvatarKey);
        }
      }
    } catch (e) {
      print('❌ Ошибка загрузки локального аватара: $e');
    }
    return null;
  }

  Future<void> updateProfileFields({
    String? firstName,
    String? lastName,
    String? description,
    String? photoBaseUrl,
  }) async {
    try {
      final currentData = await getProfileData();
      if (currentData == null) {
        print('⚠️ Нет сохраненных данных профиля для обновления');
        return;
      }

      if (firstName != null) currentData['firstName'] = firstName;
      if (lastName != null) currentData['lastName'] = lastName;
      if (description != null) currentData['description'] = description;
      if (photoBaseUrl != null) currentData['photoBaseUrl'] = photoBaseUrl;

      currentData['updatedAt'] = DateTime.now().toIso8601String();

      await _cacheService.set(_profileKey, currentData, ttl: _profileTTL);
      print('✅ Поля профиля обновлены в кэше');
    } catch (e) {
      print('❌ Ошибка обновления полей профиля: $e');
    }
  }

  Future<void> clearProfileCache() async {
    try {
      await _cacheService.remove(_profileKey);
      await _cacheService.remove(_profileAvatarKey);

      final avatarPath = await getLocalAvatarPath();
      if (avatarPath != null) {
        final file = File(avatarPath);
        if (await file.exists()) {
          await file.delete();
        }
      }

      print('✅ Кэш профиля очищен');
    } catch (e) {
      print('❌ Ошибка очистки кэша профиля: $e');
    }
  }

  Future<void> syncWithServerProfile(Profile serverProfile) async {
    try {
      final cachedData = await getProfileData();

      if (cachedData != null) {
        print(
          '⚠️ Локальные данные профиля уже существуют, пропускаем синхронизацию',
        );
        return;
      }

      await saveProfileData(
        userId: serverProfile.id,
        firstName: serverProfile.firstName,
        lastName: serverProfile.lastName,
        description: serverProfile.description,
        photoBaseUrl: serverProfile.photoBaseUrl,
        photoId: serverProfile.photoId,
      );
      print('✅ Профиль инициализирован с сервера');
    } catch (e) {
      print('❌ Ошибка синхронизации профиля: $e');
    }
  }

  Future<Profile?> getMergedProfile(Profile? serverProfile) async {
    try {
      final cachedData = await getProfileData();

      if (cachedData == null && serverProfile == null) {
        return null;
      }

      if (cachedData == null && serverProfile != null) {
        return serverProfile;
      }

      if (cachedData != null && serverProfile == null) {
        return Profile(
          id: cachedData['userId'] ?? 0,
          phone: '',
          firstName: cachedData['firstName'] ?? '',
          lastName: cachedData['lastName'] ?? '',
          description: cachedData['description'],
          photoBaseUrl: cachedData['photoBaseUrl'],
          photoId: cachedData['photoId'] ?? 0,
          updateTime: 0,
          options: [],
          accountStatus: 0,
          profileOptions: [],
        );
      }

      return Profile(
        id: serverProfile!.id,
        phone: serverProfile.phone,
        firstName: cachedData!['firstName'] ?? serverProfile.firstName,
        lastName: cachedData['lastName'] ?? serverProfile.lastName,
        description: cachedData['description'] ?? serverProfile.description,
        photoBaseUrl: cachedData['photoBaseUrl'] ?? serverProfile.photoBaseUrl,
        photoId: cachedData['photoId'] ?? serverProfile.photoId,
        updateTime: serverProfile.updateTime,
        options: serverProfile.options,
        accountStatus: serverProfile.accountStatus,
        profileOptions: serverProfile.profileOptions,
      );
    } catch (e) {
      print('❌ Ошибка получения объединенного профиля: $e');
      return serverProfile;
    }
  }

  Future<bool> hasLocalChanges() async {
    try {
      final cachedData = await getProfileData();
      return cachedData != null;
    } catch (e) {
      return false;
    }
  }
}
