import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';

class WeekdayHeaderChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool isExpanded;

  const WeekdayHeaderChip({
    super.key,
    required this.label,
    required this.color,
    this.isExpanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final shortLabel = label.length > 3 ? label.substring(0, 3) : label;
    final chip = Container(
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        shortLabel.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          fontFamily: AppColors.fontFamily,
        ),
      ),
    );

    return isExpanded ? Expanded(child: chip) : chip;
  }
}

class CalendarDayCell extends StatelessWidget {
  final String day;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback? onTap;
  final double cellAspectRatio;

  const CalendarDayCell({
    super.key,
    required this.day,
    this.isSelected = false,
    this.isDisabled = false,
    this.onTap,
    this.cellAspectRatio = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    if (day.isEmpty) {
      return Expanded(
        child: AspectRatio(aspectRatio: cellAspectRatio, child: const SizedBox()),
      );
    }

    const selectedBg = Color(0xFF0247C4);

    return Expanded(
      child: AspectRatio(
        aspectRatio: cellAspectRatio,
        child: GestureDetector(
          onTap: isDisabled ? null : onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? selectedBg : Colors.transparent,
              border: Border.all(
                color: isSelected ? selectedBg : Colors.grey.shade300,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              day,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : isDisabled
                        ? Colors.grey.shade400
                        : Colors.black,
                fontSize: 12,
                fontFamily: AppColors.fontFamily,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CalendarGrid extends StatelessWidget {
  final DateTime date;
  final int? selectedDay;
  final ValueChanged<int> onDaySelected;
  final bool disablePastDays;
  final double spacing;
  final double cellAspectRatio;

  const CalendarGrid({
    super.key,
    required this.date,
    this.selectedDay,
    required this.onDaySelected,
    this.disablePastDays = false,
    this.spacing = 6,
    this.cellAspectRatio = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final daysInMonth = DateTime(date.year, date.month + 1, 0).day;
    final firstWeekday = DateTime(date.year, date.month, 1).weekday;
    final startOffset = firstWeekday == 7 ? 0 : firstWeekday;

    final rows = <Widget>[];
    int currentDay = 1;

    for (int i = 0; i < 6; i++) {
      final rowChildren = <Widget>[];
      for (int j = 0; j < 7; j++) {
        final index = i * 7 + j;
        if (index < startOffset) {
          rowChildren.add(CalendarDayCell(day: '', cellAspectRatio: cellAspectRatio));
        } else if (currentDay <= daysInMonth) {
          final day = currentDay;
          final cellDate = DateTime(date.year, date.month, day);
          final isPast = disablePastDays && cellDate.isBefore(todayDate);
          rowChildren.add(CalendarDayCell(
            day: '$day',
            isSelected: selectedDay != null && day == selectedDay,
            isDisabled: isPast,
            onTap: isPast ? null : () => onDaySelected(day),
            cellAspectRatio: cellAspectRatio,
          ));
          currentDay++;
        } else {
          rowChildren.add(CalendarDayCell(day: '', cellAspectRatio: cellAspectRatio));
        }
        if (j < 6) rowChildren.add(SizedBox(width: spacing));
      }
      rows.add(Row(children: rowChildren));
      if (currentDay > daysInMonth && i >= 4) break;
      if (i < 5) rows.add(SizedBox(height: spacing));
    }

    return Column(children: rows);
  }
}

class ModalCalendar extends StatelessWidget {
  final DateTime calendarDate;
  final int? selectedDay;
  final ValueChanged<int> onDaySelected;
  final ValueChanged<DateTime> onMonthChanged;
  final bool disablePastDays;
  final bool showBorder;
  final double cellAspectRatio;
  final double spacing;

  const ModalCalendar({
    super.key,
    required this.calendarDate,
    this.selectedDay,
    required this.onDaySelected,
    required this.onMonthChanged,
    this.disablePastDays = false,
    this.showBorder = true,
    this.cellAspectRatio = 1.0,
    this.spacing = 6,
  });

  @override
  Widget build(BuildContext context) {
    final monthYearStr =
        '${DateFormat('MMMM', context.locale.toString()).format(calendarDate).toUpperCase()} ${calendarDate.year}';
    final now = DateTime.now();
    final isAtStart =
        calendarDate.year == now.year && calendarDate.month == now.month;

    final weekdays = Row(
      children: [
        WeekdayHeaderChip(label: 'weekday_sun'.tr(), color: Colors.red),
        SizedBox(width: spacing),
        WeekdayHeaderChip(label: 'weekday_mon'.tr(), color: const Color(0xFF0247C4)),
        SizedBox(width: spacing),
        WeekdayHeaderChip(label: 'weekday_tue'.tr(), color: const Color(0xFF0247C4)),
        SizedBox(width: spacing),
        WeekdayHeaderChip(label: 'weekday_wed'.tr(), color: const Color(0xFF0247C4)),
        SizedBox(width: spacing),
        WeekdayHeaderChip(label: 'weekday_thu'.tr(), color: const Color(0xFF0247C4)),
        SizedBox(width: spacing),
        WeekdayHeaderChip(label: 'weekday_fri'.tr(), color: const Color(0xFF4CAF50)),
        SizedBox(width: spacing),
        WeekdayHeaderChip(label: 'weekday_sat'.tr(), color: const Color(0xFF0247C4)),
      ],
    );

    final content = Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () => onMonthChanged(
                  DateTime(calendarDate.year, calendarDate.month - 1, 1)),
              child: const Icon(Icons.chevron_left, size: 20, color: Colors.black),
            ),
            const SizedBox(width: 12),
            Text(
              monthYearStr,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.black,
                fontFamily: AppColors.fontFamily,
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: isAtStart
                  ? null
                  : () => onMonthChanged(
                      DateTime(calendarDate.year, calendarDate.month + 1, 1)),
              child: Icon(
                Icons.chevron_right,
                size: 20,
                color: isAtStart ? Colors.grey.shade300 : Colors.black,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        weekdays,
        const SizedBox(height: 8),
        CalendarGrid(
          date: calendarDate,
          selectedDay: selectedDay,
          onDaySelected: onDaySelected,
          disablePastDays: disablePastDays,
          cellAspectRatio: cellAspectRatio,
          spacing: spacing,
        ),
      ],
    );

    if (showBorder) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.all(12),
        child: content,
      );
    }

    return content;
  }
}
