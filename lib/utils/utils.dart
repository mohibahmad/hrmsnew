
export 'app_colors.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'ui_helpers.dart';
import 'helpers.dart';
import '../services/biometric_service.dart';
import '../services/preferences_service.dart';
import '../services/time_off_service.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Future<bool> offerBiometricLogin({
  required BuildContext context,
  required String email,
  required String password,
}) async {
  final available = await BiometricService.isAvailable();
  if (!available) {
    final supported = await BiometricService.isSupported();
    if (supported && context.mounted) {
      FlashySnackBar.show(
        context,
        message: 'biometric_not_enrolled'.tr(),
        isError: true,
      );
    }
    return false;
  }

  final biometricName = await BiometricService.getBiometricName();
  if (!context.mounted) return false;

  final result = await BiometricService.authenticate(
    reason: 'enable_biometric_signup_reason'.tr(
      namedArgs: {
        'biometric': LocalizationHelper.localizeBiometricName(biometricName),
      },
    ),
  );

  if (result == BiometricAuthResult.cancelled) {
    if (context.mounted) _showPasswordHint(context);
    return false;
  }

  if (result != BiometricAuthResult.success) {
    switch (result) {
      case BiometricAuthResult.lockedOut:
        if (context.mounted) {
          FlashySnackBar.show(
            context,
            message: 'biometric_locked_out'.tr(),
            isError: true,
          );
        }
        break;
      case BiometricAuthResult.permanentlyLockedOut:
        if (context.mounted) {
          FlashySnackBar.show(
            context,
            message: 'biometric_permanently_locked_out'.tr(),
            isError: true,
          );
        }
        break;
      case BiometricAuthResult.notAvailable:
        if (context.mounted) {
          FlashySnackBar.show(
            context,
            message: 'biometric_not_enrolled'.tr(),
            isError: true,
          );
        }
        break;
      default:
        if (context.mounted) _showPasswordHint(context);
    }
    return false;
  }

  try {
    await PreferencesService.setBiometricCredentials(
      email: email,
      password: password,
    );
    await PreferencesService.setBiometricEnabled(true);
  } catch (_) {
    await PreferencesService.clearBiometricCredentials();
    if (context.mounted) {
      FlashySnackBar.show(
        context,
        message: 'biometric_credentials_not_found'.tr(),
        isError: true,
      );
    }
    return false;
  }

  if (context.mounted) {
    FlashySnackBar.show(
      context,
      title: 'success'.tr(),
      message: 'biometric_enabled_success'.tr(),
    );
  }
  return true;
}

void _showPasswordHint(BuildContext context) {
  FlashySnackBar.show(
    context,
    message: 'biometric_cancelled_password_hint'.tr(),
  );
}
const List<String> kRequiredFields = [
  'name',
  'phone',
  'email',
  'fatherName',
  'nationalId',
  'religion',
  'dob',
  'gender',
  'address',
  'relationshipStatus',
  'position',
  'type1',
  'type2',
  'experienceLevel',
  'education',
  'salaryAmount',
  'annualLeaves',
  'joiningDate',
  'frontId',
  'backId',
  'cv',
];

const Map<String, String> kFieldKeys = {
  'name': 'field_full_name',
  'phone': 'field_contact_number',
  'email': 'field_email_address',
  'fatherName': 'field_father_name',
  'nationalId': 'field_national_id',
  'religion': 'field_religion',
  'dob': 'field_date_of_birth',
  'gender': 'field_gender',
  'address': 'field_address',
  'relationshipStatus': 'field_relationship_status',
  'position': 'field_job_position',
  'type1': 'field_employee_type',
  'type2': 'field_work_model',
  'experienceLevel': 'field_experience_level',
  'education': 'field_education',
  'currency': 'field_currency',
  'salaryAmount': 'field_salary_amount',
  'annualLeaves': 'field_annual_leaves',
  'sickLeaves': 'field_sick_leaves',
  'casualLeaves': 'field_casual_leaves',
  'medicalLeaves': 'field_medical_leaves',
  'joiningDate': 'field_joining_date',
  'profileImage': 'field_profile_image_url',
  'frontId': 'field_front_id_image_url',
  'backId': 'field_back_id_image_url',
  'cv': 'field_cv_url',
};

Map<String, String> get kFieldLabels =>
    kFieldKeys.map((k, v) => MapEntry(k, v.tr()));

const Map<String, String> kHeaderMap = {
  'full name': 'name',
  'contact number': 'phone',
  'company phone no': 'phone',
  'company phone no.': 'phone',
  'company phone': 'phone',
  'company no': 'phone',
  'email address': 'email',
  'father name/husband name': 'fatherName',
  'father name': 'fatherName',
  'national id': 'nationalId',
  'professed religion': 'religion',
  'date of birth': 'dob',
  'gender': 'gender',
  'address': 'address',
  'relationship status': 'relationshipStatus',
  'job position': 'position',
  'employee type': 'type1',
  'work model': 'type2',
  'experience level': 'experienceLevel',
  'education': 'education',
  'monthly salary amount': 'salaryAmount',
  'salary amount': 'salaryAmount',
  'leave policy': 'leavePolicy',
  'annual leaves': 'annualLeaves',
  'sick leaves': 'sickLeaves',
  'casual leaves': 'casualLeaves',
  'medical leaves': 'medicalLeaves',
  'medical': 'medicalLeaves',
  'joining date': 'joiningDate',
  'profile image url': 'profileImage',
  'profile image': 'profileImage',
  'profile pic': 'profileImage',
  'profile picture': 'profileImage',
  'profile photo': 'profileImage',
  'avatar': 'profileImage',
  'photo': 'profileImage',
  'image url': 'profileImage',
  'front id image url': 'frontId',
  'front id image': 'frontId',
  'front id': 'frontId',
  'front id card': 'frontId',
  'id front': 'frontId',
  'id front image': 'frontId',
  'id front image url': 'frontId',
  'id front url': 'frontId',
  'id card front': 'frontId',
  'id card (front)': 'frontId',
  'id card front image': 'frontId',
  'id card front url': 'frontId',
  'cnic front': 'frontId',
  'cnic front image': 'frontId',
  'cnic front url': 'frontId',
  'front cnic': 'frontId',
  'front side': 'frontId',
  'front side id': 'frontId',
  'front side id card': 'frontId',
  'front id link': 'frontId',
  'id_front': 'frontId',
  'front_id': 'frontId',
  'back id image url': 'backId',
  'back id image': 'backId',
  'back id': 'backId',
  'back id card': 'backId',
  'id back': 'backId',
  'id back image': 'backId',
  'id back image url': 'backId',
  'id back url': 'backId',
  'id card back': 'backId',
  'id card (back)': 'backId',
  'id card back image': 'backId',
  'id card back url': 'backId',
  'cnic back': 'backId',
  'cnic back image': 'backId',
  'cnic back url': 'backId',
  'back cnic': 'backId',
  'back side': 'backId',
  'back side id': 'backId',
  'back side id card': 'backId',
  'back id link': 'backId',
  'id_back': 'backId',
  'back_id': 'backId',
  'cv url': 'cv',
  'cv link': 'cv',
  'cv': 'cv',
  'resume': 'cv',
  'resume url': 'cv',
  'resume link': 'cv',
  'currency': 'currency',
};

