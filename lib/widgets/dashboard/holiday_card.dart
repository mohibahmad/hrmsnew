import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class HolidayCard extends StatelessWidget {
  final String day;
  final String month;
  final String remainingDays;
  final String dayOfWeek;
  final String holidayName;
  final bool isActive;

  const HolidayCard({
    super.key,
    required this.day,
    required this.month,
    required this.remainingDays,
    required this.dayOfWeek,
    required this.holidayName,
    this.isActive = false,
  });

  static String _localizeMonth(String month) {
    switch (month) {
      case 'January':
        return 'month_january'.tr();
      case 'February':
        return 'month_february'.tr();
      case 'March':
        return 'month_march'.tr();
      case 'April':
        return 'month_april'.tr();
      case 'May':
        return 'month_may'.tr();
      case 'June':
        return 'month_june'.tr();
      case 'July':
        return 'month_july'.tr();
      case 'August':
        return 'month_august'.tr();
      case 'September':
        return 'month_september'.tr();
      case 'October':
        return 'month_october'.tr();
      case 'November':
        return 'month_november'.tr();
      case 'December':
        return 'month_december'.tr();
      default:
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

    final bool isFriday = dayOfWeek == 'Friday';
    Color leftBg = isFriday
        ? const Color(0xFF4AC000)
        : (isActive ? activeLeftBg : inactiveLeftBg);
    Color rightBg = isFriday
        ? const Color(0xFF45B800)
        : (isActive ? activeRightBg : inactiveRightBg);
    Color mainTextColor = isFriday || isActive
        ? activeTextColor
        : inactiveTextColor;
    Color subTextColor = isFriday || isActive
        ? activeSubTextColor
        : inactiveSubTextColor;
    Color badgeBg = isFriday
        ? const Color(0xFF4AC000)
        : (isActive ? activeBadgeBg : inactiveBadgeBg);

    return Container(
      height: 115,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          Container(
            width: 50,
            color: leftBg,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  day,
                  style: TextStyle(
                    color: mainTextColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'SF Pro Display',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  _localizeMonth(month),
                  style: TextStyle(
                    color: mainTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'SF Pro Display',
                  ),
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
                    holidayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mainTextColor,
                      fontSize: 13,
                      height: 1.1,
                      fontWeight: FontWeight.w500,
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
