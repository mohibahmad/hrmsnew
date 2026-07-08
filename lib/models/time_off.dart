class TimeOff {
  final String? id;
  final String name;
  final String email;
  final String position;
  final String contact;
  final String action;
  final String type;
  final String startDate;
  final String endDate;
  final int requestedDays;
  final String notes;
  final String status;
  final String? workerAvatar;
  final String? createdAt;

  const TimeOff({
    this.id,
    required this.name,
    this.email = '',
    this.position = '',
    this.contact = '',
    required this.action,
    this.type = '',
    required this.startDate,
    required this.endDate,
    this.requestedDays = 0,
    this.notes = '',
    this.status = 'Approved',
    this.workerAvatar,
    this.createdAt,
  });

  factory TimeOff.fromMap(Map<String, dynamic> data, {String? id}) {
    return TimeOff(
      id: id ?? data['id'],
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      position: data['position'] ?? '',
      contact: data['contact'] ?? data['phone'] ?? '',
      action: data['action'] ?? '',
      type: data['type'] ?? '',
      startDate: data['startDate'] ?? '',
      endDate: data['endDate'] ?? '',
      requestedDays: data['requestedDays'] ?? 0,
      notes: data['notes'] ?? '',
      status: data['status'] ?? 'Approved',
      workerAvatar: data['workerAvatar'],
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
      'action': action,
      'type': type,
      'startDate': startDate,
      'endDate': endDate,
      'requestedDays': requestedDays,
      'notes': notes,
      'status': status,
      if (workerAvatar != null) 'workerAvatar': workerAvatar,
      if (createdAt != null) 'createdAt': createdAt,
    };
  }
}
