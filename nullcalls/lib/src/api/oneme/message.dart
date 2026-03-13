enum MessagingSide {
  client(0),
  server(1);

  final int value;
  const MessagingSide(this.value);

  factory MessagingSide.fromValue(int value) {
    return MessagingSide.values.firstWhere((e) => e.value == value);
  }
}

class OneMeMessage<T> {
  final int sequenceNumber;
  final int opcode;
  final T payload;
  final int version;
  final MessagingSide side;

  const OneMeMessage({
    required this.sequenceNumber,
    required this.opcode,
    required this.payload,
    required this.version,
    required this.side,
  });

  factory OneMeMessage.create({
    required int sequenceNumber,
    required int opcode,
    required T payload,
  }) {
    return OneMeMessage(
      sequenceNumber: sequenceNumber,
      opcode: opcode,
      payload: payload,
      version: 11,
      side: MessagingSide.client,
    );
  }

  factory OneMeMessage.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic) payloadParser,
  ) {
    return OneMeMessage(
      sequenceNumber: json['seq'] as int,
      opcode: json['opcode'] as int,
      payload: payloadParser(json['payload']),
      version: json['ver'] as int,
      side: MessagingSide.fromValue(json['cmd'] as int),
    );
  }

  Map<String, dynamic> toJson(dynamic Function(T) payloadSerializer) {
    return {
      'seq': sequenceNumber,
      'opcode': opcode,
      'payload': payloadSerializer(payload),
      'ver': version,
      'cmd': side.value,
    };
  }
}
