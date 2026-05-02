/// Базовый класс результата операции (Result Pattern)
/// 
/// Использование:
/// ```dart
/// Future<Result<User>> fetchUser(int id) async {
///   try {
///     final user = await api.getUser(id);
///     return Result.success(user);
///   } catch (e) {
///     return Result.failure(AppError.unknown(e.toString()));
///   }
/// }
/// ```
sealed class Result<T> {
  const Result();

  factory Result.success(T data) = Success<T>;
  factory Result.failure(AppError error) = Failure<T>;

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;

  T? get data => isSuccess ? (this as Success<T>).data : null;
  AppError? get error => isFailure ? (this as Failure<T>).error : null;

  R when<R>({
    required R Function(T data) success,
    required R Function(AppError error) failure,
  }) {
    return switch (this) {
      Success<T>(data: final d) => success(d),
      Failure<T>(error: final e) => failure(e),
    };
  }

  R? whenOrNull<R>({
    R? Function(T data)? success,
    R? Function(AppError error)? failure,
  }) {
    return switch (this) {
      Success<T>(data: final d) => success?.call(d),
      Failure<T>(error: final e) => failure?.call(e),
    };
  }

  T getOrThrow() {
    return switch (this) {
      Success<T>(data: final d) => d,
      Failure<T>(error: final e) => throw e,
    };
  }

  T getOrElse(T Function(AppError error) onFailure) {
    return switch (this) {
      Success<T>(data: final d) => d,
      Failure<T>(error: final e) => onFailure(e),
    };
  }

  T? getOrNull() => data;
}

final class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Success<T> &&
          runtimeType == other.runtimeType &&
          data == other.data;

  @override
  int get hashCode => data.hashCode;
}

final class Failure<T> extends Result<T> {
  final AppError error;
  const Failure(this.error);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Failure<T> &&
          runtimeType == other.runtimeType &&
          error == other.error;

  @override
  int get hashCode => error.hashCode;
}

/// Базовый класс ошибки приложения
sealed class AppError implements Exception {
  final String message;
  final StackTrace? stackTrace;

  const AppError(this.message, {this.stackTrace});

  factory AppError.network({String? message, StackTrace? stackTrace}) =
      NetworkError;
  factory AppError.server({String? message, int? code, StackTrace? stackTrace}) =
      ServerError;
  factory AppError.cache({String? message, StackTrace? stackTrace}) = CacheError;
  factory AppError.validation(String message, {StackTrace? stackTrace}) =
      ValidationError;
  factory AppError.unauthorized({String? message, StackTrace? stackTrace}) =
      UnauthorizedError;
  factory AppError.notFound({String? message, StackTrace? stackTrace}) =
      NotFoundError;
  factory AppError.unknown(String message, {StackTrace? stackTrace}) =
      UnknownError;

  @override
  String toString() => message;
}

final class NetworkError extends AppError {
  NetworkError({String? message, super.stackTrace})
      : super(message ?? 'Ошибка сети');
}

final class ServerError extends AppError {
  final int? code;
  ServerError({String? message, this.code, super.stackTrace})
      : super(message ?? 'Ошибка сервера');
}

final class CacheError extends AppError {
  CacheError({String? message, super.stackTrace})
      : super(message ?? 'Ошибка кэша');
}

final class ValidationError extends AppError {
  ValidationError(super.message, {super.stackTrace});
}

final class UnauthorizedError extends AppError {
  UnauthorizedError({String? message, super.stackTrace})
      : super(message ?? 'Требуется авторизация');
}

final class NotFoundError extends AppError {
  NotFoundError({String? message, super.stackTrace})
      : super(message ?? 'Не найдено');
}

final class UnknownError extends AppError {
  UnknownError(super.message, {super.stackTrace});
}
