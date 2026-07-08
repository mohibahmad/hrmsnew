class Attendance {
  final String? id;
  final String name;
  final String email;
  final String role;
  final String status;
  final String attendanceType;
  final String workType;
  final String? type;
  final String? desc;
  final String? profileImage;
  final dynamic createdAt;

  const Attendance({
    this.id,
    required this.name,
    this.email = '',
    this.role = '',
    required this.status,
    this.attendanceType = '',
    this.workType = '',
    this.type,
    this.desc,
    this.profileImage,
    this.createdAt,
  });

  factory Attendance.fromMap(Map<String, dynamic> data, {String? id}) {
    return Attendance(
      id: id ?? data['id'],
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      role: data['role'] ?? data['position'] ?? '',
      status: data['status'] ?? '',
      attendanceType: data['attendanceType'] ?? '',
      workType: data['workType'] ?? '',
      type: data['type'],
      desc: data['desc'],
      profileImage: data['profileImage'],
      createdAt: data['createdAt'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'email': email,
      'role': role,
      'status': status,
      'attendanceType': attendanceType,
      'workType': workType,
      if (type != null) 'type': type,
      if (desc != null) 'desc': desc,
      if (profileImage != null) 'profileImage': profileImage,
      if (createdAt != null) 'createdAt': createdAt,
    };
  }
}