bool isAtLeast18(DateTime dob) => Validators.isAtLeast18(dob);

String? normalizeEducation(String input) {
  final normalized = input.trim().toLowerCase();
  const valid = {
    'matric',
    'intermediate',
    'bachelor',
    'bachelors',
    "bachelor's",
    'master',
    'masters',
    "master's",
    'other',
  };
  if (!valid.contains(normalized)) return null;
  return switch (normalized) {
    'bachelors' || "bachelor's" => 'Bachelor',
    'masters' || "master's" => 'Master',
    _ => normalized[0].toUpperCase() + normalized.substring(1),
  };
}

bool isDateField(String fieldKey) =>
    fieldKey == 'dob' || fieldKey == 'joiningDate';

DateTime? parseDate(String dateStr) {
  if (dateStr.trim().isEmpty) return null;
  return AppDateUtils.parseDdMmYyyy(dateStr);
}

String formatDateForField(DateTime date) => AppDateUtils.formatDate(date);

Map<String, String> validateWorkerData(
  Map<String, dynamic> workerData, {
  required Set<String> existingEmails,
  required Set<String> existingNationalIds,
  required Set<String> csvEmails,
  required Set<String> csvNationalIds,
}) {
  final fieldErrors = <String, String>{};
  final requiredMessage = 'validation_required'.tr();

  for (final field in kRequiredFields) {
    final value = workerData[field]?.toString().trim() ?? '';
    if (value.isEmpty) {
      fieldErrors[field] = requiredMessage;
    }
  }

  for (final field in ['name', 'fatherName']) {
    final raw = workerData[field]?.toString() ?? '';
    if (raw.isNotEmpty) {
      workerData[field] = Validators.titleCase(raw);
    }
  }

  final currency = workerData['currency']?.toString().trim() ?? '';
  if (currency.isNotEmpty) {
    if (!CurrencyUtils.isSupported(currency)) {
      fieldErrors['currency'] = 'invalid_currency_value'.tr();
    } else {
      workerData['currency'] = CurrencyUtils.normalize(currency);
    }
  } else {
    workerData.remove('currency');
  }

  final dobStr = workerData['dob']?.toString().trim() ?? '';
  if (dobStr.isNotEmpty) {
    final dob = AppDateUtils.parseDdMmYyyy(dobStr);
    if (dob == null) {
      fieldErrors['dob'] = 'validation_invalid_date'.tr();
    } else if (!isAtLeast18(dob)) {
      fieldErrors['dob'] = 'validation_min_age'.tr();
    }
  }

  final gender = workerData['gender']?.toString().trim() ?? '';
  if (gender.isNotEmpty) {
    final normalizedGender = gender.toLowerCase();
    const validGenders = {'male', 'female', 'other', 'others'};
    if (!validGenders.contains(normalizedGender)) {
      fieldErrors['gender'] = 'validation_invalid_gender'.tr();
    } else {
      workerData['gender'] = normalizedGender == 'male'
          ? 'Male'
          : normalizedGender == 'female'
          ? 'Female'
          : 'Other';
    }
  }

  final experienceLevel =
      workerData['experienceLevel']?.toString().trim() ?? '';
  if (experienceLevel.isNotEmpty) {
    final normalized = experienceLevel.toLowerCase();
    const valid = {'fresher', 'junior', 'mid-level', 'mid level', 'senior'};
    if (!valid.contains(normalized)) {
      fieldErrors['experienceLevel'] = 'validation_invalid_experience_level'
          .tr();
    } else {
      workerData['experienceLevel'] = normalized == 'fresher'
          ? 'Fresher'
          : normalized == 'junior'
          ? 'Junior'
          : normalized == 'mid-level' || normalized == 'mid level'
          ? 'Mid-Level'
          : 'Senior';
    }
  }

  final education = workerData['education']?.toString().trim() ?? '';
  if (education.isNotEmpty) {
    final normalizedEducation = normalizeEducation(education);
    if (normalizedEducation == null) {
      fieldErrors['education'] = 'validation_invalid_education'.tr();
    } else {
      workerData['education'] = normalizedEducation;
    }
  }

  final relationshipStatus =
      workerData['relationshipStatus']?.toString().trim() ?? '';
  if (relationshipStatus.isNotEmpty) {
    final normalized = relationshipStatus.toLowerCase();
    const valid = {'single', 'married'};
    if (!valid.contains(normalized)) {
      fieldErrors['relationshipStatus'] = 'validation_invalid_relationship'
          .tr();
    } else {
      workerData['relationshipStatus'] =
          normalized[0].toUpperCase() + normalized.substring(1);
    }
  }

  final employeeType = workerData['type1']?.toString().trim() ?? '';
  if (employeeType.isNotEmpty) {
    final normalized = employeeType.toLowerCase();
    const valid = {
      'full-time',
      'full time',
      'part-time',
      'part time',
      'contract',
      'freelance',
      'intern',
    };
    if (!valid.contains(normalized)) {
      fieldErrors['type1'] = 'validation_invalid_employee_type'.tr();
    } else if (normalized == 'full-time' || normalized == 'full time') {
      workerData['type1'] = 'Full-Time';
    } else if (normalized == 'part-time' || normalized == 'part time') {
      workerData['type1'] = 'Part-Time';
    } else if (normalized == 'contract') {
      workerData['type1'] = 'Contract';
    } else if (normalized == 'freelance') {
      workerData['type1'] = 'Freelance';
    } else {
      workerData['type1'] = 'Intern';
    }
  }

  final workModel = workerData['type2']?.toString().trim() ?? '';
  if (workModel.isNotEmpty) {
    final normalized = workModel.toLowerCase();
    const valid = {'on-site', 'on site', 'onsite', 'remote', 'hybrid'};
    if (!valid.contains(normalized)) {
      fieldErrors['type2'] = 'validation_invalid_work_model'.tr();
    } else if (normalized == 'remote') {
      workerData['type2'] = 'Remote';
    } else if (normalized == 'hybrid') {
      workerData['type2'] = 'Hybrid';
    } else {
      workerData['type2'] = 'On-Site';
    }
  }

  final position = workerData['position']?.toString().trim() ?? '';
  if (position.isNotEmpty) {
    workerData['position'] = Validators.titleCase(position);
  }

  final religion = workerData['religion']?.toString().trim() ?? '';
  if (religion.isNotEmpty) {
    workerData['religion'] = Validators.capitalizeFirst(religion);
  }

  final leavePolicy = workerData['leavePolicy']?.toString().trim() ?? '';
  if (leavePolicy.isEmpty) {
    workerData['leavePolicy'] = 'Standard';
  }

  final phone = workerData['phone']?.toString().trim() ?? '';
  if (phone.isNotEmpty && !Validators.isValidPhone(phone)) {
    fieldErrors['phone'] = 'validation_invalid_phone'.tr();
  }

  final email = WorkerIdentity.normalizeEmail(workerData['email']);
  if (email.isEmpty) {
    if ((workerData['email']?.toString().trim() ?? '').isNotEmpty) {
      fieldErrors['email'] = requiredMessage;
    }
  } else if (!Validators.isValidEmail(email)) {
    fieldErrors['email'] = 'validation_invalid_email'.tr();
  } else if (Validators.hasWhitespace(email)) {
    fieldErrors['email'] = 'validation_invalid_email'.tr();
  } else if (Validators.isPlaceholderEmailDomain(email)) {
    fieldErrors['email'] = 'validation_invalid_email_domain'.tr();
  } else {
    workerData['email'] = email;
    if (existingEmails.contains(email) || csvEmails.contains(email)) {
      fieldErrors['email'] = 'validation_duplicate_email'.tr();
    }
  }

  final rawNationalId = workerData['nationalId']?.toString().trim() ?? '';
  final nationalId = WorkerIdentity.normalizeNationalId(rawNationalId);
  if (rawNationalId.isNotEmpty &&
      !Validators.isValidNationalId(rawNationalId)) {
    fieldErrors['nationalId'] = 'validation_invalid_national_id'.tr();
  } else if (nationalId.isNotEmpty &&
      (existingNationalIds.contains(nationalId) ||
          csvNationalIds.contains(nationalId))) {
    fieldErrors['nationalId'] = 'validation_duplicate_national_id'.tr();
  }

  final salaryText = workerData['salaryAmount']?.toString().trim() ?? '';
  if (salaryText.isNotEmpty) {
    final amount = Validators.parseAmount(salaryText);
    if (amount == null) {
      fieldErrors['salaryAmount'] = 'valid_amount_required'.tr();
    } else if (amount <= 0) {
      fieldErrors['salaryAmount'] = 'amount_must_be_positive'.tr();
    }
  }

  final annualLeavesText = workerData['annualLeaves']?.toString().trim() ?? '';
  if (annualLeavesText.isNotEmpty) {
    final annualLeaves = int.tryParse(annualLeavesText);
    if (annualLeaves == null || annualLeaves < 0 || annualLeaves > 366) {
      fieldErrors['annualLeaves'] = 'invalid_number'.tr();
      workerData['annualLeaves'] = 0;
      workerData['availableAnnualLeaves'] = 0;
    } else {
      workerData['annualLeaves'] = annualLeaves;
      workerData['availableAnnualLeaves'] = annualLeaves;
    }
  } else {
    workerData['annualLeaves'] = 0;
    workerData['availableAnnualLeaves'] = 0;
  }
  workerData['leavesUsed'] = 0;

  for (final key in ['sickLeaves', 'casualLeaves', 'medicalLeaves']) {
    final text = workerData[key]?.toString().trim() ?? '';
    if (text.isEmpty) {
      workerData[key] = 0;
      workerData['available${key[0].toUpperCase()}${key.substring(1)}'] = 0;
      continue;
    }
    final days = int.tryParse(text);
    if (days == null || days < 0 || days > 366) {
      fieldErrors[key] = 'invalid_number'.tr();
      workerData[key] = 0;
      workerData['available${key[0].toUpperCase()}${key.substring(1)}'] = 0;
    } else {
      workerData[key] = days;
      workerData['available${key[0].toUpperCase()}${key.substring(1)}'] = days;
    }
  }
  workerData.addAll(TimeOffService.canonicalWorkerLeaveFields(workerData));

  final joiningDateText = workerData['joiningDate']?.toString().trim() ?? '';
  if (joiningDateText.isNotEmpty) {
    final joiningDate = AppDateUtils.parseDdMmYyyy(joiningDateText);
    if (joiningDate == null) {
      fieldErrors['joiningDate'] = 'validation_invalid_date'.tr();
    } else {
      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);
      final joiningOnly = DateTime(
        joiningDate.year,
        joiningDate.month,
        joiningDate.day,
      );
      if (joiningOnly.isAfter(todayOnly)) {
        fieldErrors['joiningDate'] = 'joining_date_cannot_be_future'.tr();
      }
    }
  }

  return fieldErrors;
}

