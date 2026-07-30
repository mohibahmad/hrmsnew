import 'package:cloud_firestore/cloud_firestore.dart';

String _safeString(dynamic value) {
  return value?.toString() ?? '';
}

String? _safeNullableString(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int _safeInt(dynamic value) {
  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(value?.toString().trim() ?? '') ?? 0;
}

bool? _safeBool(dynamic value) {
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

String _formatDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

String _dateToString(dynamic value) {
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

List<String> _parseSelectedDates(dynamic value) {
  if (value is! Iterable) {
    return <String>[];
  }

  final dates = <String>[];

  for (final item in value) {
    final date = _dateToString(item);

    if (date.isNotEmpty && !dates.contains(date)) {
      dates.add(date);
    }
  }

  return dates;
}

class TimeOff {
  final String? id;
  final String workerId;
  final String workerName;
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
  final bool? isPaidLeave;
  final String? workerAvatar;
  final String? createdAt;
  final String? updatedAt;
  final String? cancelledAt;

  const TimeOff({
    this.id,
    this.workerId = '',
    this.workerName = '',
    required this.name,
    this.email = '',
    this.position = '',
    this.contact = '',
    required this.action,
    this.type = '',
    required this.startDate,
    required this.endDate,
    this.selectedDates = const <String>[],
    this.requestedDays = 0,
    this.notes = '',
    this.status = 'Approved',
    this.isPaidLeave,
    this.workerAvatar,
    this.createdAt,
    this.updatedAt,
    this.cancelledAt,
  });

  factory TimeOff.fromMap(Map<String, dynamic> data, {String? id}) {
    final selectedDates = _parseSelectedDates(data['selectedDates']);

    final requestedDays = _safeInt(data['requestedDays']);

    return TimeOff(
      id: _safeNullableString(id ?? data['id']),
      workerId: _safeString(data['workerId']).trim(),
      workerName: _safeString(data['workerName'] ?? data['name']).trim(),
      name: _safeString(data['name'] ?? data['workerName']).trim(),
      email: _safeString(data['email']).trim(),
      position: _safeString(data['position'] ?? data['role']).trim(),
      contact: _safeString(data['contact'] ?? data['phone']).trim(),
      action: _safeString(
        data['action'] ?? data['type'] ?? data['leaveType'],
      ).trim(),
      type: _safeString(
        data['type'] ?? data['action'] ?? data['leaveType'],
      ).trim(),
      startDate: _dateToString(data['startDate']),
      endDate: _dateToString(data['endDate']),
      selectedDates: selectedDates,
      requestedDays: requestedDays > 0 ? requestedDays : selectedDates.length,
      notes: _safeString(data['notes']).trim(),
      status: _safeString(data['status'] ?? 'Approved').trim(),
      isPaidLeave: _safeBool(data['isPaidLeave']),
      workerAvatar: _safeNullableString(
        data['workerAvatar'] ?? data['profileImage'],
      ),
      createdAt: _timestampToString(data['createdAt']),
      updatedAt: _timestampToString(data['updatedAt']),
      cancelledAt: _timestampToString(data['cancelledAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null && id!.trim().isNotEmpty) 'id': id!.trim(),
      if (workerId.trim().isNotEmpty) 'workerId': workerId.trim(),
      if (workerName.trim().isNotEmpty) 'workerName': workerName.trim(),
      'name': name.trim(),
      'email': email.trim(),
      'position': position.trim(),
      'contact': contact.trim(),
      'action': action.trim(),
      'type': type.trim(),
      'startDate': startDate.trim(),
      'endDate': endDate.trim(),
      'selectedDates': List<String>.from(selectedDates),
      'requestedDays': requestedDays,
      'notes': notes.trim(),
      'status': status.trim(),
      if (isPaidLeave != null) 'isPaidLeave': isPaidLeave,
      if (workerAvatar != null && workerAvatar!.trim().isNotEmpty)
        'workerAvatar': workerAvatar!.trim(),
      if (createdAt != null && createdAt!.trim().isNotEmpty)
        'createdAt': createdAt!.trim(),
      if (updatedAt != null && updatedAt!.trim().isNotEmpty)
        'updatedAt': updatedAt!.trim(),
      if (cancelledAt != null && cancelledAt!.trim().isNotEmpty)
        'cancelledAt': cancelledAt!.trim(),
    };
  }
}
