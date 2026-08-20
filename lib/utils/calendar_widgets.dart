import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class WeekdayHeaderChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool isExpanded;
  final Radius borderRadius;

  const WeekdayHeaderChip({
    super.key,
    required this.label,
    required this.color,
    this.isExpanded = true,
    this.borderRadius = const Radius.circular(3),
  });

  @override
  Widget build(BuildContext context) {
    final shortLabel = label.length > 3 ? label.substring(0, 3) : label;
    final chip = Container(
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.all(borderRadius),
      ),
      child: Text(
        shortLabel.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
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
  final Color selectedColor;
  final BorderRadius cellBorderRadius;

  const CalendarDayCell({
    super.key,
    required this.day,
    this.isSelected = false,
    this.isDisabled = false,
    this.onTap,
    this.cellAspectRatio = 1.0,
    this.selectedColor = const Color(0xFF0247C4),
    this.cellBorderRadius = const BorderRadius.all(Radius.circular(3)),
  });

  @override
  Widget build(BuildContext context) {
    if (day.isEmpty) {
      return Expanded(
        child: AspectRatio(aspectRatio: cellAspectRatio, child: const SizedBox()),
      );
    }

    return Expanded(
      child: AspectRatio(
        aspectRatio: cellAspectRatio,
        child: GestureDetector(
          onTap: isDisabled ? null : onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? selectedColor : Colors.transparent,
              border: Border.all(
                color: isSelected ? selectedColor : Colors.grey.shade300,
                width: 1,
              ),
              borderRadius: cellBorderRadius,
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
  final bool disableFutureDays;
  final double spacing;
  final double cellAspectRatio;
  final Color selectedColor;
  final BorderRadius cellBorderRadius;

  const CalendarGrid({
    super.key,
    required this.date,
    this.selectedDay,
    required this.onDaySelected,
    this.disablePastDays = false,
    this.disableFutureDays = false,
    this.spacing = 6,
    this.cellAspectRatio = 1.0,
    this.selectedColor = const Color(0xFF0247C4),
    this.cellBorderRadius = const BorderRadius.all(Radius.circular(3)),
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
          rowChildren.add(CalendarDayCell(day: '', cellAspectRatio: cellAspectRatio, selectedColor: selectedColor, cellBorderRadius: cellBorderRadius));
        } else if (currentDay <= daysInMonth) {
          final day = currentDay;
          final cellDate = DateTime(date.year, date.month, day);
          final isPast = disablePastDays && cellDate.isBefore(todayDate);
          final isFuture = disableFutureDays && cellDate.isAfter(todayDate);
          final isDisabled = isPast || isFuture;
          rowChildren.add(CalendarDayCell(
            day: '$day',
            isSelected: selectedDay != null && day == selectedDay,
            isDisabled: isDisabled,
            onTap: isDisabled ? null : () => onDaySelected(day),
            cellAspectRatio: cellAspectRatio,
            selectedColor: selectedColor,
            cellBorderRadius: cellBorderRadius,
          ));
          currentDay++;
        } else {
          rowChildren.add(CalendarDayCell(day: '', cellAspectRatio: cellAspectRatio, selectedColor: selectedColor, cellBorderRadius: cellBorderRadius));
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
  final bool disablePastMonths;
  final bool allowFutureMonths;
  final bool disableFutureDays;
  final bool showBorder;
  final Radius weekdayBorderRadius;
  final double cellAspectRatio;
  final double spacing;
  final Color selectedColor;
  final BorderRadius cellBorderRadius;

  const ModalCalendar({
    super.key,
    required this.calendarDate,
    this.selectedDay,
    required this.onDaySelected,
    required this.onMonthChanged,
    this.disablePastDays = false,
    this.disablePastMonths = false,
    this.allowFutureMonths = false,
    this.disableFutureDays = false,
    this.showBorder = true,
    this.weekdayBorderRadius = const Radius.circular(3),
    this.cellAspectRatio = 1.0,
    this.spacing = 6,
    this.selectedColor = const Color(0xFF0247C4),
    this.cellBorderRadius = const BorderRadius.all(Radius.circular(3)),
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
        WeekdayHeaderChip(label: 'weekday_sun'.tr(), color: const Color(0xFFFF1014), borderRadius: weekdayBorderRadius),
        SizedBox(width: spacing),
        WeekdayHeaderChip(label: 'weekday_mon'.tr(), color: const Color(0xFF0247C4), borderRadius: weekdayBorderRadius),
        SizedBox(width: spacing),
        WeekdayHeaderChip(label: 'weekday_tue'.tr(), color: const Color(0xFF0247C4), borderRadius: weekdayBorderRadius),
        SizedBox(width: spacing),
        WeekdayHeaderChip(label: 'weekday_wed'.tr(), color: const Color(0xFF0247C4), borderRadius: weekdayBorderRadius),
        SizedBox(width: spacing),
        WeekdayHeaderChip(label: 'weekday_thu'.tr(), color: const Color(0xFF0247C4), borderRadius: weekdayBorderRadius),
        SizedBox(width: spacing),
        WeekdayHeaderChip(label: 'weekday_fri'.tr(), color: const Color(0xFF4CAF50), borderRadius: weekdayBorderRadius),
        SizedBox(width: spacing),
        WeekdayHeaderChip(label: 'weekday_sat'.tr(), color: const Color(0xFF0247C4), borderRadius: weekdayBorderRadius),
      ],
    );

    final content = Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: disablePastMonths && isAtStart
                  ? null
                  : () => onMonthChanged(
                      DateTime(calendarDate.year, calendarDate.month - 1, 1)),
              child: Icon(
                Icons.chevron_left,
                size: 20,
                color:
                    disablePastMonths && isAtStart ? Colors.grey.shade300 : Colors.black,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              monthYearStr,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: !allowFutureMonths && isAtStart
                  ? null
                  : () => onMonthChanged(
                      DateTime(calendarDate.year, calendarDate.month + 1, 1)),
              child: Icon(
                Icons.chevron_right,
                size: 20,
                color:
                    !allowFutureMonths && isAtStart ? Colors.grey.shade300 : Colors.black,
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
          disableFutureDays: disableFutureDays,
          cellAspectRatio: cellAspectRatio,
          spacing: spacing,
          selectedColor: selectedColor,
          cellBorderRadius: cellBorderRadius,
        ),
      ],
    );

    if (showBorder) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: content,
      );
    }

    return content;
  }
}