({int missing, int invalidDob, int invalidGender, int duplicate})
validationCounts(List<Map<String, dynamic>> workers) {
  final requiredMessage = 'validation_required'.tr();
  final duplicateEmailMessage = 'validation_duplicate_email'.tr();
  final duplicateNationalIdMessage = 'validation_duplicate_national_id'.tr();

  int missing = 0;
  int invalidDob = 0;
  int invalidGender = 0;
  int duplicate = 0;

  for (final worker in workers) {
    final errors = worker['_fieldErrors'];
    if (errors is! Map<String, String>) continue;
    if (errors.values.contains(requiredMessage)) {
      missing++;
    }
    if (errors.containsKey('dob') && errors['dob'] != requiredMessage) {
      invalidDob++;
    }
    if (errors.containsKey('gender') && errors['gender'] != requiredMessage) {
      invalidGender++;
    }
    if (errors['email'] == duplicateEmailMessage ||
        errors['nationalId'] == duplicateNationalIdMessage) {
      duplicate++;
    }
  }

  return (
    missing: missing,
    invalidDob: invalidDob,
    invalidGender: invalidGender,
    duplicate: duplicate,
  );
}

Map<String, String> fieldErrors(Map<String, dynamic> worker) {
  final errors = worker['_fieldErrors'];
  if (errors is Map<String, String>) return errors;
  return const {};
}

bool hasFieldError(Map<String, dynamic> worker, String field) {
  final errors = worker['_fieldErrors'];
  return errors is Map && errors.containsKey(field);
}

bool hasWorkerErrors(Map<String, dynamic> worker) {
  final errors = worker['_fieldErrors'];
  return errors is Map && errors.isNotEmpty;
}

Set<String> errorFieldNames(List<Map<String, dynamic>> validWorkers) {
  final fields = <String>{};
  for (final worker in validWorkers) {
    final errors = worker['_fieldErrors'];
    if (errors is Map) {
      fields.addAll(errors.keys.cast<String>());
    }
  }
  return fields;
}
class ChartData {
  final List<String> labels;
  final List<double> values;

