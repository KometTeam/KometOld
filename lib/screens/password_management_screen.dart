import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_service.dart';

/// Экран управления паролем 2FA.
/// Если 2FA уже установлена — показывает меню управления (удалить, изменить пароль, изменить email).
/// Если нет — показывает процесс установки.
class PasswordManagementScreen extends StatefulWidget {
  const PasswordManagementScreen({super.key});

  @override
  State<PasswordManagementScreen> createState() =>
      _PasswordManagementScreenState();
}

enum _Mode {
  loading,
  // Установка новой 2FA
  setupStart,
  setupPassword,
  setupHint,
  setupEmail,
  setupVerifyEmail,
  setupDone,
  // Управление существующей 2FA
  manageMenu,
  manageVerifyPassword,
  // Удаление 2FA
  removeConfirm,
  // Смена пароля
  changePassword,
  changePasswordHint,
  changePasswordDone,
  // Смена email
  changeEmail,
  changeEmailVerify,
  changeEmailDone,
}

class _PasswordManagementScreenState extends State<PasswordManagementScreen> {
  _Mode _mode = _Mode.loading;
  bool _has2fa = false;

  // TrackId для текущей сессии
  String? _trackId;

  // Данные 2FA с сервера
  String? _currentEmail;
  String? _currentHint;

  // Контроллеры ввода
  final _passwordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _hintCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _verifyPasswordCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureNewPassword = true;
  bool _isLoading = false;
  String? _errorText;
  bool _trackIdReceived = false; // чтобы обработать только первый 2fa_setup_started

  // Для подтверждения смены пароля — нужен новый trackId после verify
  String? _verifiedTrackId;
  // Куда идти после verify password
  _Mode? _afterVerifyMode;

  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _loadAndInit();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _passwordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _hintCtrl.dispose();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _verifyPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAndInit() async {
    final prefs = await SharedPreferences.getInstance();
    _has2fa = prefs.getBool('has_2fa_password') ?? false;

    _sub = ApiService.instance.messages.listen(_onMessage);

    if (_has2fa) {
      // Начинаем сессию управления 2FA — получаем trackId
      setState(() => _mode = _Mode.loading);
      _trackIdReceived = false;
      ApiService.instance.start2FAManage();
    } else {
      // Для новой 2FA — сначала показываем стартовый экран, trackId получим по кнопке
      setState(() => _mode = _Mode.setupStart);
    }
  }

  void _onMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    final type = msg['type'] as String?;

