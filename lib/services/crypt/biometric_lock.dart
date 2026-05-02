// biometric_lock.dart — биометрическая разблокировка master_key.
//
// Архитектура:
//   - Флаг "биометрия включена" (boolean) храним в SharedPreferences.
//   - Сам master_key (32 байта hex) храним во flutter_secure_storage
//     с дефолтными опциями (encryptedSharedPreferences=true). На Android
//     это EncryptedSharedPreferences — надёжно и совместимо.
//   - Биометрию проверяем через local_auth ПЕРЕД чтением/записью.
//
// Раньше пытались использовать `authenticationRequired: true` или
// сложные комбинации Android Keystore — на разных устройствах это
// поведение разное. Самый надёжный способ — простой storage + явная
// проверка биометрии перед операциями.

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hex.dart';
import 'master_key_manager.dart';

class BiometricNotAvailableException implements Exception {
  final String message;
  BiometricNotAvailableException(this.message);
  @override
  String toString() => 'BiometricNotAvailable: $message';
}

class BiometricCancelledException implements Exception {
  final String message;
  BiometricCancelledException([this.message = 'Биометрия отменена']);
  @override
  String toString() => message;
}

class BiometricLock {
  BiometricLock._internal();
  static final BiometricLock instance = BiometricLock._internal();

  static const String _kBiometricKey = 'komet_master_v2_biometric_key';
  static const String _kBiometricEnabledFlag =
      'komet_master_v2_biometric_enabled_flag';

  final LocalAuthentication _localAuth = LocalAuthentication();

  /// Дефолтные опции flutter_secure_storage. На Android это
  /// EncryptedSharedPreferences — надёжно и совместимо.
  FlutterSecureStorage _bioStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  void setBioStorageForTesting(FlutterSecureStorage storage) {
    _bioStorage = storage;
  }

  /// True если устройство поддерживает биометрию И она настроена.
  Future<bool> isAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      if (!canCheck || !isSupported) return false;
      final available = await _localAuth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (e) {
      debugPrint('BiometricLock.isAvailable error: $e');
      return false;
    }
  }

  /// True, если включён биометрический unlock.
  Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final flag = prefs.getBool(_kBiometricEnabledFlag) ?? false;
      if (!flag) return false;
      // Двойная проверка — есть ли реально ключ в storage.
      final hasKey = await _bioStorage.containsKey(key: _kBiometricKey);
      if (!hasKey) {
        // Storage пустой — снимаем флаг.
        await prefs.setBool(_kBiometricEnabledFlag, false);
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('BiometricLock.isEnabled error: $e');
      return false;
    }
  }

  /// Включает биометрический unlock. master_key должен быть в RAM.
  Future<void> enable() async {
    final mgr = MasterKeyManager.instance;
    if (!mgr.isUnlocked) {
      throw MasterLockedException(
        'Сначала разблокируйте приложение мастер-паролем',
      );
    }
    if (!await isAvailable()) {
      throw BiometricNotAvailableException(
        'Биометрия не настроена на устройстве',
      );
    }

    // Запрашиваем биометрию для подтверждения.
    final bool ok;
    try {
      ok = await _localAuth.authenticate(
        localizedReason:
            'Подтвердите включение биометрической разблокировки',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (e) {
      debugPrint('BiometricLock.enable authenticate error: $e');
      throw BiometricNotAvailableException('Ошибка биометрии: $e');
    }
    if (!ok) throw BiometricCancelledException();

    // Сохраняем master_key в biometric-storage с проверкой.
    final masterCopy = mgr.masterKeyCopy();
    try {
      final hex = _hex(masterCopy);
      await _bioStorage.write(key: _kBiometricKey, value: hex);

      // Проверяем что write реально записал.
      final readBack = await _bioStorage.read(key: _kBiometricKey);
      if (readBack != hex) {
        debugPrint(
          'BiometricLock.enable: write verify failed. Wrote ${hex.length} '
          'chars, read back ${readBack?.length ?? 0}',
        );
        throw BiometricNotAvailableException(
          'Не удалось сохранить ключ в защищённое хранилище',
        );
      }

      // Устанавливаем флаг ТОЛЬКО после успешной записи и проверки.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kBiometricEnabledFlag, true);
      debugPrint('BiometricLock.enable: success');
    } finally {
      for (var i = 0; i < masterCopy.length; i++) {
        masterCopy[i] = 0;
      }
    }
  }

  /// Выключает биометрический unlock и стирает ключ.
  Future<void> disable() async {
    try {
      await _bioStorage.delete(key: _kBiometricKey);
    } catch (e) {
      debugPrint('BiometricLock.disable storage delete error: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kBiometricEnabledFlag, false);
    } catch (e) {
      debugPrint('BiometricLock.disable prefs error: $e');
    }
  }

  /// Разблокирует master_key через биометрию.
  Future<void> unlockWithBiometrics() async {
    if (!await isEnabled()) {
      throw BiometricNotAvailableException(
        'Биометрический unlock не включён',
      );
    }

    final bool ok;
    try {
      ok = await _localAuth.authenticate(
        localizedReason: 'Разблокируйте зашифрованные чаты',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (e) {
      debugPrint('BiometricLock.unlock authenticate error: $e');
      throw BiometricNotAvailableException('Ошибка биометрии: $e');
    }
    if (!ok) throw BiometricCancelledException();

    final hex = await _bioStorage.read(key: _kBiometricKey);
    if (hex == null || hex.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kBiometricEnabledFlag, false);
      throw BiometricNotAvailableException(
        'Биометрический ключ не найден. Включите биометрию заново.',
      );
    }
    final masterBytes = _unhex(hex);
    MasterKeyManager.instance.installMasterFromBiometric(masterBytes);
  }

  /// Удаляет биометрический ключ. Вызывается из nuclearReset().
  Future<void> wipeOnReset() async {
    try {
      await _bioStorage.delete(key: _kBiometricKey);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kBiometricEnabledFlag, false);
    } catch (_) {}
  }

  String _hex(Uint8List b) => Hex.encode(b);
  Uint8List _unhex(String s) => Hex.decode(s);
}
