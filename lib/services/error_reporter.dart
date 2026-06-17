import 'package:flutter/foundation.dart';

/// Central place all non-fatal errors and global crashes flow through.
///
/// Today it logs (visible in debug, dropped in release). It is intentionally a
/// thin seam: wire a real backend (Firebase Crashlytics, Sentry, etc.) by
/// implementing [_forwardToBackend] without touching any call site.
///
/// Use [ErrorReporter.report] in `catch` blocks instead of swallowing the
/// error with `catch (_) {}`, so failures are observable in production.
class ErrorReporter {
  ErrorReporter._();

  /// Reports a handled (non-fatal) error. Safe to call from anywhere; never
  /// throws, so it will not mask the original failure or break a `catch`.
  static void report(
    Object error,
    StackTrace? stack, {
    String? context,
    bool fatal = false,
  }) {
    try {
      final label = context == null ? 'Error' : 'Error [$context]';
      debugPrint('$label: $error');
      if (stack != null && kDebugMode) {
        debugPrintStack(stackTrace: stack, label: label);
      }
      _forwardToBackend(error, stack, context: context, fatal: fatal);
    } catch (_) {
      // Reporting must never throw.
    }
  }

  /// Hook for a crash-reporting backend. No-op until one is integrated.
  ///
  /// Example (Crashlytics):
  ///   FirebaseCrashlytics.instance.recordError(error, stack,
  ///       reason: context, fatal: fatal);
  static void _forwardToBackend(
    Object error,
    StackTrace? stack, {
    String? context,
    bool fatal = false,
  }) {
    // Intentionally empty. See class doc.
  }
}
