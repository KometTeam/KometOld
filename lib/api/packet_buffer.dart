///  буфер для накопления входящих TCP-пакетов.

import 'dart:typed_data';

class PacketBuffer {
  /// Внутренний буфер (растет по мере необходимости)
  Uint8List _buffer;

  /// Текущее количество данных в буфере
  int _length = 0;

  /// Начальная емкость (16KB - разумный размер для большинства пакетов)
  static const int _initialCapacity = 16 * 1024;

  /// Максимальная емкость перед сбросом (2MB - защита от утечек памяти)
  static const int _maxCapacity = 2 * 1024 * 1024;

  PacketBuffer() : _buffer = Uint8List(_initialCapacity);

  /// Добавить новые данные в буфер
  void append(Uint8List data) {
    if (data.isEmpty) return;

    final requiredCapacity = _length + data.length;

    // Если не хватает места, увеличиваем буфер
    if (requiredCapacity > _buffer.length) {
      _grow(requiredCapacity);
    }

    // Копируем новые данные в конец
    _buffer.setRange(_length, _length + data.length, data);
    _length += data.length;
  }

  /// Извлечь указанное количество байт с начала буфера
  /// Возвращает null, если недостаточно данных
  Uint8List? extract(int count) {
    if (_length < count) return null;

    // Создаем view (не копируем) для извлекаемых данных
    final result = Uint8List.view(_buffer.buffer, 0, count);

    // Сдвигаем оставшиеся данные к началу
    if (_length > count) {
      _buffer.setRange(0, _length - count, _buffer, count);
    }
    _length -= count;

    // Если буфер стал почти пустым и слишком большим, уменьшаем его
    if (_length < _buffer.length ~/ 4 && _buffer.length > _initialCapacity) {
      _shrink();
    }

    return Uint8List.fromList(result); // Копируем только при возврате
  }

  /// Прочитать данные без удаления из буфера
  Uint8List? peek(int count) {
    if (_length < count) return null;
    return Uint8List.view(_buffer.buffer, 0, count);
  }

  /// Увеличить емкость буфера
  void _grow(int requiredCapacity) {
    int newCapacity = _buffer.length;
    while (newCapacity < requiredCapacity) {
      newCapacity *= 2;
    }

    // Защита от чрезмерного роста
    if (newCapacity > _maxCapacity) {
      newCapacity = _maxCapacity;
      if (requiredCapacity > _maxCapacity) {
        throw StateError(
          'PacketBuffer: превышен максимальный размер буфера ($_maxCapacity байт)',
        );
      }
    }

    final newBuffer = Uint8List(newCapacity);
    newBuffer.setRange(0, _length, _buffer);
    _buffer = newBuffer;
  }

  /// Уменьшить емкость буфера для экономии памяти
  void _shrink() {
    int newCapacity = _initialCapacity;
    while (newCapacity < _length) {
      newCapacity *= 2;
    }

    if (newCapacity < _buffer.length) {
      final newBuffer = Uint8List(newCapacity);
      newBuffer.setRange(0, _length, _buffer);
      _buffer = newBuffer;
    }
  }

  /// Текущее количество байт в буфере
  int get length => _length;

  /// Буфер пуст
  bool get isEmpty => _length == 0;

  /// Текущая емкость буфера (для диагностики)
  int get capacity => _buffer.length;

  /// Очистить буфер (сохраняя выделенную память)
  void clear() {
    _length = 0;
    // Не уменьшаем буфер - возможно, скоро снова понадобится
  }

  /// Полностью сбросить буфер и освободить память
  void reset() {
    _buffer = Uint8List(_initialCapacity);
    _length = 0;
  }
}
