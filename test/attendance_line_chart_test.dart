import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/widgets/dashboard/attendance_line_chart.dart';
import 'package:intl/intl.dart';

void main() {
  test('attendance bar tooltip stays inside the chart bounds', () {
    final tooltipData = buildAttendanceBarTooltipData(
      NumberFormat.decimalPattern('en'),
    );

    expect(tooltipData.fitInsideHorizontally, isTrue);
    expect(tooltipData.fitInsideVertically, isTrue);
  });

  test('attendance tooltip identifies an absent rod by its color', () {
    final tooltipData = buildAttendanceBarTooltipData(
      NumberFormat.decimalPattern('en'),
    );
    final group = BarChartGroupData(
      x: 0,
      barRods: [BarChartRodData(toY: 1, color: const Color(0xFFF13E5B))],
    );

    final item = tooltipData.getTooltipItem(group, 0, group.barRods.single, 0);

    expect(item?.text, 'Absent: 1');
  });
}
