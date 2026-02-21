part of 'chat_screen.dart';

extension on _ChatScreenState {
  // Voice Recording Duration Formatter
  String _formatRecordingDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  // Start Voice Recording
  Future<void> _startVoiceRecordingUi() async {
    _voiceRecordingTimer?.cancel();

    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      _showErrorSnackBar('Нет разрешения на запись аудио');
      return;
    }

    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _currentRecordingPath = '${directory.path}/voice_$timestamp.m4a';

    print('Начинаем запись в: $_currentRecordingPath');

    try {
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _currentRecordingPath!,
      );
      _isActuallyRecording = true;
      print('📝 Запись голосового сообщения начата: $_currentRecordingPath');
    } catch (e) {
      print('❌ Ошибка начала записи: $e');
      _showErrorSnackBar('Не удалось начать запись');
      return;
    }

    // ignore: invalid_use_of_protected_member
    setState(() {
      _isVoiceRecordingUi = true;
      _isVoiceRecordingPaused = false;
      _voiceRecordingDuration = Duration.zero;
      _recordCancelDragDx = 0.0;
    });

    _voiceRecordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_isVoiceRecordingUi) return;
      if (_isVoiceRecordingPaused) return;
      // ignore: invalid_use_of_protected_member
      setState(() {
        _voiceRecordingDuration += const Duration(seconds: 1);
      });
    });
  }

  // Cancel Voice Recording
  Future<void> _cancelVoiceRecordingUi() async {
    _voiceRecordingTimer?.cancel();

    if (_isActuallyRecording) {
      await _audioRecorder.stop();
      _isActuallyRecording = false;

      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          await file.delete();
          print('🗑️ Запись удалена: $_currentRecordingPath');
        }
      }
    }

    if (!mounted) return;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _isVoiceRecordingUi = false;
      _isVoiceRecordingPaused = false;
      _voiceRecordingDuration = Duration.zero;
      _recordCancelDragDx = 0.0;
      _currentRecordingPath = null;
    });
  }

  // Toggle Voice Recording Pause
  Future<void> _toggleVoiceRecordingPause() async {
    if (_isActuallyRecording) {
      if (_isVoiceRecordingPaused) {
        await _audioRecorder.resume();
        print('▶️ Запись возобновлена');
      } else {
        await _audioRecorder.pause();
        print('⏸️ Запись на паузе');
      }
    }

    if (!mounted) return;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _isVoiceRecordingPaused = !_isVoiceRecordingPaused;
      _recordCancelDragDx = 0.0;
    });
  }

  // Send Voice Message
  Future<void> _sendVoiceMessage() async {
    if (!_isActuallyRecording || _currentRecordingPath == null) {
      print('⚠️ Нет активной записи для отправки');
      return;
    }

    _voiceRecordingTimer?.cancel();

    // Останавливаем запись
    String? path;
    try {
      path = await _audioRecorder.stop();
      print('🛑 Recorder stopped, returned path: $path');
    } catch (e) {
      print('❌ Error stopping recorder: $e');
    }

    _isActuallyRecording = false;

    // Критично для Windows: даем время на освобождение файла и запись метаданных
    await Future.delayed(const Duration(milliseconds: 200));

    // Проверяем файл по пути, а не по возвращаемому значению из stop()
    final filePath = _currentRecordingPath!;
    final file = File(filePath);
    var fileExists = await file.exists();
    var fileSize = fileExists ? await file.length() : 0;

    // Дополнительная попытка если файл еще не готов (Windows)
    if (!fileExists || fileSize == 0) {
      await Future.delayed(const Duration(milliseconds: 300));
      fileExists = await file.exists();
      fileSize = fileExists ? await file.length() : 0;
    }

    if (!fileExists || fileSize == 0) {
      print('❌ Файл не создан или пуст: $filePath');
      if (mounted) {
        _showErrorSnackBar('Не удалось сохранить запись');
      }
      await _cancelVoiceRecordingUi();
      return;
    }

    print('✅ Файл записан: $filePath (${fileSize} bytes)');

    final duration = _voiceRecordingDuration;

    // Единый setState с проверкой mounted
    if (mounted) {
      // ignore: invalid_use_of_protected_member
      setState(() {
        _isVoiceRecordingUi = false;
        _isVoiceRecordingPaused = false;
        _voiceRecordingDuration = Duration.zero;
        _recordCancelDragDx = 0.0;
        _currentRecordingPath = null;
        _isVoiceUploading = true;
        _voiceUploadProgress = 0.0;
        _isVoiceUploadFailed = false;
      });
    }

    print('📤 Отправка голосового сообщения: $filePath, длительность: ${duration.inSeconds}s');

    // Для Android запускаем фоновую загрузку с уведомлением
    String? uploadId;
    if (Platform.instance.operatingSystem.android) {
      final voiceUploadService = VoiceUploadService();
      uploadId = await voiceUploadService.startBackgroundUpload(
        filePath: filePath,
        chatId: widget.chatId,
        durationSeconds: duration.inSeconds,
        fileSize: fileSize,
        senderId: _actualMyId ?? 0,
      );
    }

    try {
      await ApiService.instance.sendVoiceMessage(
        widget.chatId,
        localPath: filePath,
        durationSeconds: duration.inSeconds,
        fileSize: fileSize,
        senderId: _actualMyId,
        onProgress: (progress) {
          if (mounted) {
            // ignore: invalid_use_of_protected_member
            setState(() {
              _isVoiceUploading = progress < 1.0;
              _voiceUploadProgress = progress;
            });
          }
          
          // Обновляем прогресс в уведомлении (Android)
          if (Platform.instance.operatingSystem.android && uploadId != null) {
            VoiceUploadService().updateProgress(uploadId, widget.chatId, progress);
          }
        },
      );

      print('✅ Голосовое сообщение успешно отправлено');
      
      // Завершаем уведомление (Android)
      if (Platform.instance.operatingSystem.android && uploadId != null) {
        await VoiceUploadService().completeUpload(uploadId, widget.chatId);
      }
      
      if (mounted) {
        // ignore: invalid_use_of_protected_member
        setState(() {
          _isVoiceUploading = false;
          _voiceUploadProgress = 0.0;
          _isVoiceUploadFailed = false;
          _cachedVoicePath = null;
        });
      }

      // Удаляем временный файл после успешной отправки
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        print('⚠️ Не удалось удалить временный файл: $e');
      }
    } catch (e, stackTrace) {
      print('❌ Ошибка отправки голосового сообщения: $e');
      print(stackTrace);
      
      // Показываем ошибку в уведомлении (Android)
      if (Platform.instance.operatingSystem.android && uploadId != null) {
        await VoiceUploadService().cancelUpload(
          uploadId,
          widget.chatId,
          errorMessage: 'Не удалось отправить голосовое сообщение',
        );
      }
      
      if (mounted) {
        // ignore: invalid_use_of_protected_member
        setState(() {
          _isVoiceUploading = false;
          _voiceUploadProgress = 0.0;
          _isVoiceUploadFailed = true;
          _cachedVoicePath = filePath;
        });
        _showErrorSnackBar('Не удалось отправить голосовое сообщение');
      }
    }
  }

  // Retry Send Voice Message
  Future<void> _retrySendVoiceMessage() async {
    if (_cachedVoicePath == null) return;

    final file = File(_cachedVoicePath!);
    if (!await file.exists()) {
      _showErrorSnackBar('Файл голосового сообщения не найден');
      return;
    }

    final fileSize = await file.length();
    final duration = _voiceRecordingDuration;

    if (mounted) {
      // ignore: invalid_use_of_protected_member
      setState(() {
        _isVoiceUploadFailed = false;
        _isVoiceUploading = true;
        _voiceUploadProgress = 0.0;
      });
    }

    // Для Android запускаем фоновую загрузку с уведомлением
    String? uploadId;
    if (Platform.instance.operatingSystem.android) {
      final voiceUploadService = VoiceUploadService();
      uploadId = await voiceUploadService.startBackgroundUpload(
        filePath: _cachedVoicePath!,
        chatId: widget.chatId,
        durationSeconds: duration.inSeconds,
        fileSize: fileSize,
        senderId: _actualMyId ?? 0,
      );
    }

    try {
      await ApiService.instance.sendVoiceMessage(
        widget.chatId,
        localPath: _cachedVoicePath!,
        durationSeconds: duration.inSeconds,
        fileSize: fileSize,
        senderId: _actualMyId,
        onProgress: (progress) {
          if (mounted) {
            // ignore: invalid_use_of_protected_member
            setState(() {
              _isVoiceUploading = progress < 1.0;
              _voiceUploadProgress = progress;
            });
          }
          
          // Обновляем прогресс в уведомлении (Android)
          if (Platform.instance.operatingSystem.android && uploadId != null) {
            VoiceUploadService().updateProgress(uploadId, widget.chatId, progress);
          }
        },
      );

      // Завершаем уведомление (Android)
      if (Platform.instance.operatingSystem.android && uploadId != null) {
        await VoiceUploadService().completeUpload(uploadId, widget.chatId);
      }

      if (mounted) {
        // ignore: invalid_use_of_protected_member
        setState(() {
          _isVoiceUploading = false;
          _voiceUploadProgress = 0.0;
          _isVoiceUploadFailed = false;
          _cachedVoicePath = null;
        });
      }

      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        print('⚠️ Не удалось удалить временный файл: $e');
      }
    } catch (e) {
      print('❌ Ошибка повторной отправки голосового сообщения: $e');
      
      // Показываем ошибку в уведомлении (Android)
      if (Platform.instance.operatingSystem.android && uploadId != null) {
        await VoiceUploadService().cancelUpload(
          uploadId,
          widget.chatId,
          errorMessage: 'Не удалось отправить голосовое сообщение',
        );
      }
      
      if (mounted) {
        // ignore: invalid_use_of_protected_member
        setState(() {
          _isVoiceUploading = false;
          _voiceUploadProgress = 0.0;
          _isVoiceUploadFailed = true;
        });
        _showErrorSnackBar('Не удалось отправить голосовое сообщение');
      }
    }
  }

  // Build Voice Preview Bubble
  Widget _buildVoicePreviewBubble(VoicePreviewItem item) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.isUploading ? Icons.mic : Icons.error_outline,
                      color: colors.onPrimary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.isUploading ? 'Голосовое сообщение' : 'Ошибка отправки',
                      style: TextStyle(
                        color: colors.onPrimary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                if (item.isUploading) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 200,
                    child: LinearProgressIndicator(
                      value: item.progress,
                      backgroundColor: colors.onPrimary.withValues(alpha: 0.3),
                      valueColor: AlwaysStoppedAnimation<Color>(colors.onPrimary),
                    ),
                  ),
                ],
                if (item.isFailed && item.onRetry != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: item.onRetry,
                    child: Text(
                      'Повторить',
                      style: TextStyle(
                        color: colors.onPrimary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Build Voice Recording Bar
  Widget _buildVoiceRecordingBar({
    required bool isBlocked,
    required bool isGlass,
  }) {
    final colors = Theme.of(context).colorScheme;

    final cancelProgress = (_recordCancelDragDx.abs() / _ChatScreenState._recordCancelThreshold).clamp(0.0, 1.0);
    final cancelColor = Color.lerp(
      colors.onSurface.withValues(alpha: 0.7),
      colors.error,
      cancelProgress,
    )!;

    final canInteract = !isBlocked && !_isVoiceRecordingPaused;

    final trashButton = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: (!isBlocked) ? _cancelVoiceRecordingUi : null,
        child: Padding(
          padding: const EdgeInsets.all(6.0),
          child: Icon(
            Icons.delete_rounded,
            size: 20,
            color: colors.error,
          ),
        ),
      ),
    );

    final content = Row(
      children: [
        Text(
          _formatRecordingDuration(_voiceRecordingDuration),
          style: TextStyle(
            color: colors.onSurface.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final offset = Tween<Offset>(begin: const Offset(-0.15, 0), end: Offset.zero).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: offset, child: child),
            );
          },
          child: _isVoiceRecordingPaused
              ? SizedBox(key: const ValueKey<String>('trash'), child: trashButton)
              : const SizedBox(key: ValueKey<String>('trashSpacer'), width: 32, height: 32),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: _isVoiceRecordingPaused
                  ? const SizedBox(
                key: ValueKey<String>('waveform'),
                height: 24,
                child: _FakeWaveform(),
              )
                  : Transform.translate(
                key: const ValueKey<String>('cancel'),
                offset: Offset(_recordCancelDragDx, 0),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: canInteract ? _cancelVoiceRecordingUi : null,
                  child: Text(
                    'CANCEL',
                    style: TextStyle(
                      color: cancelColor,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        const SizedBox(width: _ChatScreenState._recordSendButtonSpace + _ChatScreenState._recordButtonGap + _ChatScreenState._recordPauseButtonSpace)
      ],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: canInteract
          ? (_) => _handleRecordCancelDragStart()
          : null,
      onHorizontalDragUpdate: canInteract
          ? (details) => _handleRecordCancelDragUpdate(details)
          : null,
      onHorizontalDragEnd: canInteract
          ? (_) => _handleRecordCancelDragEnd()
          : null,
      child: content,
    );
  }

  // Drag Handlers for Recording Cancel
  void _handleRecordCancelDragStart() {
    _recordCancelReturnController.stop();
  }

  void _handleRecordCancelDragUpdate(DragUpdateDetails details) {
    final next = (_recordCancelDragDx + details.delta.dx).clamp(-_ChatScreenState._recordCancelThreshold * 1.25, 0.0);
    if (next == _recordCancelDragDx) return;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _recordCancelDragDx = next;
    });
  }

  void _handleRecordCancelDragEnd() {
    final reached = _recordCancelDragDx <= -_ChatScreenState._recordCancelThreshold;
    if (reached) {
      _cancelVoiceRecordingUi();
      return;
    }

    final tween = Tween<double>(begin: _recordCancelDragDx, end: 0.0).animate(
      CurvedAnimation(parent: _recordCancelReturnController, curve: Curves.easeOutCubic),
    );
    void listener() {
      // ignore: invalid_use_of_protected_member
      setState(() {
        _recordCancelDragDx = tween.value;
      });
    }

    _recordCancelReturnController
      ..removeListener(listener)
      ..reset();
    _recordCancelReturnController.addListener(listener);
    _recordCancelReturnController.forward().whenComplete(() {
      _recordCancelReturnController.removeListener(listener);
    });
  }

  // Video Message Recording Methods

  String _formatVideoDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _startVideoRecordingUi() async {
    _videoRecordingTimer?.cancel();

    try {
      final cameraPermission = await Permission.camera.request();
      final micPermission = await Permission.microphone.request();

      if (!cameraPermission.isGranted || !micPermission.isGranted) {
        _showErrorSnackBar('Нет разрешения на доступ к камере или микрофону');
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _showErrorSnackBar('Камера не найдена');
        return;
      }

      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      await _cameraController?.dispose();
      _cameraController = null;

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: true,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      // ignore: invalid_use_of_protected_member
      setState(() {
        _cameraController = controller;
        _isVideoRecordingUi = true;
        _isActuallyVideoRecording = false;
        _videoRecordingDuration = Duration.zero;
        _isVideoRecordingPaused = false;
        _recordCancelDragDx = 0.0;
      });

      await controller.startVideoRecording();

      if (!mounted) return;

      // ignore: invalid_use_of_protected_member
      setState(() {
        _isActuallyVideoRecording = true;
      });

      _videoRecordingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted || !_isVideoRecordingUi) return;
        final newDuration = _videoRecordingDuration + const Duration(milliseconds: 100);
        if (newDuration >= const Duration(seconds: 60)) {
          _videoRecordingTimer?.cancel();
          _sendVideoMessage();
          return;
        }
        // ignore: invalid_use_of_protected_member
        setState(() {
          _videoRecordingDuration = newDuration;
        });
      });
    } catch (e) {
      print('❌ [VIDEO] Ошибка запуска камеры: $e');
      _showErrorSnackBar('Не удалось запустить камеру');
      await _cancelVideoRecordingUi();
    }
  }

  Future<void> _cancelVideoRecordingUi() async {
    _videoRecordingTimer?.cancel();

    if (_isActuallyVideoRecording && _cameraController != null) {
      try {
        final xfile = await _cameraController!.stopVideoRecording();
        _isActuallyVideoRecording = false;
        try {
          final f = File(xfile.path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      } catch (e) {
        print('⚠️ [VIDEO] Ошибка остановки при отмене: $e');
        _isActuallyVideoRecording = false;
      }
    }

    await _cameraController?.dispose();

    if (!mounted) return;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _cameraController = null;
      _isVideoRecordingUi = false;
      _isVideoRecordingPaused = false;
      _videoRecordingDuration = Duration.zero;
      _recordCancelDragDx = 0.0;
      _currentVideoRecordingPath = null;
      _isActuallyVideoRecording = false;
    });
  }

  Future<void> _sendVideoMessage() async {
    if (_cameraController == null) {
      await _cancelVideoRecordingUi();
      return;
    }

    _videoRecordingTimer?.cancel();

    // Сохраняем ссылку на контроллер и длительность ДО setState,
    // чтобы сразу скрыть UI (иначе пользователь видит "зависание")
    final capturedController = _cameraController!;
    final duration = _videoRecordingDuration;
    final wasRecording = _isActuallyVideoRecording;

    // ignore: invalid_use_of_protected_member
    setState(() {
      _cameraController = null;
      _isVideoRecordingUi = false;
      _isActuallyVideoRecording = false;
      _isVideoRecordingPaused = false;
      _videoRecordingDuration = Duration.zero;
      _recordCancelDragDx = 0.0;
      _currentVideoRecordingPath = null;
      _isVideoUploading = wasRecording;
      _videoUploadProgress = 0.0;
      _isVideoUploadFailed = false;
    });

    if (!wasRecording) {
      await capturedController.dispose();
      return;
    }

    XFile? videoFile;
    try {
      videoFile = await capturedController.stopVideoRecording();
    } catch (e) {
      print('❌ [VIDEO] Ошибка остановки записи: $e');
      await capturedController.dispose();
      if (mounted) {
        // ignore: invalid_use_of_protected_member
        setState(() { _isVideoUploading = false; });
      }
      return;
    }

    await capturedController.dispose();

    final rawPath = videoFile.path;
    final rawFile = File(rawPath);

    if (!await rawFile.exists() || await rawFile.length() == 0) {
      _showErrorSnackBar('Видеофайл не найден или пуст');
      if (mounted) {
        // ignore: invalid_use_of_protected_member
        setState(() { _isVideoUploading = false; });
      }
      return;
    }

    // Обрезаем видео в квадрат 480×480 через FFmpeg (center-crop + scale)
    final dir = rawFile.parent;
    final croppedPath = '${dir.path}/video_sq_${DateTime.now().millisecondsSinceEpoch}.mp4';
    const int targetSize = 480;

    print('📹 [FFMPEG] Входной файл: $rawPath');
    print('📹 [FFMPEG] Выходной файл: $croppedPath');

    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-i', rawPath,
      // \, экранирует запятую внутри min() от парсера граф-фильтров FFmpeg
      '-vf', 'crop=min(iw\\,ih):min(iw\\,ih),scale=$targetSize:$targetSize',
      '-c:v', 'libx264',
      '-preset', 'fast',
      '-crf', '18',
      '-c:a', 'aac',
      '-movflags', '+faststart',
      croppedPath,
    ]);

    // Логируем весь вывод FFmpeg для отладки
    final logs = await session.getAllLogs();
    for (final log in logs) {
      print('📹 [FFMPEG] ${log.getMessage()}');
    }

    final returnCode = await session.getReturnCode();
    print('📹 [FFMPEG] Return code: $returnCode');

    // Удаляем исходный файл в любом случае
    try { await rawFile.delete(); } catch (_) {}

    String filePath;
    if (ReturnCode.isSuccess(returnCode)) {
      filePath = croppedPath;
      print('✅ [FFMPEG] Обрезка успешна: $croppedPath');
    } else {
      print('❌ [FFMPEG] Ошибка обрезки, returnCode=$returnCode');
      _showErrorSnackBar('Не удалось обработать видеокружок');
      if (mounted) {
        // ignore: invalid_use_of_protected_member
        setState(() { _isVideoUploading = false; });
      }
      return;
    }

    final file = File(filePath);
    if (!await file.exists() || await file.length() == 0) {
      _showErrorSnackBar('Обработанный видеофайл не найден');
      if (mounted) {
        // ignore: invalid_use_of_protected_member
        setState(() { _isVideoUploading = false; });
      }
      return;
    }

    final fileSize = await file.length();

    try {
      await ApiService.instance.sendVideoMessage(
        widget.chatId,
        localPath: filePath,
        durationSeconds: duration.inSeconds,
        fileSize: fileSize,
        width: targetSize,
        height: targetSize,
        senderId: _actualMyId,
        onProgress: (progress) {
          if (mounted) {
            // ignore: invalid_use_of_protected_member
            setState(() {
              _isVideoUploading = progress < 1.0;
              _videoUploadProgress = progress;
            });
          }
        },
      );

      if (mounted) {
        // ignore: invalid_use_of_protected_member
        setState(() {
          _isVideoUploading = false;
          _videoUploadProgress = 0.0;
          _isVideoUploadFailed = false;
          _cachedVideoPath = null;
        });
      }

      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    } catch (e) {
      print('❌ [VIDEO] Ошибка отправки видеокружка: $e');
      if (mounted) {
        // ignore: invalid_use_of_protected_member
        setState(() {
          _isVideoUploading = false;
          _videoUploadProgress = 0.0;
          _isVideoUploadFailed = true;
          _cachedVideoPath = filePath;
        });
        _showErrorSnackBar('Не удалось отправить видеокружок');
      }
    }
  }

  // Floating circular camera preview — positioned above the input bar
  Widget _buildVideoCirclePreview() {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    const circleSize = 200.0;
    const ringPadding = 6.0;
    final outerSize = circleSize + ringPadding * 2;
    final progress = (_videoRecordingDuration.inMilliseconds / 60000.0).clamp(0.0, 1.0);
    final previewSize = controller.value.previewSize;

    final screenHeight = MediaQuery.of(context).size.height;

    return Positioned(
      bottom: screenHeight * 0.18,
      left: 0,
      right: 0,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: outerSize,
              height: outerSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Progress arc
                  CustomPaint(
                    size: Size(outerSize, outerSize),
                    painter: _VideoProgressArcPainter(progress: progress),
                  ),
                  // Circular camera preview
                  ClipOval(
                    child: SizedBox.square(
                      dimension: circleSize,
                      child: previewSize != null
                          ? FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: previewSize.height,
                                height: previewSize.width,
                                child: CameraPreview(controller),
                              ),
                            )
                          : CameraPreview(controller),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (_isActuallyVideoRecording)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _formatVideoDuration(_videoRecordingDuration),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoRecordingBar({
    required bool isBlocked,
    required bool isGlass,
  }) {
    final colors = Theme.of(context).colorScheme;

    final cancelProgress = (_recordCancelDragDx.abs() / _ChatScreenState._recordCancelThreshold).clamp(0.0, 1.0);
    final cancelColor = Color.lerp(
      colors.onSurface.withValues(alpha: 0.7),
      colors.error,
      cancelProgress,
    )!;

    final content = Row(
      children: [
        _RecordingDot(isRecording: _isActuallyVideoRecording),
        const SizedBox(width: 8),
        Text(
          _formatVideoDuration(_videoRecordingDuration),
          style: TextStyle(
            color: colors.onSurface.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Center(
            child: Transform.translate(
              offset: Offset(_recordCancelDragDx, 0),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: (!isBlocked) ? _cancelVideoRecordingUi : null,
                child: Text(
                  'CANCEL',
                  style: TextStyle(
                    color: cancelColor,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        const SizedBox(width: _ChatScreenState._recordSendButtonSpace),
      ],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (!isBlocked) ? (_) => _handleRecordCancelDragStart() : null,
      onHorizontalDragUpdate: (!isBlocked) ? (d) => _handleRecordCancelDragUpdate(d) : null,
      onHorizontalDragEnd: (!isBlocked) ? (_) => _handleVideoCancelDragEnd() : null,
      child: content,
    );
  }

  void _handleVideoCancelDragEnd() {
    final reached = _recordCancelDragDx <= -_ChatScreenState._recordCancelThreshold;
    if (reached) {
      _cancelVideoRecordingUi();
      return;
    }

    final tween = Tween<double>(begin: _recordCancelDragDx, end: 0.0).animate(
      CurvedAnimation(parent: _recordCancelReturnController, curve: Curves.easeOutCubic),
    );
    void listener() {
      // ignore: invalid_use_of_protected_member
      setState(() {
        _recordCancelDragDx = tween.value;
      });
    }

    _recordCancelReturnController
      ..removeListener(listener)
      ..reset();
    _recordCancelReturnController.addListener(listener);
    _recordCancelReturnController.forward().whenComplete(() {
      _recordCancelReturnController.removeListener(listener);
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Arc progress painter for the video circle
// ─────────────────────────────────────────────────────────────────────────────

class _VideoProgressArcPainter extends CustomPainter {
  final double progress;

  _VideoProgressArcPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    // Background track
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );

    // Progress fill
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        2 * pi * progress,
        false,
        Paint()
          ..color = Colors.red
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_VideoProgressArcPainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// Blinking recording dot for the recording bar
// ─────────────────────────────────────────────────────────────────────────────

class _RecordingDot extends StatefulWidget {
  final bool isRecording;

  const _RecordingDot({required this.isRecording});

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _opacity = Tween<double>(begin: 1.0, end: 0.2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.isRecording) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_RecordingDot old) {
    super.didUpdateWidget(old);
    if (widget.isRecording && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.isRecording) {
      _ctrl.stop();
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
