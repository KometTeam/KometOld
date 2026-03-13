class TransmitData {
  final String command;
  final int sequence;
  final int participantId;
  final dynamic data;
  final String participantType;

  const TransmitData({
    required this.command,
    required this.sequence,
    required this.participantId,
    required this.data,
    required this.participantType,
  });

  factory TransmitData.create({
    required int sequence,
    required int participantId,
    required dynamic data,
  }) {
    return TransmitData(
      command: 'transmit-data',
      sequence: sequence,
      participantId: participantId,
      data: data,
      participantType: 'USER',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'command': command,
      'sequence': sequence,
      'participantId': participantId,
      'data': data,
      'participantType': participantType,
    };
  }
}
