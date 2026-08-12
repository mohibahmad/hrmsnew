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

  /// Minimum allowed salary amount for a real worker.
  static const double minSalaryAmount = 1000;

  static final RegExp _email = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@"
    r"[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?"
    r"(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$",
  );


  /// Validates that a phone number is not all zeros (e.g., '000000').
  static bool isValidPhone(String? value) {
    if (value == null) return false;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    final digits = trimmed.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return false;
    // Reject if all digits are the same (e.g., '000000', '111111')
    if (digits.split('').every((d) => d == digits[0])) return false;
    return true;
  }

  static bool isValidEmail(String? value) {
    if (value == null) return false;
    return _email.hasMatch(value.trim());
  }

  static const Set<String> placeholderEmailDomains = {'example.com'};

  static bool isPlaceholderEmailDomain(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return false;
    final atIndex = trimmed.lastIndexOf('@');
    if (atIndex < 0 || atIndex == trimmed.length - 1) return false;
    final domain = trimmed.substring(atIndex + 1).toLowerCase();
    return placeholderEmailDomains.contains(domain);
  }

  static bool hasWhitespace(String? value) {
    if (value == null) return false;
    return value.contains(RegExp(r'\s'));
  }

  /// Capitalizes the first letter of each word, lowercasing the rest.
  /// e.g. "Flutter developer" -> "Flutter Developer", "islam" -> "Islam".
  static String titleCase(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return trimmed;
    return trimmed
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map((word) {
          // Preserve fully-uppercase words (acronyms such as QA, UI/UX, HR,
          // PHP) instead of collapsing them to "Qa".
          if (word.length > 1 && word == word.toUpperCase()) {
            return word;
          }
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  /// Capitalizes only the first letter of the whole string.
  /// e.g. "islam" -> "Islam", "christianity" -> "Christianity".
  static String capitalizeFirst(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return trimmed;
    return trimmed[0].toUpperCase() + trimmed.substring(1).toLowerCase();
  }

  static final RegExp _companyId = RegExp(r'^[A-Z0-9-]+$');
  static final RegExp _nationalIdSeparators = RegExp(r'[\s-]');

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

  static bool isValidNationalId(String? value) {
    final cleaned = (value ?? '').replaceAll(_nationalIdSeparators, '');
    if (cleaned.isEmpty || cleaned.length < 6) return false;
    return RegExp(r'^[A-Za-z0-9]+$').hasMatch(cleaned);
  }

  static String? email(String? value, {bool required = false}) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return required ? 'email_is_required'.tr() : null;
    if (!isValidEmail(trimmed)) return 'enter_valid_email'.tr();
    // Reject placeholder / example domains (e.g. x@example.com) too.
    if (isPlaceholderEmailDomain(trimmed)) return 'enter_valid_email'.tr();
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

    final dobValue = w['dob'];
    final dobText = (dobValue?.toString() ?? '').trim();
    if (dobText.isNotEmpty) {
      // Add Worker converts a selected DOB to a Firestore Timestamp before
      // this service-level validation runs. Parse the original value by type
      // instead of converting Timestamp/DateTime values back into strings.
      final dob = AppDateUtils.dateFromValue(dobValue);
      if (dob == null) {
        throw ValidationException(
          '${'date_of_birth'.tr()}: ${'invalid_date_format'.tr()}',
          field: 'dob',
        );
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

    final salary = parseAmount(w['salaryAmount']);
    if (salary == null || !salary.isFinite || salary <= 0) {
      throw ValidationException(
        'please_enter_salary_amount'.tr(),
        field: 'salaryAmount',
      );
    }
    if (salary < minSalaryAmount) {
      throw ValidationException(
        'salary_min_amount_error'.tr(
          namedArgs: {'amount': minSalaryAmount.toStringAsFixed(0)},
        ),
        field: 'salaryAmount',
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
    if (amount > 999999999) {
      throw ValidationException(
        'amount_cannot_exceed_max'.tr(),
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
