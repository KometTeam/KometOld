import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';

import 'package:gwid/services/komet_enc_meta_service.dart';
import 'package:gwid/widgets/message_bubble/services/file_download_service.dart';

class EncryptedFileTile extends StatefulWidget {
  final String  fileName;
  final int     fileSize;
  final int     fileId;
  final String? token;
  final int?    chatId;
  final Color   textColor;
  final bool    isUltraOptimized;
  final bool    showNameHeader;
  final VoidCallback onDownload;

  const EncryptedFileTile({
    required this.fileName,
    required this.fileSize,
    required this.fileId,
    required this.textColor,
    required this.isUltraOptimized,
    required this.showNameHeader,
    required this.onDownload,
    this.token,
    this.chatId,
  });

  @override
  State<EncryptedFileTile> createState() => EncryptedFileTileState();
}

class EncryptedFileTileState extends State<EncryptedFileTile> {
  Uint8List? _preview;
  String?    _decPath;

  @override
  void initState() {
    super.initState();
    _tryLoadPreview();
    // Подписываемся на глобальный updateTick — когда warmUp или
    // _restoreDownloadedFileNames добавляют новые имена/превью,
    // тайл перестраивается даже при первом заходе в чат.
    KometEncMetaService.instance.updateTick.addListener(_onGlobalUpdate);
  }

  void _onGlobalUpdate() {
    if (!mounted) return;
    _refreshFromCache();
  }

  @override
  void didUpdateWidget(EncryptedFileTile old) {
    super.didUpdateWidget(old);
    if (old.fileId != widget.fileId) _tryLoadPreview();
  }

  void _tryLoadPreview() {
    _refreshFromCache();
    // Подписываемся на изменения progress чтобы поймать момент
    // когда расшифровка завершится.
    FileDownloadProgressService()
        .getProgress(widget.fileId.toString())
        .addListener(_onProgressChanged);
  }

  /// Единая логика синхронизации кэша → state. ВАЖНО: _decPath
  /// устанавливается ВСЕГДА когда есть путь — иначе тап на не-картинку
  /// (mp4/pdf/etc) запускал бы повторное скачивание.
  void _refreshFromCache() {
    final cached = KometEncMetaService.instance.getPreview(widget.fileId);
    final path   = KometEncMetaService.instance.getDecPath(widget.fileId);

    bool changed = false;
    if (path != null && path != _decPath) {
      _decPath = path;
      changed = true;
    }
    if (cached != null && cached != _preview) {
      _preview = cached;
      changed = true;
    }
    if (changed && mounted) setState(() {});

    // Если есть путь но нет байтов превью — догружаем с диска (для картинок)
    if (cached == null && path != null && _preview == null) {
      _loadFromDisk(path);
    }
  }

  void _onProgressChanged() {
    if (!mounted) return;
    final prog = FileDownloadProgressService()
        .getProgress(widget.fileId.toString())
        .value;
    if (prog >= 1.0) _refreshFromCache();
  }

