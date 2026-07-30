String _safeString(dynamic value) {
  return value?.toString() ?? '';
}

String? _safeNullableString(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int? _safeNullableInt(dynamic value) {
  if (value == null) return null;

  if (value is num) {
    return value.toInt();
  }

  final text = value.toString().trim();

  if (text.isEmpty) return null;

  return int.tryParse(text);
}

double? _safeNullableDouble(dynamic value) {
  if (value == null) return null;

  if (value is num) {
    final number = value.toDouble();
    return number.isFinite ? number : null;
  }

  final text = value.toString().trim();

  if (text.isEmpty) return null;

  final cleaned = text.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.\-]'), '');

  final number = double.tryParse(cleaned);

  if (number == null || !number.isFinite) {
    return null;
  }

  return number;
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

dynamic _safeDateValue(dynamic value) {
  if (value == null) return null;

  if (value is String && value.trim().isEmpty) {
    return null;
  }

  return value;
}

class Payroll {
  final String? id;
  final String workerId;
  final String name;
  final String email;
  final String position;
  final String contact;
  final String status;
  final String? profileImage;
  final String totalWorkDays;
  final String absents;
  final int? paidLeaves;
  final int? unpaidLeaves;
  final String leaves;
  final String overtimeAmount;
  final String absentDeduction;
  final String leaveDeduction;
  final bool? deductionsAreTotals;
  final String salary;
  final String? salaryType;
  final String netSalary;
  final double? netSalaryAmount;
  final String? netSalaryFormatted;
  final String? payrollKey;
  final dynamic payPeriod;
  final dynamic payrollDate;
  final dynamic cancelledAt;
  final dynamic paidAt;
  final dynamic createdAt;
  final dynamic lastModified;

  const Payroll({
    this.id,
    this.workerId = '',
    required this.name,
    this.email = '',
    this.position = '',
    this.contact = '',
    required this.status,
    this.profileImage,
    this.totalWorkDays = '',
    this.absents = '',
    this.paidLeaves,
    this.unpaidLeaves,
    this.leaves = '',
    this.overtimeAmount = '',
    this.absentDeduction = '',
    this.leaveDeduction = '',
    this.deductionsAreTotals,
    this.salary = '',
    this.salaryType,
    this.netSalary = '',
    this.netSalaryAmount,
    this.netSalaryFormatted,
    this.payrollKey,
    this.payPeriod,
    this.payrollDate,
    this.cancelledAt,
    this.paidAt,
    this.createdAt,
    this.lastModified,
  });

  factory Payroll.fromMap(Map<String, dynamic> data, {String? id}) {
    final netSalary = _safeString(data['netSalary']).trim();

    return Payroll(
      id: _safeNullableString(id ?? data['id']),
      workerId: _safeString(data['workerId']).trim(),
      name: _safeString(data['name'] ?? data['workerName']).trim(),
      email: _safeString(data['email']).trim(),
      position: _safeString(data['position']).trim(),
      contact: _safeString(data['contact'] ?? data['phone']).trim(),
      status: _safeString(data['status']).trim(),
      profileImage: _safeNullableString(data['profileImage']),
      totalWorkDays: _safeString(data['totalWorkDays']).trim(),
      absents: _safeString(data['absents']).trim(),
      paidLeaves: _safeNullableInt(data['paidLeaves']),
      unpaidLeaves: _safeNullableInt(data['unpaidLeaves']),
      leaves: _safeString(data['leaves']).trim(),
      overtimeAmount: _safeString(data['overtimeAmount']).trim(),
      absentDeduction: _safeString(data['absentDeduction']).trim(),
      leaveDeduction: _safeString(data['leaveDeduction']).trim(),
      deductionsAreTotals: _safeNullableBool(data['deductionsAreTotals']),
      salary: _safeString(data['salary']).trim(),
      salaryType: _safeNullableString(data['salaryType']),
      netSalary: netSalary.isNotEmpty
          ? netSalary
          : _safeString(data['netSalaryFormatted']).trim(),
      netSalaryAmount: _safeNullableDouble(data['netSalaryAmount']),
      netSalaryFormatted: _safeNullableString(data['netSalaryFormatted']),
      payrollKey: _safeNullableString(data['payrollKey']),
      payPeriod: _safeDateValue(data['payPeriod']),
      payrollDate: _safeDateValue(data['payrollDate']),
      cancelledAt: _safeDateValue(data['cancelledAt']),
      paidAt: _safeDateValue(data['paidAt']),
      createdAt: _safeDateValue(data['createdAt']),
      lastModified: _safeDateValue(data['lastModified']),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null && id!.trim().isNotEmpty) 'id': id!.trim(),
      if (workerId.trim().isNotEmpty) 'workerId': workerId.trim(),
      'name': name.trim(),
      'email': email.trim(),
      'position': position.trim(),
      'contact': contact.trim(),
      'status': status.trim(),
      if (profileImage != null && profileImage!.trim().isNotEmpty)
        'profileImage': profileImage!.trim(),
      'totalWorkDays': totalWorkDays.trim(),
      'absents': absents.trim(),
      if (paidLeaves != null) 'paidLeaves': paidLeaves,
      if (unpaidLeaves != null) 'unpaidLeaves': unpaidLeaves,
      'leaves': leaves.trim(),
      'overtimeAmount': overtimeAmount.trim(),
      'absentDeduction': absentDeduction.trim(),
      'leaveDeduction': leaveDeduction.trim(),
      if (deductionsAreTotals != null)
        'deductionsAreTotals': deductionsAreTotals,
      'salary': salary.trim(),
      if (salaryType != null && salaryType!.trim().isNotEmpty)
        'salaryType': salaryType!.trim(),
      'netSalary': netSalary.trim(),
      if (netSalaryAmount != null) 'netSalaryAmount': netSalaryAmount,
      if (netSalaryFormatted != null && netSalaryFormatted!.trim().isNotEmpty)
        'netSalaryFormatted': netSalaryFormatted!.trim(),
      if (payrollKey != null && payrollKey!.trim().isNotEmpty)
        'payrollKey': payrollKey!.trim(),
      if (payPeriod != null) 'payPeriod': payPeriod,
      if (payrollDate != null) 'payrollDate': payrollDate,
      'cancelledAt': cancelledAt,
      if (paidAt != null) 'paidAt': paidAt,
      if (createdAt != null) 'createdAt': createdAt,
      if (lastModified != null) 'lastModified': lastModified,
    };
  }
}
