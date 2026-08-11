import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/widgets/dashboard/leave_types_pie_chart.dart';

void main() {
  test('displayed leave percentages always add up to 100', () {
    final percentages = calculateRoundedLeavePercentages(const [
      MapEntry('Casual Leave', 119),
      MapEntry('Sick Leave', 43),
      MapEntry('Medical Leave', 21),
      MapEntry('Annual Leave', 17),
    ], 200);

    expect(percentages.values.reduce((a, b) => a + b), 100);
    expect(percentages, {
      'Casual Leave': 60,
      'Sick Leave': 22,
      'Medical Leave': 10,
      'Annual Leave': 8,
    });
  });

  test('equal leave counts are rounded deterministically', () {
    final percentages = calculateRoundedLeavePercentages(const [
      MapEntry('Casual Leave', 1),
      MapEntry('Sick Leave', 1),
      MapEntry('Medical Leave', 1),
    ], 3);

    expect(percentages, {
      'Casual Leave': 34,
      'Sick Leave': 33,
      'Medical Leave': 33,
    });
  });
}
