// key_share_export_screen.dart — экран «Поделиться ключом чата».
//
// Открывается из chat_encryption_settings_screen → кнопка
// «Поделиться ключом». Доступно только если у чата уже есть kk2-ключ.
//
// Шаги:
//   1. Пользователь видит чат-id и поле «Использовать свой пароль»
//      (по умолчанию выкл — будет авто-passphrase).
//   2. Нажимает «Сгенерировать QR».
//   3. Показывается QR-код + passphrase крупным шрифтом.
//   4. «Скопировать строку» / «Поделиться».
//
// Безопасность:
//   - Passphrase передаётся ОТДЕЛЬНЫМ каналом (голос, SMS, мессенджер).
//   - QR через сервер MAX уйдёт зашифрованным сам (если в текущем чате
//     включено шифрование — но здесь и парадокс: если шифрование уже
//     работает, нам не нужно делиться ключом). Поэтому передавать QR
//     лучше: показать с экрана на экран, или загрузить как файл.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:gwid/services/chat_encryption_service.dart';
import 'package:gwid/services/crypt/key_share_codec.dart';
import 'package:gwid/services/crypt/master_key_manager.dart';

class KeyShareExportScreen extends StatefulWidget {
  final int chatId;

  const KeyShareExportScreen({super.key, required this.chatId});

  @override
  State<KeyShareExportScreen> createState() => _KeyShareExportScreenState();
}

class _KeyShareExportScreenState extends State<KeyShareExportScreen> {
  final _customPwCtl = TextEditingController();
  bool _useCustomPw = false;
  bool _busy = false;

  KeyShareExport? _result;

  @override
  void dispose() {
    _customPwCtl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() => _busy = true);

    try {
      final mgr = MasterKeyManager.instance;
      if (!mgr.isUnlocked) {
        throw MasterLockedException();
      }

      // Получаем chat_key из MasterKeyManager.
      final secret = await mgr.getOrCreateChatKey(widget.chatId);
      final keyBytes = secret.exposeCopy();

      try {
        final cfg = await ChatEncryptionService.getConfigForChat(widget.chatId);

        final result = await exportChatKey(
          chatKey: keyBytes,
          meta: KeyShareMeta(
            label: 'Чат #${widget.chatId}',
            senderChatId: widget.chatId,
            obfuscationProfile:
                cfg?.obfuscationProfile ?? 'ru_full',
            createdAt:
                DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
          ),
          userPassphrase: _useCustomPw && _customPwCtl.text.isNotEmpty
              ? _customPwCtl.text
              : null,
        );

        if (!mounted) return;
        setState(() => _result = result);
      } finally {
        // Затираем копию ключа.
        for (var i = 0; i < keyBytes.length; i++) {
          keyBytes[i] = 0;
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyEncoded() async {
    if (_result == null) return;
    await Clipboard.setData(ClipboardData(text: _result!.encoded));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Код скопирован')),
    );
  }

  Future<void> _shareEncoded() async {
    if (_result == null) return;
    await Share.share(_result!.encoded);
  }

  Future<void> _copyPassphrase() async {
    if (_result == null) return;
    await Clipboard.setData(ClipboardData(text: _result!.passphrase));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Пароль скопирован')),
    );
  }

  Future<void> _saveToFile() async {
    if (_result == null) return;
    File? tmpFile;
    try {
      final dir = await getTemporaryDirectory();
      final filename =
          'kometold_chat${widget.chatId}_${DateTime.now().millisecondsSinceEpoch}.key';
      tmpFile = File('${dir.path}/$filename');
      await tmpFile.writeAsString(_result!.encoded);
      if (!mounted) return;
      // F-NEW fix: дожидаемся завершения share, потом сразу удаляем файл.
      // Раньше файл оставался в tmp до очистки ОС — это лишняя поверхность
      // утечки (даже зашифрованный ключ — sensitive metadata: chat_id,
      // timestamp, label).
      try {
        await Share.shareXFiles([XFile(tmpFile.path)]);
      } finally {
        try {
          if (await tmpFile.exists()) {
            await tmpFile.delete();
          }
        } catch (_) {
          // best-effort
        }
      }
    } catch (e) {
      // Если что-то упало до share — тоже чистим.
      if (tmpFile != null) {
        try {
          if (await tmpFile.exists()) await tmpFile.delete();
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка сохранения: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Поделиться ключом', style: GoogleFonts.inter()),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _result == null ? _buildSetupForm() : _buildResultView(),
        ),
      ),
    );
  }

  Widget _buildSetupForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Чат #${widget.chatId}',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: Colors.amber.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.amber.shade700),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber, color: Colors.amber.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Тот, кто получит этот ключ, сможет читать ВСЕ '
                    'зашифрованные сообщения этого чата (текущие и '
                    'будущие). Передавайте его только тому, с кем '
                    'действительно хотите переписываться.',
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Свой пароль'),
          subtitle: Text(
            _useCustomPw
                ? 'Вы введёте пароль и сообщите его получателю'
                : 'Будет сгенерирована короткая фраза автоматически',
            style: GoogleFonts.inter(fontSize: 12),
          ),
          value: _useCustomPw,
          onChanged: _busy ? null : (v) => setState(() => _useCustomPw = v),
        ),
        if (_useCustomPw) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _customPwCtl,
            decoration: const InputDecoration(
              labelText: 'Пароль (минимум 8 символов)',
              border: OutlineInputBorder(),
              helperText: 'Длиннее = безопаснее. Буквы+цифры+знаки.',
            ),
          ),
        ],
        const SizedBox(height: 32),
        if (_busy)
          const LinearProgressIndicator()
        else
          FilledButton.icon(
            onPressed: _generate,
            icon: const Icon(Icons.qr_code),
            label: const Text('Сгенерировать QR-код'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
      ],
    );
  }

  Widget _buildResultView() {
    final r = _result!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Готово',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Получатель сканирует QR через KometOld и вводит пароль:',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        const SizedBox(height: 16),
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: QrImageView(
              data: r.encoded,
              size: 280,
              version: QrVersions.auto,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.password),
                    const SizedBox(width: 8),
                    Text(
                      r.passphraseGenerated
                          ? 'Пароль (передайте отдельно)'
                          : 'Ваш пароль',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SelectableText(
                  r.passphrase,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _copyPassphrase,
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Скопировать пароль'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _copyEncoded,
              icon: const Icon(Icons.copy),
              label: const Text('Копировать код'),
            ),
            OutlinedButton.icon(
              onPressed: _shareEncoded,
              icon: const Icon(Icons.share),
              label: const Text('Поделиться'),
            ),
            OutlinedButton.icon(
              onPressed: _saveToFile,
              icon: const Icon(Icons.save_alt),
              label: const Text('Сохранить файл'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Card(
          color: Colors.blue.withValues(alpha: 0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.blue.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Получатель: открыть KometOld → Настройки чата → '
              'Шифрование → Импортировать ключ → Сканировать QR → '
              'ввести пароль.\n\n'
              'Пароль НЕ ПЕРЕДАВАЙТЕ через тот же канал, что и QR. '
              'Скажите голосом, отправьте SMS, или передайте лично.',
              style: GoogleFonts.inter(fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}
