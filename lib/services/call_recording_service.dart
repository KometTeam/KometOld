import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;

/// Сервис для записи звонков
class CallRecordingService {
  static final CallRecordingService instance = CallRecordingService._internal();
  factory CallRecordingService() => instance;
  CallRecordingService._internal();

  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  Timer? _recordingTimer;
  Duration _recordingDuration = Duration.zero;

  /// Stream для отслеживания состояния записи
  final StreamController<RecordingState> _stateController =
      StreamController<RecordingState>.broadcast();

  Stream<RecordingState> get recordingState => _stateController.stream;

  /// Текущее состояние записи
  RecordingState get currentState => RecordingState(
    isRecording: _isRecording,
    duration: _recordingDuration,
    path: _currentRecordingPath,
  );

  /// Начать запись звонка
  ///
  /// [contactName] - имя контакта для имени файла
  /// [contactId] - ID контакта для имени файла
  Future<String?> startRecording({
    required String contactName,
    required int contactId,
  }) async {
    if (_isRecording) {
      print('⚠️ Запись уже идет');
      return _currentRecordingPath;
    }

    try {
      // Проверяем разрешение на запись
      if (Platform.isAndroid || Platform.isIOS) {
        final permission = await Permission.microphone.request();
        if (!permission.isGranted) {
          throw Exception('Нет разрешения на запись аудио');
        }

        // На Android также проверяем разрешение на хранилище (для старых версий)
        if (Platform.isAndroid) {
          // На Android 10+ (API 29+) разрешение storage не требуется для app-specific директорий
          // Но для записи в публичные папки может потребоваться
          try {
            await Permission.storage.request();
          } catch (e) {
            // Игнорируем ошибки, так как на новых версиях Android это может быть недоступно
            print('⚠️ Разрешение storage недоступно (это нормально на Android 10+): $e');
          }
        }
      }

      // Получаем директорию для сохранения записей
      final directory = await _getRecordingsDirectory();

      // Генерируем имя файла
      final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final sanitizedContactName = _sanitizeFileName(contactName);
      final fileName = 'call_${sanitizedContactName}_${contactId}_$timestamp.m4a';
      final filePath = '${directory.path}/$fileName';

      print('🎙️ Начинаем запись звонка: $filePath');
      print('📁 Полный путь: $filePath');

      // Начинаем запись
      try {
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: filePath,
        );
      } catch (e) {
        print('❌ Ошибка начала записи в путь $filePath: $e');
        // Пробуем fallback на внутреннее хранилище
        final appDir = await getApplicationDocumentsDirectory();
        final fallbackDir = Directory(path.join(appDir.path, 'call_recordings'));
        if (!await fallbackDir.exists()) {
          await fallbackDir.create(recursive: true);
        }
        final fallbackPath = path.join(fallbackDir.path, fileName);
        print('📁 Пробуем fallback путь: $fallbackPath');
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: fallbackPath,
        );
        _currentRecordingPath = fallbackPath;
        print('✅ Запись начата в fallback директорию: $fallbackPath');
      }

      _isRecording = true;
      _currentRecordingPath = filePath;
      _recordingStartTime = DateTime.now();
      _recordingDuration = Duration.zero;

