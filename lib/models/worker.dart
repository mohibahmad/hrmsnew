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
  double? result;
  if (value is double) {
    result = value;
  } else if (value is int) {
    result = value.toDouble();
  } else if (value is num) {
    result = value.toDouble();
  } else {
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    // NOTE: double.tryParse('NaN'/'Infinity') returns NaN/Infinity, not null.
    result = double.tryParse(text);
  }
  // Firestore rejects non-finite doubles (NaN/Infinity) with invalid-argument.
  if (result != null && !result.isFinite) return null;
  return result;
}




int? _safeInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return num.tryParse(text)?.toInt();
}



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

  
  
  
  return DateTime.utc(parsed.year, parsed.month, parsed.day);
}



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
  final int? annualLeaves;
  final int? sickLeaves;
  final int? casualLeaves;
  final int? medicalLeaves;
  final int? availableAnnualLeaves;
  final int? availableSickLeaves;
  final int? availableCasualLeaves;
  final int? availableMedicalLeaves;
  final int? leavesUsed;
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
    this.medicalLeaves,
    this.availableAnnualLeaves,
    this.availableSickLeaves,
    this.availableCasualLeaves,
    this.availableMedicalLeaves,
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
      annualLeaves: _safeInt(data['annualLeaves']),
      sickLeaves: _safeInt(data['sickLeaves']),
      casualLeaves: _safeInt(data['casualLeaves']),
      medicalLeaves: _safeInt(data['medicalLeaves']),
      availableAnnualLeaves: _safeInt(data['availableAnnualLeaves']),
      availableSickLeaves: _safeInt(data['availableSickLeaves']),
      availableCasualLeaves: _safeInt(data['availableCasualLeaves']),
      availableMedicalLeaves: _safeInt(data['availableMedicalLeaves']),
      leavesUsed: _safeInt(data['leavesUsed']),
      joiningDate: _safeBusinessDate(
        data['joiningDate'] ?? data['dateOfJoining'],
      ),
      profileImage: _safeNullableString(data['profileImage']),
      frontId: _safeNullableString(
        data['idFront'] ??
            data['frontId'] ??
            data['front_id'] ??
            data['id_front'],
      ),
      backId: _safeNullableString(
        data['idBack'] ??
            data['backId'] ??
            data['back_id'] ??
            data['id_back'],
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
    _addStringField(map, 'profileImage', profileImage, forUpdate);
    _addStringField(map, 'idFront', frontId, forUpdate);
    _addStringField(map, 'idBack', backId, forUpdate);
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
    _addNumericField(map, 'medicalLeaves', medicalLeaves, forUpdate);
    _addNumericField(
      map,
      'availableAnnualLeaves',
      availableAnnualLeaves,
      forUpdate,
    );
    _addNumericField(
      map,
      'availableSickLeaves',
      availableSickLeaves,
      forUpdate,
    );
    _addNumericField(
      map,
      'availableCasualLeaves',
      availableCasualLeaves,
      forUpdate,
    );
    _addNumericField(
      map,
      'availableMedicalLeaves',
      availableMedicalLeaves,
      forUpdate,
    );
    _addNumericField(map, 'leavesUsed', leavesUsed, forUpdate);

    _addDateOnlyField(map, 'dob', dob, forUpdate);
    _addDateTimestampField(map, 'joiningDate', joiningDate, forUpdate);

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
    num? value,
    bool forUpdate,
  ) {
    if (value != null && value.isFinite) {
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

  
  
  
  static void _addDateTimestampField(
    Map<String, dynamic> map,
    String key,
    DateTime? value,
    bool forUpdate,
  ) {
    if (value != null) {
      map[key] = Timestamp.fromDate(
        DateTime(value.year, value.month, value.day),
      );
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
    int? annualLeaves,
    int? sickLeaves,
    int? casualLeaves,
    int? medicalLeaves,
    int? availableAnnualLeaves,
    int? availableSickLeaves,
    int? availableCasualLeaves,
    int? availableMedicalLeaves,
    int? leavesUsed,
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
      medicalLeaves: medicalLeaves ?? this.medicalLeaves,
      availableAnnualLeaves:
          availableAnnualLeaves ?? this.availableAnnualLeaves,
      availableSickLeaves:
          availableSickLeaves ?? this.availableSickLeaves,
      availableCasualLeaves:
          availableCasualLeaves ?? this.availableCasualLeaves,
      availableMedicalLeaves:
          availableMedicalLeaves ?? this.availableMedicalLeaves,
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
