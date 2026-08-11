import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../services/auth_service.dart';
import '../../utils/chart_utils.dart';
import '../custom_timeframe_dropdown.dart';

const _presentColor = Color(0xFF16B887);
const _absentColor = Color(0xFFF13E5B);

int _labelStepFor(int count) {
  if (count <= 12) return 1;
  if (count <= 24) return 2;
  if (count <= 32) return 5;
  if (count <= 40) return 7;
  return 10;
}

BarTouchTooltipData buildAttendanceBarTooltipData(NumberFormat numberFmt) {
  return BarTouchTooltipData(
    getTooltipColor: (_) => const Color(0xFF2C3E50),
    tooltipBorderRadius: const BorderRadius.all(Radius.circular(8)),
    fitInsideHorizontally: true,
    fitInsideVertically: true,
    getTooltipItem: (group, groupIndex, rod, rodIndex) {
      final isPresent = rodIndex == 0;
      final color = isPresent ? _presentColor : _absentColor;
      return BarTooltipItem(
        '${isPresent ? 'Present' : 'Absent'}: ${numberFmt.format(rod.toY)}',
        const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
          fontFamily: 'SF Pro Display',
        ),
        children: [
          TextSpan(
            text: ' ',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      );
    },
  );
}

class AttendanceLineChart extends ConsumerStatefulWidget {
  final String period;
  final bool isEmpty;
  final List<Map<String, dynamic>> attendanceDocs;

  const AttendanceLineChart({
    super.key,
    required this.period,
    this.isEmpty = false,
    this.attendanceDocs = const [],
  });

  @override
  ConsumerState<AttendanceLineChart> createState() =>
      _AttendanceLineChartState();
}

class _AttendanceLineChartState extends ConsumerState<AttendanceLineChart> {
  late AuthService _authService;

  @override
  void initState() {
    super.initState();
    _authService = ref.read(authServiceProvider);
  }

  @override
  Widget build(BuildContext context) {
    final latestAttendanceDocs = latestAttendanceRecordPerWorker(
      widget.attendanceDocs,
      period: widget.period,
    );
    final presentAttendanceDocs = _forStatus(latestAttendanceDocs, 'present');
    final absentAttendanceDocs = _forStatus(latestAttendanceDocs, 'absent');
    final locale = context.locale.toString();

    final presentChartData = getChartData(
      widget.period,
      presentAttendanceDocs,
      _authService.currentUser?.isAnonymous ?? false,
      locale,
    );
    final absentChartData = getChartData(
      widget.period,
      absentAttendanceDocs,
      false,
      locale,
    );
    final hasAbsentData =
        absentAttendanceDocs.isNotEmpty &&
        absentChartData.values.any((value) => value > 0);

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: widget.isEmpty
            ? _buildEmptyState()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    CustomTimeframeDropdown.localizePeriod(widget.period),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 22),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildLegendItem(_presentColor, 'Present'),
                        if (hasAbsentData) ...[
                          const SizedBox(width: 24),
                          _buildLegendItem(_absentColor, 'Absent'),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 330,
                    child: _buildBarChart(
                      presentChartData: presentChartData,
                      absentChartData: absentChartData,
                      hasAbsentData: hasAbsentData,
                      locale: locale,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  List<Map<String, dynamic>> _forStatus(
    List<Map<String, dynamic>> records,
    String status,
  ) {
    return records.where((record) {
      return (record['status'] ?? '').toString().trim().toLowerCase() == status;
    }).toList();
  }

  Widget _buildBarChart({
    required ChartData presentChartData,
    required ChartData absentChartData,
    required bool hasAbsentData,
    required String locale,
  }) {
    final numberFmt = NumberFormat.decimalPattern(locale);
    final allValues = [...presentChartData.values, ...absentChartData.values];
    final rawMaxY = allValues.isEmpty
        ? 1.0
        : allValues.reduce((a, b) => a > b ? a : b);
    final range = getNiceRange(rawMaxY);
    final labelStep = _labelStepFor(presentChartData.labels.length);

    return TweenAnimationBuilder<double>(
      key: ValueKey(widget.period),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 750),
      curve: Curves.easeOutQuart,
      builder: (context, animation, child) {
        return BarChart(
          BarChartData(
            minY: 0,
            maxY: range.maxY,
            alignment: BarChartAlignment.spaceAround,
            groupsSpace: 18,
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: buildAttendanceBarTooltipData(numberFmt),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: range.interval,
              getDrawingHorizontalLine: (value) =>
                  const FlLine(color: Color(0xFFE6EFEC), strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 42,
                  interval: range.interval,
                  getTitlesWidget: (value, meta) {
                    if (value < 0 || value > range.maxY) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      space: 8,
                      child: Text(
                        numberFmt.format(value.toInt()),
                        style: const TextStyle(
                          color: Color(0xFF65717E),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 38,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= presentChartData.labels.length) {
                      return const SizedBox.shrink();
                    }
                    if (index % labelStep != 0 &&
                        index != presentChartData.labels.length - 1) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      space: 10,
                      child: Text(
                        presentChartData.labels[index],
                        style: TextStyle(
                          color: const Color(0xFF65717E),
                          fontSize: presentChartData.labels.length >= 10
                              ? 10
                              : 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            barGroups: List.generate(presentChartData.values.length, (index) {
              final present = presentChartData.values[index] * animation;
              final absent = absentChartData.values[index] * animation;
              return BarChartGroupData(
                x: index,
                barsSpace: 7,
                barRods: [
                  _buildRod(present, _presentColor),
                  if (hasAbsentData) _buildRod(absent, _absentColor),
                ],
              );
            }),
          ),
          duration: Duration.zero,
        );
      },
    );
  }

  BarChartRodData _buildRod(double value, Color color) {
    return BarChartRodData(
      toY: value,
      color: color,
      width: 12,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
    );
  }

  Widget _buildEmptyState() {
    return SizedBox(
      height: 430,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bar_chart, size: 50, color: Color(0xFF9CA3AF)),
            const SizedBox(height: 12),
            Text(
              'no_attendance_data_yet'.tr(),
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF9CA3AF),
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF65717E),
            fontWeight: FontWeight.w600,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ],
    );
  }
}
