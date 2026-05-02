// recovery.dart — фасад для UI поверх recovery-методов MasterKeyManager.
//
// Группирует вызовы scanForCorruptedChatKeys / hasPendingPasswordChange /
// recoverWithOldPassword / dropCorruptedChatKeys / dismissPendingPasswordChange
// в удобный для UI интерфейс.

import 'master_key_manager.dart';

/// Сводка состояния шифрования: что в порядке, что битое.
class RecoveryReport {
  /// Список chat_id, чьи обёртки нечитаемы.
  final List<int> brokenChats;

  /// True, если в storage остались pending salt+check от прерванной
  /// changeMasterPassword (старый пароль может помочь).
  final bool hasPendingChange;

  RecoveryReport({
    required this.brokenChats,
    required this.hasPendingChange,
  });

  bool get hasIssues => brokenChats.isNotEmpty || hasPendingChange;
}

class RecoveryService {
  /// Сканирует storage и возвращает отчёт.
  /// Master должен быть unlocked.
  static Future<RecoveryReport> diagnose() async {
    final mgr = MasterKeyManager.instance;
    if (!mgr.isUnlocked) {
      throw MasterLockedException(
        'Сначала разблокируйте мастер-ключ',
      );
    }
    final broken = await mgr.scanForCorruptedChatKeys();
    final pending = await mgr.hasPendingPasswordChange();
    return RecoveryReport(
      brokenChats: broken,
      hasPendingChange: pending,
    );
  }

  /// Восстанавливает чаты со старым паролем.
  /// Возвращает количество восстановленных.
  static Future<int> recoverWithOldPassword({
    required String oldPassword,
    required List<int> brokenChatIds,
  }) {
    return MasterKeyManager.instance.recoverWithOldPassword(
      oldPassword: oldPassword,
      corruptedChatIds: brokenChatIds,
    );
  }

  /// Удаляет битые обёртки (доступ к этим чатам теряется).
  static Future<void> dropBrokenChats(List<int> ids) {
    return MasterKeyManager.instance.dropCorruptedChatKeys(ids);
  }

  /// Отменяет pending password change (без восстановления).
  static Future<void> dismissPendingChange() {
    return MasterKeyManager.instance.dismissPendingPasswordChange();
  }
}
