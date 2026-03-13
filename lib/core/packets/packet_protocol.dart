import 'dart:typed_data';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

/// Структура пакета протокола
class Packet {
  final int version;
  final int command;
  final int sequence;
  final int opcode;
  final Map<String, dynamic> payload;
  final DateTime receivedAt;
  
  const Packet({
    required this.version,
    required this.command,
    required this.sequence,
    required this.opcode,
    required this.payload,
    required this.receivedAt,
  });
  
  factory Packet.fromBytes(Uint8List data) {
    if (data.length < 10) {
      throw PacketParseException('Недостаточно данных для заголовка: ${data.length} байт');
    }
    
    final version = data[0];
    final command = data.buffer.asByteData().getUint16(1, Endian.big);
    final sequence = data[3];
    final opcode = data.buffer.asByteData().getUint16(4, Endian.big);
    final payloadLength = data.buffer.asByteData().getUint32(6, Endian.big);
    
    if (data.length < 10 + payloadLength) {
      throw PacketParseException('Недостаточно данных для payload: ожидалось $payloadLength, получено ${data.length - 10}');
    }
    
    final payloadBytes = data.sublist(10, 10 + payloadLength);
    final payload = msgpack.deserialize(payloadBytes) as Map<dynamic, dynamic>;
    
    return Packet(
      version: version,
      command: command,
      sequence: sequence,
      opcode: opcode,
      payload: payload.cast<String, dynamic>(),
      receivedAt: DateTime.now(),
    );
  }
  
  Uint8List toBytes() {
    final payloadBytes = msgpack.serialize(payload);
    final payloadLength = payloadBytes.length;
    
    final result = BytesBuilder();
    result.addByte(version);
    result.add(Uint8List(2)..buffer.asByteData().setUint16(0, command, Endian.big));
    result.addByte(sequence);
    result.add(Uint8List(2)..buffer.asByteData().setUint16(0, opcode, Endian.big));
    result.add(Uint8List(4)..buffer.asByteData().setUint32(0, payloadLength, Endian.big));
    result.add(payloadBytes);
    
    return result.toBytes();
  }
  
  Map<String, dynamic> toMap() => {
    'ver': version,
    'cmd': command,
    'seq': sequence,
    'opcode': opcode,
    'payload': payload,
  };
  
  @override
  String toString() => 
      'Packet(v=$version, cmd=$command, seq=$sequence, op=$opcode, payload=${payload.length} fields)';
}

/// Буфер для накопления входящих данных пакетов
class PacketBuffer {
  final List<int> _buffer = [];
  
  /// Размер буфера
  int get length => _buffer.length;
  
  /// Добавить данные в буфер
  void append(Uint8List data) {
    _buffer.addAll(data);
  }
  
  /// Посмотреть данные без удаления
  Uint8List? peek(int count) {
    if (_buffer.length < count) return null;
    return Uint8List.fromList(_buffer.sublist(0, count));
  }
  
  /// Извлечь данные из буфера
  Uint8List? extract(int count) {
    if (_buffer.length < count) return null;
    final result = Uint8List.fromList(_buffer.sublist(0, count));
    _buffer.removeRange(0, count);
    return result;
  }
  
  /// Попытаться прочитать пакет из буфера
  Packet? tryReadPacket() {
    // Минимальный размер заголовка: 10 байт
    if (_buffer.length < 10) return null;
    
    final header = Uint8List.fromList(_buffer.sublist(0, 10));
    final payloadLength = header.buffer.asByteData().getUint32(6, Endian.big);
    final totalLength = 10 + payloadLength;
    
    if (_buffer.length < totalLength) return null;
    
    final packetData = extract(totalLength);
    if (packetData == null) return null;
    
    try {
      return Packet.fromBytes(packetData);
    } catch (e) {
      print('⚠️ Ошибка парсинга пакета: $e');
      return null;
    }
  }
  
  /// Сбросить буфер
  void reset() {
    _buffer.clear();
  }
}

/// Исключение парсинга пакета
class PacketParseException implements Exception {
  final String message;
  PacketParseException(this.message);
  
  @override
  String toString() => 'PacketParseException: $message';
}
