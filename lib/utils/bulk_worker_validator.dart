import 'package:easy_localization/easy_localization.dart';
import '../utils/date_utils.dart';
import '../utils/currency_utils.dart';
import '../utils/worker_identity.dart';
import '../utils/validators.dart';

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
  'salaryType',
  'currency',
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
  'salaryType': 'field_salary_type',
  'currency': 'field_currency',
  'salaryAmount': 'field_salary_amount',
  'annualLeaves': 'field_annual_leaves',
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
  'salary type': 'salaryType',
  'salary amount': 'salaryAmount',
  'leave policy': 'leavePolicy',
  'annual leaves': 'annualLeaves',
  'sick leaves': 'sickLeaves',
  'casual leaves': 'casualLeaves',
  'joining date': 'joiningDate',
  'profile image url': 'profileImage',
  'profile image': 'profileImage',
  'profile pic': 'profileImage',
  'image url': 'profileImage',
  'front id image url': 'frontId',
  'front id': 'frontId',
  'back id image url': 'backId',
  'back id': 'backId',
  'cv url': 'cv',
  'cv': 'cv',
  'currency': 'currency',
};

bool isAtLeast18(DateTime dob) {
  final now = DateTime.now();
  int age = now.year - dob.year;
  if (now.month < dob.month ||
      (now.month == dob.month && now.day < dob.day)) {
    age--;
  }
  return age >= 18;
}

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
  return AppDateUtils.parseDateString(dateStr.trim());
}

String formatDateForField(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

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

  final currency = workerData['currency']?.toString().trim() ?? '';
  if (currency.isNotEmpty) {
    if (!CurrencyUtils.isSupported(currency)) {
      fieldErrors['currency'] = 'invalid_currency_value'.tr();
    } else {
      workerData['currency'] = CurrencyUtils.normalize(currency);
    }
  }

  final dobStr = workerData['dob']?.toString().trim() ?? '';
  if (dobStr.isNotEmpty) {
    final dob = AppDateUtils.parseDateString(dobStr);
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
      fieldErrors['experienceLevel'] =
          'validation_invalid_experience_level'.tr();
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
      fieldErrors['relationshipStatus'] =
          'validation_invalid_relationship'.tr();
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

  final salaryType = workerData['salaryType']?.toString().trim() ?? '';
  if (salaryType.isNotEmpty) {
    final normalized = salaryType.toLowerCase();
    const valid = {'monthly', 'hourly', 'contract'};
    if (!valid.contains(normalized)) {
      fieldErrors['salaryType'] = 'validation_invalid_salary_type'.tr();
    } else {
      workerData['salaryType'] =
          normalized[0].toUpperCase() + normalized.substring(1);
    }
  }

  final leavePolicy = workerData['leavePolicy']?.toString().trim() ?? '';
  if (leavePolicy.isEmpty) {
    workerData['leavePolicy'] = 'Standard';
  }

  final email = WorkerIdentity.normalizeEmail(workerData['email']);
  if (email.isEmpty) {
    if ((workerData['email']?.toString().trim() ?? '').isNotEmpty) {
      fieldErrors['email'] = requiredMessage;
    }
  } else if (!Validators.isValidEmail(email)) {
    fieldErrors['email'] = 'validation_invalid_email'.tr();
  } else {
    workerData['email'] = email;
    if (existingEmails.contains(email) || csvEmails.contains(email)) {
      fieldErrors['email'] = 'validation_duplicate_email'.tr();
    }
  }

  final nationalId = WorkerIdentity.normalizeNationalId(
    workerData['nationalId'],
  );
  if (nationalId.isNotEmpty &&
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

  final annualLeavesText =
      workerData['annualLeaves']?.toString().trim() ?? '';
  if (annualLeavesText.isNotEmpty) {
    final annualLeaves = int.tryParse(annualLeavesText);
    if (annualLeaves == null || annualLeaves < 0 || annualLeaves > 366) {
      fieldErrors['annualLeaves'] = 'invalid_number'.tr();
      workerData['availableAnnualLeaves'] = '0';
    } else {
      workerData['annualLeaves'] = annualLeaves.toString();
      workerData['availableAnnualLeaves'] = annualLeaves.toString();
    }
  } else {
    workerData['availableAnnualLeaves'] = '0';
  }
  workerData['leavesUsed'] = '0';

  final joiningDateText =
      workerData['joiningDate']?.toString().trim() ?? '';
  if (joiningDateText.isNotEmpty) {
    final joiningDate = AppDateUtils.parseDateString(joiningDateText);
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
validationCounts(
  List<Map<String, dynamic>> workers,
) {
  final requiredMessage = 'validation_required'.tr();
  final duplicateEmailMessage = 'validation_duplicate_email'.tr();
  final duplicateNationalIdMessage =
      'validation_duplicate_national_id'.tr();

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