  final bool isAdaptive;

  final DateTime? rangeStart;
  final DateTime? rangeEnd;

  ChartData(
    this.labels,
    this.values, {
    this.isAdaptive = false,
    this.rangeStart,
    this.rangeEnd,
  });
}

String normalizedAttendanceStatus(Map<String, dynamic> record) {
  final status = (record['status'] ?? '').toString().trim().toLowerCase();
  return switch (status) {
    'present' || 'p' => 'present',
    'absent' || 'a' => 'absent',
    'leave' || 'l' || 'approved' => 'leave',
    _ => status,
  };
}

List<Map<String, dynamic>> attendanceRecordsForStatus(
  List<Map<String, dynamic>> records,
  String status,
) {
  final normalizedStatus = status.trim().toLowerCase();
  return records
      .where((record) => normalizedAttendanceStatus(record) == normalizedStatus)
      .toList();
}

DateTime? _dashboardAttendanceDate(Map<String, dynamic> record) {
  return AppDateUtils.dateFromValue(record['attendanceDate'] ?? record['date']);
}

List<Map<String, dynamic>> attendanceRecordsForPeriod(
  List<Map<String, dynamic>> records,
  String period, {
  DateTime? now,
}) {
  final referenceDate = now ?? DateTime.now();
  final start = AppDateUtils.periodStart(period, referenceDate);
  final end = AppDateUtils.periodEnd(period, referenceDate);

  return records.where((record) {
    final status = normalizedAttendanceStatus(record);
    if (status != 'present' && status != 'absent') return false;

    final date = _dashboardAttendanceDate(record);
    if (date == null) return false;
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }).toList();
}

DateTime? _attendanceRevisionDate(Map<String, dynamic> record) {
  return AppDateUtils.dateFromValue(record['updatedAt']) ??
      AppDateUtils.dateFromValue(record['createdAt']);
}

bool _isNewerAttendanceRecord(
  Map<String, dynamic> candidate,
  Map<String, dynamic> existing,
) {
  final candidateDate = _dashboardAttendanceDate(candidate);
  final existingDate = _dashboardAttendanceDate(existing);

  if (candidateDate != null && existingDate != null) {
    if (candidateDate.isAfter(existingDate)) return true;
    if (candidateDate.isBefore(existingDate)) return false;
  } else if (candidateDate != null) {
    return true;
  } else if (existingDate != null) {
    return false;
  }

  final candidateRevision = _attendanceRevisionDate(candidate);
  final existingRevision = _attendanceRevisionDate(existing);
  if (candidateRevision != null && existingRevision != null) {
    return candidateRevision.isAfter(existingRevision);
  }
  return candidateRevision != null && existingRevision == null;
}

