import 'dart:convert';

/// Модель для ответа на запрос звонка (opcode 78, cmd 1)
class CallResponse {
  final String conversationId;
  final CallInternalCallerParams internalCallerParams;
  final List<dynamic> rejectedParticipants;

  CallResponse({
    required this.conversationId,
    required this.internalCallerParams,
    required this.rejectedParticipants,
  });

  factory CallResponse.fromJson(Map<String, dynamic> json) {
    final internalParamsStr = json['internalCallerParams'] as String;
    final internalParamsJson = jsonDecode(internalParamsStr) as Map<String, dynamic>;

    return CallResponse(
      conversationId: json['conversationId'] as String,
      internalCallerParams: CallInternalCallerParams.fromJson(internalParamsJson),
      rejectedParticipants: json['rejectedParticipants'] as List<dynamic>? ?? [],
    );
  }
}

/// Параметры звонка от сервера с данными для WebRTC
class CallInternalCallerParams {
  final CallerId id;
  final bool isConcurrent;
  final String endpoint;
  final String wtEndpoint;
  final String clientType;
  final TurnConfig turn;
  final StunConfig stun;
  final int deviceIdx;

  CallInternalCallerParams({
    required this.id,
    required this.isConcurrent,
    required this.endpoint,
    required this.wtEndpoint,
    required this.clientType,
    required this.turn,
    required this.stun,
    required this.deviceIdx,
  });

  factory CallInternalCallerParams.fromJson(Map<String, dynamic> json) {
    return CallInternalCallerParams(
      id: CallerId.fromJson(json['id'] as Map<String, dynamic>),
      isConcurrent: json['isConcurrent'] as bool,
      endpoint: json['endpoint'] as String,
      wtEndpoint: json['wtEndpoint'] as String,
      clientType: json['clientType'] as String,
      turn: TurnConfig.fromJson(json['turn'] as Map<String, dynamic>),
      stun: StunConfig.fromJson(json['stun'] as Map<String, dynamic>),
      deviceIdx: json['deviceIdx'] as int,
    );
  }
}

/// ID звонящего
class CallerId {
  final int internal;
  final String external;

  CallerId({
    required this.internal,
    required this.external,
  });

  factory CallerId.fromJson(Map<String, dynamic> json) {
    return CallerId(
      internal: json['internal'] as int,
      external: json['external'] as String,
    );
  }
}

/// Конфигурация TURN серверов
class TurnConfig {
  final List<String> urls;
  final String username;
  final String credential;

  TurnConfig({
    required this.urls,
    required this.username,
    required this.credential,
  });

  factory TurnConfig.fromJson(Map<String, dynamic> json) {
    return TurnConfig(
      urls: (json['urls'] as List<dynamic>).cast<String>(),
      username: json['username'] as String,
      credential: json['credential'] as String,
    );
  }
}

/// Конфигурация STUN серверов
class StunConfig {
  final List<String> urls;

  StunConfig({
    required this.urls,
  });

  factory StunConfig.fromJson(Map<String, dynamic> json) {
    return StunConfig(
      urls: (json['urls'] as List<dynamic>).cast<String>(),
    );
  }
}
