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
      _sendDragPullDy = 0.0;
      _sendDragDy = 0.0;
      _isSendDragging = false;
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

    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      _showErrorSnackBar('Нет разрешения на запись видео');
      return;
    }

    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _currentVideoRecordingPath = '${directory.path}/video_$timestamp.mp4';

    print('Начинаем запись видео в: $_currentVideoRecordingPath');

    // Note: В реальном приложении нужно использовать камеру/видео плагин
    // Здесь мы используем те же настройки для базовой интеграции
    try {
      _isActuallyVideoRecording = true;
      print('📹 Запись видеокружка начата: $_currentVideoRecordingPath');
    } catch (e) {
      print('❌ Ошибка начала записи видео: $e');
      _showErrorSnackBar('Не удалось начать запись видео');
      return;
    }

    if (!mounted) return;
    setState(() {
      _isVideoRecordingUi = true;
      _isVideoRecordingPaused = false;
      _videoRecordingDuration = Duration.zero;
      _recordCancelDragDx = 0.0;
    });

    _videoRecordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_isVideoRecordingUi) return;
      if (_isVideoRecordingPaused) return;
      setState(() {
        _videoRecordingDuration += const Duration(seconds: 1);
      });
    });
  }

  Future<void> _cancelVideoRecordingUi() async {
    _videoRecordingTimer?.cancel();

    if (_isActuallyVideoRecording) {
      _isActuallyVideoRecording = false;

      if (_currentVideoRecordingPath != null) {
        final file = File(_currentVideoRecordingPath!);
        if (await file.exists()) {
          await file.delete();
          print('🗑️ Видеозапись удалена: $_currentVideoRecordingPath');
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _isVideoRecordingUi = false;
      _isVideoRecordingPaused = false;
      _videoRecordingDuration = Duration.zero;
      _recordCancelDragDx = 0.0;
      _currentVideoRecordingPath = null;
    });
  }

  Future<void> _toggleVideoRecordingPause() async {
    if (_isActuallyVideoRecording) {
      // Pause/Resume видеозаписи (реализация зависит от используемого плагина)
      print(_isVideoRecordingPaused ? '▶️ Запись видео возобновлена' : '⏸️ Запись видео на паузе');
    }

    if (!mounted) return;
    setState(() {
      _isVideoRecordingPaused = !_isVideoRecordingPaused;
      _recordCancelDragDx = 0.0;
    });
  }

  Future<void> _sendVideoMessage() async {
    if (!_isActuallyVideoRecording || _currentVideoRecordingPath == null) {
      print('⚠️ Нет активной видеозаписи для отправки');
      return;
    }

    _videoRecordingTimer?.cancel();

    _isActuallyVideoRecording = false;

    await Future.delayed(const Duration(milliseconds: 200));

    final filePath = _currentVideoRecordingPath!;
    final file = File(filePath);
    var fileExists = await file.exists();
    var fileSize = fileExists ? await file.length() : 0;

    if (!fileExists || fileSize == 0) {
      await Future.delayed(const Duration(milliseconds: 300));
      fileExists = await file.exists();
      fileSize = fileExists ? await file.length() : 0;
    }

    if (!fileExists || fileSize == 0) {
      print('❌ Видеофайл не создан или пуст: $filePath');
      if (mounted) {
        _showErrorSnackBar('Не удалось сохранить видеозапись');
      }
      await _cancelVideoRecordingUi();
      return;
    }

    print('✅ Видеофайл записан: $filePath (${fileSize} bytes)');

    final duration = _videoRecordingDuration;

    if (mounted) {
      setState(() {
        _isVideoRecordingUi = false;
        _isVideoRecordingPaused = false;
        _videoRecordingDuration = Duration.zero;
        _recordCancelDragDx = 0.0;
        _currentVideoRecordingPath = null;
        _isVideoUploading = true;
        _videoUploadProgress = 0.0;
        _isVideoUploadFailed = false;
      });
    }

    print('📤 Отправка видеокружка: $filePath, длительность: ${duration.inSeconds}s');

    try {
      await ApiService.instance.sendVideoMessage(
        widget.chatId,
        localPath: filePath,
        durationSeconds: duration.inSeconds,
        fileSize: fileSize,
        width: _videoWidth,
        height: _videoHeight,
        senderId: _actualMyId,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _isVideoUploading = progress < 1.0;
              _videoUploadProgress = progress;
            });
          }
        },
      );

      print('✅ Видеокружок успешно отправлен');
      
      if (mounted) {
        setState(() {
          _isVideoUploading = false;
          _videoUploadProgress = 0.0;
          _isVideoUploadFailed = false;
          _cachedVideoPath = null;
        });
      }

      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        print('⚠️ Не удалось удалить временный видеофайл: $e');
      }
    } catch (e, stackTrace) {
      print('❌ Ошибка отправки видеокружка: $e');
      print(stackTrace);
      
      if (mounted) {
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

    final canInteract = !isBlocked && !_isVideoRecordingPaused;

    final trashButton = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: (!isBlocked) ? _cancelVideoRecordingUi : null,
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
          _formatVideoDuration(_videoRecordingDuration),
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
          child: _isVideoRecordingPaused
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
              child: _isVideoRecordingPaused
                  ? const SizedBox(
                key: ValueKey<String>('recordingIcon'),
                height: 24,
                child: Icon(Icons.videocam, color: Colors.red, size: 20),
              )
                  : Transform.translate(
                key: const ValueKey<String>('cancel'),
                offset: Offset(_recordCancelDragDx, 0),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: canInteract ? _cancelVideoRecordingUi : null,
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
}