List<Map<String, dynamic>> latestAttendanceRecordPerWorker(
  List<Map<String, dynamic>> records, {
  String? period,
  String? Function(Map<String, dynamic> record)? workerIdResolver,
}) {
  final latestByWorker = <String, Map<String, dynamic>>{};
  for (final record in records) {
    final workerId = (record['workerId'] ?? '').toString().trim();
    final email = (record['email'] ?? '').toString().trim().toLowerCase();
    final name = (record['name'] ?? record['workerName'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final recordId = (record['id'] ?? '').toString().trim();

    String? workerKey;
    if (workerIdResolver != null) {
      final resolvedId = workerIdResolver(record);
      if (resolvedId == null || resolvedId.isEmpty) continue;
      workerKey = 'id:$resolvedId';
    } else {
      workerKey = workerId.isNotEmpty
          ? 'id:$workerId'
          : email.isNotEmpty
          ? 'email:$email'
          : name.isNotEmpty
          ? 'name:$name'
          : 'record:$recordId';
    }

    final bucketKey = period == null ? '' : _attendanceBucketKey(record);
    final groupedKey = bucketKey == null ? workerKey : '$workerKey|$bucketKey';

    final existing = latestByWorker[groupedKey];
    if (existing == null) {
      latestByWorker[groupedKey] = record;
      continue;
    }

    if (_isNewerAttendanceRecord(record, existing)) {
      latestByWorker[groupedKey] = record;
    }
  }

  return latestByWorker.values.toList();
}

String? _attendanceBucketKey(Map<String, dynamic> record) {
  final date = _dashboardAttendanceDate(record);
  if (date == null) return null;

  return '${date.year}-${date.month}-${date.day}';
}

class NiceChartRange {
  final double maxY;
  final double interval;
  NiceChartRange(this.maxY, this.interval);
}

NiceChartRange getNiceRange(double rawMax) {
  if (rawMax <= 0) {
    return NiceChartRange(5, 1);
  }
  if (rawMax <= 5) {
    return NiceChartRange(5, 1);
  } else if (rawMax <= 7) {
    return NiceChartRange(7, 1);
  } else if (rawMax <= 10) {
    return NiceChartRange(10, 2);
  } else if (rawMax <= 15) {
    return NiceChartRange(15, 3);
  } else if (rawMax <= 20) {
    return NiceChartRange(20, 4);
  } else if (rawMax <= 30) {
    return NiceChartRange(30, 5);
  } else if (rawMax <= 40) {
    return NiceChartRange(40, 8);
  } else if (rawMax <= 50) {
    return NiceChartRange(50, 10);
  } else if (rawMax <= 75) {
    return NiceChartRange(75, 15);
  } else if (rawMax <= 100) {
    return NiceChartRange(100, 20);
  } else if (rawMax <= 150) {
    return NiceChartRange(150, 30);
  } else if (rawMax <= 200) {
    return NiceChartRange(200, 40);
  } else if (rawMax <= 250) {
    return NiceChartRange(250, 50);
  } else if (rawMax <= 300) {
    return NiceChartRange(300, 50);
  } else if (rawMax <= 400) {
    return NiceChartRange(400, 100);
  } else if (rawMax <= 500) {
    return NiceChartRange(500, 100);
  } else if (rawMax <= 600) {
    return NiceChartRange(600, 100);
  } else if (rawMax <= 800) {
    return NiceChartRange(800, 200);
  } else if (rawMax <= 1000) {
    return NiceChartRange(1000, 200);
  } else if (rawMax <= 1500) {
    return NiceChartRange(1500, 300);
  } else if (rawMax <= 2000) {
    return NiceChartRange(2000, 400);
  } else if (rawMax <= 2500) {
    return NiceChartRange(2500, 500);
  } else if (rawMax <= 3000) {
    return NiceChartRange(3000, 500);
  } else if (rawMax <= 4000) {
    return NiceChartRange(4000, 1000);
  } else if (rawMax <= 5000) {
    return NiceChartRange(5000, 1000);
  } else {
    double roughStep = rawMax / 5.0;
    double log10Val = (roughStep.truncate().toString().length - 1).toDouble();
    double power = 1.0;
    for (int i = 0; i < log10Val; i++) {
      power *= 10;
    }
    double normalized = roughStep / power;
    double step;
    if (normalized < 1.5) {
      step = 1.0 * power;
    } else if (normalized < 3.5) {
      step = 2.0 * power;
    } else if (normalized < 7.5) {
      step = 5.0 * power;
    } else {
      step = 10.0 * power;
    }
    double maxY = ((rawMax / step).ceil() * step);
    return NiceChartRange(maxY, step);
  }
}

ChartData getChartData(
  String period,
  List<Map<String, dynamic>> docs,
  String locale,
) {
  final now = DateTime.now();
  final normalizedPeriod = switch (period.trim()) {
    'Weekly' || 'This Week' => 'Week',
    'Monthly' || 'This Month' => 'Month',
    '6 Months' || '6 Monthly' || 'Last 6 Months' => '6 Month',
    'This Year' => 'Yearly',
    final value => value,
  };

  if (docs.isEmpty) {
    switch (normalizedPeriod) {
      case 'Today':
        final labels = <String>[];
        for (int i = 6; i >= 0; i--) {
          final date = now.subtract(Duration(days: i));
          labels.add(DateFormat('E', locale).format(date).toUpperCase());
        }
        return ChartData(labels, List.filled(7, 0.0));

      case 'Week':
        final labels = <String>[];
        final startOfWeek = AppDateUtils.periodStart('Week', now);
        for (int i = 0; i < 7; i++) {
          final date = startOfWeek.add(Duration(days: i));
          labels.add(DateFormat('E', locale).format(date).toUpperCase());
        }
        return ChartData(labels, List.filled(7, 0.0));

      case 'Month':
        return ChartData([
          'week_label_1'.tr(),
          'week_label_2'.tr(),
          'week_label_3'.tr(),
          'week_label_4'.tr(),
        ], List.filled(4, 0.0));

      case '6 Month':
        final labels = <String>[];
        for (int i = 5; i >= 0; i--) {
          final date = DateTime(now.year, now.month - i, 1);
          labels.add(DateFormat('MMM', locale).format(date).toUpperCase());
        }
        return ChartData(labels, List.filled(6, 0.0));

      case 'Yearly':
      default:
        final labels = <String>[];
        for (int i = 0; i < 12; i++) {
          final date = DateTime(now.year, i + 1, 1);
          labels.add(DateFormat('MMM', locale).format(date).toUpperCase());
        }
        return ChartData(labels, List.filled(12, 0.0));
    }
  }

  final parsedRecords = <DateTime>[];
  for (final doc in docs) {
    final dt = _dashboardAttendanceDate(doc);
    if (dt != null) {
      parsedRecords.add(dt);
    }
  }

  if (normalizedPeriod == 'All Time' && parsedRecords.isNotEmpty) {
    return _buildAllTimeMonthlyChartData(parsedRecords, locale);
  }

  final start = AppDateUtils.periodStart(normalizedPeriod, now);
  final end = AppDateUtils.periodEnd(normalizedPeriod, now);

  switch (normalizedPeriod) {
    case 'Today':
      final labels = <String>[];
      final values = List.filled(7, 0.0);
      for (int i = 6; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        labels.add(DateFormat('E', locale).format(date).toUpperCase());
      }
      for (final dt in parsedRecords) {
        if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
          values[6] += 1.0;
        }
      }
      return ChartData(labels, values);

    case 'Week':
      final labels = <String>[];
      final values = List.filled(7, 0.0);

      for (int i = 0; i < 7; i++) {
        final date = start.add(Duration(days: i));
        labels.add(DateFormat('E', locale).format(date).toUpperCase());
      }

      for (final dt in parsedRecords) {
        final difference = dt.difference(start).inDays;
        if (difference >= 0 && difference < 7) {
          values[difference] += 1.0;
        }
      }
      return ChartData(labels, values);

    case 'Month':
      final labels = [
        'week_label_1'.tr(),
        'week_label_2'.tr(),
        'week_label_3'.tr(),
        'week_label_4'.tr(),
      ];
      final values = List.filled(4, 0.0);
      final totalDays = end.difference(start).inDays + 1;

      for (final dt in parsedRecords) {
        final difference = dt.difference(start).inDays;
        if (difference >= 0 && difference < totalDays) {
          final weekIdx = difference * 4 ~/ totalDays;
          if (weekIdx >= 0 && weekIdx < 4) {
            values[weekIdx] += 1.0;
          }
        }
      }
      return ChartData(labels, values);

    case '6 Month':
      final labels = <String>[];
      final values = List.filled(6, 0.0);

      for (int i = 5; i >= 0; i--) {
        final date = DateTime(now.year, now.month - i, 1);
        labels.add(DateFormat('MMM', locale).format(date).toUpperCase());
      }

      for (final dt in parsedRecords) {
        for (int i = 0; i < 6; i++) {
          final targetDate = DateTime(now.year, now.month - (5 - i), 1);
          if (dt.year == targetDate.year && dt.month == targetDate.month) {
            values[i] += 1.0;
            break;
          }
        }
      }
      return ChartData(labels, values);

    case 'Yearly':
    default:
      final labels = <String>[];
      final values = List.filled(12, 0.0);

      for (int i = 0; i < 12; i++) {
        final date = DateTime(now.year, i + 1, 1);
        labels.add(DateFormat('MMM', locale).format(date).toUpperCase());
      }

      for (final dt in parsedRecords) {
        if (dt.year == now.year && dt.month <= 12) {
          values[dt.month - 1] += 1.0;
        }
      }
      return ChartData(labels, values);
  }
}

ChartData _buildAllTimeMonthlyChartData(
  List<DateTime> parsedRecords,
  String locale,
) {
  final sorted = [...parsedRecords]..sort();
  final totalsByMonth = <int, double>{};
  for (final date in sorted) {
    final monthKey = date.year * 12 + date.month - 1;
    totalsByMonth[monthKey] = (totalsByMonth[monthKey] ?? 0) + 1;
  }

  final monthKeys = totalsByMonth.keys.toList()..sort();
  final labels = <String>[];
  final values = <double>[];
  for (final monthKey in monthKeys) {
    final year = monthKey ~/ 12;
    final month = monthKey % 12 + 1;
    labels.add(
      DateFormat(
        'MMM yy',
        locale,
      ).format(DateTime(year, month, 1)).toUpperCase(),
    );
    values.add(totalsByMonth[monthKey]!);
  }

  return ChartData(
    labels,
    values,
    isAdaptive: true,
    rangeStart: DateTime(
      sorted.first.year,
      sorted.first.month,
      sorted.first.day,
    ),
    rangeEnd: DateTime(sorted.last.year, sorted.last.month, sorted.last.day),
  );
}
class CompanyProfileHelper {
  static String companyNameOrFallback(String? value) {
    final trimmed = (value ?? '').trim();
    return trimmed.isEmpty ? 'HRMS' : trimmed;
  }

  static Future<Map<String, dynamic>> getCompanyProfileWithFirestore(
    FirestoreService? firestore,
  ) async {
    final isGuest = PreferencesService.cachedIsGuest;
    Map<String, dynamic>? profile;
    if (!isGuest && firestore != null) {
      try {
        profile = await firestore.getUserProfile();
      } catch (_) {
        profile = null;
      }
    }

    Map<String, String>? guestProfile;
    if (isGuest) {
      try {
        guestProfile = await PreferencesService.getGuestProfileData();
      } catch (_) {
        guestProfile = null;
      }
    }

    final companyName =
        (profile?['businessName'] ??
                profile?['companyName'] ??
                guestProfile?['businessName'] ??
                guestProfile?['companyName'] ??
                '')
            .toString()
            .trim();

    final companyId =
        (profile?['companyId'] ??
                profile?['businessId'] ??
                guestProfile?['companyId'] ??
                guestProfile?['businessId'] ??
                '')
            .toString()
            .trim();

    String profilePicUrl = '';

    if (profile != null) {
      profilePicUrl = (profile['profilePic'] ?? '').toString().trim();
    }

    if (profilePicUrl.isEmpty && guestProfile != null) {
      profilePicUrl =
          (guestProfile['profilePic'] ??
                  guestProfile['profilePicUrl'] ??
                  guestProfile['photoUrl'] ??
                  guestProfile['companyLogoUrl'] ??
                  '')
              .toString()
              .trim();
    }

    if (isGuest && profilePicUrl.isEmpty) {
      try {
        profilePicUrl = (await PreferencesService.getProfilePicUrl() ?? '')
            .trim();
      } catch (_) {}
    }

    if (isGuest) {
      final notifierPic = AuthService.profilePicNotifier.value ?? '';
      if (notifierPic.isNotEmpty) {
        profilePicUrl = notifierPic;
      }
    }

    String companyStampUrl = '';

    if (profile != null) {
      companyStampUrl = (profile['companyStampUrl'] ?? '').toString().trim();
    }

    if (companyStampUrl.isEmpty && guestProfile != null) {
      companyStampUrl =
          (guestProfile['companyStampUrl'] ??
                  guestProfile['stampUrl'] ??
                  guestProfile['companyStamp'] ??
                  guestProfile['companySignature'] ??
                  guestProfile['signatureUrl'] ??
                  guestProfile['signature'] ??
                  '')
              .toString()
              .trim();
    }

    if (isGuest && companyStampUrl.isEmpty) {
      try {
        companyStampUrl = (await PreferencesService.getCompanyStampUrl() ?? '')
            .trim();
      } catch (_) {}
    }

    if (isGuest && companyStampUrl.isEmpty) {
      final notifierStamp = AuthService.companyStampNotifier.value ?? '';
      if (notifierStamp.isNotEmpty) {
        companyStampUrl = notifierStamp;
      }
    }

    final address = (profile?['address'] ?? guestProfile?['address'] ?? '')
        .toString()
        .trim();

    final email = (profile?['email'] ?? guestProfile?['email'] ?? '')
        .toString()
        .trim();

    final phone =
        (profile?['contact1'] ??
                profile?['phone'] ??
                guestProfile?['contact1'] ??
                guestProfile?['phone'] ??
                '')
            .toString()
            .trim();

    return {
      'companyName': companyName,
      'companyId': companyId,
      'profilePicUrl': profilePicUrl,
      'companyStampUrl': companyStampUrl,
      'address': address,
      'email': email,
      'phone': phone,
    };
  }
}
String formatMoney(double amount, String symbol) {
  return '$symbol${amount.toStringAsFixed(0)}';
}

class CurrencyUtils {
  CurrencyUtils._();

  static String amountText(dynamic value) {
    final text = (value ?? '').toString().trim();
    if (RegExp(r'^-?\d+\.0+$').hasMatch(text)) {
      return text.replaceAll(RegExp(r'\.0+$'), '');
    }
    return text;
  }

  static String formatWithCommas(dynamic value) {
    if (value == null) return '';
    final clean = amountText(value).replaceAll(',', '');
    if (clean.isEmpty) return '';
    final parts = clean.split('.');
    final intPart = parts[0];
    final parsed = int.tryParse(intPart);
    if (parsed == null) return clean;
    final formattedInt = NumberFormat('#,##0', 'en_US').format(parsed);
    return parts.length > 1 ? '$formattedInt.${parts[1]}' : formattedInt;
  }

  static const String defaultCode = 'USD';

  static String get companyCurrency =>
      PreferencesService.cachedCompanyCurrency ?? defaultCode;

  static const List<String> commonCodes = [
    'USD',
    'EUR',
    'GBP',
    'PKR',
    'INR',
    'AED',
  ];

  static const List<String> supportedCodes = [
    'USD',
    'EUR',
    'GBP',
    'JPY',
    'INR',
    'PKR',
    'RUB',
    'BRL',
    'SAR',
    'AED',
    'CAD',
    'AUD',
    'QAR',
    'KWD',
    'OMR',
  ];

  static const Map<String, List<String>> localeCurrencies = {
    'en': [
      'USD',
      'EUR',
      'GBP',
      'JPY',
      'INR',
      'PKR',
      'CAD',
      'AUD',
      'SAR',
      'AED',
      'QAR',
      'KWD',
      'OMR',
      'RUB',
      'BRL',
    ],
    'es': [
      'EUR',
      'USD',
      'GBP',
      'JPY',
      'INR',
      'PKR',
      'CAD',
      'AUD',
      'SAR',
      'AED',
      'QAR',
      'KWD',
      'OMR',
      'RUB',
      'BRL',
    ],
    'fr': [
      'EUR',
      'USD',
      'GBP',
      'JPY',
      'INR',
      'PKR',
      'CAD',
      'AUD',
      'SAR',
      'AED',
      'QAR',
      'KWD',
      'OMR',
      'RUB',
      'BRL',
    ],
    'pt': [
      'BRL',
      'EUR',
      'USD',
      'GBP',
      'JPY',
      'INR',
      'PKR',
      'CAD',
      'AUD',
      'SAR',
      'AED',
      'QAR',
      'KWD',
      'OMR',
      'RUB',
    ],
    'ru': [
      'RUB',
      'EUR',
      'USD',
      'GBP',
      'JPY',
      'INR',
      'PKR',
      'CAD',
      'AUD',
      'SAR',
      'AED',
      'QAR',
      'KWD',
      'OMR',
      'BRL',
    ],
  };

  static const Map<String, String> _symbols = {
    'USD': r'$',
    'EUR': '€',
    'GBP': '£',
    'JPY': '¥',
    'INR': '₹',
    'PKR': 'PKR',
    'RUB': '₽',
    'BRL': r'R$',
    'SAR': '﷼',
    'AED': 'د.إ',
    'CAD': r'CA$',
    'AUD': r'A$',
    'QAR': 'ر.ق',
    'KWD': 'د.ك',
    'OMR': 'ر.ع.',
  };

  static bool isSupported(dynamic value) {
    final code = value?.toString().trim().toUpperCase() ?? '';
    return supportedCodes.contains(code);
  }

  static String normalize(dynamic value) {
    final code = value?.toString().trim().toUpperCase() ?? '';
    return supportedCodes.contains(code) ? code : companyCurrency;
  }

  static String symbolFor(dynamic value) =>
      _symbols[normalize(value)] ?? _symbols[companyCurrency]!;

  static String formatCompactLocale(
    double value,
    String locale, {
    required String symbol,
  }) {
    final lang = locale.toLowerCase().split('_').first;
    final abs = value.abs();

    double unit;
    String suffix;
    if (abs >= 1e12) {
      unit = 1e12;
      suffix = switch (lang) {
        'ru' => 'трлн',
        'es' => 'B',
        'fr' => 'Bi',
        'pt' => 'tri',
        _ => 'T',
      };
    } else if (abs >= 1e9) {
      unit = 1e9;
      suffix = switch (lang) {
        'ru' => 'млрд',
        'es' => 'B',
        'fr' => 'Md',
        'pt' => 'bi',
        _ => 'B',
      };
    } else if (abs >= 1e6) {
      unit = 1e6;
      suffix = switch (lang) {
        'ru' => 'млн',
        'es' => 'M',
        'fr' => 'M',
        'pt' => 'mi',
        _ => 'M',
      };
    } else if (abs >= 1e3) {
      unit = 1e3;
      suffix = switch (lang) {
        'ru' => 'тыс.',
        'es' => 'mil',
        'fr' => 'k',
        'pt' => 'mil',
        _ => 'K',
      };
    } else {
      unit = 1;
      suffix = '';
    }

    final scaled = unit == 1 ? value : value / unit;
    String numberPart;
    try {
      numberPart = NumberFormat('0.##', locale).format(scaled);
    } catch (_) {
      numberPart = scaled.toStringAsFixed(2);
      if (numberPart.contains('.')) {
        numberPart = numberPart
            .replaceAll(RegExp(r'0+$'), '')
            .replaceAll(RegExp(r'\.$'), '');
      }
    }

    numberPart = numberPart.replaceFirst(RegExp(r'[,.]0+$'), '');
    if (suffix.isEmpty) return '$symbol$numberPart';

    return lang == 'en'
        ? '$symbol$numberPart$suffix'
        : '$symbol$numberPart $suffix';
  }
}

class CommaCurrencyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final clean = newValue.text.replaceAll(',', '');

    if (clean.isEmpty) return const TextEditingValue(text: '');

    if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(clean)) return oldValue;

    final dotIdx = clean.indexOf('.');
    final intPart = dotIdx == -1 ? clean : clean.substring(0, dotIdx);
    final decPart = dotIdx == -1 ? '' : clean.substring(dotIdx);

    final buf = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    final formatted = buf.toString() + decPart;

    int cleanCursor = 0;
    final cursorLimit = newValue.selection.baseOffset.clamp(
      0,
      newValue.text.length,
    );
    for (int i = 0; i < cursorLimit; i++) {
      if (newValue.text[i] != ',') cleanCursor++;
    }

    int newPos = 0;
    int cleanCount = 0;
    for (int i = 0; i < formatted.length && cleanCount < cleanCursor; i++) {
      newPos++;
      if (formatted[i] != ',') cleanCount++;
    }
    newPos = newPos.clamp(0, formatted.length);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newPos),
    );
  }
}
class AppDateUtils {
  static const Map<String, int> _monthNames = {
    'january': 1,
    'jan': 1,
    'february': 2,
    'feb': 2,
    'march': 3,
    'mar': 3,
    'april': 4,
    'apr': 4,
    'may': 5,
    'june': 6,
    'jun': 6,
    'july': 7,
    'jul': 7,
    'august': 8,
    'aug': 8,
    'september': 9,
    'sep': 9,
    'sept': 9,
    'october': 10,
    'oct': 10,
    'november': 11,
    'nov': 11,
    'december': 12,
    'dec': 12,
  };

