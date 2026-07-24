import 'package:cloud_firestore/cloud_firestore.dart';

String _expenseDateToString(dynamic value) {
  if (value == null) return '';
  if (value is Timestamp) {
    final d = value.toDate();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
  if (value is DateTime) {
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  }
  return value.toString();
}

class Expense {
  final String? id;
  final String name;
  final String description;
  final String date;
  final String category;
  final double amount;
  final String? createdAt;

  const Expense({
    this.id,
    required this.name,
    this.description = '',
    this.date = '',
    required this.category,
    required this.amount,
    this.createdAt,
  });

  factory Expense.fromMap(Map<String, dynamic> data, {String? id}) {
    return Expense(
      id: id ?? data['id'],
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      date: _expenseDateToString(data['date']),
      category: data['category'] ?? '',
      amount: (data['amount'] ?? 0).toDouble(),
      createdAt: data['createdAt']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'description': description,
      'date': date,
      'category': category,
      'amount': amount,
      if (createdAt != null) 'createdAt': createdAt,
    };
  }
}
