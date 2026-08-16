import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/utils.dart';

class SafeParser {
  SafeParser._();

  static String asString(dynamic value) {
    return (value?.toString() ?? '').trim();
  }

  static String? asStringOrNull(dynamic value) {
    final result = asString(value);
    return result.isEmpty ? null : result;
  }

  static num? asNumber(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;

    final text = value.toString().trim().replaceAll(',', '');
    return num.tryParse(text);
  }

  static double? asDouble(dynamic value) {
    final number = asNumber(value);
    if (number == null) return null;
    if (!number.isFinite) return null;
    return number.toDouble();
  }

  static int? asInt(dynamic value) {
    final number = asNumber(value);
    return number?.toInt();
  }

  static bool? asBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;

    final text = value.toString().trim().toLowerCase();

    if (text == 'true' || text == '1' || text == 'yes') {
      return true;
    }

    if (text == 'false' || text == '0' || text == 'no') {
      return false;
    }

    return null;
  }

  static DateTime? asDateTime(dynamic value) {
    if (value == null) return null;

    if (value is Timestamp) {
      return value.toDate().toUtc();
    }

    if (value is DateTime) {
      return value.toUtc();
    }

    return DateTime.tryParse(value.toString().trim())?.toUtc();
  }

  static DateTime? asDateOnly(dynamic value) {
    final dateTime = asDateTime(value);
    if (dateTime == null) return null;

    return DateTime.utc(dateTime.year, dateTime.month, dateTime.day);
  }
}

extension SafeParserExtension on Object? {
  String get asString => SafeParser.asString(this);
  String? get asStringOrNull => SafeParser.asStringOrNull(this);
  num? get asNumber => SafeParser.asNumber(this);
  double? get asDouble => SafeParser.asDouble(this);
  int? get asInt => SafeParser.asInt(this);
  bool? get asBool => SafeParser.asBool(this);
  DateTime? get asDateTime => SafeParser.asDateTime(this);
  DateTime? get asDateOnly => SafeParser.asDateOnly(this);
}

extension FieldAdder on Map<String, dynamic> {
  void addField(
    String key,
    dynamic value,
    bool forUpdate, {
    bool isDate = false,
    bool isTimestamp = false,
  }) {
    if (value == null) {
      if (forUpdate) {
        this[key] = FieldValue.delete();
      }
      return;
    }

    if (isDate && value is DateTime) {
      final year = value.year.toString().padLeft(4, '0');
      final month = value.month.toString().padLeft(2, '0');
      final day = value.day.toString().padLeft(2, '0');
      this[key] = '$year-$month-$day';
      return;
    }

    if (isTimestamp && value is DateTime) {
      this[key] = Timestamp.fromDate(
        DateTime(value.year, value.month, value.day),
      );
      return;
    }

    this[key] = value;
  }
}

