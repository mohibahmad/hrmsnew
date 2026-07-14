import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import '../custom_timeframe_dropdown.dart';

class SparklineCard extends StatelessWidget {
  final String title;
  final String amount;
  final double rawValue;
  final String period;
  final Color lineColor;

  const SparklineCard({
    super.key,
    required this.title,
    required this.amount,
    required this.rawValue,
    required this.period,
    required this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    final bool isEmpty = amount == '\$0';
    return Card(
      elevation: 0,
      color: Color(0xFFFFFFFF),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: !isEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        flex: 0,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: lineColor == const Color(0xFF4C84E0)
                                  ? SvgPicture.asset(
                                      'assets/total_salary.svg',
                                      height: 20,
                                      width: 20,
                                      colorFilter: const ColorFilter.mode(
                                        Color(0xFF155ED5),
                                        BlendMode.srcIn,
                                      ),
                                    )
                                  : Image.asset(
                                      'assets/expense.png',
                                      height: 20,
                                      width: 20,
                                      color: const Color(0xFF155ED5),
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 18,
                                  fontFamily: 'SF Pro Display',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                                child: Text(
                                  amount,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              period == 'Month'
                                  ? (title == 'expenses'.tr()
                                        ? 'monthly'.tr().toLowerCase()
                                        : 'month'.tr().toLowerCase())
                                  : (period == 'Week'
                                        ? (title == 'expenses'.tr()
                                              ? 'weekly'.tr().toLowerCase()
                                              : 'week'.tr().toLowerCase())
                                        : CustomTimeframeDropdown.localizePeriod(
                                            period,
                                          )),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black,
                                fontFamily: 'SF Pro Display',
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 90,
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(period),
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 650),
                    curve: Curves.easeOutQuart,
                    builder: (context, animValue, child) {
                      final double m = period == 'Week'
                          ? 0.3
                          : period == 'Month'
                          ? 0.6
                          : period == '6 Month'
                          ? 0.9
                          : 1.0;
                      final double scaleFactor =
                          (rawValue > 0 ? rawValue : 1.0) / 7.0;
                      final spots = [
                        FlSpot(0, 3 * m * scaleFactor),
                        FlSpot(1, 6 * m * scaleFactor),
                        FlSpot(2, 4 * m * scaleFactor),
                        FlSpot(3, 4 * m * scaleFactor),
                        FlSpot(4, 7 * m * scaleFactor),
                        FlSpot(5, 5 * m * scaleFactor),
                        FlSpot(6, 6 * m * scaleFactor),
                        FlSpot(7, 2 * m * scaleFactor),
                        FlSpot(8, 7 * m * scaleFactor),
                      ];

                      return LineChart(
                        LineChartData(
                          minX: -0.5,
                          maxX: (spots.length - 1).toDouble() + 0.5,
                          minY: 0,
                          maxY: 13 * scaleFactor,
                          lineTouchData: LineTouchData(
                            touchTooltipData: LineTouchTooltipData(
                              tooltipRoundedRadius: 8,
                              getTooltipItems: (tSpots) {
                                if (tSpots.isEmpty) return <LineTooltipItem>[];
                                final seenX = <double>{};
                                final nf = NumberFormat.currency(
                                  locale: context.locale.toString(),
                                  symbol: '\$ ',
                                  decimalDigits: 0,
                                );
                                return tSpots.map((tSpot) {
                                  if (seenX.add(tSpot.x)) {
                                    final label = nf.format(tSpot.y);
                                    return LineTooltipItem(
                                      label,
                                      const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    );
                                  }
                                  return LineTooltipItem(
                                    '',
                                    const TextStyle(
                                      color: Colors.transparent,
                                      fontSize: 0,
                                    ),
                                  );
                                }).toList();
                              },
                            ),
                          ),
                          gridData: FlGridData(show: false),
                          titlesData: FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: spots
                                  .map((s) => FlSpot(s.x, s.y * animValue))
                                  .toList(),
                              isCurved: true,
                              color: lineColor.withValues(alpha: 0.06),
                              barWidth: 1.2,
                              isStrokeCapRound: false,
                              dotData: FlDotData(show: false),
                            ),
                            LineChartBarData(
                              spots: spots
                                  .map((s) => FlSpot(s.x, s.y * animValue))
                                  .toList(),
                              isCurved: true,
                              color: lineColor,
                              barWidth: 0.6,
                              isStrokeCapRound: false,
                              dotData: FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                gradient: LinearGradient(
                                  colors: [
                                    lineColor == const Color(0xFF0EA5E9)
                                        ? const Color(
                                            0xFF93D7FD,
                                          ).withValues(alpha: 0.50)
                                        : const Color(
                                            0xFF8DA9F1,
                                          ).withValues(alpha: 0.50),
                                    lineColor == const Color(0xFF0EA5E9)
                                        ? const Color(
                                            0xFF93D7FD,
                                          ).withValues(alpha: 0.20)
                                        : const Color(
                                            0xFF8DA9F1,
                                          ).withValues(alpha: 0.20),
                                    lineColor == const Color(0xFF0EA5E9)
                                        ? const Color(
                                            0xFF93D7FD,
                                          ).withValues(alpha: 0.0)
                                        : const Color(
                                            0xFF8DA9F1,
                                          ).withValues(alpha: 0.0),
                                  ],
                                  stops: [0.0, 0.3, 0.8],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  lineColor == const Color(0xFF4C84E0)
                      ? SvgPicture.asset(
                          'assets/total_salary.svg',
                          height: 40,
                          width: 40,
                          colorFilter: const ColorFilter.mode(
                            Color(0xFF9CA3AF),
                            BlendMode.srcIn,
                          ),
                        )
                      : Image.asset(
                          'assets/expense.png',
                          height: 40,
                          width: 40,
                          color: const Color(0xFF9CA3AF),
                        ),
                  const SizedBox(height: 8),
                  Text(
                    lineColor == const Color(0xFF4C84E0)
                        ? 'no_salary_records_yet'.tr()
                        : 'no_expenses_recorded_yet'.tr(),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF9CA3AF),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
