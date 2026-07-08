import 'package:intl/intl.dart';

class AppDateUtils {
  static const Map<String, int> _monthNames = {
    'january': 1, 'jan': 1,
    'february': 2, 'feb': 2,
    'march': 3, 'mar': 3,
    'april': 4, 'apr': 4,
    'may': 5,
    'june': 6, 'jun': 6,
    'july': 7, 'jul': 7,
    'august': 8, 'aug': 8,
    'september': 9, 'sep': 9, 'sept': 9,
    'october': 10, 'oct': 10,
    'november': 11, 'nov': 11,
    'december': 12, 'dec': 12,
  };

  static int? parseMonth(String monthStr, {String? locale}) {
    final trimmed = monthStr.trim().toLowerCase();
    final fromMap = _monthNames[trimmed];
    if (fromMap != null) return fromMap;
    final fromInt = int.tryParse(trimmed);
    if (fromInt != null && fromInt >= 1 && fromInt <= 12) return fromInt;
    try {
      final fmt = locale != null ? DateFormat('MMMM', locale) : DateFormat('MMMM');
      for (int i = 1; i <= 12; i++) {
        if (fmt.format(DateTime(2024, i)) == monthStr.trim()) return i;
      }
    } catch (_) {}
    return null;
  }
  static DateTime? parseDateString(String dateStr) {
    try {
      // First try standard ISO format parsing
      final parsed = DateTime.tryParse(dateStr);
      if (parsed != null) return parsed;

      // Try split by '/'
      final parts = dateStr.split('/');
      if (parts.length == 3) {
        // Check if the first part is a year (e.g. 4 digits)
        if (parts[0].length == 4) {
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final day = int.parse(parts[2]);
          return DateTime(year, month, day);
        } else if (parts[2].length == 4) {
          final year = int.parse(parts[2]);
          final val1 = int.parse(parts[0]);
          final val2 = int.parse(parts[1]);
          // If val1 > 12, it must be the day, so it's dd/MM/yyyy
          // If val2 > 12, it must be the day, so it's MM/dd/yyyy
          if (val1 > 12) {
            return DateTime(year, val2, val1);
          } else if (val2 > 12) {
            return DateTime(year, val1, val2);
          } else {
            // Default to day first as per our original logic
            return DateTime(year, val2, val1);
          }
        }
      }

      // Try split by '-'
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

  static bool isDateWithinPeriod(String dateStr, String period) {
    final date = parseDateString(dateStr);
    if (date == null) return true;

    final now = DateTime.now();
    // Cap reference date at June 10, 2026 for dummy data consistency if today is earlier
    final refDate = now.isBefore(DateTime(2026, 6, 10))
        ? DateTime(2026, 6, 10)
        : now;

    final diff = refDate.difference(date).inDays;
    if (diff < 0) return true; // Future date

    switch (period) {
      case 'Today':
        return diff == 0;
      case 'Week':
        return diff <= 7;
      case 'Month':
        return diff <= 30;
      case '6 Month':
        return diff <= 180;
      case 'Yearly':
        return diff <= 365;
      default:
        return true;
    }
  }

  static bool isTimestampWithinPeriod(dynamic createdAt, String period) {
    if (createdAt == null) return true;

    DateTime? date;
    if (createdAt is DateTime) {
      date = createdAt;
    } else {
      date = parseDateString(createdAt.toString());
    }
    if (date == null) return true;

    final now = DateTime.now();
    final refDate = now.isBefore(DateTime(2026, 6, 10))
        ? DateTime(2026, 6, 10)
        : now;

    final diff = refDate.difference(date).inDays;
    if (diff < 0) return true;

    switch (period) {
      case 'Today':
        return diff == 0;
      case 'Week':
        return diff <= 7;
      case 'Month':
        return diff <= 30;
      case '6 Month':
        return diff <= 180;
      case 'Yearly':
        return diff <= 365;
      default:
        return true;
    }
  }
}
