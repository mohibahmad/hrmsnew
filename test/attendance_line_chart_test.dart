import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/widgets/dashboard/attendance_line_chart.dart';
import 'package:intl/intl.dart';

void main() {
  test('attendance tooltip stays inside the chart bounds', () {
    final tooltipData = buildAttendanceTooltipData(NumberFormat.decimalPattern('en'));

    expect(tooltipData.fitInsideHorizontally, isTrue);
    expect(tooltipData.fitInsideVertically, isTrue);
  });
}
