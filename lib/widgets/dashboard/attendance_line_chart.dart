import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers.dart';
import '../../services/auth_service.dart';
import '../../utils/chart_utils.dart';
import '../custom_timeframe_dropdown.dart';

int _labelStepFor(int count) {
  if (count <= 12) return 1;
  if (count <= 24) return 2;
  if (count <= 32) return 5;
  if (count <= 40) return 7;
  return 10;
}

LineTouchTooltipData buildAttendanceTooltipData(NumberFormat numberFmt) {
  return LineTouchTooltipData(
    getTooltipColor: (spot) => const Color(0xFF2C3E50),
    tooltipBorderRadius: const BorderRadius.all(Radius.circular(8)),
    fitInsideHorizontally: true,
    fitInsideVertically: true,
    getTooltipItems: (spots) {
      return spots.map((spot) {
        final isPresent = spot.bar.color == const Color(0xFF97FFA9);
        final label = isPresent ? 'Present' : 'Absent';
        final color = isPresent
            ? const Color(0xFF97FFA9)
            : const Color(0xFFE74C3C);

        return LineTooltipItem(
          '$label: ${numberFmt.format(spot.y)}',
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
      }).toList();
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
  void didUpdateWidget(covariant AttendanceLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.period != oldWidget.period) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // Count each worker once in every visible chart bucket. This preserves all
    // months in "This Year" while ensuring an updated Present status replaces
    // a stale Absent status for the same worker and month.
    final latestAttendanceDocs = latestAttendanceRecordPerWorker(
      widget.attendanceDocs,
      period: widget.period,
    );

    // Filter present attendance records
    final presentAttendanceDocs = latestAttendanceDocs.where((attendance) {
      final status = (attendance['status'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      return status == 'present';
    }).toList();

    // Filter absent attendance records
    final absentAttendanceDocs = latestAttendanceDocs.where((attendance) {
      final status = (attendance['status'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      return status == 'absent';
    }).toList();

    // Get chart data for present
    final presentChartData = getChartData(
      widget.period,
      presentAttendanceDocs,
      _authService.currentUser?.isAnonymous ?? false,
      context.locale.toString(),
    );

    // Get chart data for absent
    final absentChartData = getChartData(
      widget.period,
      absentAttendanceDocs,
      false,
      context.locale.toString(),
    );

    // Show absent line whenever there is absent data.
    final hasAbsentData =
        absentAttendanceDocs.isNotEmpty &&
        absentChartData.values.any((value) => value > 0);

    return Card(
      elevation: 0,
      color: const Color(0xFFFFFFFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: !widget.isEmpty
            ? Column(
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
                  const SizedBox(height: 30),
                  SizedBox(
                    height: 330,
                    child: Builder(
                      builder: (context) {
                        // Localized number format for axis/tooltip values
                        final numberFmt = NumberFormat.decimalPattern(
                          context.locale.toString(),
                        );

                        // Calculate max Y for both datasets
                        final allValues = [
                          ...presentChartData.values,
                          ...absentChartData.values,
                        ];
                        final double rawMaxY = allValues.isEmpty
                            ? 1.0
                            : allValues.reduce((a, b) => a > b ? a : b);

                        final range = getNiceRange(rawMaxY);

                        final presentSpots = List.generate(
                          presentChartData.values.length,
                          (i) =>
                              FlSpot(i.toDouble(), presentChartData.values[i]),
                        );

                        final absentSpots = List.generate(
                          absentChartData.values.length,
                          (i) =>
                              FlSpot(i.toDouble(), absentChartData.values[i]),
                        );

                        return TweenAnimationBuilder<double>(
                          key: ValueKey(widget.period),
                          tween: Tween(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 750),
                          curve: Curves.easeOutQuart,
                          builder: (context, animValue, child) {
                            return Padding(
                              padding: const EdgeInsets.only(
                                right: 20.0,
                                top: 4.0,
                                bottom: 2.0,
                              ),
                              child: LineChart(
                                LineChartData(
                                  minX: -0.4,
                                  maxX:
                                      (presentSpots.length - 1).toDouble() +
                                      0.4,
                                  clipData: const FlClipData.none(),
                                  minY: 0,
                                  maxY: range.maxY,
                                  lineTouchData: LineTouchData(
                                    touchTooltipData:
                                        buildAttendanceTooltipData(numberFmt),
                                    touchSpotThreshold: 10,
                                    handleBuiltInTouches: true,
                                  ),
                                  gridData: FlGridData(
                                    show: true,
                                    drawHorizontalLine: false,
                                    drawVerticalLine: true,
                                    verticalInterval: 1,
                                    checkToShowVerticalLine: (value) {
                                      if ((value - value.round()).abs() >=
                                          0.01) {
                                        return false;
                                      }

                                      final idx = value.round();
                                      final labelStep = _labelStepFor(
                                        presentChartData.labels.length,
                                      );
                                      return idx % labelStep == 0;
                                    },
                                    getDrawingVerticalLine: (value) => FlLine(
                                      color: Colors.black.withValues(
                                        alpha: 0.12,
                                      ),
                                      strokeWidth: 1,
                                    ),
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
                                        reservedSize: 48,
                                        interval: range.interval,
                                        getTitlesWidget: (value, meta) {
                                          const style = TextStyle(
                                            color: Color(0xFF0247C4),
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'SF Pro Display',
                                          );
                                          if (value < 0 || value > range.maxY) {
                                            return const SizedBox.shrink();
                                          }
                                          return SideTitleWidget(
                                            meta: meta,
                                            space: 8,
                                            child: Text(
                                              numberFmt.format(value.toInt()),
                                              style: style,
                                              textAlign: TextAlign.right,
                                              maxLines: 1,
                                              softWrap: false,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 40,
                                        interval: 1,
                                        getTitlesWidget: (value, meta) {
                                          if ((value - value.round()).abs() >
                                              0.01) {
                                            return const SizedBox.shrink();
                                          }
                                          final idx = value.round();
                                          if (idx < 0 ||
                                              idx >=
                                                  presentChartData
                                                      .labels
                                                      .length) {
                                            return const SizedBox.shrink();
                                          }

                                          final labelStep = _labelStepFor(
                                            presentChartData.labels.length,
                                          );
                                          if (idx % labelStep != 0 &&
                                              idx !=
                                                  presentChartData
                                                          .labels
                                                          .length -
                                                      1) {
                                            return const SizedBox.shrink();
                                          }
                                          final style = TextStyle(
                                            color: const Color(0xFF0247C4),
                                            fontSize:
                                                presentChartData
                                                        .labels
                                                        .length >=
                                                    10
                                                ? 11
                                                : 13,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'SF Pro Display',
                                          );
                                          return SideTitleWidget(
                                            meta: meta,
                                            space: 0,
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  width: 2,
                                                  height: 8,
                                                  color: const Color(
                                                    0xFF939393,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  presentChartData.labels[idx],
                                                  style: style,
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
                                      bottom: BorderSide(
                                        color: Color(0xFF939393),
                                        width: 1,
                                      ),
                                      left: BorderSide(
                                        color: Color(0xFF939393),
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  lineBarsData: [
                                    ..._buildVisibleBars(
                                      presentSpots,
                                      animValue,
                                      lineColor: const Color(0xFF97FFA9),
                                      fillColor: const Color(0xFFDCFCE7),
                                    ),
                                    if (hasAbsentData)
                                      ..._buildVisibleBars(
                                        absentSpots,
                                        animValue,
                                        lineColor: const Color(0xFFE74C3C),
                                        fillColor: const Color(0xFFFADBD8),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  // Legend
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildLegendItem(const Color(0xFF97FFA9), 'Present'),
                      const SizedBox(width: 30),
                      if (hasAbsentData)
                        _buildLegendItem(const Color(0xFFE74C3C), 'Absent'),
                    ],
                  ),
                ],
              )
            : SizedBox(
                height: 430,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.bar_chart,
                        size: 50,
                        color: Color(0xFF9CA3AF),
                      ),
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
              ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(width: 20, height: 4, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ],
    );
  }

  List<LineChartBarData> _buildVisibleBars(
    List<FlSpot> spots,
    double animValue, {
    required Color lineColor,
    required Color fillColor,
  }) {
    final bars = <LineChartBarData>[];
    var index = 0;

    while (index < spots.length) {
      while (index < spots.length && spots[index].y <= 0) {
        index++;
      }
      if (index >= spots.length) break;

      final firstPositive = index;
      while (index + 1 < spots.length && spots[index + 1].y > 0) {
        index++;
      }
      final lastPositive = index;
      final start = firstPositive > 0 ? firstPositive - 1 : firstPositive;
      final end = lastPositive + 1 < spots.length
          ? lastPositive + 1
          : lastPositive;
      final rawVisibleSpots = spots
          .sublist(start, end + 1)
          .map((spot) => FlSpot(spot.x, spot.y * animValue))
          .toList();
      final visibleSpots = <FlSpot>[];
      for (final spot in rawVisibleSpots) {
        final repeatsPreviousValue =
            spot.y > 0 &&
            visibleSpots.isNotEmpty &&
            visibleSpots.last.y > 0 &&
            (visibleSpots.last.y - spot.y).abs() < 0.0001;
        if (repeatsPreviousValue) {
          // Keep the latest bucket when consecutive months have the same
          // value, so one count is represented by one visible peak/dot.
          visibleSpots[visibleSpots.length - 1] = spot;
        } else {
          visibleSpots.add(spot);
        }
      }

      bars.add(
        LineChartBarData(
          spots: visibleSpots,
          isCurved: false,
          color: lineColor,
          barWidth: 2,
          dotData: FlDotData(
            show: true,
            checkToShowDot: (spot, barData) => spot.y > 0,
            getDotPainter: (spot, percent, barData, index) {
              return FlDotCirclePainter(
                radius: 4,
                color: lineColor,
                strokeWidth: 0,
              );
            },
          ),
          belowBarData: BarAreaData(show: true, color: fillColor),
        ),
      );
      index++;
    }

    return bars;
  }
}
