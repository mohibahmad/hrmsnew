import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/currency_utils.dart';

String _safeString(dynamic value) {
  return (value?.toString() ?? '').trim();
}

String? _safeNullableString(dynamic value) {
  final text = (value?.toString() ?? '').trim();
  return text.isEmpty ? null : text;
}

double? _safeDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return double.tryParse(text);
}

/// Parses a timestamp (e.g. `createdAt`) preserving the exact instant. Only
/// used for timestamps, never for date-only business values.
DateTime? _safeTimestamp(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text)?.toUtc();
}

DateTime? _safeBusinessDate(dynamic value) {
  DateTime? parsed;

  if (value is Timestamp) {
    parsed = value.toDate();
  } else if (value is DateTime) {
    parsed = value;
  } else {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    parsed = DateTime.tryParse(text);
  }

  if (parsed == null) return null;

  // Normalize to a UTC-anchored midnight using the parsed calendar fields
  // (year/month/day). This strips any local offset so callers reading
  // `.year/.month/.day` always get the intended calendar date.
  return DateTime.utc(parsed.year, parsed.month, parsed.day);
}

/// Serializes a date-only business value to the canonical `YYYY-MM-DD` form
/// so it is timezone-agnostic inside Firestore.
String _addDateOnly(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

bool? _safeNullableBool(dynamic value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value.toString().trim().toLowerCase();
  if (text == 'true' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == '0' || text == 'no') return false;
  return null;
}

/// Canonicalizes a worker status case-insensitively. Unknown non-empty statuses
/// (e.g. `Terminated`, `Archived`, `Deleted`) are preserved, never silently
/// turned into `Active`, so payroll/attendance/assets eligibility rules that
/// exclude former workers continue to work.
String _normalizeWorkerStatus(dynamic value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return 'Active';

  return switch (raw.toLowerCase()) {
    'active' => 'Active',
    'inactive' => 'Inactive',
    'suspended' => 'Suspended',
    'onleave' || 'on leave' || 'on_leave' || 'on-leave' => 'OnLeave',
    'terminated' => 'Terminated',
    'archived' => 'Archived',
    'deleted' => 'Deleted',
    _ => raw,
  };
}

class Worker {
  final String? id;
  final String name;
  final String? fatherName;
  final String? email;
  final String? phone;
  final String? nationalId;
  final String? religion;
  final DateTime? dob;
  final String? gender;
  final String? address;
  final String? relationshipStatus;
  final String? type1;
  final String? position;
  final String? type2;
  final String? experienceLevel;
  final String? education;
  final String? salaryType;
  final String? currency;
  final double? salaryAmount;
  final String? leavePolicy;
  final double? annualLeaves;
  final double? sickLeaves;
  final double? casualLeaves;
  final double? availableAnnualLeaves;
  final double? leavesUsed;
  final DateTime? joiningDate;
  final String? profileImage;
  final String? frontId;
  final String? backId;
  final String? cv;
  final DateTime? createdAt;
  final bool? payrollInitialized;
  final String? status;

  const Worker({
    this.id,
    required this.name,
    this.fatherName,
    this.email,
    this.phone,
    this.nationalId,
    this.religion,
    this.dob,
    this.gender,
    this.address,
    this.relationshipStatus,
    this.type1,
    this.position,
    this.type2,
    this.experienceLevel,
    this.education,
    this.salaryType,
    this.currency,
    this.salaryAmount,
    this.leavePolicy,
    this.annualLeaves,
    this.sickLeaves,
    this.casualLeaves,
    this.availableAnnualLeaves,
    this.leavesUsed,
    this.joiningDate,
    this.profileImage,
    this.frontId,
    this.backId,
    this.cv,
    this.createdAt,
    this.payrollInitialized,
    this.status,
  });

  factory Worker.fromMap(Map<String, dynamic> data, {String? id}) {
    final rawSalary = _safeDouble(data['salaryAmount'] ?? data['salary']);
    final salary = (rawSalary != null && rawSalary < 0) ? null : rawSalary;

    final rawCurrency = _safeNullableString(data['currency']);
    final currency = rawCurrency != null
        ? CurrencyUtils.normalize(rawCurrency)
        : null;

    final status = _normalizeWorkerStatus(data['status']);

    return Worker(
      id: _safeNullableString(id ?? data['id']),
      name: _safeString(data['name']),
      fatherName: _safeNullableString(data['fatherName']),
      email: _safeNullableString(data['email']),
      phone: _safeNullableString(data['phone'] ?? data['contact']),
      nationalId: _safeNullableString(data['nationalId'] ?? data['cnic']),
      religion: _safeNullableString(data['religion']),
      dob: _safeBusinessDate(data['dob']),
      gender: _safeNullableString(data['gender']),
      address: _safeNullableString(data['address']),
      relationshipStatus: _safeNullableString(data['relationshipStatus']),
      type1: _safeNullableString(data['type1'] ?? data['workType']),
      position: _safeNullableString(data['position'] ?? data['role']),
      type2: _safeNullableString(data['type2'] ?? data['attendanceType']),
      experienceLevel: _safeNullableString(data['experienceLevel']),
      education: _safeNullableString(data['education']),
      salaryType: _safeNullableString(data['salaryType']),
      currency: currency,
      salaryAmount: salary,
      leavePolicy: _safeNullableString(data['leavePolicy']),
      annualLeaves: _safeDouble(data['annualLeaves']),
      sickLeaves: _safeDouble(data['sickLeaves']),
      casualLeaves: _safeDouble(data['casualLeaves']),
      availableAnnualLeaves: _safeDouble(data['availableAnnualLeaves']),
      leavesUsed: _safeDouble(data['leavesUsed']),
      joiningDate: _safeBusinessDate(
        data['joiningDate'] ?? data['dateOfJoining'],
      ),
      profileImage: _safeNullableString(data['profileImage']),
      frontId: _safeNullableString(
        data['frontId'] ??
            data['front_id'] ??
            data['idFront'] ??
            data['id_front'],
      ),
      backId: _safeNullableString(
        data['backId'] ?? data['back_id'] ?? data['idBack'] ?? data['id_back'],
      ),
      cv: _safeNullableString(data['cv']),
      createdAt: _safeTimestamp(data['createdAt']),
      payrollInitialized:
          _safeNullableBool(
            data['payroll_initialized'] ?? data['payrollInitialized'],
          ) ??
          false,
      status: status,
    );
  }

  Map<String, dynamic> toMap({bool forUpdate = false}) {
    final map = <String, dynamic>{'name': name.trim()};

    _addStringField(map, 'fatherName', fatherName, forUpdate);
    _addStringField(map, 'email', email, forUpdate);
    _addStringField(map, 'phone', phone, forUpdate);
    _addStringField(map, 'nationalId', nationalId, forUpdate);
    _addStringField(map, 'religion', religion, forUpdate);
    _addStringField(map, 'gender', gender, forUpdate);
    _addStringField(map, 'address', address, forUpdate);
    _addStringField(map, 'relationshipStatus', relationshipStatus, forUpdate);
    _addStringField(map, 'type1', type1, forUpdate);
    _addStringField(map, 'position', position, forUpdate);
    _addStringField(map, 'type2', type2, forUpdate);
    _addStringField(map, 'experienceLevel', experienceLevel, forUpdate);
    _addStringField(map, 'education', education, forUpdate);
    _addStringField(map, 'salaryType', salaryType, forUpdate);
    _addStringField(map, 'leavePolicy', leavePolicy, forUpdate);
    _addStringField(map, 'profileImage', profileImage, forUpdate);
    _addStringField(map, 'frontId', frontId, forUpdate);
    _addStringField(map, 'backId', backId, forUpdate);
    _addStringField(map, 'cv', cv, forUpdate);
    _addStringField(map, 'status', status, forUpdate);

    if (currency != null) {
      map['currency'] = CurrencyUtils.normalize(currency);
    } else if (forUpdate) {
      map['currency'] = FieldValue.delete();
    }

    _addNumericField(map, 'salaryAmount', salaryAmount, forUpdate);
    _addNumericField(map, 'annualLeaves', annualLeaves, forUpdate);
    _addNumericField(map, 'sickLeaves', sickLeaves, forUpdate);
    _addNumericField(map, 'casualLeaves', casualLeaves, forUpdate);
    _addNumericField(
      map,
      'availableAnnualLeaves',
      availableAnnualLeaves,
      forUpdate,
    );
    _addNumericField(map, 'leavesUsed', leavesUsed, forUpdate);

    _addDateOnlyField(map, 'dob', dob, forUpdate);
    _addDateOnlyField(map, 'joiningDate', joiningDate, forUpdate);

    if (!forUpdate) {
      if (createdAt != null) {
        map['createdAt'] = Timestamp.fromDate(createdAt!);
      } else {
        map['createdAt'] = FieldValue.serverTimestamp();
      }
    }

    map['payroll_initialized'] = payrollInitialized ?? false;

    return map;
  }

  static void _addStringField(
    Map<String, dynamic> map,
    String key,
    String? value,
    bool forUpdate,
  ) {
    if (value != null && value.trim().isNotEmpty) {
      map[key] = value.trim();
    } else if (forUpdate) {
      map[key] = FieldValue.delete();
    }
  }

  static void _addNumericField(
    Map<String, dynamic> map,
    String key,
    double? value,
    bool forUpdate,
  ) {
    if (value != null) {
      map[key] = value;
    } else if (forUpdate) {
      map[key] = FieldValue.delete();
    }
  }

  static void _addDateOnlyField(
    Map<String, dynamic> map,
    String key,
    DateTime? value,
    bool forUpdate,
  ) {
    if (value != null) {
      map[key] = _addDateOnly(value);
    } else if (forUpdate) {
      map[key] = FieldValue.delete();
    }
  }

  Worker copyWith({
    String? id,
    String? name,
    String? fatherName,
    String? email,
    String? phone,
    String? nationalId,
    String? religion,
    DateTime? dob,
    String? gender,
    String? address,
    String? relationshipStatus,
    String? type1,
    String? position,
    String? type2,
    String? experienceLevel,
    String? education,
    String? salaryType,
    String? currency,
    double? salaryAmount,
    String? leavePolicy,
    double? annualLeaves,
    double? sickLeaves,
    double? casualLeaves,
    double? availableAnnualLeaves,
    double? leavesUsed,
    DateTime? joiningDate,
    String? profileImage,
    String? frontId,
    String? backId,
    String? cv,
    DateTime? createdAt,
    bool? payrollInitialized,
    String? status,
  }) {
    return Worker(
      id: id ?? this.id,
      name: name ?? this.name,
      fatherName: fatherName ?? this.fatherName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      nationalId: nationalId ?? this.nationalId,
      religion: religion ?? this.religion,
      dob: dob ?? this.dob,
      gender: gender ?? this.gender,
      address: address ?? this.address,
      relationshipStatus: relationshipStatus ?? this.relationshipStatus,
      type1: type1 ?? this.type1,
      position: position ?? this.position,
      type2: type2 ?? this.type2,
      experienceLevel: experienceLevel ?? this.experienceLevel,
      education: education ?? this.education,
      salaryType: salaryType ?? this.salaryType,
      currency: currency ?? this.currency,
      salaryAmount: salaryAmount ?? this.salaryAmount,
      leavePolicy: leavePolicy ?? this.leavePolicy,
      annualLeaves: annualLeaves ?? this.annualLeaves,
      sickLeaves: sickLeaves ?? this.sickLeaves,
      casualLeaves: casualLeaves ?? this.casualLeaves,
      availableAnnualLeaves:
          availableAnnualLeaves ?? this.availableAnnualLeaves,
      leavesUsed: leavesUsed ?? this.leavesUsed,
      joiningDate: joiningDate ?? this.joiningDate,
      profileImage: profileImage ?? this.profileImage,
      frontId: frontId ?? this.frontId,
      backId: backId ?? this.backId,
      cv: cv ?? this.cv,
      createdAt: createdAt ?? this.createdAt,
      payrollInitialized: payrollInitialized ?? this.payrollInitialized,
      status: status ?? this.status,
    );
  }
}
