class Payroll {
  final String? id;
  final String name;
  final String email;
  final String position;
  final String contact;
  final String status;
  final String? profileImage;
  final String totalWorkDays;
  final String absents;
  final String leaves;
  final String overtimeDays;
  final String absentDeduction;
  final String leaveDeduction;
  final String salary;
  final String netSalary;
  final String? createdAt;

  const Payroll({
    this.id,
    required this.name,
    this.email = '',
    this.position = '',
    this.contact = '',
    required this.status,
    this.profileImage,
    this.totalWorkDays = '',
    this.absents = '',
    this.leaves = '',
    this.overtimeDays = '',
    this.absentDeduction = '',
    this.leaveDeduction = '',
    this.salary = '',
    this.netSalary = '',
    this.createdAt,
  });

  factory Payroll.fromMap(Map<String, dynamic> data, {String? id}) {
    return Payroll(
      id: id ?? data['id'],
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      position: data['position'] ?? '',
      contact: data['contact'] ?? data['phone'] ?? '',
      status: data['status'] ?? '',
      profileImage: data['profileImage'],
      totalWorkDays: data['totalWorkDays'] ?? '',
      absents: data['absents'] ?? '',
      leaves: data['leaves'] ?? '',
      overtimeDays: data['overtimeDays'] ?? '',
      absentDeduction: data['absentDeduction'] ?? '',
      leaveDeduction: data['leaveDeduction'] ?? '',
      salary: data['salary'] ?? '',
      netSalary: data['netSalary'] ?? '',
      createdAt: data['createdAt'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'email': email,
      'position': position,
      'contact': contact,
      'status': status,
      if (profileImage != null) 'profileImage': profileImage,
      'totalWorkDays': totalWorkDays,
      'absents': absents,
      'leaves': leaves,
      'overtimeDays': overtimeDays,
      'absentDeduction': absentDeduction,
      'leaveDeduction': leaveDeduction,
      'salary': salary,
      'netSalary': netSalary,
      if (createdAt != null) 'createdAt': createdAt,
    };
  }
}
