/// Input validation for HRMS records.
///
/// These run at the Firestore write boundary (see `FirestoreService`) so that
/// no screen can persist a structurally invalid record, regardless of its own
/// form-level checks. Form widgets may still call the same helpers to surface
/// inline errors before submitting.
library;

/// Thrown when a record fails validation before being written to Firestore.
class ValidationException implements Exception {
  final String message;
  final String? field;

  const ValidationException(this.message, {this.field});

  @override
  String toString() =>
      field == null ? 'ValidationException: $message'
                    : 'ValidationException($field): $message';
}

class Validators {
  Validators._();

  // Reasonable, permissive email shape. Intentionally not RFC-5322 strict —
  // the goal is to catch typos and empty/garbage values, not to reject valid
  // but unusual addresses.
  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static bool isValidEmail(String? value) {
    if (value == null) return false;
    return _email.hasMatch(value.trim());
  }

  /// Returns null when [value] is a non-empty string, otherwise an error
  /// message. Convenient as a `TextFormField.validator`.
  static String? requiredField(String? value, {String label = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    return null;
  }

  static String? email(String? value, {bool required = false}) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return required ? 'Email is required' : null;
    if (!isValidEmail(trimmed)) return 'Enter a valid email address';
    return null;
  }

  /// Parses a currency/amount string (e.g. "1,200.50", "\$ 95,000") to a
  /// double, or null when it can't be parsed.
  static double? parseAmount(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    final cleaned = raw.toString().replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  static String _str(Map<String, dynamic> m, String key) =>
      (m[key] ?? '').toString().trim();

  // --- Record-level validation. Throw ValidationException on first failure. ---

  static void validateWorker(Map<String, dynamic> w) {
    if (_str(w, 'name').isEmpty) {
      throw const ValidationException('Worker name is required', field: 'name');
    }
    final emailErr = email(w['email']?.toString());
    if (emailErr != null) {
      throw ValidationException(emailErr, field: 'email');
    }
  }

  static void validateExpense(Map<String, dynamic> e) {
    if (_str(e, 'name').isEmpty) {
      throw const ValidationException('Expense name is required', field: 'name');
    }
    if (_str(e, 'category').isEmpty) {
      throw const ValidationException(
        'Expense category is required',
        field: 'category',
      );
    }
    final amount = parseAmount(e['amount']);
    if (amount == null) {
      throw const ValidationException(
        'A valid amount is required',
        field: 'amount',
      );
    }
    if (amount <= 0) {
      throw const ValidationException(
        'Amount must be greater than zero',
        field: 'amount',
      );
    }
  }

  static void validateAttendance(Map<String, dynamic> a) {
    if (_str(a, 'name').isEmpty) {
      throw const ValidationException('Worker name is required', field: 'name');
    }
    if (_str(a, 'status').isEmpty) {
      throw const ValidationException('Status is required', field: 'status');
    }
  }

  static void validatePayroll(Map<String, dynamic> p) {
    if (_str(p, 'name').isEmpty) {
      throw const ValidationException('Worker name is required', field: 'name');
    }
    if (_str(p, 'status').isEmpty) {
      throw const ValidationException('Payment status is required', field: 'status');
    }
  }

  static void validateTimeOff(Map<String, dynamic> t) {
    if (_str(t, 'name').isEmpty) {
      throw const ValidationException('Worker name is required', field: 'name');
    }
    if (_str(t, 'action').isEmpty) {
      throw const ValidationException(
        'Leave type is required',
        field: 'action',
      );
    }
    if (_str(t, 'startDate').isEmpty) {
      throw const ValidationException(
        'Start date is required',
        field: 'startDate',
      );
    }
    if (_str(t, 'endDate').isEmpty) {
      throw const ValidationException(
        'End date is required',
        field: 'endDate',
      );
    }
  }

  static void validateAsset(Map<String, dynamic> a) {
    if (_str(a, 'name').isEmpty) {
      throw const ValidationException('Name is required', field: 'name');
    }
    if (_str(a, 'type').isEmpty) {
      throw const ValidationException('Asset type is required', field: 'type');
    }
  }

  static void validateHoliday(Map<String, dynamic> h) {
    if (_str(h, 'name').isEmpty) {
      throw const ValidationException('Holiday name is required', field: 'name');
    }
  }
}