String _normalizeWorkerStatus(dynamic value) {
  final raw = value?.toString().trim() ?? '';

  if (raw.isEmpty) {
    return 'Active';
  }

  switch (raw.toLowerCase()) {
    case 'active':
      return 'Active';
    case 'inactive':
      return 'Inactive';
    case 'suspended':
      return 'Suspended';
    case 'onleave':
    case 'on leave':
    case 'on_leave':
    case 'on-leave':
      return 'OnLeave';
    case 'terminated':
      return 'Terminated';
    case 'archived':
      return 'Archived';
    case 'deleted':
      return 'Deleted';
    default:
      return raw;
  }
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
    final rawSalary =
        SafeParser.asDouble(data['salaryAmount']) ??
        SafeParser.asDouble(data['salary']);

    final salaryAmount = rawSalary != null && rawSalary < 0 ? null : rawSalary;

    final rawCurrency = SafeParser.asStringOrNull(data['currency']);
    final currency = rawCurrency == null
        ? null
        : CurrencyUtils.normalize(rawCurrency);

    return Worker(
      id: id ?? SafeParser.asStringOrNull(data['id']),
      name: SafeParser.asString(data['name']),
      fatherName: SafeParser.asStringOrNull(data['fatherName']),
      email: SafeParser.asStringOrNull(data['email']),
      phone: SafeParser.asStringOrNull(data['phone'] ?? data['contact']),
      nationalId: SafeParser.asStringOrNull(
        data['nationalId'] ?? data['cnic'],
      ),
      religion: SafeParser.asStringOrNull(data['religion']),
      dob: SafeParser.asDateOnly(data['dob']),
      gender: SafeParser.asStringOrNull(data['gender']),
      address: SafeParser.asStringOrNull(data['address']),
      relationshipStatus: SafeParser.asStringOrNull(
        data['relationshipStatus'],
      ),
      type1: SafeParser.asStringOrNull(data['type1'] ?? data['workType']),
      position: SafeParser.asStringOrNull(data['position'] ?? data['role']),
      type2: SafeParser.asStringOrNull(
        data['type2'] ?? data['attendanceType'],
      ),
      experienceLevel: SafeParser.asStringOrNull(data['experienceLevel']),
      education: SafeParser.asStringOrNull(data['education']),
      salaryType: SafeParser.asStringOrNull(data['salaryType']),
      currency: currency,
      salaryAmount: salaryAmount,
      leavePolicy: SafeParser.asStringOrNull(data['leavePolicy']),
      annualLeaves: SafeParser.asInt(data['annualLeaves']),
      sickLeaves: SafeParser.asInt(data['sickLeaves']),
      casualLeaves: SafeParser.asInt(data['casualLeaves']),
      medicalLeaves: SafeParser.asInt(data['medicalLeaves']),
      availableAnnualLeaves: SafeParser.asInt(data['availableAnnualLeaves']),
      availableSickLeaves: SafeParser.asInt(data['availableSickLeaves']),
      availableCasualLeaves: SafeParser.asInt(data['availableCasualLeaves']),
      availableMedicalLeaves: SafeParser.asInt(data['availableMedicalLeaves']),
      leavesUsed: SafeParser.asInt(data['leavesUsed']),
      joiningDate: SafeParser.asDateOnly(
        data['joiningDate'] ?? data['dateOfJoining'],
      ),
      profileImage: SafeParser.asStringOrNull(data['profileImage']),
      frontId: SafeParser.asStringOrNull(
        data['idFront'] ??
            data['frontId'] ??
            data['front_id'] ??
            data['id_front'],
      ),
      backId: SafeParser.asStringOrNull(
        data['idBack'] ?? data['backId'] ?? data['back_id'] ?? data['id_back'],
      ),
      cv: SafeParser.asStringOrNull(data['cv']),
      createdAt: SafeParser.asDateTime(data['createdAt']),
      payrollInitialized:
          SafeParser.asBool(
            data['payroll_initialized'] ?? data['payrollInitialized'],
          ) ??
          false,
      status: _normalizeWorkerStatus(data['status']),
    );
  }

  Map<String, dynamic> toMap({bool forUpdate = false}) {
    final map = <String, dynamic>{
      'name': name.trim(),
    };

    void addNumberField(String key, num? value) {
      if (value != null && value.isFinite) {
        map[key] = value;
      } else if (forUpdate) {
        map[key] = FieldValue.delete();
      }
    }

    map.addField('fatherName', fatherName, forUpdate);
    map.addField('email', email, forUpdate);
    map.addField('phone', phone, forUpdate);
    map.addField('nationalId', nationalId, forUpdate);
    map.addField('religion', religion, forUpdate);
    map.addField('gender', gender, forUpdate);
    map.addField('address', address, forUpdate);
    map.addField('relationshipStatus', relationshipStatus, forUpdate);
    map.addField('type1', type1, forUpdate);
    map.addField('position', position, forUpdate);
    map.addField('type2', type2, forUpdate);
    map.addField('experienceLevel', experienceLevel, forUpdate);
    map.addField('education', education, forUpdate);
    map.addField('salaryType', salaryType, forUpdate);
    map.addField('profileImage', profileImage, forUpdate);
    // ID images are read and written app-wide under `frontId`/`backId`;
    // `fromMap` still accepts the legacy `idFront`/`idBack` keys for docs
    // written before the rename, so emitting the canonical keys keeps every
    // reader (bulk media uploader, documents screen, edit flow) working.
    map.addField('frontId', frontId, forUpdate);
    map.addField('backId', backId, forUpdate);
    map.addField('cv', cv, forUpdate);
    map.addField('status', status, forUpdate);
    map.addField('leavePolicy', leavePolicy, forUpdate);

    if (currency != null) {
      map['currency'] = CurrencyUtils.normalize(currency);
    } else if (forUpdate) {
      map['currency'] = FieldValue.delete();
    }

    addNumberField('salaryAmount', salaryAmount);
    addNumberField('annualLeaves', annualLeaves);
    addNumberField('sickLeaves', sickLeaves);
    addNumberField('casualLeaves', casualLeaves);
    addNumberField('medicalLeaves', medicalLeaves);
    addNumberField('availableAnnualLeaves', availableAnnualLeaves);
    addNumberField('availableSickLeaves', availableSickLeaves);
    addNumberField('availableCasualLeaves', availableCasualLeaves);
    addNumberField('availableMedicalLeaves', availableMedicalLeaves);
    addNumberField('leavesUsed', leavesUsed);

    map.addField('dob', dob, forUpdate, isTimestamp: true);
    map.addField('joiningDate', joiningDate, forUpdate, isTimestamp: true);

    if (!forUpdate) {
      if (createdAt != null) {
        map['createdAt'] = Timestamp.fromDate(createdAt!);
      } else {
        map['createdAt'] = FieldValue.serverTimestamp();
      }
    }

    map['payroll_initialized'] = payrollInitialized ?? true;

    return map;
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
      availableSickLeaves: availableSickLeaves ?? this.availableSickLeaves,
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