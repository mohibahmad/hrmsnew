import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/currency_utils.dart';

// ============= SINGLE PARSER EXTENSION (SAB KAAM EK JAGAH) =============
class SafeParser {
  SafeParser._();

  static String asString(dynamic value) => (value?.toString() ?? '').trim();

  static String? asStringOrNull(dynamic value) {
    final s = (value?.toString() ?? '').trim();
    return s.isEmpty ? null : s;
  }

  static num? asNumber(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    final clean = value.toString().trim().replaceAll(',', '');
    return num.tryParse(clean);
  }

  static double? asDouble(dynamic value) {
    final n = asNumber(value);
    if (n == null) return null;
    return n.isFinite ? n.toDouble() : null;
  }

  static int? asInt(dynamic value) => asNumber(value)?.toInt();

  static bool? asBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toLowerCase();
    if (['true', '1', 'yes'].contains(text)) return true;
    if (['false', '0', 'no'].contains(text)) return false;
    return null;
  }

  static DateTime? asDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    return DateTime.tryParse(value.toString().trim())?.toUtc();
  }

  static DateTime? asDateOnly(dynamic value) {
    final dt = asDateTime(value);
    if (dt == null) return null;
    return DateTime.utc(dt.year, dt.month, dt.day);
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

// ============= SINGLE FIELD ADDER (4 FUNCTIONS KI JAGAH 1) =============
extension FieldAdder on Map<String, dynamic> {
  void addField(
    String key,
    dynamic value,
    bool forUpdate, {
    bool isDate = false,
    bool isTimestamp = false,
  }) {
    if (value == null) {
      if (forUpdate) this[key] = FieldValue.delete();
      return;
    }

    if (isDate && value is DateTime) {
      final y = value.year.toString().padLeft(4, '0');
      final m = value.month.toString().padLeft(2, '0');
      final d = value.day.toString().padLeft(2, '0');
      this[key] = '$y-$m-$d';
    } else if (isTimestamp && value is DateTime) {
      this[key] = Timestamp.fromDate(
        DateTime(value.year, value.month, value.day),
      );
    } else {
      this[key] = value;
    }
  }
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

// ============= WORKER MODEL (SAME PROPERTIES, SAME FUNCTIONS) =============
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

  // ============= fromMap - CLEANER BUT SAME LOGIC =============
  factory Worker.fromMap(Map<String, dynamic> data, {String? id}) {
    final rawSalary =
        SafeParser.asDouble(data['salaryAmount']) ??
        SafeParser.asDouble(data['salary']);
    final salary = (rawSalary != null && rawSalary < 0) ? null : rawSalary;

    final rawCurrency = SafeParser.asStringOrNull(data['currency']);
    final currency = rawCurrency != null
        ? CurrencyUtils.normalize(rawCurrency)
        : null;

    final status = _normalizeWorkerStatus(data['status']);

    return Worker(
      id: id ?? SafeParser.asStringOrNull(data['id']),
      name: SafeParser.asString(data['name']),
      fatherName: SafeParser.asStringOrNull(data['fatherName']),
      email: SafeParser.asStringOrNull(data['email']),
      phone: SafeParser.asStringOrNull(data['phone'] ?? data['contact']),
      nationalId: SafeParser.asStringOrNull(data['nationalId'] ?? data['cnic']),
      religion: SafeParser.asStringOrNull(data['religion']),
      dob: SafeParser.asDateOnly(data['dob']),
      gender: SafeParser.asStringOrNull(data['gender']),
      address: SafeParser.asStringOrNull(data['address']),
      relationshipStatus: SafeParser.asStringOrNull(data['relationshipStatus']),
      type1: SafeParser.asStringOrNull(data['type1'] ?? data['workType']),
      position: SafeParser.asStringOrNull(data['position'] ?? data['role']),
      type2: SafeParser.asStringOrNull(data['type2'] ?? data['attendanceType']),
      experienceLevel: SafeParser.asStringOrNull(data['experienceLevel']),
      education: SafeParser.asStringOrNull(data['education']),
      salaryType: SafeParser.asStringOrNull(data['salaryType']),
      currency: currency,
      salaryAmount: salary,
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
      status: status,
    );
  }

  // ============= toMap - SAME OUTPUT, LESS CODE =============
  Map<String, dynamic> toMap({bool forUpdate = false}) {
    final map = <String, dynamic>{'name': name.trim()};

    final stringValues = {
      'fatherName': fatherName,
      'email': email,
      'phone': phone,
      'nationalId': nationalId,
      'religion': religion,
      'gender': gender,
      'address': address,
      'relationshipStatus': relationshipStatus,
      'type1': type1,
      'position': position,
      'type2': type2,
      'experienceLevel': experienceLevel,
      'education': education,
      'salaryType': salaryType,
      'profileImage': profileImage,
      'idFront': frontId,
      'idBack': backId,
      'cv': cv,
      'status': status,
      'leavePolicy': leavePolicy,
    };

    stringValues.forEach((key, value) {
      map.addField(key, value, forUpdate);
    });

    // Currency
    if (currency != null) {
      map['currency'] = CurrencyUtils.normalize(currency);
    } else if (forUpdate) {
      map['currency'] = FieldValue.delete();
    }

    // Numeric fields
    final numericValues = {
      'salaryAmount': salaryAmount,
      'annualLeaves': annualLeaves,
      'sickLeaves': sickLeaves,
      'casualLeaves': casualLeaves,
      'medicalLeaves': medicalLeaves,
      'availableAnnualLeaves': availableAnnualLeaves,
      'availableSickLeaves': availableSickLeaves,
      'availableCasualLeaves': availableCasualLeaves,
      'availableMedicalLeaves': availableMedicalLeaves,
      'leavesUsed': leavesUsed,
    };

    numericValues.forEach((key, value) {
      if (value != null && value.isFinite) {
        map[key] = value;
      } else if (forUpdate) {
        map[key] = FieldValue.delete();
      }
    });

    // Date fields
    map.addField('dob', dob, forUpdate, isTimestamp: true);
    map.addField('joiningDate', joiningDate, forUpdate, isTimestamp: true);

    // Created at
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

  // ============= copyWith - BILKUL SAME =============
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
