import 'dart:typed_data';
import 'package:msgpack_dart/msgpack_dart.dart';
import 'package:es_compression/lz4.dart';

Lz4Codec? _lz4Codec;
bool _lz4Initialized = false;

Lz4Codec? get _lz4 {
  if (!_lz4Initialized) {
    _lz4Initialized = true;
    try {
      _lz4Codec = Lz4Codec();
    } catch (e) {
      print('⚠️ LZ4 compression not available: $e');
      _lz4Codec = null;
    }
  }
  return _lz4Codec;
}

/// Упаковывает пакет в бинарный формат
/// 
/// Формат пакета:
/// - ver (1 byte) - версия протокола (10)
/// - cmd (2 bytes, big endian) - тип команды (0 = клиент -> сервер)
/// - seq (1 byte) - порядковый номер
/// - opcode (2 bytes, big endian) - код операции
/// - packed_len (4 bytes, big endian) - длина payload + флаг сжатия в старшем бите
/// - payload (переменная длина) - данные в MessagePack формате
Uint8List packPacket({
  required int ver,
  required int cmd,
  required int seq,
  required int opcode,
  required Map<String, dynamic> payload,
}) {
  // Сериализуем payload в MessagePack
  Uint8List payloadBytes = serialize(payload);
  bool isCompressed = false;

  // Сжимаем если payload >= 32 байт и LZ4 доступен
  if (payloadBytes.length >= 32 && _lz4 != null) {
    try {
      // Добавляем размер несжатых данных в начало (4 байта, big endian)
      final uncompressedSize = ByteData(4)
        ..setUint32(0, payloadBytes.length, Endian.big);

      final compressedData = _lz4!.encode(payloadBytes);

      final builder = BytesBuilder();
      builder.add(uncompressedSize.buffer.asUint8List());
      builder.add(compressedData);
      payloadBytes = builder.toBytes();
      isCompressed = true;
    } catch (e) {
      print('⚠️ LZ4 compression failed, sending uncompressed: $e');
    }
  }

  // Создаем заголовок (10 байт)
  final header = ByteData(10);
  header.setUint8(0, ver);
  header.setUint16(1, cmd, Endian.big);
  header.setUint8(3, seq);
  header.setUint16(4, opcode, Endian.big);

  // Устанавливаем длину payload с флагом сжатия
  int packedLen = payloadBytes.length;
  if (isCompressed) {
    packedLen |= (1 << 24); // Устанавливаем флаг сжатия в старшем байте
  }
  header.setUint32(6, packedLen, Endian.big);

  // Собираем полный пакет
  final builder = BytesBuilder();
  builder.add(header.buffer.asUint8List());
  builder.add(payloadBytes);

  return builder.toBytes();
}

/// Распаковывает пакет из бинарного формата
/// 
/// Возвращает null если данных недостаточно или произошла ошибка
Map<String, dynamic>? unpackPacket(Uint8List data) {
  if (data.length < 10) {
    return null;
  }

  final byteData = data.buffer.asByteData(
    data.offsetInBytes,
    data.lengthInBytes,
  );

  final ver = byteData.getUint8(0);
  final cmd = byteData.getUint16(1, Endian.big);
  final seq = byteData.getUint8(3);
  final opcode = byteData.getUint16(4, Endian.big);
  final packedLen = byteData.getUint32(6, Endian.big);

  // Извлекаем флаг сжатия и реальную длину
  final compFlag = packedLen >> 24;
  final payloadLength = packedLen & 0x00FFFFFF;

  if (data.length < 10 + payloadLength) {
    return null;
  }

  Uint8List payloadBytes = data.sublist(10, 10 + payloadLength);

  // Декомпрессия если нужно
  if (compFlag != 0) {
    if (_lz4 != null) {
      try {
        // Первые 4 байта - размер несжатых данных (пропускаем)
        final compressedData = payloadBytes.sublist(4);
        payloadBytes = Uint8List.fromList(_lz4!.decode(compressedData));
      } catch (e) {
        print('⚠️ LZ4 decompression failed: $e');
        return null;
      }
    } else {
      print('⚠️ LZ4 not available, cannot decompress packet');
      return null;
    }
  }

  // Десериализуем MessagePack
  final dynamic payload = deserialize(payloadBytes);

  return {
    'ver': ver,
    'cmd': cmd,
    'seq': seq,
    'opcode': opcode,
    'payload': payload,
  };
}
