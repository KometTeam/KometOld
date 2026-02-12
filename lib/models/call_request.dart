import 'dart:convert';
import 'package:uuid/uuid.dart';

/// Модель для запроса звонка (opcode 78, cmd 0)
class CallRequest {
  final String conversationId;
  final List<int> calleeIds;
  final CallInternalParams internalParams;
  final bool isVideo;

  CallRequest({
    required this.conversationId,
    required this.calleeIds,
    required this.internalParams,
    this.isVideo = false,
  });

  /// Создает запрос звонка с автоматической генерацией параметров
  factory CallRequest.create({
    required int calleeId,
    required String deviceId,
    bool isVideo = false,
  }) {
    return CallRequest(
      conversationId: const Uuid().v4(),
      calleeIds: [calleeId],
      internalParams: CallInternalParams.generate(deviceId: deviceId),
      isVideo: isVideo,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'conversationId': conversationId,
      'calleeIds': calleeIds,
      'internalParams': jsonEncode(internalParams.toJson()),
      'isVideo': isVideo,
    };
  }
}

/// Внутренние параметры звонка
class CallInternalParams {
  final String deviceId;
  final String sdkVersion;
  final String clientAppKey;
  final String platform;
  final int protocolVersion;
  final String domainId;
  final String capabilities;

  CallInternalParams({
    required this.deviceId,
    required this.sdkVersion,
    required this.clientAppKey,
    required this.platform,
    required this.protocolVersion,
    required this.domainId,
    required this.capabilities,
  });

  /// Генерирует параметры с дефолтными значениями
  factory CallInternalParams.generate({required String deviceId}) {
    return CallInternalParams(
      deviceId: deviceId,
      sdkVersion: '2.8.9',
      clientAppKey: _generateClientAppKey(),
      platform: 'ANDROID',
      protocolVersion: 5,
      domainId: '',
      capabilities: _generateCapabilities(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'sdkVersion': sdkVersion,
      'clientAppKey': clientAppKey,
      'platform': platform,
      'protocolVersion': protocolVersion,
      'domainId': domainId,
      'capabilities': capabilities,
    };
  }

  /// Генерирует случайный clientAppKey в формате как у веб-версии
  static String _generateClientAppKey() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final random = DateTime.now().millisecondsSinceEpoch;
    final buffer = StringBuffer();
    
    for (int i = 0; i < 17; i++) {
      buffer.write(chars[(random + i) % chars.length]);
    }
    
    return buffer.toString();
  }

  /// Генерирует capabilities (hex string)
  static String _generateCapabilities() {
    // Используем те же capabilities что и в веб-версии
    // Можно попробовать рандомизировать, но пока оставим константу
    return '2A03F';
  }
}
