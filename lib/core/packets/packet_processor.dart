import 'dart:typed_data';

/// Абстракция для обработки входящих пакетов
abstract class PacketProcessor {
  /// Обработать входящий пакет
  /// 
  /// Возвращает true если пакет был успешно обработан
  bool process(Uint8List packet);
  
  /// Сбросить состояние процессора
  void reset();
}

/// Результат обработки пакета
class PacketResult {
  final bool success;
  final dynamic data;
  final String? error;
  
  const PacketResult._({required this.success, this.data, this.error});
  
  factory PacketResult.success(dynamic data) => 
      PacketResult._(success: true, data: data);
  
  factory PacketResult.error(String error) => 
      PacketResult._(success: false, error: error);
}
