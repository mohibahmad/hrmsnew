import 'package:cloud_firestore/cloud_firestore.dart';

String _safeString(dynamic value) {
  return value?.toString() ?? '';
}

String? _safeNullableString(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

String _formatExpenseDate(DateTime date) {
  final localDate = date.toLocal();

  return '${localDate.day.toString().padLeft(2, '0')}/'
      '${localDate.month.toString().padLeft(2, '0')}/'
      '${localDate.year}';
}

String _expenseDateToString(dynamic value) {
  if (value == null) return '';

  if (value is Timestamp) {
    return _formatExpenseDate(value.toDate());
  }

  if (value is DateTime) {
    return _formatExpenseDate(value);
  }

  final text = value.toString().trim();

  if (text.isEmpty) return '';

  final parsed = DateTime.tryParse(text);

  if (parsed != null) {
    return _formatExpenseDate(parsed);
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

  if (text.isEmpty) return null;

  final parsed = DateTime.tryParse(text);

  return parsed?.toIso8601String() ?? text;
}

double _expenseAmountToDouble(dynamic value) {
  if (value is num) {
    final amount = value.toDouble();
    return amount.isFinite ? amount : 0;
  }

  final text = value?.toString().trim() ?? '';

  if (text.isEmpty) return 0;

  final cleaned = text.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.\-]'), '');

  final amount = double.tryParse(cleaned) ?? 0;

  return amount.isFinite ? amount : 0;
}

class Expense {
  final String? id;
  final String workerId;
  final String workerEmail;
  final String name;
  final String description;
  final String date;
  final String category;
  final double amount;
  final String? payrollKey;
  final String? payPeriod;
  final String? paidAt;
  final String? createdAt;
  final String? updatedAt;

  const Expense({
    this.id,
    this.workerId = '',
    this.workerEmail = '',
    required this.name,
    this.description = '',
    this.date = '',
    required this.category,
    required this.amount,
    this.payrollKey,
    this.payPeriod,
    this.paidAt,
    this.createdAt,
    this.updatedAt,
  });

  factory Expense.fromMap(Map<String, dynamic> data, {String? id}) {
    return Expense(
      id: _safeNullableString(id ?? data['id']),
      workerId: _safeString(data['workerId']).trim(),
      workerEmail: _safeString(
        data['workerEmail'] ?? data['email'],
      ).trim().toLowerCase(),
      name: _safeString(data['name'] ?? data['title']).trim(),
      description: _safeString(data['description']).trim(),
      date: _expenseDateToString(data['date']),
      category: _safeString(data['category'] ?? data['type']).trim(),
      amount: _expenseAmountToDouble(data['amount']),
      payrollKey: _safeNullableString(data['payrollKey']),
      payPeriod: _timestampToString(data['payPeriod']),
      paidAt: _timestampToString(data['paidAt']),
      createdAt: _timestampToString(data['createdAt']),
      updatedAt: _timestampToString(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null && id!.trim().isNotEmpty) 'id': id!.trim(),
      if (workerId.trim().isNotEmpty) 'workerId': workerId.trim(),
      if (workerEmail.trim().isNotEmpty)
        'workerEmail': workerEmail.trim().toLowerCase(),
      'name': name.trim(),
      'description': description.trim(),
      'date': date.trim(),
      'category': category.trim(),
      'amount': amount,
      if (payrollKey != null && payrollKey!.trim().isNotEmpty)
        'payrollKey': payrollKey!.trim(),
      if (payPeriod != null && payPeriod!.trim().isNotEmpty)
        'payPeriod': payPeriod!.trim(),
      if (paidAt != null && paidAt!.trim().isNotEmpty) 'paidAt': paidAt!.trim(),
      if (createdAt != null && createdAt!.trim().isNotEmpty)
        'createdAt': createdAt!.trim(),
      if (updatedAt != null && updatedAt!.trim().isNotEmpty)
        'updatedAt': updatedAt!.trim(),
    };
  }
}