    switch (type) {
      // --- Начало сессии (112) ---
      case '2fa_setup_started':
        if (_trackIdReceived) break; // игнорируем повторные вызовы
        _trackIdReceived = true;
        _trackId = msg['trackId'] as String?;
        if (_has2fa) {
          // Загружаем информацию о текущей 2FA
          ApiService.instance.get2FAInfo(_trackId!);
        } else {
          // trackId получен, переходим к вводу пароля
          setState(() {
            _isLoading = false;
            _mode = _Mode.setupPassword;
          });
        }

      // --- Информация о 2FA (104) ---
      case '2fa_info':
        _currentEmail = msg['email'] as String?;
        _currentHint = msg['hint'] as String?;
        setState(() => _mode = _Mode.manageMenu);

      // --- Пароль подтверждён (113 OK) ---
      case '2fa_password_verified':
        // trackId может обновиться
        _verifiedTrackId = msg['trackId'] as String? ?? _trackId;
        setState(() {
          _isLoading = false;
          _errorText = null;
          _mode = _afterVerifyMode ?? _Mode.manageMenu;
        });

      // --- Неверный пароль (113 ERROR) ---
      case '2fa_password_wrong':
        setState(() {
          _isLoading = false;
          _errorText = 'Неверный пароль';
        });

      // --- Пароль установлен (107 OK) ---
      case '2fa_password_set':
        if (_mode == _Mode.changePassword || _mode == _Mode.changePasswordHint) {
          setState(() {
            _isLoading = false;
            _mode = _Mode.changePasswordHint;
          });
        } else {
          setState(() {
            _isLoading = false;
            _mode = _Mode.setupHint;
          });
        }

      // --- Подсказка установлена (108 OK) ---
      case '2fa_hint_set':
        if (_mode == _Mode.changePasswordHint) {
          // После установки подсказки — финальное подтверждение смены пароля
          ApiService.instance.confirm2FAChange(
            _verifiedTrackId ?? _trackId!,
            _newPasswordCtrl.text.trim(),
            _hintCtrl.text.trim(),
          );
        } else {
          setState(() {
            _isLoading = false;
            _mode = _Mode.setupEmail;
          });
        }

      // --- Email установлен / код отправлен (109 OK) ---
      case '2fa_email_set':
        setState(() {
          _isLoading = false;
          _mode = _mode == _Mode.changeEmail
              ? _Mode.changeEmailVerify
              : _Mode.setupVerifyEmail;
        });

      // --- Email подтверждён (110 OK) ---
      case '2fa_email_verified':
        if (_mode == _Mode.changeEmailVerify) {
          // Отправляем финальное подтверждение смены email
          ApiService.instance.confirm2FAEmailChange(_verifiedTrackId ?? _trackId!);
        } else {
          // Установка новой 2FA — финальное подтверждение
          ApiService.instance.confirm2FASetup(
            _trackId!,
            _passwordCtrl.text.trim(),
            _hintCtrl.text.trim(),
          );
        }

      // --- 2FA завершена / обновлена (111 OK) ---
      case '2fa_setup_complete':
        SharedPreferences.getInstance().then((prefs) {
          if (_mode == _Mode.removeConfirm) {
            prefs.setBool('has_2fa_password', false);
          } else {
            prefs.setBool('has_2fa_password', true);
          }
        });
        setState(() {
          _isLoading = false;
          if (_mode == _Mode.removeConfirm) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Двухфакторная аутентификация отключена')),
            );
          } else if (_mode == _Mode.changePasswordHint) {
            _mode = _Mode.changePasswordDone;
          } else if (_mode == _Mode.changeEmailVerify) {
            _mode = _Mode.changeEmailDone;
          } else {
            _mode = _Mode.setupDone;
          }
        });

      // --- Ошибки ---
      case '2fa_error':
        setState(() {
          _isLoading = false;
          final payload = msg['payload'];
          _errorText = payload?['localizedMessage'] as String? ??
              payload?['message'] as String? ??
              'Ошибка';
        });
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _buildScaffold({required String title, required Widget body}) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: body,
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String label, {
    bool obscure = false,
    VoidCallback? toggleObscure,
    TextInputType keyboardType = TextInputType.text,
    String? hint,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        suffixIcon: toggleObscure != null
            ? IconButton(
                icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: toggleObscure,
              )
            : null,
        errorText: _errorText,
      ),
      onChanged: (_) {
        if (_errorText != null) setState(() => _errorText = null);
      },
    );
  }

  Widget _buildPrimaryButton(String label, VoidCallback? onTap) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _isLoading ? null : onTap,
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label),
      ),
    );
  }

  // ── Экраны ────────────────────────────────────────────────────────────────

  Widget _buildLoading() {
    return _buildScaffold(
      title: 'Пароль аккаунта',
      body: const Center(child: CircularProgressIndicator()),
    );
  }

  // ── УСТАНОВКА ─────────────────────────────────────────────────────────────

  Widget _buildSetupStart() {
    return _buildScaffold(
      title: 'Установить пароль',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, size: 64),
          const SizedBox(height: 16),
          const Text(
            'Двухфакторная аутентификация',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Пароль будет запрашиваться при каждом входе в аккаунт дополнительно к SMS-коду.',
            style: TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 32),
          _buildPrimaryButton('Установить пароль', () {
            setState(() {
              _isLoading = true;
              _trackIdReceived = false;
            });
            ApiService.instance.start2FASetup();
          }),
        ],
      ),
    );
  }

  Widget _buildSetupPassword() {
    return _buildScaffold(
      title: 'Придумайте пароль',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Минимум 6 символов. Используйте буквы, цифры и символы.'),
          const SizedBox(height: 24),
          _buildTextField(
            _passwordCtrl,
            'Пароль',
            obscure: _obscurePassword,
            toggleObscure: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
          const SizedBox(height: 24),
          _buildPrimaryButton('Далее', () {
            final pw = _passwordCtrl.text.trim();
            if (pw.length < 6) {
              setState(() => _errorText = 'Минимум 6 символов');
              return;
            }
            setState(() => _isLoading = true);
            ApiService.instance.set2FAPassword(_trackId!, pw);
          }),
        ],
      ),
    );
  }

  Widget _buildSetupHint() {
    return _buildScaffold(
      title: 'Подсказка для пароля',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Необязательно. Подсказка будет отображаться на экране входа.'),
          const SizedBox(height: 24),
          _buildTextField(_hintCtrl, 'Подсказка (необязательно)'),
          const SizedBox(height: 24),
          _buildPrimaryButton('Далее', () {
            final hint = _hintCtrl.text.trim();
            if (hint.isEmpty) {
              // Пропускаем opcode 108 — сервер не принимает пустую подсказку
              setState(() => _mode = _Mode.setupEmail);
              return;
            }
            setState(() => _isLoading = true);
            ApiService.instance.set2FAHint(_trackId!, hint);
          }),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              // Пропускаем шаг подсказки
              setState(() => _mode = _Mode.setupEmail);
            },
            child: const Text('Пропустить'),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupEmail() {
    return _buildScaffold(
      title: 'Email для восстановления',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Введите email для восстановления пароля. На него придёт код подтверждения.',
          ),
          const SizedBox(height: 24),
          _buildTextField(
            _emailCtrl,
            'Email',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 24),
          _buildPrimaryButton('Отправить код', () {
            final email = _emailCtrl.text.trim();
            if (!email.contains('@')) {
              setState(() => _errorText = 'Введите корректный email');
              return;
            }
            setState(() => _isLoading = true);
            ApiService.instance.set2FAEmail(_trackId!, email);
          }),
        ],
      ),
    );
  }

  Widget _buildSetupVerifyEmail() {
    return _buildScaffold(
      title: 'Подтверждение email',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Введите код, отправленный на ${_emailCtrl.text}'),
          const SizedBox(height: 24),
          _buildTextField(
            _codeCtrl,
            'Код подтверждения',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 24),
          _buildPrimaryButton('Подтвердить', () {
            final code = _codeCtrl.text.trim();
            if (code.isEmpty) {
              setState(() => _errorText = 'Введите код');
              return;
            }
            setState(() => _isLoading = true);
            ApiService.instance.verify2FAEmailCode(_trackId!, code);
          }),
        ],
      ),
    );
  }

  Widget _buildSetupDone() {
    return _buildScaffold(
      title: 'Готово',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
          const SizedBox(height: 24),
          const Text(
            'Двухфакторная аутентификация установлена!',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Теперь при входе потребуется SMS-код и пароль.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _buildPrimaryButton('Готово', () => Navigator.of(context).pop()),
        ],
      ),
    );
  }

  // ── УПРАВЛЕНИЕ ────────────────────────────────────────────────────────────

  Widget _buildManageMenu() {
    return _buildScaffold(
      title: 'Пароль аккаунта',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock, size: 64, color: Colors.blue),
          const SizedBox(height: 16),
          const Text(
            'Двухфакторная аутентификация включена',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          if (_currentEmail != null) ...[
            const SizedBox(height: 8),
            Text('Email: $_currentEmail', style: const TextStyle(color: Colors.grey)),
          ],
          if (_currentHint != null && _currentHint!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Подсказка: $_currentHint', style: const TextStyle(color: Colors.grey)),
          ],
          const SizedBox(height: 32),
          _buildMenuTile(
            icon: Icons.password,
            title: 'Изменить пароль',
            subtitle: 'Задать новый пароль для входа',
            onTap: () {
              _afterVerifyMode = _Mode.changePassword;
              setState(() => _mode = _Mode.manageVerifyPassword);
            },
          ),
          const SizedBox(height: 12),
          _buildMenuTile(
            icon: Icons.email_outlined,
            title: 'Изменить email',
            subtitle: _currentEmail != null
                ? 'Текущий: $_currentEmail'
                : 'Задать email для восстановления',
            onTap: () {
              _afterVerifyMode = _Mode.changeEmail;
              setState(() => _mode = _Mode.manageVerifyPassword);
            },
          ),
          const SizedBox(height: 12),
          _buildMenuTile(
            icon: Icons.lock_open,
            title: 'Отключить пароль',
            subtitle: 'Убрать двухфакторную аутентификацию',
            color: Colors.red,
            onTap: () {
              _afterVerifyMode = _Mode.removeConfirm;
              setState(() => _mode = _Mode.manageVerifyPassword);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title, style: color != null ? TextStyle(color: color) : null),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _buildManageVerifyPassword() {
    String subtitle = '';
    if (_afterVerifyMode == _Mode.removeConfirm) {
      subtitle = 'Для отключения двухфакторной аутентификации подтвердите текущий пароль.';
    } else if (_afterVerifyMode == _Mode.changePassword) {
      subtitle = 'Для смены пароля подтвердите текущий пароль.';
    } else {
      subtitle = 'Для изменения email подтвердите текущий пароль.';
    }

    return _buildScaffold(
      title: 'Подтверждение пароля',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle),
          if (_currentHint != null && _currentHint!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Подсказка: $_currentHint',
                style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 24),
          _buildTextField(
            _verifyPasswordCtrl,
            'Текущий пароль',
            obscure: _obscurePassword,
            toggleObscure: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
          const SizedBox(height: 24),
          _buildPrimaryButton('Подтвердить', () {
            final pw = _verifyPasswordCtrl.text.trim();
            if (pw.isEmpty) {
              setState(() => _errorText = 'Введите пароль');
              return;
            }
            setState(() => _isLoading = true);
            ApiService.instance.verify2FAPassword(_trackId!, pw);
          }),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() => _mode = _Mode.manageMenu),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
  }

  Widget _buildChangePassword() {
    return _buildScaffold(
      title: 'Новый пароль',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Введите новый пароль (минимум 6 символов).'),
          const SizedBox(height: 24),
          _buildTextField(
            _newPasswordCtrl,
            'Новый пароль',
            obscure: _obscureNewPassword,
            toggleObscure: () =>
                setState(() => _obscureNewPassword = !_obscureNewPassword),
          ),
          const SizedBox(height: 24),
          _buildPrimaryButton('Далее', () {
            final pw = _newPasswordCtrl.text.trim();
            if (pw.length < 6) {
              setState(() => _errorText = 'Минимум 6 символов');
              return;
            }
            setState(() {
              _isLoading = true;
              _mode = _Mode.changePasswordHint;
            });
            ApiService.instance.change2FAPassword(
                _verifiedTrackId ?? _trackId!, pw, _hintCtrl.text.trim());
          }),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() => _mode = _Mode.manageMenu),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
  }

  Widget _buildChangePasswordHint() {
    return _buildScaffold(
      title: 'Новая подсказка',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Подсказка для нового пароля (необязательно).'),
          const SizedBox(height: 24),
          _buildTextField(_hintCtrl, 'Подсказка'),
          const SizedBox(height: 24),
          _buildPrimaryButton('Сохранить', () {
            setState(() => _isLoading = true);
            final hint = _hintCtrl.text.trim();
            // Если подсказка непустая — сначала устанавливаем её (108), потом финал (111)
            // Если пустая — сразу финальное подтверждение без hint
            if (hint.isNotEmpty) {
              ApiService.instance.set2FAHint(_verifiedTrackId ?? _trackId!, hint);
              // После 2fa_hint_set придёт и мы вызовем confirm2FAChange
            } else {
              ApiService.instance.confirm2FAChange(
                _verifiedTrackId ?? _trackId!,
                _newPasswordCtrl.text.trim(),
                '',
              );
            }
          }),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              setState(() => _isLoading = true);
              ApiService.instance.confirm2FAChange(
                _verifiedTrackId ?? _trackId!,
                _newPasswordCtrl.text.trim(),
                '',
              );
            },
            child: const Text('Без подсказки'),
          ),
        ],
      ),
    );
  }

  Widget _buildChangePasswordDone() {
    return _buildScaffold(
      title: 'Готово',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
          const SizedBox(height: 24),
          const Text(
            'Пароль успешно изменён',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _buildPrimaryButton('Готово', () => Navigator.of(context).pop()),
        ],
      ),
    );
  }

  Widget _buildChangeEmail() {
    return _buildScaffold(
      title: 'Изменить email',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Введите новый email для восстановления пароля.'),
          const SizedBox(height: 24),
          _buildTextField(
            _emailCtrl,
            'Email',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 24),
          _buildPrimaryButton('Отправить код', () {
            final email = _emailCtrl.text.trim();
            if (!email.contains('@')) {
              setState(() => _errorText = 'Введите корректный email');
              return;
            }
            setState(() => _isLoading = true);
            ApiService.instance.change2FAEmail(_verifiedTrackId ?? _trackId!, email);
          }),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() => _mode = _Mode.manageMenu),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
  }

  Widget _buildChangeEmailVerify() {
    return _buildScaffold(
      title: 'Подтверждение email',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Введите код, отправленный на ${_emailCtrl.text}'),
          const SizedBox(height: 24),
          _buildTextField(
            _codeCtrl,
            'Код подтверждения',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 24),
          _buildPrimaryButton('Подтвердить', () {
            final code = _codeCtrl.text.trim();
            if (code.isEmpty) {
              setState(() => _errorText = 'Введите код');
              return;
            }
            setState(() => _isLoading = true);
            ApiService.instance.verify2FAEmailChangeCode(
                _verifiedTrackId ?? _trackId!, code);
          }),
        ],
      ),
    );
  }

  Widget _buildChangeEmailDone() {
    return _buildScaffold(
      title: 'Готово',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
          const SizedBox(height: 24),
          const Text(
            'Email успешно изменён',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _buildPrimaryButton('Готово', () => Navigator.of(context).pop()),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    switch (_mode) {
      case _Mode.loading:
        return _buildLoading();
      case _Mode.setupStart:
        return _buildSetupStart();
      case _Mode.setupPassword:
        return _buildSetupPassword();
      case _Mode.setupHint:
        return _buildSetupHint();
      case _Mode.setupEmail:
        return _buildSetupEmail();
      case _Mode.setupVerifyEmail:
        return _buildSetupVerifyEmail();
      case _Mode.setupDone:
        return _buildSetupDone();
      case _Mode.manageMenu:
        return _buildManageMenu();
      case _Mode.manageVerifyPassword:
        return _buildManageVerifyPassword();
      case _Mode.removeConfirm:
        return _buildManageVerifyPassword();
      case _Mode.changePassword:
        return _buildChangePassword();
      case _Mode.changePasswordHint:
        return _buildChangePasswordHint();
      case _Mode.changePasswordDone:
        return _buildChangePasswordDone();
      case _Mode.changeEmail:
        return _buildChangeEmail();
      case _Mode.changeEmailVerify:
        return _buildChangeEmailVerify();
      case _Mode.changeEmailDone:
        return _buildChangeEmailDone();
    }
  }
}
