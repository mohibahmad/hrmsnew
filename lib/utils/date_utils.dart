import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AppDateUtils {
  static const Map<String, int> _monthNames = {
    'january': 1,
    'jan': 1,
    'february': 2,
    'feb': 2,
    'march': 3,
    'mar': 3,
    'april': 4,
    'apr': 4,
    'may': 5,
    'june': 6,
    'jun': 6,
    'july': 7,
    'jul': 7,
    'august': 8,
    'aug': 8,
    'september': 9,
    'sep': 9,
    'sept': 9,
    'october': 10,
    'oct': 10,
    'november': 11,
    'nov': 11,
    'december': 12,
    'dec': 12,
  };

  static int? parseMonth(String monthStr, {String? locale}) {
    final trimmed = monthStr.trim().toLowerCase();
    final fromMap = _monthNames[trimmed];
    if (fromMap != null) return fromMap;
    final fromInt = int.tryParse(trimmed);
    if (fromInt != null && fromInt >= 1 && fromInt <= 12) return fromInt;
    try {
      final fmt = locale != null
          ? DateFormat('MMMM', locale)
          : DateFormat('MMMM');
      for (int i = 1; i <= 12; i++) {
        if (fmt.format(DateTime(2024, i)) == monthStr.trim()) return i;
      }
    } catch (_) {}
    return null;
  }

  static DateTime? parseDateString(String dateStr) {
    try {
      final parsed = DateTime.tryParse(dateStr);
      if (parsed != null) return parsed;

      final parts = dateStr.split('/');
      if (parts.length == 3) {
        if (parts[0].length == 4) {
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final day = int.parse(parts[2]);
          return DateTime(year, month, day);
        } else if (parts[2].length == 4) {
          final year = int.parse(parts[2]);
          final val1 = int.parse(parts[0]);
          final val2 = int.parse(parts[1]);

          if (val1 > 12) {
            return DateTime(year, val2, val1);
          } else if (val2 > 12) {
            return DateTime(year, val1, val2);
          } else {
            return DateTime(year, val2, val1);
          }
        }
      }

      final hyphenParts = dateStr.split('-');
      if (hyphenParts.length == 3) {
        if (hyphenParts[0].length == 4) {
          final year = int.parse(hyphenParts[0]);
          final month = int.parse(hyphenParts[1]);
          final day = int.parse(hyphenParts[2]);
          return DateTime(year, month, day);
        } else if (hyphenParts[2].length == 4) {
          final year = int.parse(hyphenParts[2]);
          final val1 = int.parse(hyphenParts[0]);
          final val2 = int.parse(hyphenParts[1]);
          if (val1 > 12) {
            return DateTime(year, val2, val1);
          } else {
            return DateTime(year, val2, val1);
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static String formatDate(DateTime date) {
    final dayStr = date.day.toString().padLeft(2, '0');
    final monthStr = date.month.toString().padLeft(2, '0');
    return '$dayStr/$monthStr/${date.year}';
  }

  static DateTime _periodStart(String period, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (period) {
      case 'Today':
        return today;
      case 'Week':
      case 'Weekly':
        
        final weekday = today.weekday; 
        return today.subtract(Duration(days: weekday - 1));
      case 'Month':
      case 'Monthly':
        return DateTime(today.year, today.month, 1);
      case '6 Month':
      case '6 Months':
      case '6 Monthly':
        return DateTime(today.year, today.month - 6, 1);
      case 'Yearly':
        return DateTime(today.year, 1, 1);
      default:
        return today;
    }
  }

  static bool isDateWithinPeriod(String dateStr, String period) {
    final date = parseDateString(dateStr);
    if (date == null) return true;

    final now = DateTime.now();
    final start = _periodStart(period, now);
    final end = DateTime(now.year, now.month, now.day);

    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  static bool isTimestampWithinPeriod(dynamic createdAt, String period) {
    if (createdAt == null) return true;

    final date = dateFromValue(createdAt);
    if (date == null) return true;

    final now = DateTime.now();
    final start = _periodStart(period, now);
    final end = DateTime(now.year, now.month, now.day);

    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  static DateTime? dateFromValue(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    return parseDateString(value.toString());
  }

  static DateTime? attendanceRecordDate(Map<String, dynamic> record) {
    for (final key in ['attendanceDate', 'date', 'createdAt']) {
      final date = dateFromValue(record[key]);
      if (date != null) return date;
    }
    return null;
  }

  static bool isAttendanceRecordWithinPeriod(
    Map<String, dynamic> record,
    String period,
  ) {
    final date = attendanceRecordDate(record);
    return date == null || isTimestampWithinPeriod(date, period);
  }
}
