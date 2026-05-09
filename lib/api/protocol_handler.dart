/// Изолированный обработчик бинарного протокола.

import 'dart:typed_data';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

/// Типы команд бинарного протокола.
///
/// Заголовок пакета (10 байт): ver(1) + cmd(1) + seq(2 BE) + opcode(2 BE) + packedLen(4 BE).
///
/// `request` отправляется клиентом, а push'ами от сервера — `push`. Ответы сервера
/// используют `ok` / `notFound` / `error`. Push и ok имеют одинаковое значение (1) —
/// различаются по контексту: если seq совпал с pending, это ответ.
abstract class CmdType {
  static const int request = 0;
  static const int push = 1;
  static const int ok = 1;
  static const int notFound = 2;
  static const int error = 3;
}

/// Структура распарсенного пакета
class ParsedPacket {
  final int version;
  final int cmd;
  final int seq;
  final int opcode;
  final dynamic payload;

  const ParsedPacket({
    required this.version,
    required this.cmd,
    required this.seq,
    required this.opcode,
    required this.payload,
  });

  Map<String, dynamic> toMap() => {
    'ver': version,
    'cmd': cmd,
    'seq': seq,
    'opcode': opcode,
    'payload': payload,
  };
}

class ProtocolHandler {
  ProtocolHandler._();

  static const int headerSize = 10;

  /// Максимальный размер распакованных данных (защита от OOM)
  static const int maxDecompressedSize = 5 * 1024 * 1024; // 5MB

  /// Парсит заголовок и возвращает длину payload
  /// Возвращает null, если данных недостаточно
  static int? tryParseHeader(Uint8List headerBytes) {
    if (headerBytes.length < headerSize) return null;

    // Байты 6-9: длина payload (big-endian, 3 байта) + флаг сжатия (1 байт)
    final packedLen = ByteData.view(headerBytes.buffer, 6, 4)
        .getUint32(0, Endian.big);

    // Маскируем флаг сжатия, берем только длину
    final payloadLen = packedLen & 0x00FFFFFF;

    return payloadLen;
  }

  /// Парсит полный пакет (заголовок + payload)
  static ParsedPacket? parsePacket(Uint8List packet) {
    if (packet.length < headerSize) return null;

    try {
      // Парсим заголовок: ver(1) + cmd(1) + seq(2 BE) + opcode(2 BE) + packedLen(4 BE)
      final bd = ByteData.view(packet.buffer, packet.offsetInBytes, packet.lengthInBytes);
      final ver = bd.getUint8(0);
      final cmd = bd.getUint8(1);
      final seq = bd.getUint16(2, Endian.big);
      final opcode = bd.getUint16(4, Endian.big);

      final packedLen = bd.getUint32(6, Endian.big);

      final compFlag = packedLen >> 24;
      final payloadLen = packedLen & 0x00FFFFFF;

      // Проверяем, что пакет полный
      if (packet.length < headerSize + payloadLen) return null;

      // Извлекаем payload
      final payloadBytes = packet.sublist(headerSize, headerSize + payloadLen);

      // Распаковываем payload
      final payload = _unpackPayload(payloadBytes, compFlag != 0);

      return ParsedPacket(
        version: ver,
        cmd: cmd,
        seq: seq,
        opcode: opcode,
        payload: payload,
      );
    } catch (e) {
      return null;
    }
  }

  /// Распаковывает payload (LZ4 + MsgPack)
  static dynamic _unpackPayload(Uint8List payloadBytes, bool isCompressed) {
    if (payloadBytes.isEmpty) return null;

    try {
      Uint8List decompressedBytes = payloadBytes;

      // Пробуем LZ4 декомпрессию
      if (isCompressed || payloadBytes.length > 10) {
        try {
          decompressedBytes = _lz4DecompressBlockPure(
            payloadBytes,
            maxDecompressedSize,
          );
        } catch (_) {
          // Если декомпрессия не удалась, используем оригинальные байты
          decompressedBytes = payloadBytes;
        }
      }

      // MsgPack десериализация
      return _deserializeMsgpack(decompressedBytes);
    } catch (e) {
      return null;
    }
  }

