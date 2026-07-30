import 'package:cloud_firestore/cloud_firestore.dart';

String? _timestampToString(dynamic value) {
  if (value == null) return null;

  if (value is Timestamp) {
    return value.toDate().toIso8601String();
  }

  if (value is DateTime) {
    return value.toIso8601String();
  }

  final text = value.toString().trim();

  if (text.isEmpty) return null;

  return text;
}

String _safeString(dynamic value) {
  return value?.toString() ?? '';
}

String? _safeNullableString(dynamic value) {
  final text = value?.toString().trim() ?? '';

  return text.isEmpty ? null : text;
}

bool _safeBool(dynamic value) {
  if (value is bool) return value;

  if (value is num) {
    return value != 0;
  }

  final text = value?.toString().trim().toLowerCase() ?? '';

  return text == 'true' || text == '1' || text == 'yes' || text == 'read';
}

Map<String, dynamic> _safeDataMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }

  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  return <String, dynamic>{};
}

class AppNotification {
  final String? id;
  final String type;
  final String title;
  final String message;
  final bool isRead;
  final String? createdAt;

  /// Notification click/navigation data.
  ///
  /// Examples:
  /// {
  ///   'name': 'Ali Ahmad',
  ///   'period': '2026-07',
  /// }
  final Map<String, dynamic> data;

  /// Unique key used to prevent duplicate notifications.
  ///
  /// Example:
  /// payroll_due_2026-07
  final String? notificationKey;

  const AppNotification({
    this.id,
    this.type = '',
    this.title = '',
    this.message = '',
    this.isRead = false,
    this.createdAt,
    this.data = const <String, dynamic>{},
    this.notificationKey,
  });

  factory AppNotification.fromMap(Map<String, dynamic> data, {String? id}) {
    return AppNotification(
      id: _safeNullableString(id ?? data['id']),
      type: _safeString(data['type']).trim(),
      title: _safeString(data['title']),
      message: _safeString(data['message']),
      isRead: _safeBool(data['isRead']),
      createdAt: _timestampToString(data['createdAt']),
      data: _safeDataMap(data['data']),
      notificationKey: _safeNullableString(data['notificationKey']),
    );
  }

  factory AppNotification.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return AppNotification.fromMap(
      document.data() ?? <String, dynamic>{},
      id: document.id,
    );
  }

  DateTime? get createdAtDate {
    final value = createdAt?.trim();

    if (value == null || value.isEmpty) {
      return null;
    }

    return DateTime.tryParse(value);
  }

  bool get isUnread => !isRead;

  AppNotification copyWith({
    String? id,
    String? type,
    String? title,
    String? message,
    bool? isRead,
    String? createdAt,
    Map<String, dynamic>? data,
    String? notificationKey,
  }) {
    return AppNotification(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      data: data == null
          ? Map<String, dynamic>.from(this.data)
          : Map<String, dynamic>.from(data),
      notificationKey: notificationKey ?? this.notificationKey,
    );
  }

  AppNotification markAsRead() {
    if (isRead) return this;

    return copyWith(isRead: true);
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null && id!.trim().isNotEmpty) 'id': id!.trim(),
      'type': type.trim(),
      'title': title,
      'message': message,
      'isRead': isRead,
      if (createdAt != null && createdAt!.trim().isNotEmpty)
        'createdAt': createdAt!.trim(),
      if (data.isNotEmpty) 'data': Map<String, dynamic>.from(data),
      if (notificationKey != null && notificationKey!.trim().isNotEmpty)
        'notificationKey': notificationKey!.trim(),
    };
  }
}
