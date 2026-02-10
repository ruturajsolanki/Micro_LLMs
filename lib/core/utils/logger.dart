import 'package:logger/logger.dart' as log;

/// Application logger with structured output.
/// 
/// In debug mode, outputs to console with colors.
/// In release mode, outputs minimal logs to avoid leaking sensitive info.
/// 
/// Usage:
/// ```dart
/// AppLogger.d('Debug message');
/// AppLogger.i('Info message');
/// AppLogger.w('Warning message');
/// AppLogger.e('Error message', error: e, stackTrace: stack);
/// ```
class AppLogger {
  static final _logger = log.Logger(
    printer: log.PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      // Only show time in debug
      dateTimeFormat: log.DateTimeFormat.onlyTimeAndSinceStart,
    ),
    filter: _AppLogFilter(),
  );
  
  // Named loggers for different components
  static final Map<String, log.Logger> _namedLoggers = {};
  
  AppLogger._();
  
  /// Get a named logger for a specific component.
  /// This helps with filtering and identifying log sources.
  static log.Logger named(String name) {
    return _namedLoggers.putIfAbsent(
      name,
      () => log.Logger(
        printer: log.PrefixPrinter(
          log.PrettyPrinter(
            methodCount: 1,
            errorMethodCount: 6,
            lineLength: 100,
            colors: true,
            printEmojis: false,
            dateTimeFormat: log.DateTimeFormat.onlyTime,
          ),
        ),
        filter: _AppLogFilter(),
      ),
    );
  }
  
  /// Debug level log.
  static void d(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.d(message, error: error, stackTrace: stackTrace);
  }
  
  /// Info level log.
  static void i(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }
  
  /// Warning level log.
  static void w(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }
  
  /// Error level log.
  static void e(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }
  
  /// Fatal level log - for unrecoverable errors.
  static void f(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.f(message, error: error, stackTrace: stackTrace);
  }
  
  /// Log LLM inference details.
  static void llm(String message, {
    int? tokensGenerated,
    Duration? duration,
    double? tokensPerSecond,
  }) {
    final details = StringBuffer(message);
    if (tokensGenerated != null) details.write(' | tokens: $tokensGenerated');
    if (duration != null) details.write(' | time: ${duration.inMilliseconds}ms');
    if (tokensPerSecond != null) details.write(' | speed: ${tokensPerSecond.toStringAsFixed(1)} t/s');
    named('LLM').i(details.toString());
  }
  
  /// Log memory status.
  static void memory(String operation, {
    int? usedMB,
    int? availableMB,
  }) {
    final details = StringBuffer(operation);
    if (usedMB != null) details.write(' | used: ${usedMB}MB');
    if (availableMB != null) details.write(' | available: ${availableMB}MB');
    named('Memory').d(details.toString());
  }
}

/// Custom log filter that respects build mode.
class _AppLogFilter extends log.LogFilter {
  @override
  bool shouldLog(log.LogEvent event) {
    // In release mode, only log warnings and above
    const isRelease = bool.fromEnvironment('dart.vm.product');
    if (isRelease) {
      return event.level.index >= log.Level.warning.index;
    }
    return true;
  }
}

/// Logger mixin for classes that need logging.
/// 
/// Usage:
/// ```dart
/// class MyService with Loggable {
///   void doSomething() {
///     logger.i('Doing something');
///   }
/// }
/// ```
mixin Loggable {
  log.Logger get logger => AppLogger.named(runtimeType.toString());
}
