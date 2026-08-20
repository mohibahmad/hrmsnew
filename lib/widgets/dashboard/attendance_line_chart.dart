import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../utils/utils.dart';
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
      final isPresent = rod.color == _presentColor;
      return BarTooltipItem(
        '${isPresent ? 'present'.tr() : 'absent'.tr()}: ${numberFmt.format(rod.toY)}',
        const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      );
    },
  );
}

class AttendanceLineChart extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final dedupedDocs = latestAttendanceRecordPerWorker(
      attendanceDocs,
      period: period,
    );
    final presentAttendanceDocs = attendanceRecordsForStatus(
      dedupedDocs,
      'present',
    );
    final absentAttendanceDocs = attendanceRecordsForStatus(
      dedupedDocs,
      'absent',
    );
    final locale = context.locale.toString();

    final presentChartData = getChartData(
      period,
      presentAttendanceDocs,
      locale,
    );
    final absentChartData = getChartData(
      period,
      absentAttendanceDocs,
      locale,
    );
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: isEmpty
            ? _buildEmptyState()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    CustomTimeframeDropdown.localizePeriod(period),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildLegendItem(_presentColor, 'present'.tr()),
                        const SizedBox(width: 24),
                        _buildLegendItem(_absentColor, 'absent'.tr()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 330,
                    child: _buildBarChart(
                      presentChartData: presentChartData,
                      absentChartData: absentChartData,
                      locale: locale,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildBarChart({
    required ChartData presentChartData,
    required ChartData absentChartData,
    required String locale,
  }) {
    final numberFmt = NumberFormat.decimalPattern(locale);
    final allValues = [...presentChartData.values, ...absentChartData.values];
    final rawMaxY = allValues.isEmpty
        ? 1.0
        : allValues.reduce((a, b) => a > b ? a : b);
    final range = getNiceRange(rawMaxY);

    final chartMaxY = rawMaxY > 0 && (rawMaxY / range.maxY) > 0.8
        ? ((rawMaxY / 0.8) / range.interval).ceil() * range.interval
        : range.maxY;
    final labelStep = _labelStepFor(presentChartData.labels.length);

    return TweenAnimationBuilder<double>(
      key: ValueKey(period),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 750),
      curve: Curves.easeOutQuart,
      builder: (context, animation, child) {
        return BarChart(
          BarChartData(
            minY: 0,
            maxY: chartMaxY,
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
                        ),
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 48,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    if ((value - value.round()).abs() > 0.001) {
                      return const SizedBox.shrink();
                    }
                    final index = value.round();
                    if (index < 0 || index >= presentChartData.labels.length) {
                      return const SizedBox.shrink();
                    }
                    if (index % labelStep != 0 &&
                        index != presentChartData.labels.length - 1) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      space: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 2,
                            height: 8,
                            color: const Color(0xFF9AA1A8),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            presentChartData.labels[index],
                            style: TextStyle(
                              color: const Color(0xFF65717E),
                              fontSize: presentChartData.labels.length >= 10
                                  ? 11.5
                                  : 13,
                              letterSpacing: 0.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(
              show: true,
              border: const Border(
                bottom: BorderSide(color: Color(0xFF9AA1A8), width: 1),
              ),
            ),
            barGroups: List.generate(presentChartData.values.length, (index) {
              final present = presentChartData.values[index] * animation;
              final absent = absentChartData.values[index] * animation;
              final rods = <BarChartRodData>[
                if (present > 0) _buildRod(present, _presentColor),
                if (absent > 0) _buildRod(absent, _absentColor),
              ];
              return BarChartGroupData(x: index, barsSpace: 7, barRods: rods);
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
      width: 18,
      borderRadius: BorderRadius.zero,
    );
  }

  Widget _buildEmptyState() {
    return SizedBox(
      height: 430,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bar_chart, size: 50, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              'no_attendance_data_yet'.tr(),
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textMuted,
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
            borderRadius: BorderRadius.zero,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF65717E),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