  /// Чистая Dart реализация LZ4
  static Uint8List _lz4DecompressBlockPure(Uint8List src, int maxOutputSize) {
    final dst = BytesBuilder(copy: false);
    int srcPos = 0;

    while (srcPos < src.length) {
      if (srcPos >= src.length) break;

      final token = src[srcPos++];
      var literalLen = token >> 4;

      // Читаем дополнительные байты длины литералов
      if (literalLen == 15) {
        while (srcPos < src.length) {
          final b = src[srcPos++];
          literalLen += b;
          if (b != 255) break;
        }
      }

      // Копируем литералы
      if (literalLen > 0) {
        if (srcPos + literalLen > src.length) {
          throw StateError('LZ4: literal length выходит за пределы буфера');
        }
        final literals = src.sublist(srcPos, srcPos + literalLen);
        srcPos += literalLen;
        dst.add(literals);

        if (dst.length > maxOutputSize) {
          throw StateError('LZ4: превышен максимальный размер вывода');
        }
      }

      // Конец потока
      if (srcPos >= src.length) break;

      // Читаем offset
      if (srcPos + 1 >= src.length) {
        throw StateError('LZ4: неполный offset в потоке');
      }
      final offset = src[srcPos] | (src[srcPos + 1] << 8);
      srcPos += 2;

      if (offset == 0) {
        throw StateError('LZ4: offset не может быть 0');
      }

      // Читаем длину match
      var matchLen = (token & 0x0F) + 4;

      if ((token & 0x0F) == 0x0F) {
        while (srcPos < src.length) {
          final b = src[srcPos++];
          matchLen += b;
          if (b != 255) break;
        }
      }

      // Копируем match с учетом перекрытия
      final dstBytes = dst.toBytes();
      final dstLen = dstBytes.length;
      final matchPos = dstLen - offset;

      if (matchPos < 0) {
        throw StateError('LZ4: match указывает за пределы данных');
      }

      final match = <int>[];
      for (int i = 0; i < matchLen; i++) {
        match.add(dstBytes[matchPos + (i % offset)]);
      }
      dst.add(Uint8List.fromList(match));

      if (dst.length > maxOutputSize) {
        throw StateError('LZ4: превышен максимальный размер вывода');
      }
    }

    return Uint8List.fromList(dst.toBytes());
  }

  /// MsgPack десериализация с обработкой дефектных пакетов
  static dynamic _deserializeMsgpack(Uint8List data) {
    try {
      dynamic payload = msgpack.deserialize(data);

      if (payload is int &&
          data.length > 1 &&
          payload <= -1 &&
          payload >= -32) {
        // Пробуем пропустить первые байты
        final candidateOffsets = <int>[1, 2, 3, 4];

        for (final offset in candidateOffsets) {
          if (offset >= data.length) continue;

          try {
            final tail = data.sublist(offset);
            final realPayload = msgpack.deserialize(tail);
            payload = realPayload;
            break;
          } catch (_) {
            // Пробуем следующий offset
          }
        }
      }

      // Рекурсивная декодировка вложенных токенов
      return _decodeBlockTokens(payload);
    } catch (e) {
      return null;
    }
  }

  /// Декодирует специальные токены в payload
  static dynamic _decodeBlockTokens(dynamic obj) {
    if (obj is Map) {
      final result = <String, dynamic>{};
      obj.forEach((key, value) {
        result[key.toString()] = _decodeBlockTokens(value);
      });
      return result;
    } else if (obj is List) {
      return obj.map(_decodeBlockTokens).toList();
    } else if (obj is Uint8List) {
      // Пробуем распаковать вложенные данные
      try {
        final nested = _lz4DecompressBlockPure(obj, maxDecompressedSize);
        final decoded = msgpack.deserialize(nested);
        return _decodeBlockTokens(decoded);
      } catch (_) {
        return obj;
      }
    }
    return obj;
  }
}
