import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../services/dashboard_chart_service.dart';
import '../../utils/app_colors.dart';

class SparklineCard extends StatelessWidget {
  final String title;
  final String amount;
  final double rawValue;
  final List<DashboardChartPoint> points;
  final String period;
  final Color lineColor;
  final String currencySymbol;
  final int tooltipDecimalDigits;

  const SparklineCard({
    super.key,
    required this.title,
    required this.amount,
    required this.rawValue,
    required this.points,
    required this.period,
    required this.lineColor,
    this.currencySymbol = r'$',
    this.tooltipDecimalDigits = 0,
  });

  static String formatTooltipAmount({
    required double value,
    required String locale,
    required String currencySymbol,
    required int maxDecimalDigits,
  }) {
    final safeMaxDigits = maxDecimalDigits.clamp(0, 20);
    var visibleDigits = 0;
    if (safeMaxDigits > 0 && value.isFinite) {
      final fixedValue = value.toStringAsFixed(safeMaxDigits);
      final separatorIndex = fixedValue.indexOf('.');
      if (separatorIndex >= 0) {
        final fraction = fixedValue
            .substring(separatorIndex + 1)
            .replaceFirst(RegExp(r'0+$'), '');
        visibleDigits = fraction.length;
      }
    }
    final symbolSpacing = RegExp(r'[A-Za-z]').hasMatch(currencySymbol)
        ? ' '
        : '';
    return NumberFormat.currency(
      locale: locale,
      symbol: '$currencySymbol$symbolSpacing',
      decimalDigits: visibleDigits,
    ).format(value);
  }

  @override
  Widget build(BuildContext context) {
    final bool isEmpty = rawValue <= 0 || points.isEmpty;
    return Card(
      elevation: 0,
      color: AppColors.white,
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
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                amount,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    height: 100,
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey(period),
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 650),
                      curve: Curves.easeOutQuart,
                      builder: (context, animValue, child) {
                        final spots = points.asMap().entries.map((entry) {
                          return FlSpot(
                            entry.key.toDouble(),
                            entry.value.value,
                          );
                        }).toList();
                        final highestValue = points.fold<double>(0, (
                          highest,
                          p,
                        ) {
                          return p.value > highest ? p.value : highest;
                        });
                        final hasSinglePoint = spots.length == 1;

                        return LineChart(
                          LineChartData(
                            minX: hasSinglePoint ? -0.5 : 0,
                            maxX: hasSinglePoint
                                ? 0.5
                                : (spots.length - 1).toDouble(),
                            minY: 0,
                            maxY: highestValue > 0 ? highestValue * 1.25 : 1,
                            lineTouchData: LineTouchData(
                              touchTooltipData: LineTouchTooltipData(
                                tooltipBorderRadius: const BorderRadius.all(
                                  Radius.circular(8),
                                ),
                                fitInsideHorizontally: true,
                                fitInsideVertically: false,
                                maxContentWidth: 180,
                                tooltipPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                tooltipMargin: 10,
                                getTooltipItems: (tSpots) {
                                  if (tSpots.isEmpty) {
                                    return <LineTooltipItem>[];
                                  }
                                  final seenX = <double>{};
                                  return tSpots.map((tSpot) {
                                    if (seenX.add(tSpot.x)) {
                                      final pointIndex = tSpot.x
                                          .round()
                                          .clamp(0, points.length - 1)
                                          .toInt();
                                      final point = points[pointIndex];
                                      final dateLabel = _dateLabel(
                                        context,
                                        point.date,
                                      );
                                      final formattedAmount =
                                          formatTooltipAmount(
                                            value: point.value,
                                            locale: context.locale.toString(),
                                            currencySymbol: currencySymbol,
                                            maxDecimalDigits:
                                                tooltipDecimalDigits,
                                          );
                                      final label =
                                          '$dateLabel\n$title: $formattedAmount';
                                      return LineTooltipItem(
                                        label,
                                        const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      );
                                    }
                                    return const LineTooltipItem(
                                      '',
                                      TextStyle(
                                        color: Colors.transparent,
                                        fontSize: 0,
                                      ),
                                    );
                                  }).toList();
                                },
                              ),
                            ),
                            gridData: const FlGridData(show: false),
                            titlesData: const FlTitlesData(show: false),
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
                                dotData: const FlDotData(show: false),
                              ),
                              LineChartBarData(
                                spots: spots
                                    .map((s) => FlSpot(s.x, s.y * animValue))
                                    .toList(),
                                isCurved: true,
                                color: lineColor,
                                barWidth: 0.6,
                                isStrokeCapRound: false,
                                dotData: FlDotData(
                                  show: hasSinglePoint,
                                  getDotPainter:
                                      (spot, percent, barData, index) {
                                        return FlDotCirclePainter(
                                          radius: 4,
                                          color: lineColor,
                                          strokeWidth: 0,
                                        );
                                      },
                                ),
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
                                    stops: const [0.0, 0.3, 0.8],
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
                            AppColors.textMuted,
                            BlendMode.srcIn,
                          ),
                        )
                      : Image.asset(
                          'assets/expense.png',
                          height: 40,
                          width: 40,
                          color: AppColors.textMuted,
                        ),
                  const SizedBox(height: 8),
                  Text(
                    lineColor == const Color(0xFF4C84E0)
                        ? 'no_salary_records_yet'.tr()
                        : 'no_expenses_recorded_yet'.tr(),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  String _dateLabel(BuildContext context, DateTime date) {
    final locale = context.locale.toString();
    if (period == 'Today') {
      return DateFormat('MMM d • h a', locale).format(date);
    }
    if (period == 'Week') {
      return DateFormat('EEE, MMM d', locale).format(date);
    }
    if (period == 'Month') {
      return DateFormat('MMM d', locale).format(date);
    }
    return DateFormat('MMMM yyyy', locale).format(date);
  }
}
