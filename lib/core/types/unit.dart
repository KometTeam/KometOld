/// Unit type для функций, которые не возвращают значения
/// 
/// Использование вместо void для работы с Result:
/// ```dart
/// Future<Result<Unit>> saveData() async {
///   await prefs.setString('key', 'value');
///   return Result.success(unit);
/// }
/// ```
final class Unit {
  const Unit._();
  static const Unit instance = Unit._();
}

const unit = Unit.instance;
