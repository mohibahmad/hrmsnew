import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/currency_utils.dart';

String _safeString(dynamic value) {
  return value?.toString() ?? '';
}

String? _safeNullableString(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

String? _timestampToString(dynamic value) {
  if (value == null) return null;

  if (value is Timestamp) {
    return value.toDate().toIso8601String();
  }

  if (value is DateTime) {
    return value.toIso8601String();
  }

  final text = value.toString().trim();

  return text.isEmpty ? null : text;
}

String _formatDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

String _dateOnly(dynamic value) {
  if (value == null) return '';

  if (value is Timestamp) {
    return _formatDate(value.toDate());
  }

  if (value is DateTime) {
    return _formatDate(value);
  }

  final text = value.toString().trim();

  if (text.isEmpty) return '';

  final parsedDate = DateTime.tryParse(text);

  if (parsedDate != null) {
    return _formatDate(parsedDate);
  }

  return text;
}

bool? _safeNullableBool(dynamic value) {
  if (value == null) return null;

  if (value is bool) {
    return value;
  }

  if (value is num) {
    return value != 0;
  }

  final text = value.toString().trim().toLowerCase();

  if (text == 'true' || text == '1' || text == 'yes') {
    return true;
  }

  if (text == 'false' || text == '0' || text == 'no') {
    return false;
  }

  return null;
}

class Worker {
  final String? id;
  final String name;
  final String fatherName;
  final String email;
  final String phone;
  final String nationalId;
  final String religion;
  final String dob;
  final String gender;
  final String address;
  final String relationshipStatus;
  final String type1;
  final String position;
  final String type2;
  final String experienceLevel;
  final String education;
  final String salaryType;
  final String currency;
  final String salaryAmount;
  final String leavePolicy;
  final String annualLeaves;
  final String sickLeaves;
  final String casualLeaves;
  final String availableAnnualLeaves;
  final String leavesUsed;
  final String joiningDate;
  final String? profileImage;
  final String? frontId;
  final String? backId;
  final String? cv;
  final String? createdAt;
  final bool? payrollInitialized;
  final String status;

  const Worker({
    this.id,
    required this.name,
    this.fatherName = '',
    this.email = '',
    this.phone = '',
    this.nationalId = '',
    this.religion = '',
    this.dob = '',
    this.gender = 'Male',
    this.address = '',
    this.relationshipStatus = 'Single',
    this.type1 = 'Full-Time',
    this.position = 'Employee',
    this.type2 = 'On-Site',
    this.experienceLevel = 'Mid-Level',
    this.education = "Bachelor's",
    this.salaryType = 'Monthly',
    this.currency = 'USD',
    this.salaryAmount = '',
    this.leavePolicy = 'Standard',
    this.annualLeaves = '',
    this.sickLeaves = '',
    this.casualLeaves = '',
    this.availableAnnualLeaves = '',
    this.leavesUsed = '',
    this.joiningDate = '',
    this.profileImage,
    this.frontId,
    this.backId,
    this.cv,
    this.createdAt,
    this.payrollInitialized,
    this.status = '',
  });

  factory Worker.fromMap(Map<String, dynamic> data, {String? id}) {
    return Worker(
      id: _safeNullableString(id ?? data['id']),
      name: _safeString(data['name']).trim(),
      fatherName: _safeString(data['fatherName']).trim(),
      email: _safeString(data['email']).trim(),
      phone: _safeString(data['phone'] ?? data['contact']).trim(),
      nationalId: _safeString(data['nationalId'] ?? data['cnic']).trim(),
      religion: _safeString(data['religion']).trim(),
      dob: _dateOnly(data['dob']),
      gender: _safeString(data['gender'] ?? 'Male').trim(),
      address: _safeString(data['address']).trim(),
      relationshipStatus: _safeString(
        data['relationshipStatus'] ?? 'Single',
      ).trim(),
      type1: _safeString(
        data['type1'] ?? data['workType'] ?? 'Full-Time',
      ).trim(),
      position: _safeString(
        data['position'] ?? data['role'] ?? 'Employee',
      ).trim(),
      type2: _safeString(
        data['type2'] ?? data['attendanceType'] ?? 'On-Site',
      ).trim(),
      experienceLevel: _safeString(
        data['experienceLevel'] ?? 'Mid-Level',
      ).trim(),
      education: _safeString(data['education'] ?? "Bachelor's").trim(),
      salaryType: _safeString(data['salaryType'] ?? 'Monthly').trim(),
      currency: CurrencyUtils.normalize(_safeString(data['currency'])),
      salaryAmount: _safeString(data['salaryAmount'] ?? data['salary']).trim(),
      leavePolicy: _safeString(data['leavePolicy'] ?? 'Standard').trim(),
      annualLeaves: _safeString(data['annualLeaves']).trim(),
      sickLeaves: _safeString(data['sickLeaves']).trim(),
      casualLeaves: _safeString(data['casualLeaves']).trim(),
      availableAnnualLeaves: _safeString(data['availableAnnualLeaves']).trim(),
      leavesUsed: _safeString(data['leavesUsed']).trim(),
      joiningDate: _dateOnly(data['joiningDate'] ?? data['dateOfJoining']),
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
      createdAt: _timestampToString(data['createdAt']),
      payrollInitialized: _safeNullableBool(
        data['payroll_initialized'] ?? data['payrollInitialized'],
      ),
      status: _safeString(data['status']).trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null && id!.trim().isNotEmpty) 'id': id!.trim(),
      'name': name.trim(),
      'fatherName': fatherName.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
      'nationalId': nationalId.trim(),
      'religion': religion.trim(),
      'dob': dob.trim(),
      'gender': gender.trim(),
      'address': address.trim(),
      'relationshipStatus': relationshipStatus.trim(),
      'type1': type1.trim(),
      'position': position.trim(),
      'type2': type2.trim(),
      'experienceLevel': experienceLevel.trim(),
      'education': education.trim(),
      'salaryType': salaryType.trim(),
      'currency': CurrencyUtils.normalize(currency),
      'salaryAmount': salaryAmount.trim(),
      'leavePolicy': leavePolicy.trim(),
      'annualLeaves': annualLeaves.trim(),
      'sickLeaves': sickLeaves.trim(),
      'casualLeaves': casualLeaves.trim(),
      if (availableAnnualLeaves.trim().isNotEmpty)
        'availableAnnualLeaves': availableAnnualLeaves.trim(),
      if (leavesUsed.trim().isNotEmpty) 'leavesUsed': leavesUsed.trim(),
      'joiningDate': joiningDate.trim(),
      if (profileImage != null && profileImage!.trim().isNotEmpty)
        'profileImage': profileImage!.trim(),
      if (frontId != null && frontId!.trim().isNotEmpty)
        'frontId': frontId!.trim(),
      if (backId != null && backId!.trim().isNotEmpty) 'backId': backId!.trim(),
      if (cv != null && cv!.trim().isNotEmpty) 'cv': cv!.trim(),
      if (createdAt != null && createdAt!.trim().isNotEmpty)
        'createdAt': createdAt!.trim(),
      if (payrollInitialized != null) 'payroll_initialized': payrollInitialized,
      'status': status.trim(),
    };
  }

  Worker copyWith({
    String? id,
    String? name,
    String? fatherName,
    String? email,
    String? phone,
    String? nationalId,
    String? religion,
    String? dob,
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
    String? salaryAmount,
    String? leavePolicy,
    String? annualLeaves,
    String? sickLeaves,
    String? casualLeaves,
    String? availableAnnualLeaves,
    String? leavesUsed,
    String? joiningDate,
    String? profileImage,
    String? frontId,
    String? backId,
    String? cv,
    String? createdAt,
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
