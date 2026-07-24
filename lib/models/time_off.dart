import 'package:cloud_firestore/cloud_firestore.dart';

String _dateToString(dynamic value) {
  if (value == null) return '';
  if (value is Timestamp) {
    final d = value.toDate();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
  if (value is DateTime) {
    return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }
  return value.toString();
}

List<String> _parseSelectedDates(dynamic value) {
  if (value is! Iterable) return [];
  return value.map((date) {
    if (date is Timestamp) {
      final d = date.toDate();
      return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
    if (date is DateTime) {
      return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
    return date.toString();
  }).toList();
}

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
  final List<String> selectedDates;
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
    this.selectedDates = const [],
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
      startDate: _dateToString(data['startDate']),
      endDate: _dateToString(data['endDate']),
      selectedDates: _parseSelectedDates(data['selectedDates']),
      requestedDays: data['requestedDays'] ?? 0,
      notes: data['notes'] ?? '',
      status: data['status'] ?? 'Approved',
      workerAvatar: data['workerAvatar'],
      createdAt: data['createdAt']?.toString(),
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
      'selectedDates': selectedDates,
      'requestedDays': requestedDays,
      'notes': notes,
      'status': status,
      if (workerAvatar != null) 'workerAvatar': workerAvatar,
      if (createdAt != null) 'createdAt': createdAt,
    };
  }
}
