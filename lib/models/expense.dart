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
      date: data['date'] ?? '',
      category: data['category'] ?? '',
      amount: (data['amount'] ?? 0).toDouble(),
      createdAt: data['createdAt'],
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
