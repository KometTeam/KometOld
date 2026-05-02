// encrypted_photo_widget.dart — превью фото из зашифрованного чата.
//
// Логика:
//   1. Скачиваем байты с url через http.
//   2. Проверяем magic CRPT в первых 4 байтах.
//   3. Если CRPT — расшифровываем через ключ чата → Image.memory.
//   4. Если не CRPT — показываем как обычно.
//   5. Кэшируем расшифрованные байты в RAM (LRU 30 элементов).
//
// Используется в chat_message_bubble вместо Image.network для чатов,
// где включено encryptFiles.

import 'dart:async';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:gwid/services/encrypted_file_service.dart';

class EncryptedPhotoWidget extends StatefulWidget {
  final String url;
  final int chatId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Uint8List? previewBytes;
  final Widget Function()? placeholderBuilder;
  final Widget Function()? errorBuilder;

  const EncryptedPhotoWidget({
    super.key,
    required this.url,
    required this.chatId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.previewBytes,
    this.placeholderBuilder,
    this.errorBuilder,
  });

  @override
  State<EncryptedPhotoWidget> createState() => _EncryptedPhotoWidgetState();
}

class _EncryptedPhotoWidgetState extends State<EncryptedPhotoWidget> {
  // Простой LRU-кэш расшифрованных байтов (по url). 30 записей хватает
  // для прокрутки чата без перерасшифровки видимых элементов.
  static final Map<String, Uint8List> _cache = <String, Uint8List>{};
  static const int _cacheLimit = 30;

  Uint8List? _decryptedBytes;
  bool _loading = false;
  bool _failed = false;
  bool _notEncrypted = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(EncryptedPhotoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.chatId != widget.chatId) {
      _decryptedBytes = null;
      _failed = false;
      _notEncrypted = false;
      _start();
    }
  }

  Future<void> _start() async {
    // Проверяем кэш.
    final cached = _cache[widget.url];
    if (cached != null) {
      if (mounted) setState(() => _decryptedBytes = cached);
      return;
    }

    if (_loading) return;
    setState(() => _loading = true);

    try {
      // 1. Скачиваем.
      final resp = await http.get(Uri.parse(widget.url));
      if (resp.statusCode != 200) {
        if (mounted) setState(() {
          _loading = false;
          _failed = true;
        });
        return;
      }
      final bytes = resp.bodyBytes;

      // 2. Если это не CRPT — возвращаем как есть (фото отправили без
      //    шифрования, например, до включения encrypt files).
      if (bytes.length < 4 ||
          bytes[0] != 0x43 || // 'C'
          bytes[1] != 0x52 || // 'R'
          bytes[2] != 0x50 || // 'P'
          bytes[3] != 0x54) {
        // 'T'
        _putCache(widget.url, bytes);
        if (mounted) setState(() {
          _loading = false;
          _notEncrypted = true;
          _decryptedBytes = bytes;
        });
        return;
      }

      // 3. Расшифровываем. EncryptedFileService.tryDecrypt принимает
      //    путь к файлу, поэтому пишем во временный файл, расшифровываем,
      //    читаем, удаляем.
      final tmp = await getTemporaryDirectory();
      final tmpFile = File(
        '${tmp.path}/enc_preview_${DateTime.now().microsecondsSinceEpoch}.bin',
      );
      await tmpFile.writeAsBytes(bytes);

      try {
        final encSvc = EncryptedFileService.instance;
        final decPath = await encSvc.tryDecrypt(
          chatId: widget.chatId,
          filePath: tmpFile.path,
        );
        if (decPath == null) {
          if (mounted) setState(() {
            _loading = false;
            _failed = true;
          });
          return;
        }
        final decBytes = await File(decPath).readAsBytes();
        // Удаляем временный расшифрованный файл — он только для превью.
        try {
          await File(decPath).delete();
        } catch (_) {}

        _putCache(widget.url, decBytes);
        if (mounted) setState(() {
          _loading = false;
          _decryptedBytes = decBytes;
        });
      } finally {
        try {
          await tmpFile.delete();
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _putCache(String url, Uint8List bytes) {
    if (_cache.length >= _cacheLimit) {
      // Удаляем самый старый (insertion order).
      final firstKey = _cache.keys.first;
      _cache.remove(firstKey);
    }
    _cache[url] = bytes;
  }

  @override
  Widget build(BuildContext context) {
    if (_decryptedBytes != null) {
      return Image.memory(
        _decryptedBytes!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            widget.errorBuilder?.call() ?? _defaultError(),
      );
    }

    if (_failed) {
      return widget.errorBuilder?.call() ?? _defaultError();
    }

    // Loading — показываем preview если есть, иначе placeholder.
    if (widget.previewBytes != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            widget.previewBytes!,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            gaplessPlayback: true,
          ),
          if (_loading)
            const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      );
    }

    return widget.placeholderBuilder?.call() ?? _defaultLoading();
  }

  Widget _defaultLoading() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.black12,
      alignment: Alignment.center,
      child: const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _defaultError() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.black12,
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image, color: Colors.black38),
    );
  }
}
