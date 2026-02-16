import '../result/result.dart';

/// Расширения для Future
extension FutureResultExtensions<T> on Future<T> {
  /// Преобразовать Future в Result
  Future<Result<T>> toResult() async {
    try {
      final data = await this;
      return Result.success(data);
    } on AppError catch (e) {
      return Result.failure(e);
    } catch (e, stack) {
      return Result.failure(AppError.unknown(e.toString(), stackTrace: stack));
    }
  }

  /// Преобразовать с обработкой ошибок
  Future<Result<R>> mapResult<R>(R Function(T data) mapper) async {
    try {
      final data = await this;
      return Result.success(mapper(data));
    } on AppError catch (e) {
      return Result.failure(e);
    } catch (e, stack) {
      return Result.failure(AppError.unknown(e.toString(), stackTrace: stack));
    }
  }
}

/// Расширения для обработки Result
extension ResultFutureExtensions<T> on Future<Result<T>> {
  /// Выполнить действие при успехе
  Future<Result<T>> onSuccess(void Function(T data) action) async {
    final result = await this;
    if (result.isSuccess) {
      action(result.data as T);
    }
    return result;
  }

  /// Выполнить действие при ошибке
  Future<Result<T>> onFailure(void Function(AppError error) action) async {
    final result = await this;
    if (result.isFailure) {
      action(result.error as AppError);
    }
    return result;
  }
}
