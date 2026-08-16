import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:easy_localization/easy_localization.dart';
import 'rounded_donut_chart.dart';

class TotalWorkersCard extends StatelessWidget {
  final int count;
  final int maleCount;
  final int femaleCount;
  final int otherCount;
  const TotalWorkersCard({
    super.key,
    required this.count,
    required this.maleCount,
    required this.femaleCount,
    required this.otherCount,
  });

  @override
  Widget build(BuildContext context) {
    final double malePercent = count > 0 ? (maleCount / count) : 0.0;
    final double femalePercent = count > 0 ? (femaleCount / count) : 0.0;
    final double otherPercent = count > 0 ? (otherCount / count) : 0.0;
    final String malePercentStr = '${(malePercent * 100).toStringAsFixed(0)}%';
    final String femalePercentStr =
        '${(femalePercent * 100).toStringAsFixed(0)}%';
    final String otherPercentStr =
        '${(otherPercent * 100).toStringAsFixed(0)}%';

    return Card(
      elevation: 0,
      color: const Color(0xFFFFFFFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: count > 0
            ? Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SvgPicture.asset(
                          'assets/workers_icon_slidebar.svg',
                          height: 20,
                          width: 20,
                          colorFilter: const ColorFilter.mode(
                            Color(0xFF155ED5),
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'total_workers'.tr(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$count',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          fontFamily: 'SF Pro Display',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final chartSize = constraints.maxHeight
                            .clamp(96.0, 122.0)
                            .toDouble();
                        final availableLegendWidth =
                            constraints.maxWidth - chartSize - 14;
                        final legendWidth = availableLegendWidth
                            .clamp(0.0, 168.0)
                            .toDouble();
                        return Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox.square(
                                dimension: chartSize,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    RoundedDonutChart(
                                      malePercent: malePercent,
                                      femalePercent: femalePercent,
                                      otherPercent: otherPercent,
                                      size: chartSize,
                                      strokeWidth: 20,
                                    ),
                                    MediaQuery(
                                      data: MediaQuery.of(context).copyWith(
                                        textScaler: const TextScaler.linear(1),
                                      ),
                                      child: Text(
                                        'gender'.tr(),
                                        maxLines: 1,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0F172A),
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),
                              SizedBox(
                                width: legendWidth,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    buildLegendItem(
                                      const Color(0xFF155ED5),
                                      'male'.tr(),
                                      malePercentStr,
                                      'workers_count'.tr(
                                        namedArgs: {
                                          'count': maleCount.toString(),
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    buildLegendItem(
                                      const Color(0xFFFF2D2D),
                                      'female'.tr(),
                                      femalePercentStr,
                                      'workers_count'.tr(
                                        namedArgs: {
                                          'count': femaleCount.toString(),
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    buildLegendItem(
                                      const Color(0xFF8B5CF6),
                                      'other'.tr(),
                                      otherPercentStr,
                                      'workers_count'.tr(
                                        namedArgs: {
                                          'count': otherCount.toString(),
                                        },
                                      ),
                                    ),
                                  ],
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
                    SvgPicture.asset(
                      'assets/total_workers.svg',
                      height: 40,
                      width: 40,
                      colorFilter: const ColorFilter.mode(
                        Color(0xFF9CA3AF),
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'no_workers_added_yet'.tr(),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9CA3AF),
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  static Widget buildLegendItem(
    Color color,
    String title,
    String percent,
    String subtitle,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        fontFamily: 'SF Pro Display',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    percent,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: Color(0xFF334155),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ],
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                  fontFamily: 'SF Pro Display',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
