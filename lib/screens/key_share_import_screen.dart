// key_share_import_screen.dart — экран импорта ключа чата.
//
// Сценарий:
//   1. Открывается из chat_encryption_settings_screen → «Импортировать ключ».
//   2. Пользователь видит две вкладки: «Сканировать QR» и «Вставить код».
//   3. После получения kshare:v1:... строки → форма ввода passphrase.
//   4. Кнопка «Импортировать». Argon2id запускается → расшифровка blob.
//   5. Ключ импортируется в MasterKeyManager.importChatKey(chatId, key).
//   6. ChatEncryptionConfig обновляется (password = serialized key).
//   7. Возвращаем true в Navigator.pop.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:gwid/services/chat_encryption_service.dart';
import 'package:gwid/services/crypt/key_share_codec.dart';
import 'package:gwid/services/crypt/master_key_manager.dart';

class KeyShareImportScreen extends StatefulWidget {
  final int chatId;

  const KeyShareImportScreen({super.key, required this.chatId});

  @override
  State<KeyShareImportScreen> createState() => _KeyShareImportScreenState();
}

class _KeyShareImportScreenState extends State<KeyShareImportScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  // F-NEW fix: контроллер создаём ОДИН раз, а не в каждом build(). Иначе
  // при каждой перерисовке страницы (например, после setState из onChanged
  // в paste-tab) открывалась новая сессия камеры — ресурс утечка.
  final MobileScannerController _scannerController = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  // F-NEW fix: флаг "уже обработали кадр". MobileScanner.onDetect стреляет
  // каждым кадром пока QR в видоискателе — без флага мы спамили _onCodeAcquired
  // десятки раз и спамили setState (и могли зайти в _onImport дважды).
  bool _scannerHandled = false;

  String? _scannedCode;
  KeyShareMeta? _peekedMeta;

  final _pasteCtl = TextEditingController();
  final _passphraseCtl = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // F-NEW fix: подписываемся на изменения paste-поля, чтобы кнопка
    // "Принять код" реактивно становилась активной/неактивной без
    // ожидания внешнего setState.
    _pasteCtl.addListener(_onPasteChanged);
  }

  void _onPasteChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tab.dispose();
    _pasteCtl.removeListener(_onPasteChanged);
    _pasteCtl.dispose();
    _passphraseCtl.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _onCodeAcquired(String raw) async {
    if (_busy) return;
    if (_scannerHandled) return; // защита от повторного срабатывания
    final code = raw.trim();
    if (!code.startsWith(keyShareSchemePrefix)) {
      setState(() {
        _error = 'Это не код ключа KometOld';
      });
      return;
    }
    try {
      final meta = peekShareMeta(code);
      // Останавливаем сканер сразу — нам уже хватило одного кадра.
      _scannerHandled = true;
      try {
        await _scannerController.stop();
      } catch (_) {
        // Ignore — на некоторых платформах stop может бросить если
        // камера уже остановлена.
      }
      if (!mounted) return;
      setState(() {
        _scannedCode = code;
        _peekedMeta = meta;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = 'Битый код: $e';
      });
    }
  }

  Future<void> _onPaste() async {
    final cb = await Clipboard.getData('text/plain');
    if (cb?.text != null) {
      _pasteCtl.text = cb!.text!;
    }
  }

  Future<void> _onAcceptPasted() async {
    await _onCodeAcquired(_pasteCtl.text);
  }

  Future<void> _onPickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) {
        setState(() => _error = 'Файл недоступен');
        return;
      }
      final content = await File(path).readAsString();
      // В файле может быть префикс/suffix (например, заголовок). Найдём
      // подстроку kshare:v1:<base64url>. Разрешаем `=` для совместимости
      // с base64url, в котором добавлено padding.
      final match = RegExp(r'kshare:v1:[A-Za-z0-9_=-]+').firstMatch(content);
      if (match == null) {
        setState(() => _error = 'В файле не найден ключ KometOld');
        return;
      }
      await _onCodeAcquired(match.group(0)!);
    } catch (e) {
      setState(() => _error = 'Ошибка чтения файла: $e');
    }
  }

  Future<void> _onImport() async {
    final code = _scannedCode;
    if (code == null) return;
    final passphrase = _passphraseCtl.text;
    if (passphrase.isEmpty) {
      setState(() => _error = 'Введите пароль');
      return;
    }

    final mgr = MasterKeyManager.instance;
    if (!mgr.isUnlocked) {
      setState(() => _error = 'Сначала разблокируйте приложение');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final decoded = await importChatKey(
        encoded: code,
        passphrase: passphrase,
      );
      try {
        // Импортируем ключ в MasterKeyManager.
        await mgr.importChatKey(widget.chatId, decoded.chatKey);

        // Обновляем конфиг чата (ссылка на ключ в Secure Storage).
        final serialized =
            ChatEncryptionService.serializeChatKey(widget.chatId);
        final cfg = await ChatEncryptionService.getConfigForChat(widget.chatId);
        await ChatEncryptionService.saveRawConfigForChat(
          widget.chatId,
          ChatEncryptionConfig(
            password: serialized,
            sendEncrypted: true,
            legacyXorPassword: cfg?.legacyXorPassword,
            obfuscationProfile: decoded.meta.obfuscationProfile,
          ),
        );
      } finally {
        // Затираем расшифрованный ключ.
        for (var i = 0; i < decoded.chatKey.length; i++) {
          decoded.chatKey[i] = 0;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ключ импортирован')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Не удалось импортировать. Проверьте пароль.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Импорт ключа', style: GoogleFonts.inter()),
        bottom: _scannedCode == null
            ? TabBar(
                controller: _tab,
                tabs: const [
                  Tab(text: 'QR', icon: Icon(Icons.qr_code_scanner)),
                  Tab(text: 'Текст', icon: Icon(Icons.content_paste)),
                  Tab(text: 'Файл', icon: Icon(Icons.attach_file)),
                ],
              )
            : null,
      ),
      body: _scannedCode == null ? _buildAcquireUi() : _buildPassphraseUi(),
    );
  }

  Widget _buildAcquireUi() {
    return TabBarView(
      controller: _tab,
      children: [
        _buildScannerTab(),
        _buildPasteTab(),
        _buildFileTab(),
      ],
    );
  }

  Widget _buildScannerTab() {
    return Column(
      children: [
        Expanded(
          child: MobileScanner(
            controller: _scannerController,
            onDetect: (capture) {
              if (_scannerHandled) return;
              for (final barcode in capture.barcodes) {
                final raw = barcode.rawValue;
                if (raw != null) {
                  _onCodeAcquired(raw);
                  break;
                }
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Наведите камеру на QR-код от отправителя',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildPasteTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _pasteCtl,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: 'Код kshare:v1:…',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.content_paste),
                onPressed: _onPaste,
                tooltip: 'Вставить из буфера',
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          FilledButton(
            onPressed: _pasteCtl.text.isEmpty ? null : _onAcceptPasted,
            child: const Text('Принять код'),
          ),
        ],
      ),
    );
  }

  Widget _buildFileTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          Icon(
            Icons.file_upload_outlined,
            size: 80,
            color: Colors.grey.shade600,
          ),
          const SizedBox(height: 16),
          Text(
            'Загрузите .key-файл от отправителя',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 14),
          ),
          const SizedBox(height: 24),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          FilledButton.icon(
            onPressed: _onPickFile,
            icon: const Icon(Icons.folder_open),
            label: const Text('Выбрать файл'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPassphraseUi() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.check_circle, size: 56, color: Colors.green),
            const SizedBox(height: 12),
            Text(
              'Код получен',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            if (_peekedMeta != null) _buildMetaCard(),
            const SizedBox(height: 24),
            Text(
              'Введите пароль, который вам сообщил отправитель:',
              style: GoogleFonts.inter(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passphraseCtl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Пароль',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _onImport(),
            ),
            const SizedBox(height: 24),
            if (_busy)
              const LinearProgressIndicator()
            else ...[
              FilledButton(
                onPressed: _onImport,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Импортировать ключ'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  // F-NEW fix: при возврате на экран сканирования
                  // сбрасываем флаг и перезапускаем камеру.
                  _scannerHandled = false;
                  try {
                    await _scannerController.start();
                  } catch (_) {
                    // Ignore — на некоторых платформах start может
                    // бросить если камера ещё не успела остановиться.
                  }
                  if (!mounted) return;
                  setState(() {
                    _scannedCode = null;
                    _peekedMeta = null;
                    _passphraseCtl.clear();
                    _error = null;
                  });
                },
                child: const Text('Назад к сканированию'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetaCard() {
    final m = _peekedMeta!;
    final created = m.createdAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(m.createdAt * 1000)
        : null;
    final ageWarning = created != null &&
        DateTime.now().difference(created).inHours > 24;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.label != null) ...[
              Text(
                m.label!,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (created != null)
              Text(
                'Создан: ${created.toLocal()}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: ageWarning ? Colors.orange : null,
                ),
              ),
            if (ageWarning) ...[
              const SizedBox(height: 4),
              Text(
                '⚠ Код старше 24 часов — убедитесь что он актуален',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.orange,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
