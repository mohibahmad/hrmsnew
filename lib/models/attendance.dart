String _safeString(dynamic value) {
  return value?.toString() ?? '';
}

String? _safeNullableString(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

class Attendance {
  final String? id;
  final String workerId;
  final String name;
  final String email;
  final String role;
  final String status;
  final String attendanceType;
  final String workType;
  final String? type;
  final String? desc;
  final String? profileImage;
  final dynamic attendanceDate;
  final dynamic createdAt;

  const Attendance({
    this.id,
    this.workerId = '',
    required this.name,
    this.email = '',
    this.role = '',
    required this.status,
    this.attendanceType = '',
    this.workType = '',
    this.type,
    this.desc,
    this.profileImage,
    this.attendanceDate,
    this.createdAt,
  });

  factory Attendance.fromMap(Map<String, dynamic> data, {String? id}) {
    return Attendance(
      id: _safeNullableString(id ?? data['id']),
      workerId: _safeString(data['workerId']).trim(),
      name: _safeString(data['name'] ?? data['workerName']).trim(),
      email: _safeString(data['email']).trim(),
      role: _safeString(data['role'] ?? data['position']).trim(),
      status: _safeString(data['status']).trim(),
      attendanceType: _safeString(data['attendanceType']).trim(),
      workType: _safeString(data['workType']).trim(),
      type: _safeNullableString(data['type']),
      desc: _safeNullableString(data['desc'] ?? data['reason']),
      profileImage: _safeNullableString(data['profileImage']),
      attendanceDate: data['attendanceDate'],
      createdAt: data['createdAt'],
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null && id!.trim().isNotEmpty) 'id': id!.trim(),
      if (workerId.trim().isNotEmpty) 'workerId': workerId.trim(),
      'name': name.trim(),
      'email': email.trim(),
      'role': role.trim(),
      'status': status.trim(),
      'attendanceType': attendanceType.trim(),
      'workType': workType.trim(),
      if (type != null && type!.trim().isNotEmpty) 'type': type!.trim(),
      if (desc != null && desc!.trim().isNotEmpty) 'desc': desc!.trim(),
      if (profileImage != null && profileImage!.trim().isNotEmpty)
        'profileImage': profileImage!.trim(),
      if (attendanceDate != null) 'attendanceDate': attendanceDate,
      if (createdAt != null) 'createdAt': createdAt,
    };
  }
}
