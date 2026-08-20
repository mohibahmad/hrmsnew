import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:hrms/core/utils/helpers.dart';

class HolidayCard extends StatelessWidget {
  final String day;
  final String month;
  final String remainingDays;
  final String dayOfWeek;
  final List<String> holidayNames;
  final bool isActive;

  const HolidayCard({
    super.key,
    required this.day,
    required this.month,
    required this.remainingDays,
    required this.dayOfWeek,
    required this.holidayNames,
    this.isActive = false,
  });

  static String _localizeMonth(String month, String locale) {
    final index = LocalizationHelper.englishMonthNames.indexOf(month);
    if (index < 1) return month;
    try {
      return DateFormat('MMM', locale).format(DateTime(2000, index));
    } catch (_) {
      return month;
    }
  }

  static String _localizeDayOfWeek(String day) =>
      LocalizationHelper.localizeWeekday(day);

  @override
  Widget build(BuildContext context) {
    const Color activeLeftBg = Color(0xFFFF5F65);
    const Color activeRightBg = Color(0xFFFF000A);
    const Color activeTextColor = Color(0xFFFFFFFF);
    final Color activeSubTextColor = const Color(
      0xFFFFFFFF,
    ).withValues(alpha: 0.9);
    const Color activeBadgeBg = Color(0xFFFF5F65);

    const Color inactiveLeftBg = Color(0xFFE2E4E4);
    const Color inactiveRightBg = Color(0xFFF1F1F1);
    const Color inactiveTextColor = Color(0xFF000000);
    const Color inactiveSubTextColor = Colors.black;
    const Color inactiveBadgeBg = Color(0xFF4C84E0);

    Color leftBg = isActive ? activeLeftBg : inactiveLeftBg;
    Color rightBg = isActive ? activeRightBg : inactiveRightBg;
    Color mainTextColor = isActive ? activeTextColor : inactiveTextColor;
    Color subTextColor = isActive ? activeSubTextColor : inactiveSubTextColor;
    Color badgeBg = isActive ? activeBadgeBg : inactiveBadgeBg;

    String cleanHolidayName(String name) =>
        name.replaceAll(RegExp(r'[\s-]*\(\d{4}\)'), '');
    final cleanedHolidayNames = holidayNames
        .map((n) => LocalizationHelper.localizeHolidayName(cleanHolidayName(n)))
        .join(', ');

    return Container(
      height: 115,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          Container(
            width: 65,
            color: leftBg,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  day,
                  style: TextStyle(
                    color: mainTextColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _localizeMonth(month, context.locale.toString()),
                  style: TextStyle(
                    color: mainTextColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: rightBg,
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'remaining_days'.tr(),
                          style: TextStyle(
                            color: subTextColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 1.0,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 30,
                        child: Text(
                          remainingDays,
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                            color: mainTextColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _localizeDayOfWeek(dayOfWeek),
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    cleanedHolidayNames,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mainTextColor,
                      fontSize: 13,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