  Future<void> _loadFromDisk(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return;
      // Проверяем расширение по оригинальному имени
      final origName = KometEncMetaService.instance
              .getOriginalNameSync(widget.fileId) ??
          widget.fileName.replaceFirst(RegExp(r'^🔒 '), '');
      final ext = origName.split('.').last.toLowerCase();
      if (!['jpg','jpeg','png','gif','webp','bmp','heic'].contains(ext)) return;
      final size = await f.length();
      if (size > 10 * 1024 * 1024) return;
      final bytes = await f.readAsBytes();
      KometEncMetaService.instance.cachePreview(widget.fileId, bytes);
      if (mounted) setState(() { _preview = bytes; _decPath = path; });
    } catch (_) {}
  }

  @override
  void dispose() {
    KometEncMetaService.instance.updateTick.removeListener(_onGlobalUpdate);
    FileDownloadProgressService()
        .getProgress(widget.fileId.toString())
        .removeListener(_onProgressChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final br = widget.showNameHeader
        ? BorderRadius.only(
            bottomLeft:  Radius.circular(widget.isUltraOptimized ? 8 : 12),
            bottomRight: Radius.circular(widget.isUltraOptimized ? 8 : 12),
          )
        : BorderRadius.circular(widget.isUltraOptimized ? 8 : 12);

    final screenWidth  = MediaQuery.of(context).size.width;
    final maxWidth     = screenWidth < 400 ? screenWidth * 0.7 : 300.0;
    final displayName  = widget.fileName.replaceFirst(RegExp(r'^🔒 '), '');
    final sizeStr      = _formatFileSizeStatic(widget.fileSize);

    return ValueListenableBuilder<double>(
      valueListenable:
          FileDownloadProgressService().getProgress(widget.fileId.toString()),
      builder: (context, progress, _) {
        final isDownloading = progress >= 0 && progress < 1.0;
        final isDownloaded  = progress >= 1.0;

        // Превью изображения
        if (isDownloaded && _preview != null) {
          return GestureDetector(
            onTap: () { if (_decPath != null) OpenFile.open(_decPath!); },
            child: Container(
              constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 260),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(borderRadius: br),
              child: Stack(children: [
                Image.memory(_preview!,
                    fit: BoxFit.cover, width: maxWidth, gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const SizedBox()),
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    color: Colors.black54,
                    child: Text('🔒 $displayName',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
              ]),
            ),
          );
        }

        // Обычная плашка файла
        final ext      = displayName.contains('.')
            ? displayName.split('.').last.toLowerCase()
            : '';
        final iconData = _getFileIconStatic(ext);

        return GestureDetector(
          onTap: isDownloading
              ? null
              : () {
                  if (isDownloaded && _decPath != null) {
                    OpenFile.open(_decPath!);
                    return;
                  }
                  widget.onDownload();
                },
          child: AbsorbPointer(
            absorbing: isDownloading,
            child: Container(
              constraints: BoxConstraints(maxWidth: maxWidth),
              decoration: BoxDecoration(
                color: widget.textColor.withValues(alpha: 0.05),
                borderRadius: br,
                border: Border.all(
                    color: widget.textColor.withValues(alpha: 0.1)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: widget.textColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(iconData,
                          color: widget.textColor.withValues(alpha: 0.8),
                          size: 24),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('🔒 $displayName',
                              style: TextStyle(
                                  color: widget.textColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          if (progress < 0)
                            Text(sizeStr,
                                style: TextStyle(
                                    color: widget.textColor
                                        .withValues(alpha: 0.6),
                                    fontSize: 12))
                          else if (progress < 1.0)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 3,
                                    backgroundColor: widget.textColor
                                        .withValues(alpha: 0.1)),
                                const SizedBox(height: 4),
                                Text(
                                    '${(progress * 100).toStringAsFixed(0)}%',
                                    style: TextStyle(
                                        color: widget.textColor
                                            .withValues(alpha: 0.6),
                                        fontSize: 11)),
                              ],
                            )
                          else
                            Row(children: [
                              Icon(Icons.check_circle,
                                  size: 12,
                                  color: Colors.green.withValues(alpha: 0.8)),
                              const SizedBox(width: 4),
                              Text(
                                  _decPath != null
                                      ? 'Расшифровано'
                                      : 'Загружено',
                                  style: TextStyle(
                                      color: Colors.green
                                          .withValues(alpha: 0.8),
                                      fontSize: 11)),
                            ]),
                        ],
                      ),
                    ),
                    if (isDownloading)
                      const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      Icon(
                          isDownloaded
                              ? Icons.open_in_new
                              : Icons.download_outlined,
                          color: widget.textColor.withValues(alpha: 0.6),
                          size: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static String _formatFileSizeStatic(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  static IconData _getFileIconStatic(String ext) {
    switch (ext) {
      case 'pdf': return Icons.picture_as_pdf_outlined;
      case 'doc': case 'docx': return Icons.description_outlined;
      case 'xls': case 'xlsx': return Icons.table_chart_outlined;
      case 'ppt': case 'pptx': return Icons.slideshow_outlined;
      case 'zip': case 'rar': case '7z': return Icons.folder_zip_outlined;
      case 'mp3': case 'wav': case 'flac': case 'aac':
      case 'm4a': case 'ogg': return Icons.audio_file_outlined;
      case 'mp4': case 'mov': case 'avi': case 'mkv':
      case 'webm': return Icons.video_file_outlined;
      case 'jpg': case 'jpeg': case 'png': case 'gif':
      case 'webp': case 'bmp': case 'heic': return Icons.image_outlined;
      default: return Icons.insert_drive_file_outlined;
    }
  }
}
