/// Input validation for HRMS records.
///
/// These run at the Firestore write boundary (see `FirestoreService`) so that
/// no screen can persist a structurally invalid record, regardless of its own
/// form-level checks. Form widgets may still call the same helpers to surface
/// inline errors before submitting.
library;

import 'package:easy_localization/easy_localization.dart';
import 'date_utils.dart';

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
  static String? requiredField(String? value, {String? label}) {
    if (value == null || value.trim().isEmpty) return 'field_is_required'.tr(namedArgs: {'field': label ?? 'this_field'.tr()});
    return null;
  }

  static String? email(String? value, {bool required = false}) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return required ? 'email_is_required'.tr() : null;
    if (!isValidEmail(trimmed)) return 'enter_valid_email'.tr();
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
      throw ValidationException('worker_name_required'.tr(), field: 'name');
    }
    final emailErr = email(w['email']?.toString());
    if (emailErr != null) {
      throw ValidationException(emailErr, field: 'email');
    }

    final dobStr = _str(w, 'dob');
    if (dobStr.isNotEmpty) {
      final dob = AppDateUtils.parseDateString(dobStr);
      if (dob == null) {
        throw ValidationException('invalid_date_format'.tr(), field: 'dob');
      }
      final cutoff = DateTime.now().subtract(const Duration(days: 365 * 18));
      if (dob.isAfter(cutoff)) {
        throw ValidationException('worker_must_be_18'.tr(), field: 'dob');
      }
    }
  }

  static void validateExpense(Map<String, dynamic> e) {
    if (_str(e, 'name').isEmpty) {
      throw ValidationException('expense_name_required'.tr(), field: 'name');
    }
    if (_str(e, 'category').isEmpty) {
      throw ValidationException(
        'expense_category_required'.tr(),
        field: 'category',
      );
    }
    final amount = parseAmount(e['amount']);
    if (amount == null) {
      throw ValidationException(
        'valid_amount_required'.tr(),
        field: 'amount',
      );
    }
    if (amount <= 0) {
      throw ValidationException(
        'amount_must_be_positive'.tr(),
        field: 'amount',
      );
    }
  }

  static void validateAttendance(Map<String, dynamic> a) {
    if (_str(a, 'name').isEmpty) {
      throw ValidationException('worker_name_required'.tr(), field: 'name');
    }
    if (_str(a, 'status').isEmpty) {
      throw ValidationException('status_required'.tr(), field: 'status');
    }
  }

  static void validatePayroll(Map<String, dynamic> p) {
    if (_str(p, 'name').isEmpty) {
      throw ValidationException('worker_name_required'.tr(), field: 'name');
    }
    if (_str(p, 'status').isEmpty) {
      throw ValidationException('payment_status_required'.tr(), field: 'status');
    }
  }

  static void validateTimeOff(Map<String, dynamic> t) {
    if (_str(t, 'name').isEmpty) {
      throw ValidationException('worker_name_required'.tr(), field: 'name');
    }
    if (_str(t, 'action').isEmpty) {
      throw ValidationException(
        'leave_type_required'.tr(),
        field: 'action',
      );
    }
    if (_str(t, 'startDate').isEmpty) {
      throw ValidationException(
        'start_date_required'.tr(),
        field: 'startDate',
      );
    }
    if (_str(t, 'endDate').isEmpty) {
      throw ValidationException(
        'end_date_required'.tr(),
        field: 'endDate',
      );
    }
  }

  static void validateAsset(Map<String, dynamic> a) {
    if (_str(a, 'name').isEmpty) {
      throw ValidationException('name_required'.tr(), field: 'name');
    }
    if (_str(a, 'type').isEmpty) {
      throw ValidationException('asset_type_required'.tr(), field: 'type');
    }
  }

  static void validateHoliday(Map<String, dynamic> h) {
    if (_str(h, 'name').isEmpty) {
      throw ValidationException('holiday_name_required'.tr(), field: 'name');
    }
  }
}
