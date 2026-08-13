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

  static DateTime? _validatedDate(int year, int month, int day) {
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

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
      if (parsed != null) {
        return _validatedDate(parsed.year, parsed.month, parsed.day);
      }

      final parts = dateStr.split('/');
      if (parts.length == 3) {
        if (parts[0].length == 4) {
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final day = int.parse(parts[2]);
          return _validatedDate(year, month, day);
        } else if (parts[2].length == 4) {
          final year = int.parse(parts[2]);
          final val1 = int.parse(parts[0]);
          final val2 = int.parse(parts[1]);

          if (val1 > 12) {
            return _validatedDate(year, val2, val1);
          } else if (val2 > 12) {
            return _validatedDate(year, val1, val2);
          } else {
            return _validatedDate(year, val2, val1);
          }
        }
      }

      final hyphenParts = dateStr.split('-');
      if (hyphenParts.length == 3) {
        if (hyphenParts[0].length == 4) {
          final year = int.parse(hyphenParts[0]);
          final month = int.parse(hyphenParts[1]);
          final day = int.parse(hyphenParts[2]);
          return _validatedDate(year, month, day);
        } else if (hyphenParts[2].length == 4) {
          final year = int.parse(hyphenParts[2]);
          final val1 = int.parse(hyphenParts[0]);
          final val2 = int.parse(hyphenParts[1]);
          if (val1 > 12) {
            return _validatedDate(year, val2, val1);
          } else if (val2 > 12) {
            return _validatedDate(year, val1, val2);
          } else {
            return _validatedDate(year, val2, val1);
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static DateTime? parseDdMmYyyy(String value) {
    final text = value.trim();
    if (!RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(text)) return null;

    try {
      final parsed = DateFormat('dd/MM/yyyy').parseStrict(text);
      return _validatedDate(parsed.year, parsed.month, parsed.day);
    } catch (_) {
      return null;
    }
  }

  static DateTime asUtcDateOnly(DateTime value) {
    return DateTime.utc(value.year, value.month, value.day);
  }

  static String formatDate(DateTime date) {
    final dayStr = date.day.toString().padLeft(2, '0');
    final monthStr = date.month.toString().padLeft(2, '0');
    return '$dayStr/$monthStr/${date.year}';
  }

  static String formatLocaleDate(DateTime date, {String? locale}) {
    try {
      final loc = locale ?? Intl.getCurrentLocale();
      if (loc.startsWith('en')) {
        return DateFormat('dd/MM/yyyy').format(date);
      }
      return DateFormat.yMd(loc).format(date);
    } catch (_) {
      return formatDate(date);
    }
  }

  static String fromValueLocalized(dynamic value, {String? locale}) {
    if (value == null) return '';
    final date = dateFromValue(value);
    if (date == null) return value.toString();
    return formatLocaleDate(date, locale: locale);
  }

  static DateTime periodStart(String period, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (period) {
      case 'Today':
        return today;
      case 'Week':
      case 'Weekly':
      case 'This Week':
        final weekday = today.weekday;
        return today.subtract(Duration(days: weekday - 1));
      case 'Month':
      case 'Monthly':
      case 'This Month':
        return DateTime(today.year, today.month, 1);
      case '6 Month':
      case '6 Months':
      case '6 Monthly':
      case 'Last 6 Months':
        return DateTime(today.year, today.month - 5, 1);
      case 'Yearly':
      case 'This Year':
        return DateTime(today.year, 1, 1);
      case 'All Time':
        return DateTime(1, 1, 1);
      default:
        return today;
    }
  }

  static DateTime periodEnd(String period, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (period) {
      case 'Today':
        return today;
      case 'Week':
      case 'Weekly':
      case 'This Week':
        final weekday = today.weekday;
        final start = today.subtract(Duration(days: weekday - 1));
        return start.add(const Duration(days: 6));
      case 'Month':
      case 'Monthly':
      case 'This Month':
        return DateTime(now.year, now.month + 1, 0);
      case '6 Month':
      case '6 Months':
      case '6 Monthly':
      case 'Last 6 Months':
        return DateTime(now.year, now.month + 1, 0);
      case 'Yearly':
      case 'This Year':
        return DateTime(now.year, 12, 31);
      case 'All Time':
        return DateTime(9999, 12, 31);
      default:
        return today;
    }
  }

  static bool isDateWithinPeriod(String dateStr, String period) {
    final date = parseDateString(dateStr);
    if (date == null) return false;

    final now = DateTime.now();
    final start = periodStart(period, now);
    final end = periodEnd(period, now);

    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  static bool isTimestampWithinPeriod(dynamic createdAt, String period) {
    if (createdAt == null) return false;

    final date = dateFromValue(createdAt);
    if (date == null) return false;

    final now = DateTime.now();
    final start = periodStart(period, now);
    final end = periodEnd(period, now);

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

  static DateTime? canonicalAttendanceDate(Map<String, dynamic> record) {
    return dateFromValue(record['attendanceDate']);
  }

  static DateTime? holidayRecordDate(
    Map<String, dynamic> record, {
    int? fallbackYear,
  }) {
    for (final key in ['date', 'holidayDate']) {
      final date = dateFromValue(record[key]);
      if (date != null) return DateTime(date.year, date.month, date.day);
    }

    final rawDay = record['day'];
    final day = rawDay is num
        ? rawDay.toInt()
        : int.tryParse((rawDay ?? '').toString().trim());
    final month = parseMonth((record['month'] ?? '').toString());
    final rawYear = record['year'];
    final year = rawYear is num
        ? rawYear.toInt()
        : int.tryParse((rawYear ?? '').toString().trim()) ?? fallbackYear;
    if (day == null || month == null || year == null) return null;
    return _validatedDate(year, month, day);
  }

  static bool isAttendanceRecordWithinPeriod(
    Map<String, dynamic> record,
    String period,
  ) {
    final date = canonicalAttendanceDate(record);
    if (date == null) return false;
    return isTimestampWithinPeriod(date, period);
  }
}

class PendingTimeOffDraft {
  final String leaveType;
  final String? editingId;
  final Map<String, dynamic>? editingRecord;
  final Set<DateTime> selectedDates;
  final String notes;
  final bool typeChanged;
  final bool datesChanged;
  final bool notesChanged;

  const PendingTimeOffDraft({
    required this.leaveType,
    required this.editingId,
    required this.editingRecord,
    required this.selectedDates,
    required this.notes,
    required this.typeChanged,
    required this.datesChanged,
    required this.notesChanged,
  });

  bool get hasChanges {
    if (editingId != null) {
      return typeChanged || datesChanged || notesChanged;
    }
    return selectedDates.isNotEmpty ||
        notes.isNotEmpty ||
        typeChanged ||
        datesChanged ||
        notesChanged;
  }
}

bool hasUnsavedTimeOffChanges({
  required bool hasSelectedDates,
  required bool hasNotes,
  required bool isEditing,
  required bool typeChanged,
  required bool datesChanged,
}) {
  if (isEditing) {
    return hasNotes || typeChanged || datesChanged;
  }
  return hasSelectedDates || hasNotes || typeChanged;
}

int projectedTimeOffBalance({
  required int availableDays,
  required int requestedDays,
}) {
  return (availableDays - requestedDays).clamp(0, 9999);
}
