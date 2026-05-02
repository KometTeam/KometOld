import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

/// Сервис для фоновой отправки голосовых сообщений с уведомлениями
class VoiceUploadService {
  static final VoiceUploadService _instance = VoiceUploadService._internal();
  factory VoiceUploadService() => _instance;
  VoiceUploadService._internal();

  static const _channel = MethodChannel('com.gwid.app/voice_upload');

  // Текущие задачи загрузки (uploadId -> прогресс)
  final Map<String, double> _uploadProgress = {};
  final Map<String, StreamController<double>> _progressControllers = {};

  /// Начать фоновую загрузку голосового сообщения (только Android)
  Future<String?> startBackgroundUpload({
    required String filePath,
    required int chatId,
    required int durationSeconds,
    required int fileSize,
    required int senderId,
  }) async {
    if (!Platform.isAndroid) return null;

    try {
      final uploadId = '${chatId}_${DateTime.now().millisecondsSinceEpoch}';
      
      // Вызываем native код для показа уведомления
      await _channel.invokeMethod('startVoiceUpload', {
        'uploadId': uploadId,
        'chatId': chatId,
      });

      _uploadProgress[uploadId] = 0.0;
      _progressControllers[uploadId] = StreamController<double>.broadcast();

      return uploadId;
    } catch (e) {
      print('❌ Ошибка запуска фоновой загрузки: $e');
      return null;
    }
  }

  /// Обновить прогресс загрузки
  Future<void> updateProgress(String uploadId, int chatId, double progress) async {
    if (!Platform.isAndroid) return;

    try {
      _uploadProgress[uploadId] = progress;
      _progressControllers[uploadId]?.add(progress);

      await _channel.invokeMethod('updateVoiceUploadProgress', {
        'uploadId': uploadId,
        'chatId': chatId,
        'progress': (progress * 100).toInt(),
      });
    } catch (e) {
      print('⚠️ Ошибка обновления прогресса: $e');
    }
  }

  /// Завершить загрузку (успешно)
  Future<void> completeUpload(String uploadId, int chatId) async {
    if (!Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('completeVoiceUpload', {
        'uploadId': uploadId,
        'chatId': chatId,
      });

      _uploadProgress.remove(uploadId);
      await _progressControllers[uploadId]?.close();
      _progressControllers.remove(uploadId);
    } catch (e) {
      print('⚠️ Ошибка завершения загрузки: $e');
    }
  }

  /// Отменить загрузку (ошибка)
  Future<void> cancelUpload(String uploadId, int chatId, {String? errorMessage}) async {
    if (!Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('cancelVoiceUpload', {
        'uploadId': uploadId,
        'chatId': chatId,
        'errorMessage': errorMessage ?? 'Ошибка отправки',
      });

      _uploadProgress.remove(uploadId);
      await _progressControllers[uploadId]?.close();
      _progressControllers.remove(uploadId);
    } catch (e) {
      print('⚠️ Ошибка отмены загрузки: $e');
    }
  }

  /// Получить поток прогресса для конкретной загрузки
  Stream<double>? getProgressStream(String uploadId) {
    return _progressControllers[uploadId]?.stream;
  }

  /// Получить текущий прогресс
  double? getProgress(String uploadId) {
    return _uploadProgress[uploadId];
  }
}