      // Запускаем таймер для отслеживания длительности
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_isRecording && _recordingStartTime != null) {
          _recordingDuration = DateTime.now().difference(_recordingStartTime!);
          _stateController.add(currentState);
        }
      });

      _stateController.add(currentState);
      print('✅ Запись начата: $filePath');

      return filePath;
    } catch (e) {
      print('❌ Ошибка начала записи: $e');
      _isRecording = false;
      _currentRecordingPath = null;
      _recordingStartTime = null;
      _stateController.add(currentState);
      rethrow;
    }
  }

  /// Остановить запись звонка
  Future<String?> stopRecording() async {
    if (!_isRecording) {
      print('⚠️ Запись не идет');
      return null;
    }

    try {
      print('🛑 Останавливаем запись...');

      final path = await _audioRecorder.stop();
      print('✅ Запись остановлена: $path');

      _isRecording = false;
      final finalPath = _currentRecordingPath ?? path;
      _currentRecordingPath = null;
      _recordingStartTime = null;
      _recordingTimer?.cancel();
      _recordingTimer = null;
      _recordingDuration = Duration.zero;

      _stateController.add(currentState);

      return finalPath;
    } catch (e) {
      print('❌ Ошибка остановки записи: $e');
      _isRecording = false;
      _currentRecordingPath = null;
      _recordingStartTime = null;
      _recordingTimer?.cancel();
      _recordingTimer = null;
      _stateController.add(currentState);
      rethrow;
    }
  }

  /// Пауза записи
  Future<void> pauseRecording() async {
    if (!_isRecording) {
      return;
    }

    try {
      await _audioRecorder.pause();
      _recordingTimer?.cancel();
      print('⏸️ Запись приостановлена');
    } catch (e) {
      print('❌ Ошибка паузы записи: $e');
    }
  }

  /// Возобновить запись
  Future<void> resumeRecording() async {
    if (!_isRecording) {
      return;
    }

    try {
      await _audioRecorder.resume();
      _recordingStartTime = DateTime.now().subtract(_recordingDuration);
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_isRecording && _recordingStartTime != null) {
          _recordingDuration = DateTime.now().difference(_recordingStartTime!);
          _stateController.add(currentState);
        }
      });
      print('▶️ Запись возобновлена');
    } catch (e) {
      print('❌ Ошибка возобновления записи: $e');
    }
  }

  /// Проверить, идет ли запись
  bool get isRecording => _isRecording;

  /// Получить текущую длительность записи
  Duration get duration => _recordingDuration;

  /// Получить путь к текущей записи
  String? get currentPath => _currentRecordingPath;

  /// Получить директорию для сохранения записей
  Future<Directory> _getRecordingsDirectory() async {
    Directory recordingsDir;

    if (Platform.isAndroid) {
      // На Android используем публичную директорию
      // /storage/emulated/0/Komet/Call Recordings
      try {
        final externalStorage = await getExternalStorageDirectory();
        if (externalStorage != null) {
          // Получаем корень внешнего хранилища
          // externalStorage обычно: /storage/emulated/0/Android/data/com.gwid.app.gwid/files
          // Нам нужно: /storage/emulated/0/Komet/Call Recordings
          final storageRoot = externalStorage.path.split('/Android')[0];
          final targetPath = path.join(storageRoot, 'Komet', 'Call Recordings');
          recordingsDir = Directory(targetPath);

          print('📁 Пытаемся создать директорию: ${recordingsDir.path}');
          print('📁 Корень хранилища: $storageRoot');

          // Пытаемся создать директорию с принудительным созданием родительских
          try {
            // Создаем родительскую папку Komet если её нет
            final kometDir = Directory(path.join(storageRoot, 'Komet'));
            if (!await kometDir.exists()) {
              print('📁 Создаем папку Komet...');
              await kometDir.create(recursive: true);
            }

            // Создаем папку Call Recordings
            if (!await recordingsDir.exists()) {
              print('📁 Создаем папку Call Recordings...');
              await recordingsDir.create(recursive: true);
            }

            print('✅ Директория создана/существует: ${recordingsDir.path}');

            // Проверяем, что можем писать в эту директорию
            final testFile = File(path.join(recordingsDir.path, '.test_write'));
            try {
              await testFile.writeAsString('test', mode: FileMode.write);
              await testFile.delete();
              print('✅ Проверка записи успешна - можем писать в директорию');
            } catch (e) {
              print('⚠️ Не можем писать в директорию: $e');
              print('📁 Пробуем альтернативный путь через Music...');
              // Пробуем альтернативный путь - Music/Komet/Call Recordings
              final musicPath = path.join(storageRoot, 'Music', 'Komet', 'Call Recordings');
              recordingsDir = Directory(musicPath);
              if (!await recordingsDir.exists()) {
                await recordingsDir.create(recursive: true);
              }
              print('📁 Используем альтернативный путь: ${recordingsDir.path}');
            }
          } catch (e) {
            print('❌ Ошибка создания директории: $e');
            print('📁 Пробуем альтернативный путь через Music...');
            // Пробуем альтернативный путь
            try {
              final storageRoot = externalStorage.path.split('/Android')[0];
              final musicPath = path.join(storageRoot, 'Music', 'Komet', 'Call Recordings');
              recordingsDir = Directory(musicPath);
              if (!await recordingsDir.exists()) {
                await recordingsDir.create(recursive: true);
              }
              print('📁 Используем альтернативный путь: ${recordingsDir.path}');
            } catch (e2) {
              print('❌ Альтернативный путь тоже не работает: $e2');
              throw e; // Бросаем оригинальную ошибку для fallback
            }
          }
        } else {
          throw Exception('Не удалось получить внешнее хранилище');
        }
      } catch (e) {
        print('⚠️ Ошибка работы с внешним хранилищем: $e');
        print('📁 Используем внутреннее хранилище как fallback');
        // Fallback на внутреннее хранилище если внешнее недоступно
        final appDir = await getApplicationDocumentsDirectory();
        recordingsDir = Directory(path.join(appDir.path, 'call_recordings'));
        if (!await recordingsDir.exists()) {
          await recordingsDir.create(recursive: true);
        }
        print('📁 Fallback путь: ${recordingsDir.path}');
      }
    } else if (Platform.isIOS) {
      // На iOS используем Documents директорию
      final appDir = await getApplicationDocumentsDirectory();
      recordingsDir = Directory(path.join(appDir.path, 'Call Recordings'));
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }
    } else {
      // Desktop и другие платформы
      final appDir = await getApplicationDocumentsDirectory();
      recordingsDir = Directory(path.join(appDir.path, 'Call Recordings'));
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }
    }

    return recordingsDir;
  }

  /// Очистить имя файла от недопустимых символов
  String _sanitizeFileName(String name) {
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .substring(0, name.length > 50 ? 50 : name.length);
  }

  /// Освободить ресурсы
  Future<void> dispose() async {
    if (_isRecording) {
      await stopRecording();
    }
    _recordingTimer?.cancel();
    await _audioRecorder.dispose();
    await _stateController.close();
  }
}

/// Состояние записи
class RecordingState {
  final bool isRecording;
  final Duration duration;
  final String? path;

  RecordingState({
    required this.isRecording,
    required this.duration,
    this.path,
  });

  RecordingState copyWith({
    bool? isRecording,
    Duration? duration,
    String? path,
  }) {
    return RecordingState(
      isRecording: isRecording ?? this.isRecording,
      duration: duration ?? this.duration,
      path: path ?? this.path,
    );
  }
}
