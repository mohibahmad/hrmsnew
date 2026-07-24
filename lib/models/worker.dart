import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/currency_utils.dart';

String _tsToString(dynamic value) {
  if (value == null) return '';
  if (value is Timestamp) return value.toDate().toIso8601String();
  if (value is DateTime) return value.toIso8601String();
  return value.toString();
}

String _dateOnly(dynamic value) {
  if (value == null) return '';
  if (value is Timestamp) {
    final d = value.toDate();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
  if (value is DateTime) {
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }
  return value.toString();
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
  final String joiningDate;
  final String? profileImage;
  final String? frontId;
  final String? backId;
  final String? cv;
  final String? createdAt;
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
    this.joiningDate = '',
    this.profileImage,
    this.frontId,
    this.backId,
    this.cv,
    this.createdAt,
    this.status = '',
  });

  factory Worker.fromMap(Map<String, dynamic> data, {String? id}) {
    return Worker(
      id: id ?? data['id'],
      name: data['name'] ?? '',
      fatherName: data['fatherName'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      nationalId: data['nationalId'] ?? '',
      religion: data['religion'] ?? '',
      dob: _dateOnly(data['dob']),
      gender: data['gender'] ?? 'Male',
      address: data['address'] ?? '',
      relationshipStatus: data['relationshipStatus'] ?? 'Single',
      type1: data['type1'] ?? 'Full-Time',
      position: data['position'] ?? 'Employee',
      type2: data['type2'] ?? 'On-Site',
      experienceLevel: data['experienceLevel'] ?? 'Mid-Level',
      education: data['education'] ?? "Bachelor's",
      salaryType: data['salaryType'] ?? 'Monthly',
      currency: CurrencyUtils.normalize(data['currency']),
      salaryAmount: data['salaryAmount'] ?? '',
      leavePolicy: data['leavePolicy'] ?? 'Standard',
      annualLeaves: data['annualLeaves'] ?? '',
      sickLeaves: data['sickLeaves'] ?? '',
      casualLeaves: data['casualLeaves'] ?? '',
      joiningDate: _dateOnly(data['joiningDate']),
      profileImage: data['profileImage'],
      frontId: data['frontId'] ?? data['front_id'] ?? data['idFront'] ?? data['id_front'],
      backId: data['backId'] ?? data['back_id'] ?? data['idBack'] ?? data['id_back'],
      cv: data['cv'],
      createdAt: _tsToString(data['createdAt']),
      status: data['status'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'fatherName': fatherName,
      'email': email,
      'phone': phone,
      'nationalId': nationalId,
      'religion': religion,
      'dob': dob,
      'gender': gender,
      'address': address,
      'relationshipStatus': relationshipStatus,
      'type1': type1,
      'position': position,
      'type2': type2,
      'experienceLevel': experienceLevel,
      'education': education,
      'salaryType': salaryType,
      'currency': CurrencyUtils.normalize(currency),
      'salaryAmount': salaryAmount,
      'leavePolicy': leavePolicy,
      'annualLeaves': annualLeaves,
      'sickLeaves': sickLeaves,
      'casualLeaves': casualLeaves,
      'joiningDate': joiningDate,
      if (profileImage != null) 'profileImage': profileImage,
      if (frontId != null) 'frontId': frontId,
      if (backId != null) 'backId': backId,
      if (cv != null) 'cv': cv,
      if (createdAt != null) 'createdAt': createdAt,
      'status': status,
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
    String? joiningDate,
    String? profileImage,
    String? frontId,
    String? backId,
    String? cv,
    String? createdAt,
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
      joiningDate: joiningDate ?? this.joiningDate,
      profileImage: profileImage ?? this.profileImage,
      frontId: frontId ?? this.frontId,
      backId: backId ?? this.backId,
      cv: cv ?? this.cv,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
    );
  }
}
