import 'package:logging/logging.dart';

class MaxCallsLogger {
  static final Logger _logger = Logger('MaxCalls');
  static bool _initialized = false;

  static void init({bool debug = false}) {
    if (_initialized) return;
    
    Logger.root.level = debug ? Level.ALL : Level.WARNING;
    Logger.root.onRecord.listen((record) {
      // ignore: avoid_print
      print('${record.level.name}: ${record.time}: ${record.message}');
      if (record.error != null) {
        // ignore: avoid_print
        print('Error: ${record.error}');
      }
      if (record.stackTrace != null) {
        // ignore: avoid_print
        print('StackTrace: ${record.stackTrace}');
      }
    });
    
    _initialized = true;
  }

  static void debug(String message) {
    _logger.fine(message);
  }

  static void info(String message) {
    _logger.info(message);
  }

  static void warning(String message) {
    _logger.warning(message);
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.severe(message, error, stackTrace);
  }
}
