import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../utils/localization_helper.dart';

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

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static String _localizeMonth(String month, String locale) {
    final index = _monthNames.indexOf(month) + 1;
    if (index < 1) return month;
    try {
      return DateFormat('MMM', locale).format(DateTime(2000, index));
    } catch (_) {
      return month;
    }
  }

  static String _localizeDayOfWeek(String day) {
    switch (day) {
      case 'Monday':
        return 'weekday_monday'.tr();
      case 'Tuesday':
        return 'weekday_tuesday'.tr();
      case 'Wednesday':
        return 'weekday_wednesday'.tr();
      case 'Thursday':
        return 'weekday_thursday'.tr();
      case 'Friday':
        return 'weekday_friday'.tr();
      case 'Saturday':
        return 'weekday_saturday'.tr();
      case 'Sunday':
        return 'weekday_sunday'.tr();
      default:
        return day;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color activeLeftBg = const Color(0xFFFF5F65);
    final Color activeRightBg = const Color(0xFFFF000A);
    final Color activeTextColor = Color(0xFFFFFFFF);
    final Color activeSubTextColor = Color(0xFFFFFFFF).withValues(alpha: 0.9);
    final Color activeBadgeBg = const Color(0xFFFF5F65);

    final Color inactiveLeftBg = const Color(0xFFE2E4E4);
    final Color inactiveRightBg = const Color(0xFFF1F1F1);
    final Color inactiveTextColor = Color(0xFF000000);
    final Color inactiveSubTextColor = Colors.black;
    final Color inactiveBadgeBg = const Color(0xFF4C84E0);

    Color leftBg = isActive ? activeLeftBg : inactiveLeftBg;
    Color rightBg = isActive ? activeRightBg : inactiveRightBg;
    Color mainTextColor = isActive ? activeTextColor : inactiveTextColor;
    Color subTextColor = isActive ? activeSubTextColor : inactiveSubTextColor;
    Color badgeBg = isActive ? activeBadgeBg : inactiveBadgeBg;

    // Removes any 4-digit year wrapped in parentheses (e.g. "(2026)") so it
    // does not show after the holiday name and does not break localization.
    String cleanHolidayName(String name) => name.replaceAll(
      RegExp(r'[\s-]*\(\d{4}\)'),
      '',
    );
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
                    fontFamily: 'SF Pro Display',
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
                    fontFamily: 'SF Pro Display',
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
                            fontFamily: 'SF Pro Display',
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
                            fontFamily: 'SF Pro Display',
                            height: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const SizedBox(height: 2),
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
                        fontFamily: 'SF Pro Display',
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
                      fontFamily: 'SF Pro Display',
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
