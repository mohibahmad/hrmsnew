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

bool _safeBool(dynamic value, {required bool defaultValue}) {
  if (value is bool) {
    return value;
  }

  if (value is num) {
    return value != 0;
  }

  final text = value?.toString().trim().toLowerCase() ?? '';

  if (text == 'true' || text == '1' || text == 'yes') {
    return true;
  }

  if (text == 'false' || text == '0' || text == 'no') {
    return false;
  }

  return defaultValue;
}

String? _timestampToString(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is Timestamp) {
    return value.toDate().toIso8601String();
  }

  if (value is DateTime) {
    return value.toIso8601String();
  }

  final text = value.toString().trim();

  return text.isEmpty ? null : text;
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
  final bool isRecurring;
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
    this.isRecurring = false,
    this.year = 0,
    this.createdAt,
  });

  factory Holiday.fromMap(Map<String, dynamic> data, {String? id}) {
    return Holiday(
      id: _safeNullableString(id ?? data['id']),
      day: _safeInt(data['day']),
      month: _safeString(data['month']).trim(),
      remainingDays: _safeString(data['remainingDays']).trim(),
      dayOfWeek: _safeString(data['dayOfWeek']).trim(),
      name: _safeString(data['name']).trim(),
      isEnabled: _safeBool(data['isEnabled'], defaultValue: true),
      isCustom: _safeBool(data['isCustom'], defaultValue: false),
      isRecurring: _safeBool(data['isRecurring'], defaultValue: false),
      year: _safeInt(data['year']),
      createdAt: _timestampToString(data['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null && id!.trim().isNotEmpty) 'id': id!.trim(),
      'day': day,
      'month': month.trim(),
      'remainingDays': remainingDays.trim(),
      'dayOfWeek': dayOfWeek.trim(),
      'name': name.trim(),
      'isEnabled': isEnabled,
      'isCustom': isCustom,
      'isRecurring': isRecurring,
      'year': year,
      if (createdAt != null && createdAt!.trim().isNotEmpty)
        'createdAt': createdAt!.trim(),
    };
  }
}
