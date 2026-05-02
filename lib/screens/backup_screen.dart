// backup_screen.dart — экран резервного копирования и восстановления
// всех ключей чатов.

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import 'package:gwid/services/chat_encryption_service.dart';
import 'package:gwid/services/crypt/backup_codec.dart';
import 'package:gwid/services/crypt/master_key_manager.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Резервная копия', style: GoogleFonts.inter()),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Создать', icon: Icon(Icons.cloud_upload)),
            Tab(text: 'Восстановить', icon: Icon(Icons.cloud_download)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _CreateBackupTab(),
          _RestoreBackupTab(),
        ],
      ),
    );
  }
}

// ========================================================================== //
//                              CREATE
// ========================================================================== //

class _CreateBackupTab extends StatefulWidget {
  const _CreateBackupTab();

  @override
  State<_CreateBackupTab> createState() => _CreateBackupTabState();
}

class _CreateBackupTabState extends State<_CreateBackupTab> {
  final _pwCtl = TextEditingController();
  final _pwCtl2 = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _resultPath;
  int? _resultKeysCount;

  @override
  void dispose() {
    _pwCtl.dispose();
    _pwCtl2.dispose();
    super.dispose();
  }

  Future<void> _onCreate() async {
    if (_pwCtl.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Пароль минимум 8 символов'),
        ),
      );
      return;
    }
    if (_pwCtl.text != _pwCtl2.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пароли не совпадают')),
      );
      return;
    }

    setState(() {
      _busy = true;
      _resultPath = null;
    });

    try {
      final mgr = MasterKeyManager.instance;
      if (!mgr.isUnlocked) {
        throw MasterLockedException();
      }

      // Собираем все ключи. Источник: SharedPreferences для конфигов,
      // MasterKeyManager — для chat_key.
      final prefs = await SharedPreferences.getInstance();
      final keys = <BackupChatKey>[];
      for (final key in prefs.getKeys()) {
        if (!key.startsWith('encryption_chat_')) continue;
        final chatIdStr = key.substring('encryption_chat_'.length);
        final chatId = int.tryParse(chatIdStr);
        if (chatId == null) continue;

        final cfg = await ChatEncryptionService.getConfigForChat(chatId);
        if (cfg == null) continue;

        // Только чаты с новым ключом.
        if (!ChatEncryptionService.hasNewKey(cfg)) continue;

        if (!await mgr.hasChatKey(chatId)) continue;
        final secret = await mgr.getOrCreateChatKey(chatId);
        keys.add(BackupChatKey(
          chatId: chatId,
          key: secret.exposeCopy(),
          profile: cfg.obfuscationProfile,
          legacyXorPassword: cfg.legacyXorPassword,
        ));
      }

      if (keys.isEmpty) {
        throw StateError('Нет зашифрованных чатов для backup');
      }

      final blob = await packBackup(
        backupPassword: _pwCtl.text,
        keys: keys,
      );

      // Затираем ключи в RAM после упаковки.
      for (final k in keys) {
        for (var i = 0; i < k.key.length; i++) {
          k.key[i] = 0;
        }
      }

      // Сохраняем в папку Downloads чтобы файл остался доступен
      // пользователю после закрытия приложения. Fallback — tmp.
      Directory saveDir;
      try {
        // getExternalStorageDirectory() на Android = .../Android/data/…/files
        // Для Downloads нужен getExternalStorageDirectories или явный путь.
        final downloads = Directory('/storage/emulated/0/Download');
        if (await downloads.exists()) {
          saveDir = downloads;
        } else {
          saveDir = await getTemporaryDirectory();
        }
      } catch (_) {
        saveDir = await getTemporaryDirectory();
      }

      final ts = DateTime.now().millisecondsSinceEpoch;
      final filename = 'kometold_backup_$ts.backup';
      final file = File('${saveDir.path}/$filename');
      await file.writeAsBytes(blob);

      if (!mounted) return;
      setState(() {
        _resultPath = file.path;
        _resultKeysCount = keys.length;
      });

      // Предлагаем поделиться — пользователь может выбрать куда сохранить.
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Backup сохраняет ВСЕ ключи зашифрованных чатов в один '
            'зашифрованный файл (.kbak). Защищён отдельным паролем — '
            'не используйте мастер-пароль приложения.',
            style: GoogleFonts.inter(fontSize: 13),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _pwCtl,
            obscureText: _obscure,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: 'Пароль backup',
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility
                    : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pwCtl2,
            obscureText: _obscure,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Повторите пароль',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          if (_busy)
            const LinearProgressIndicator()
          else
            FilledButton.icon(
              onPressed: _onCreate,
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Создать резервную копию'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          if (_resultPath != null) ...[
            const SizedBox(height: 20),
            Card(
              color: Colors.green.withValues(alpha: 0.08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.green.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green),
                        const SizedBox(width: 8),
                        Text(
                          'Backup создан',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Сохранено ключей: $_resultKeysCount'),
                    const SizedBox(height: 4),
                    Text(
                      _resultPath!,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final p = _resultPath;
                        if (p == null) return;
                        await Share.shareXFiles([XFile(p)]);
                      },
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('Поделиться ещё раз'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ========================================================================== //
//                              RESTORE
// ========================================================================== //

class _RestoreBackupTab extends StatefulWidget {
  const _RestoreBackupTab();

  @override
  State<_RestoreBackupTab> createState() => _RestoreBackupTabState();
}

class _RestoreBackupTabState extends State<_RestoreBackupTab> {
  final _pwCtl = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  Uint8List? _selectedBlob;
  String? _selectedName;

  @override
  void dispose() {
    _pwCtl.dispose();
    super.dispose();
  }

  Future<void> _onPickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;
      final bytes = await File(path).readAsBytes();
      if (!mounted) return;
      setState(() {
        _selectedBlob = bytes;
        _selectedName = result.files.single.name;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка чтения файла: $e')),
      );
    }
  }

  Future<void> _onRestore() async {
    final blob = _selectedBlob;
    if (blob == null) return;
    if (_pwCtl.text.isEmpty) return;

    setState(() => _busy = true);

    try {
      final mgr = MasterKeyManager.instance;
      if (!mgr.isUnlocked) throw MasterLockedException();

      final keys = await unpackBackup(
        backupPassword: _pwCtl.text,
        blob: blob,
      );

      var imported = 0;
      try {
        for (final k in keys) {
          await mgr.importChatKey(k.chatId, k.key);
          final cfg = await ChatEncryptionService.getConfigForChat(k.chatId);
          await ChatEncryptionService.saveRawConfigForChat(
            k.chatId,
            ChatEncryptionConfig(
              password: ChatEncryptionService.serializeChatKey(k.chatId),
              sendEncrypted: cfg?.sendEncrypted ?? true,
              legacyXorPassword:
                  k.legacyXorPassword ?? cfg?.legacyXorPassword,
              obfuscationProfile: k.profile ?? 'ru_full',
            ),
          );
          imported++;
        }
      } finally {
        // Затираем ключи в памяти.
        for (final k in keys) {
          for (var i = 0; i < k.key.length; i++) {
            k.key[i] = 0;
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Восстановлено $imported ключей')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: ${_friendlyError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('SecretBoxAuthenticationError') ||
        msg.contains('Auth') ||
        msg.contains('tag')) {
      return 'Неверный пароль или повреждённый файл';
    }
    return msg;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Восстановить ключи чатов из ранее созданной резервной копии. '
            'Существующие ключи в этих чатах будут перезаписаны.',
            style: GoogleFonts.inter(fontSize: 13),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _busy ? null : _onPickFile,
            icon: const Icon(Icons.attach_file),
            label: Text(_selectedName ?? 'Выбрать файл резервной копии'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pwCtl,
            obscureText: _obscure,
            enabled: !_busy && _selectedBlob != null,
            decoration: InputDecoration(
              labelText: 'Пароль backup',
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility
                    : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          if (_busy)
            const LinearProgressIndicator()
          else
            FilledButton.icon(
              onPressed: _selectedBlob == null ? null : _onRestore,
              icon: const Icon(Icons.cloud_download),
              label: const Text('Восстановить'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
        ],
      ),
    );
  }
}
