import 'package:flutter/foundation.dart';


class ErrorReporter {
  ErrorReporter._();

  
  static void report(
    Object error,
    StackTrace? stack, {
    String? context,
    bool fatal = false,
  }) {
    try {
      final label = context == null ? 'Error' : 'Error [$context]';
      if (stack != null && kDebugMode) {
        debugPrintStack(stackTrace: stack, label: label);
      }
      _forwardToBackend(error, stack, context: context, fatal: fatal);
    } catch (_) {
      
    }
  }

  
  static void _forwardToBackend(
    Object error,
    StackTrace? stack, {
    String? context,
    bool fatal = false,
  }) {
    
  }
}
