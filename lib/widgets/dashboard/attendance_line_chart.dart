import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../utils/chart_utils.dart';
import '../custom_timeframe_dropdown.dart';

class AttendanceLineChart extends StatefulWidget {
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
  State<AttendanceLineChart> createState() => _AttendanceLineChartState();
}

class _AttendanceLineChartState extends State<AttendanceLineChart> {
  late AuthService _authService;

  @override
  void initState() {
    super.initState();
    _authService = Provider.of<AuthService>(context, listen: false);
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
    return Card(
      elevation: 0,
      color: Color(0xFFFFFFFF),
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
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    height: 330,
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey(widget.period),
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 750),
                      curve: Curves.easeOutQuart,
                      builder: (context, animValue, child) {
                        final chartData = getChartData(
                          widget.period,
                          widget.attendanceDocs,
                          _authService.currentUser?.isAnonymous ?? false,
                          context.locale.toString(),
                        );
                        final double rawMaxY = chartData.values.isEmpty
                            ? 1.0
                            : chartData.values.reduce((a, b) => a > b ? a : b);
                        final range = getNiceRange(rawMaxY);
                        final spots = List.generate(
                          chartData.values.length,
                          (i) => FlSpot(i.toDouble(), chartData.values[i]),
                        );

                        return Padding(
                          padding: const EdgeInsets.only(
                            right: 20.0,
                            top: 4.0,
                            bottom: 2.0,
                          ),
                          child: LineChart(
                            LineChartData(
                              minX: -0.4,
                              maxX: (spots.length - 1).toDouble() + 0.4,
                              minY: 0,
                              maxY: range.maxY,
                              lineTouchData: LineTouchData(
                                touchTooltipData: LineTouchTooltipData(
                                  getTooltipColor: (spot) =>
                                      const Color(0xFF2C3E50),
                                  tooltipBorderRadius: const BorderRadius.all(
                                    Radius.circular(8),
                                  ),
                                  getTooltipItems: (spots) {
                                    return spots.map((spot) {
                                      return LineTooltipItem(
                                        spot.y.toStringAsFixed(0),
                                        const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      );
                                    }).toList();
                                  },
                                ),
                              ),
                              gridData: FlGridData(
                                show: true,
                                drawHorizontalLine: false,
                                drawVerticalLine: true,
                                verticalInterval: 1,
                                checkToShowVerticalLine: (value) {
                                  return (value - value.round()).abs() < 0.01;
                                },
                                getDrawingVerticalLine: (value) => FlLine(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  strokeWidth: 1,
                                ),
                              ),
                              titlesData: FlTitlesData(
                                topTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                rightTitles: AxisTitles(
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
                                          value.toInt().toString(),
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
                                          idx >= chartData.labels.length) {
                                        return const SizedBox.shrink();
                                      }
                                      const style = TextStyle(
                                        color: Color(0xFF0247C4),
                                        fontSize: 13,
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
                                              color: const Color(0xFF939393),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              chartData.labels[idx],
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
                                LineChartBarData(
                                  spots: spots
                                      .map((s) => FlSpot(s.x, s.y * animValue))
                                      .toList(),
                                  isCurved: false,
                                  color: const Color(0xFF21367E),
                                  barWidth: 2,
                                  dotData: FlDotData(
                                    show: true,
                                    getDotPainter:
                                        (spot, percent, barData, index) {
                                          return FlDotCirclePainter(
                                            radius: 4,
                                            color: const Color(0xFF21367E),
                                            strokeWidth: 0,
                                          );
                                        },
                                  ),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: const Color(0xFFDEE6FF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
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
                        style: TextStyle(
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
}
