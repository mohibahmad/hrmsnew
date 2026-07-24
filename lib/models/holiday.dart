import 'package:cloud_firestore/cloud_firestore.dart';

String _tsToString(dynamic value) {
  if (value == null) return '';
  if (value is Timestamp) return value.toDate().toIso8601String();
  if (value is DateTime) return value.toIso8601String();
  return value.toString();
}

class Holiday {
  final String? id;
  final int day;
  final String month;
  final String remainingDays;
  final String dayOfWeek;
  final String name;
  final bool isEnabled;
  final bool isCustom;
  final int year;
  final String? createdAt;

  const Holiday({
    this.id,
    this.day = 0,
    this.month = '',
    this.remainingDays = '',
    this.dayOfWeek = '',
    required this.name,
    this.isEnabled = true,
    this.isCustom = false,
    this.year = 0,
    this.createdAt,
  });

  factory Holiday.fromMap(Map<String, dynamic> data, {String? id}) {
    return Holiday(
      id: id ?? data['id'],
      day: data['day'] ?? 0,
      month: data['month'] ?? '',
      remainingDays: data['remainingDays'] ?? '',
      dayOfWeek: data['dayOfWeek'] ?? '',
      name: data['name'] ?? '',
      isEnabled: data['isEnabled'] ?? true,
      isCustom: data['isCustom'] ?? false,
      year: data['year'] ?? 0,
      createdAt: _tsToString(data['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'day': day,
      'month': month,
      'remainingDays': remainingDays,
      'dayOfWeek': dayOfWeek,
      'name': name,
      'isEnabled': isEnabled,
      'isCustom': isCustom,
      'year': year,
      if (createdAt != null) 'createdAt': createdAt,
    };
  }
}
