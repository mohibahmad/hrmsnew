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
      createdAt: data['createdAt'],
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
