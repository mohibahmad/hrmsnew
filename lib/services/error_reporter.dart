import 'package:flutter/foundation.dart';

typedef ErrorBackendHandler = void Function(
  Object error,
  StackTrace? stack, {
  String? context,
  bool fatal,
});

class ErrorRecord {
  final Object error;
  final StackTrace? stackTrace;
  final String? context;
  final bool fatal;
  final DateTime timestamp;

  ErrorRecord({
    required this.error,
    this.stackTrace,
    this.context,
    this.fatal = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'error': error.toString(),
        'context': context,
        'fatal': fatal,
        'timestamp': timestamp.toIso8601String(),
        'stackTrace': stackTrace?.toString(),
      };
}

class ErrorReporter {
  ErrorReporter._();

  static final List<ErrorRecord> _recordedErrors = [];
  static ErrorBackendHandler? _backendHandler;

  static List<ErrorRecord> get recordedErrors =>
      List.unmodifiable(_recordedErrors);

  static void registerBackendHandler(ErrorBackendHandler handler) {
    _backendHandler = handler;
  }

  static void report(
    Object error,
    StackTrace? stack, {
    String? context,
    bool fatal = false,
  }) {
    try {
      final record = ErrorRecord(
        error: error,
        stackTrace: stack,
        context: context,
        fatal: fatal,
      );

      _recordedErrors.add(record);
      if (_recordedErrors.length > 100) {
        _recordedErrors.removeAt(0);
      }

      final label = context == null ? 'Error' : 'Error [$context]';
      if (kDebugMode) {
        debugPrint('⚠️ [ErrorReporter] $label: $error');
        if (stack != null) {
          debugPrintStack(stackTrace: stack, label: label);
        }
      } else {
        debugPrint('[PROD-ERROR] [$label] (fatal=$fatal) $error');
      }

      _forwardToBackend(error, stack, context: context, fatal: fatal);
    } catch (e, s) {
      debugPrint('ErrorReporter failure: $e\n$s');
    }
  }

  static void _forwardToBackend(
    Object error,
    StackTrace? stack, {
    String? context,
    bool fatal = false,
  }) {
    try {
      _backendHandler?.call(error, stack, context: context, fatal: fatal);
    } catch (e) {
      debugPrint('Failed to forward error to backend handler: $e');
    }
  }
}
