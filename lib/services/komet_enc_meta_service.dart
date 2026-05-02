// komet_enc_meta_service.dart — хранит оригинальные имена зашифрованных
// файлов и кэш расшифрованных байт-превью.
//
// Проблема: сервер MAX не хранит наши кастомные поля (originalName,
// _komet_enc). При получении сообщения attaches содержат только то что
// знает MAX: fileId, name (обфусцированное), size, url, token.
//
// Решение:
//   1. При ОТПРАВКЕ записываем маппинг fileId → originalName в
//      SharedPreferences. Пишет api_service_media после успешной
//      загрузки файла.
//   2. При РЕНДЕРЕ в bubble читаем маппинг по fileId — показываем
//      реальное имя.
//   3. После РАСШИФРОВКИ кэшируем байты в RAM (LRU 20 записей) чтобы
//      bubble мог показать Image.memory без повторной расшифровки.
//   4. Также храним путь к расшифрованному файлу — bubble открывает его.

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KometEncMetaService {
  KometEncMetaService._();
  static final KometEncMetaService instance = KometEncMetaService._();

  static const String _kOrigNames = 'komet_enc_orig_names';
  static const int _previewCacheLimit = 20;

  // RAM-кэш: fileId → расшифрованные байты для превью
  final Map<String, Uint8List> _previewCache = {};
  // RAM-кэш: fileId → путь к расшифрованному файлу
  final Map<String, String> _decPathCache = {};

  /// Слушатель для EncryptedFileTile — increment чтобы тайл перестроился
  /// когда появились новые имена / превью.
  final ValueNotifier<int> updateTick = ValueNotifier<int>(0);

  void _notifyUpdate() {
    updateTick.value++;
  }

  // --- Оригинальные имена ---

  /// Сохраняет оригинальное имя файла для последующего отображения.
  Future<void> saveOriginalName(int fileId, String originalName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = _loadMap(prefs);
      map[fileId.toString()] = originalName;
      await prefs.setString(_kOrigNames, _encodeMap(map));
    } catch (e) {
      debugPrint('KometEncMetaService.saveOriginalName error: $e');
    }
  }

  /// Читает оригинальное имя файла. Возвращает null если не найдено.
  Future<String?> getOriginalName(int fileId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = _loadMap(prefs);
      return map[fileId.toString()];
    } catch (e) {
      debugPrint('KometEncMetaService.getOriginalName error: $e');
      return null;
    }
  }

  /// Синхронный вариант — только если уже кэшировано в RAM.
  String? getOriginalNameSync(int fileId) {
    return _syncNameCache[fileId.toString()];
  }

  // RAM-кэш синхронный (заполняется при warmUp)
  final Map<String, String> _syncNameCache = {};

  /// Кладёт имя в RAM-кэш синхронно (без записи в prefs).
  void cacheNameSync(int fileId, String name) {
    _syncNameCache[fileId.toString()] = name;
    _notifyUpdate();
  }

  /// Предзагрузка маппинга в RAM. Вызывать при старте или открытии чата.
  Future<void> warmUp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = _loadMap(prefs);
      _syncNameCache.addAll(map);
      if (map.isNotEmpty) _notifyUpdate();
    } catch (_) {}
  }

  // --- Превью ---

  /// Сохраняет расшифрованные байты в RAM-кэш (для Image.memory в bubble).
  void cachePreview(int fileId, Uint8List bytes) {
    if (_previewCache.length >= _previewCacheLimit) {
      _previewCache.remove(_previewCache.keys.first);
    }
    _previewCache[fileId.toString()] = bytes;
    _notifyUpdate();
  }

  /// Читает расшифрованные байты из RAM-кэша.
  Uint8List? getPreview(int fileId) => _previewCache[fileId.toString()];

  // --- Путь к расшифрованному файлу ---

  void cacheDecPath(int fileId, String path) {
    _decPathCache[fileId.toString()] = path;
    _notifyUpdate();
  }

  String? getDecPath(int fileId) => _decPathCache[fileId.toString()];

  // --- helpers ---

  Map<String, String> _loadMap(SharedPreferences prefs) {
    final raw = prefs.getString(_kOrigNames);
    if (raw == null || raw.isEmpty) return {};
    try {
      final result = <String, String>{};
      for (final entry in raw.split('\n')) {
        final idx = entry.indexOf(':');
        if (idx < 0) continue;
        result[entry.substring(0, idx)] = entry.substring(idx + 1);
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  String _encodeMap(Map<String, String> map) {
    // Простой формат: "fileId:originalName\n..."
    // Ограничиваем 500 записями чтобы не раздувать прefs
    final entries = map.entries.toList();
    if (entries.length > 500) {
      entries.removeRange(0, entries.length - 500);
    }
    return entries.map((e) => '${e.key}:${e.value}').join('\n');
  }
}
