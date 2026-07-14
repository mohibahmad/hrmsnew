import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:easy_localization/easy_localization.dart';
import 'rounded_donut_chart.dart';

class TotalWorkersCard extends StatelessWidget {
  final int count;
  final int maleCount;
  final int femaleCount;
  const TotalWorkersCard({
    super.key,
    required this.count,
    required this.maleCount,
    required this.femaleCount,
  });

  @override
  Widget build(BuildContext context) {
    final double malePercent = count > 0 ? (maleCount / count) : 0.0;
    final double femalePercent = count > 0 ? (femaleCount / count) : 0.0;
    final String malePercentStr = '${(malePercent * 100).toStringAsFixed(0)}%';
    final String femalePercentStr =
        '${(femalePercent * 100).toStringAsFixed(0)}%';

    return Card(
      elevation: 0,
      color: Color(0xFFFFFFFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: count > 0
            ? Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                              color: const Color(0xFF155ED5),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'total_workers'.tr(),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 18,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ],
                      ),
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
                  const SizedBox(height: 30),
                  Expanded(
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          RoundedDonutChart(
                            malePercent: malePercent,
                            femalePercent: femalePercent,
                          ),
                          MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              textScaler: const TextScaler.linear(1.0),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Transform.translate(
                                  offset: const Offset(6, -9),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        malePercentStr,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF000000),
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                      Text(
                                        'male'.tr(),
                                        style: const TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF000000),
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Transform.rotate(
                                  angle: 0.35,
                                  child: Container(
                                    width: 1.0,
                                    height: 52,
                                    color: const Color(0xFF000000),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Transform.translate(
                                  offset: const Offset(-9, 5),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        femalePercentStr,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF000000),
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                      Text(
                                        'female'.tr(),
                                        style: TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF000000),
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        buildLegendItem(
                          Color(0xFF155ED5),
                          'male'.tr(),
                          'workers_count'.tr(
                            namedArgs: {'count': maleCount.toString()},
                          ),
                        ),
                        buildLegendItem(
                          Color(0xFFFF2D2D),
                          'female'.tr(),
                          'workers_count'.tr(
                            namedArgs: {'count': femaleCount.toString()},
                          ),
                        ),
                      ],
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
                      color: const Color(0xFF9CA3AF),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'no_workers_added_yet'.tr(),
                      style: TextStyle(
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

  static Widget buildLegendItem(Color color, String title, String subtitle) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                fontFamily: 'SF Pro Display',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF000000),
                fontFamily: 'SF Pro Display',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ],
    );
  }
}
