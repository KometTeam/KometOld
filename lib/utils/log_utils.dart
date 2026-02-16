import 'package:gwid/consts.dart';

/// Логирует ошибку с контекстом. Используется в catch блоках.
void logError(String context, Object? error, [StackTrace? stackTrace]) {
  // ignore: avoid_print
  print('❌ Ошибка [$context]: $error');
  if (stackTrace != null) {
    // ignore: avoid_print
    print('StackTrace: $stackTrace');
  }
}

/// Безопасно выполняет функцию, логируя ошибки
T? safeExecute<T>(String context, T Function() action) {
  try {
    return action();
  } catch (e, st) {
    logError(context, e, st);
    return null;
  }
}

/// Обрезает длинные payload для логирования
String truncatePayloadForLog(String payload) {
  if (payload.length <= AppLimits.maxLogPayloadLength) {
    return payload;
  }
  return '${payload.substring(0, AppLimits.maxLogPayloadLength)}... (обрезано, длина: ${payload.length})';
}

String truncatePayloadObjectForLog(dynamic payload) {
  final payloadStr = payload.toString();
  return truncatePayloadForLog(payloadStr);
}
