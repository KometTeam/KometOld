// secret_key.dart — обёртка для ключевого материала в RAM.
//
// В Dart у нас нет mlock/VirtualLock как в Python (это C-level примитивы),
// и нет гарантии, что bytes будут уничтожены сразу после освобождения
// ссылки (GC эвакуирует объекты в произвольный момент). Но мы можем:
//
//   1. Хранить ключ в Uint8List (mutable), а не String, чтобы можно было
//      затереть нулями при выходе из сессии.
//   2. Скрыть содержимое от toString()/hashCode (чтобы случайно не утекло
//      в логи).
//   3. Реализовать destroy(), который явно перезаписывает буфер нулями.
//
// Это НЕ защищает от:
//   - Cold boot atak (нужен зашифрованный swap на уровне ОС).
//   - Process memory dump (нужны OS-уровневые механизмы или sandbox).
//   - GC-копий до destroy() (Dart VM может оставить копию в young generation).
//
// Тем не менее эта обёртка снижает время жизни ключа в памяти до явного
// `dispose()` или вызова `MasterKeyManager.lock()`.
//
// Ссылка на оригинал: utils/secure_memory.py из Crypt v2.1.5.

import 'dart:typed_data';

/// Обёртка для секретного ключа в RAM. Поддерживает явный wipe.
class SecretKey {
  Uint8List? _bytes;
  final int _length;

  /// Принимает Uint8List и забирает ВЛАДЕНИЕ — после этого вызывающий код
  /// не должен использовать `data` напрямую (буфер будет затёрт при
  /// `dispose`).
  SecretKey.takeOwnership(Uint8List data)
    : _bytes = data,
      _length = data.length;

  /// Создаёт SecretKey копированием. Исходный буфер не трогается.
  SecretKey.copyFrom(List<int> source)
    : _bytes = Uint8List.fromList(source),
      _length = source.length;

  /// Длина ключа в байтах. Доступна даже после dispose().
  int get length => _length;

  /// True, если ключ был очищен.
  bool get isDisposed => _bytes == null;

  /// Возвращает копию байтов. Используй экономно — каждая копия живёт в RAM
  /// до GC. Возвращённая копия НЕ wipе-ается автоматически.
  ///
  /// Бросает [StateError], если ключ уже уничтожен.
  Uint8List exposeCopy() {
    final b = _bytes;
    if (b == null) {
      throw StateError('SecretKey is disposed');
    }
    return Uint8List.fromList(b);
  }

  /// Прямой доступ к внутреннему буферу (БЕЗ копирования).
  /// Используй ТОЛЬКО внутри крипто-операций (AES-GCM, Argon2id), и не
  /// сохраняй ссылку дольше операции.
  ///
  /// Бросает [StateError], если ключ уже уничтожен.
  Uint8List unsafeView() {
    final b = _bytes;
    if (b == null) {
      throw StateError('SecretKey is disposed');
    }
    return b;
  }

  /// Затирает буфер нулями и обнуляет ссылку. После этого ключ нельзя
  /// использовать.
  void dispose() {
    final b = _bytes;
    if (b == null) return;
    for (var i = 0; i < b.length; i++) {
      b[i] = 0;
    }
    _bytes = null;
  }

  /// Скрываем содержимое от случайного логирования.
  @override
  String toString() => 'SecretKey(length=$_length${isDisposed ? ", disposed" : ""})';

  /// Намеренно НЕ реализуем == и hashCode на содержимом, чтобы байты
  /// нельзя было сравнить через timing-небезопасный путь.
  @override
  int get hashCode => identityHashCode(this);

  @override
  bool operator ==(Object other) => identical(this, other);
}

/// Constant-time сравнение двух Uint8List. Возвращает true, если содержимое
/// идентично. Используется для проверки тэгов/HMAC.
///
/// Время выполнения зависит только от ДЛИНЫ (а не от количества совпадающих
/// байт), что защищает от timing-атак.
bool constantTimeEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Затирает буфер нулями. Удобно для одноразовых ключевых производных,
/// которые не хочется заворачивать в SecretKey.
void wipeBytes(Uint8List? buf) {
  if (buf == null) return;
  for (var i = 0; i < buf.length; i++) {
    buf[i] = 0;
  }
}
