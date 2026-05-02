// master_password_setup_screen.dart — первая настройка мастер-пароля.
//
// Когда показывается:
//   - При первом запуске после обновления (есть legacy-чаты) →
//     режим «migration».
//   - Когда пользователь явно включает шифрование чатов в настройках
//     приложения → режим «firstTime».
//
// В режиме «migration»:
//   1. Объясняем пользователю что было XOR, теперь будет AES-GCM.
//   2. Пользователь задаёт пароль (с подтверждением).
//   3. После «Сохранить» запускается:
//        - Argon2id (показываем индикатор «Подождите, ~2-3 секунды»).
//        - Пакетная миграция всех старых чатов.
//        - Прогресс-бар «Чат N из M».
//   4. По окончании Navigator.pop(true) — сообщаем родителю что готово.
//
// В режиме «firstTime» прогресс-бар не нужен (нет чатов для миграции).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:gwid/services/crypt/master_key_manager.dart';
import 'package:gwid/services/migration_v2.dart';

enum MasterPasswordSetupMode {
  /// Первая настройка без миграции (новый пользователь или нет старых чатов).
  firstTime,

  /// После обновления — есть legacy XOR-чаты, нужно перенести их.
  migration,
}

class MasterPasswordSetupScreen extends StatefulWidget {
  final MasterPasswordSetupMode mode;

  const MasterPasswordSetupScreen({super.key, required this.mode});

  @override
  State<MasterPasswordSetupScreen> createState() =>
      _MasterPasswordSetupScreenState();
}

class _MasterPasswordSetupScreenState
    extends State<MasterPasswordSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pwCtl = TextEditingController();
  final _pwCtl2 = TextEditingController();
  bool _obscure = true;

  String _argon2Profile = 'balanced';
  bool _busy = false;
  String? _busyText;
  double? _migrationProgress; // 0..1 или null

  @override
  void dispose() {
    _pwCtl.dispose();
    _pwCtl2.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;
    // F-NEW: текст в зависимости от профиля. На "strong" Argon2id
    // занимает 5-10 секунд — без этой подсказки пользователь думает,
    // что приложение зависло.
    final argon2Hint = switch (_argon2Profile) {
      'strong' => 'Создаём ключ из пароля (5-10 сек)…',
      'lite' => 'Создаём ключ из пароля (~1 сек)…',
      _ => 'Создаём ключ из пароля (2-3 сек)…',
    };
    setState(() {
      _busy = true;
      _busyText = argon2Hint;
    });

    final password = _pwCtl.text;

    try {
      if (widget.mode == MasterPasswordSetupMode.migration) {
        final result = await MigrationV2.migrate(
          password,
          argon2Profile: _argon2Profile,
          onProgress: (current, total, _) {
            if (mounted) {
              setState(() {
                _busyText = 'Перешифровываем чаты ($current из $total)…';
                _migrationProgress = total == 0 ? null : current / total;
              });
            }
          },
        );
        if (!mounted) return;
        if (result.hasErrors) {
          await _showResultDialog(
            'Миграция завершилась с ошибками',
            'Успешно: ${result.chatsMigrated}\n'
                'Пропущено: ${result.chatsSkipped}\n'
                'Ошибок: ${result.chatsFailed}\n\n'
                'Чаты с ошибками можно мигрировать позже из настроек.',
          );
        }
      } else {
        await MasterKeyManager.instance.setupMasterPassword(
          password,
          argon2Profile: _argon2Profile,
        );
      }

      if (!mounted) return;
      // F-NEW fix: очищаем пароль из контроллеров после успеха. Дальше
      // диспозятся в dispose(), но между Navigator.pop и dispose может
      // пройти время — на это время пароль остаётся в TextEditingController.
      // Очистка снижает время жизни. Сама строка `password` иммутабельна,
      // но её ссылку мы тоже не держим больше нужного.
      _pwCtl.clear();
      _pwCtl2.clear();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      await _showResultDialog(
        'Ошибка',
        'Не удалось завершить настройку:\n$e',
      );
      setState(() {
        _busy = false;
        _busyText = null;
        _migrationProgress = null;
      });
    }
  }

  Future<void> _showResultDialog(String title, String message) {
    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Пароль обязателен';
    if (v.length < 8) return 'Минимум 8 символов';
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v != _pwCtl.text) return 'Пароли не совпадают';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isMigration = widget.mode == MasterPasswordSetupMode.migration;

    return Scaffold(
      // В режиме migration пользователь не должен иметь возможность пропустить
      // экран — иначе шифрование сломается. Поэтому AppBar без кнопки back.
      appBar: AppBar(
        title: Text(
          isMigration ? 'Обновление шифрования' : 'Настройка шифрования',
          style: GoogleFonts.inter(),
        ),
        automaticallyImplyLeading: !isMigration,
      ),
      body: PopScope(
        // В режиме migration отключаем системный back (Android), пока идёт
        // настройка/миграция. После _busy=false и не-migration — pop разрешён.
        canPop: !isMigration && !_busy,
        child: AbsorbPointer(
          absorbing: _busy,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 56,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isMigration
                          ? 'Шифрование сообщений обновлено'
                          : 'Задайте мастер-пароль',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isMigration
                          ? 'Старое XOR-шифрование заменено на AES-256-GCM '
                              '(военный стандарт). Чтобы переключить ваши '
                              'существующие зашифрованные чаты, задайте '
                              'мастер-пароль приложения. Старые сообщения '
                              'останутся читаемыми.\n\n'
                              'Этот пароль НЕЛЬЗЯ восстановить — без него '
                              'шифрованные сообщения будут потеряны навсегда.'
                          : 'Один пароль приложения защищает ключи всех '
                              'чатов. Без этого пароля шифрованные сообщения '
                              'нельзя прочитать. Сохраните его в надёжном '
                              'месте — восстановить будет невозможно.',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _pwCtl,
                      autofocus: true,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Новый мастер-пароль',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      validator: _validatePassword,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pwCtl2,
                      obscureText: _obscure,
                      decoration: const InputDecoration(
                        labelText: 'Повторите пароль',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validateConfirm,
                    ),
                    const SizedBox(height: 16),
                    _buildArgon2Selector(),
                    const SizedBox(height: 24),
                    if (_busy) ...[
                      if (_migrationProgress != null)
                        LinearProgressIndicator(value: _migrationProgress)
                      else
                        const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        _busyText ?? '…',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 13),
                      ),
                    ] else
                      FilledButton(
                        onPressed: _onSave,
                        style: FilledButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          isMigration
                              ? 'Перешифровать чаты'
                              : 'Сохранить пароль',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArgon2Selector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Сложность ключа (тяжелее = безопаснее, но дольше unlock):',
          style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'lite',
              label: Text('Lite'),
              tooltip: '64 MiB, быстро',
            ),
            ButtonSegment(
              value: 'balanced',
              label: Text('Balanced'),
              tooltip: '128 MiB, рекомендуется',
            ),
            ButtonSegment(
              value: 'strong',
              label: Text('Strong'),
              tooltip: '256 MiB, для топовых телефонов',
            ),
          ],
          selected: {_argon2Profile},
          onSelectionChanged: (s) =>
              setState(() => _argon2Profile = s.first),
        ),
      ],
    );
  }
}