  static DateTime? _validatedDate(int year, int month, int day) {
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  static int? parseMonth(String monthStr, {String? locale}) {
    final trimmed = monthStr.trim().toLowerCase();
    final fromMap = _monthNames[trimmed];
    if (fromMap != null) return fromMap;
    final fromInt = int.tryParse(trimmed);
    if (fromInt != null && fromInt >= 1 && fromInt <= 12) return fromInt;
    try {
      final fmt = locale != null
          ? DateFormat('MMMM', locale)
          : DateFormat('MMMM');
      for (int i = 1; i <= 12; i++) {
        if (fmt.format(DateTime(2024, i)) == monthStr.trim()) return i;
      }
    } catch (_) {}
    return null;
  }

  static DateTime? parseDateString(String dateStr) {
    try {
      final parsed = DateTime.tryParse(dateStr);
      if (parsed != null) {
        return _validatedDate(parsed.year, parsed.month, parsed.day);
      }

      final parts = dateStr.split('/');
      if (parts.length == 3) {
        if (parts[0].length == 4) {
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final day = int.parse(parts[2]);
          return _validatedDate(year, month, day);
        } else if (parts[2].length == 4) {
          final year = int.parse(parts[2]);
          final val1 = int.parse(parts[0]);
          final val2 = int.parse(parts[1]);

          if (val1 > 12) {
            return _validatedDate(year, val2, val1);
          } else if (val2 > 12) {
            return _validatedDate(year, val1, val2);
          } else {
            return _validatedDate(year, val2, val1);
          }
        }
      }

      final hyphenParts = dateStr.split('-');
      if (hyphenParts.length == 3) {
        if (hyphenParts[0].length == 4) {
          final year = int.parse(hyphenParts[0]);
          final month = int.parse(hyphenParts[1]);
          final day = int.parse(hyphenParts[2]);
          return _validatedDate(year, month, day);
        } else if (hyphenParts[2].length == 4) {
          final year = int.parse(hyphenParts[2]);
          final val1 = int.parse(hyphenParts[0]);
          final val2 = int.parse(hyphenParts[1]);
          if (val1 > 12) {
            return _validatedDate(year, val2, val1);
          } else if (val2 > 12) {
            return _validatedDate(year, val1, val2);
          } else {
            return _validatedDate(year, val2, val1);
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static DateTime? parseDdMmYyyy(String value) {
    final text = value.trim();
    if (!RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(text)) return null;

    try {
      final parsed = DateFormat('dd/MM/yyyy').parseStrict(text);
      return _validatedDate(parsed.year, parsed.month, parsed.day);
    } catch (_) {
      return null;
    }
  }

  static DateTime asUtcDateOnly(DateTime value) {
    return DateTime.utc(value.year, value.month, value.day);
  }

  static String formatDate(DateTime date) {
    final dayStr = date.day.toString().padLeft(2, '0');
    final monthStr = date.month.toString().padLeft(2, '0');
    return '$dayStr/$monthStr/${date.year}';
  }

  static String dateKey(DateTime date) {
    final dayStr = date.day.toString().padLeft(2, '0');
    final monthStr = date.month.toString().padLeft(2, '0');
    return '${date.year}-$monthStr-$dayStr';
  }

  static String monthName(DateTime date, {String? locale}) {
    try {
      return DateFormat('MMMM', locale ?? 'en_US').format(date);
    } catch (_) {
      return '';
    }
  }

  static String formatLocaleDate(DateTime date, {String? locale}) {
    try {
      final loc = locale ?? Intl.getCurrentLocale();
      if (loc.startsWith('en')) {
        return DateFormat('dd/MM/yyyy').format(date);
      }
      return DateFormat.yMd(loc).format(date);
    } catch (_) {
      return formatDate(date);
    }
  }

  static String fromValueLocalized(dynamic value, {String? locale}) {
    if (value == null) return '';
    final date = dateFromValue(value);
    if (date == null) return value.toString();
    return formatLocaleDate(date, locale: locale);
  }

  static DateTime periodStart(String period, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (period) {
      case 'Today':
        return today;
      case 'Week':
      case 'Weekly':
      case 'This Week':
        final weekday = today.weekday;
        return today.subtract(Duration(days: weekday - 1));
      case 'Month':
      case 'Monthly':
      case 'This Month':
        return DateTime(today.year, today.month, 1);
      case '6 Month':
      case '6 Months':
      case '6 Monthly':
      case 'Last 6 Months':
        return DateTime(today.year, today.month - 5, 1);
      case 'Yearly':
      case 'This Year':
        return DateTime(today.year, 1, 1);
      case 'All Time':
        return DateTime(1, 1, 1);
      default:
        return today;
    }
  }

  static DateTime periodEnd(String period, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (period) {
      case 'Today':
        return today;
      case 'Week':
      case 'Weekly':
      case 'This Week':
        final weekday = today.weekday;
        final start = today.subtract(Duration(days: weekday - 1));
        return start.add(const Duration(days: 6));
      case 'Month':
      case 'Monthly':
      case 'This Month':
        return DateTime(now.year, now.month + 1, 0);
      case '6 Month':
      case '6 Months':
      case '6 Monthly':
      case 'Last 6 Months':
        return DateTime(now.year, now.month + 1, 0);
      case 'Yearly':
      case 'This Year':
        return DateTime(now.year, 12, 31);
      case 'All Time':
        return DateTime(9999, 12, 31);
      default:
        return today;
    }
  }

  static bool isDateWithinPeriod(String dateStr, String period) {
    final date = parseDateString(dateStr);
    if (date == null) return false;

    final now = DateTime.now();
    final start = periodStart(period, now);
    final end = periodEnd(period, now);

    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  static bool isTimestampWithinPeriod(dynamic createdAt, String period) {
    if (createdAt == null) return false;

    final date = dateFromValue(createdAt);
    if (date == null) return false;

    final now = DateTime.now();
    final start = periodStart(period, now);
    final end = periodEnd(period, now);

    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  static DateTime? dateFromValue(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    return parseDateString(value.toString());
  }

  static DateTime? attendanceRecordDate(Map<String, dynamic> record) {
    for (final key in ['attendanceDate', 'date', 'createdAt']) {
      final date = dateFromValue(record[key]);
      if (date != null) return date;
    }
    return null;
  }

  static DateTime? canonicalAttendanceDate(Map<String, dynamic> record) {
    return dateFromValue(record['attendanceDate']);
  }

  static DateTime? holidayRecordDate(
    Map<String, dynamic> record, {
    int? fallbackYear,
  }) {
    for (final key in ['date', 'holidayDate']) {
      final date = dateFromValue(record[key]);
      if (date != null) return DateTime(date.year, date.month, date.day);
    }

    final rawDay = record['day'];
    final day = rawDay is num
        ? rawDay.toInt()
        : int.tryParse((rawDay ?? '').toString().trim());
    final month = parseMonth((record['month'] ?? '').toString());
    final rawYear = record['year'];
    final year = rawYear is num
        ? rawYear.toInt()
        : int.tryParse((rawYear ?? '').toString().trim()) ?? fallbackYear;
    if (day == null || month == null || year == null) return null;
    return _validatedDate(year, month, day);
  }

  static bool isAttendanceRecordWithinPeriod(
    Map<String, dynamic> record,
    String period,
  ) {
    final date = canonicalAttendanceDate(record);
    if (date == null) return false;
    return isTimestampWithinPeriod(date, period);
  }
}

class PendingTimeOffDraft {
  final String leaveType;
  final String? editingId;
  final Map<String, dynamic>? editingRecord;
  final Set<DateTime> selectedDates;
  final String notes;
  final bool typeChanged;
  final bool datesChanged;
  final bool notesChanged;

  const PendingTimeOffDraft({
    required this.leaveType,
    required this.editingId,
    required this.editingRecord,
    required this.selectedDates,
    required this.notes,
    required this.typeChanged,
    required this.datesChanged,
    required this.notesChanged,
  });

  bool get hasChanges {
    if (editingId != null) {
      return typeChanged || datesChanged || notesChanged;
    }
    return selectedDates.isNotEmpty ||
        notes.isNotEmpty ||
        typeChanged ||
        datesChanged ||
        notesChanged;
  }
}

bool hasUnsavedTimeOffChanges({
  required bool hasSelectedDates,
  required bool hasNotes,
  required bool isEditing,
  required bool typeChanged,
  required bool datesChanged,
}) {
  if (isEditing) {
    return hasNotes || typeChanged || datesChanged;
  }
  return hasSelectedDates || hasNotes || typeChanged;
}

int projectedTimeOffBalance({
  required int availableDays,
  required int requestedDays,
}) {
  return (availableDays - requestedDays).clamp(0, 9999);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String pad2(int n) => n.toString().padLeft(2, '0');
String pad4(int n) => n.toString().padLeft(4, '0');
