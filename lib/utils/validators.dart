library;

import 'package:easy_localization/easy_localization.dart';
import 'currency_utils.dart';
import 'date_utils.dart';

class ValidationException implements Exception {
  final String message;
  final String? field;

  const ValidationException(this.message, {this.field});

  @override
  String toString() => field == null
      ? 'ValidationException: $message'
      : 'ValidationException($field): $message';
}

class Validators {
  Validators._();

  static final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static bool isValidEmail(String? value) {
    if (value == null) return false;
    return _email.hasMatch(value.trim());
  }

  static final RegExp _companyId = RegExp(r'^[A-Z0-9-]+$');
  static final RegExp _nationalIdSeparators = RegExp(r'[\s-]');
  static final RegExp _digitsOnly = RegExp(r'^\d+$');

  static bool isValidCompanyId(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return false;
    return _companyId.hasMatch(trimmed);
  }

  static String? companyId(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (!isValidCompanyId(trimmed)) return 'invalid_company_id_format'.tr();
    return null;
  }

  /// A national ID is valid when it contains at least 6 digits after removing
  /// separators like spaces and dashes (e.g. Pakistan CNIC `37405-1234567-1`).
  /// Short or non-numeric values (e.g. `348`) are rejected.
  static bool isValidNationalId(String? value) {
    final cleaned = (value ?? '').replaceAll(_nationalIdSeparators, '');
    if (cleaned.isEmpty || cleaned.length < 6) return false;
    return _digitsOnly.hasMatch(cleaned);
  }

  static String? email(String? value, {bool required = false}) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return required ? 'email_is_required'.tr() : null;
    if (!isValidEmail(trimmed)) return 'enter_valid_email'.tr();
    return null;
  }

  static double? parseAmount(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    final cleaned = raw.toString().replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  static String _str(Map<String, dynamic> m, String key) =>
      (m[key] ?? '').toString().trim();

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

    final gender = _str(w, 'gender').toLowerCase();
    if (gender.isNotEmpty &&
        gender != 'male' &&
        gender != 'female' &&
        gender != 'other' &&
        gender != 'others') {
      throw ValidationException('invalid_gender_value'.tr(), field: 'gender');
    }

    final currency = _str(w, 'currency');
    if (currency.isNotEmpty && !CurrencyUtils.isSupported(currency)) {
      throw ValidationException(
        'invalid_currency_value'.tr(),
        field: 'currency',
      );
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
      throw ValidationException('valid_amount_required'.tr(), field: 'amount');
    }
    if (amount <= 0) {
      throw ValidationException(
        'amount_must_be_positive'.tr(),
        field: 'amount',
      );
    }
  }

  static void validateAttendance(Map<String, dynamic> a) {
    if (_str(a, 'workerId').isEmpty) {
      throw ValidationException('worker_id_required'.tr(), field: 'workerId');
    }
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
      throw ValidationException(
        'payment_status_required'.tr(),
        field: 'status',
      );
    }
  }

  static void validateTimeOff(Map<String, dynamic> t) {
    if (_str(t, 'workerId').isEmpty) {
      throw ValidationException('worker_id_required'.tr(), field: 'workerId');
    }
    if (_str(t, 'name').isEmpty) {
      throw ValidationException('worker_name_required'.tr(), field: 'name');
    }
    if (_str(t, 'action').isEmpty) {
      throw ValidationException('leave_type_required'.tr(), field: 'action');
    }
    if (_str(t, 'startDate').isEmpty) {
      throw ValidationException('start_date_required'.tr(), field: 'startDate');
    }
    if (_str(t, 'endDate').isEmpty) {
      throw ValidationException('end_date_required'.tr(), field: 'endDate');
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
