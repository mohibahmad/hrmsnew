import 'package:easy_localization/easy_localization.dart';

import 'date_utils.dart';

class ChartData {
  final List<String> labels;
  final List<double> values;

  final bool isAdaptive;

  final DateTime? rangeStart;
  final DateTime? rangeEnd;

  ChartData(
    this.labels,
    this.values, {
    this.isAdaptive = false,
    this.rangeStart,
    this.rangeEnd,
  });
}

class NiceChartRange {
  final double maxY;
  final double interval;
  NiceChartRange(this.maxY, this.interval);
}

String normalizedAttendanceStatus(Map<String, dynamic> record) {
  final status = (record['status'] ?? '').toString().trim().toLowerCase();
  return switch (status) {
    'present' || 'p' => 'present',
    'absent' || 'a' => 'absent',
    _ => status,
  };
}

List<Map<String, dynamic>> attendanceRecordsForStatus(
  List<Map<String, dynamic>> records,
  String status,
) {
  final normalizedStatus = status.trim().toLowerCase();
  return records
      .where((record) => normalizedAttendanceStatus(record) == normalizedStatus)
      .toList();
}

DateTime? _dashboardAttendanceDate(Map<String, dynamic> record) {
  return AppDateUtils.dateFromValue(record['attendanceDate'] ?? record['date']);
}

/// Returns every Present/Absent attendance record inside [period].
///
/// Dashboard totals are based on the attendance collection itself. They must
/// not disappear just because an older record has only a worker name or its
/// worker document was later edited/removed.
List<Map<String, dynamic>> attendanceRecordsForPeriod(
  List<Map<String, dynamic>> records,
  String period, {
  DateTime? now,
}) {
  final referenceDate = now ?? DateTime.now();
  final start = AppDateUtils.periodStart(period, referenceDate);
  final end = AppDateUtils.periodEnd(period, referenceDate);

  return records.where((record) {
    final status = normalizedAttendanceStatus(record);
    if (status != 'present' && status != 'absent') return false;

    final date = _dashboardAttendanceDate(record);
    if (date == null) return false;
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }).toList();
}

DateTime? _attendanceRevisionDate(Map<String, dynamic> record) {
  return AppDateUtils.dateFromValue(record['updatedAt']) ??
      AppDateUtils.dateFromValue(record['createdAt']);
}

bool _isNewerAttendanceRecord(
  Map<String, dynamic> candidate,
  Map<String, dynamic> existing,
) {
  final candidateDate = _dashboardAttendanceDate(candidate);
  final existingDate = _dashboardAttendanceDate(existing);

  if (candidateDate != null && existingDate != null) {
    if (candidateDate.isAfter(existingDate)) return true;
    if (candidateDate.isBefore(existingDate)) return false;
  } else if (candidateDate != null) {
    return true;
  } else if (existingDate != null) {
    return false;
  }

  final candidateRevision = _attendanceRevisionDate(candidate);
  final existingRevision = _attendanceRevisionDate(existing);
  if (candidateRevision != null && existingRevision != null) {
    return candidateRevision.isAfter(existingRevision);
  }
  return candidateRevision != null && existingRevision == null;
}

List<Map<String, dynamic>> latestAttendanceRecordPerWorker(
  List<Map<String, dynamic>> records, {
  String? period,
  DateTime? now,
  /// Optional resolver that maps a record to the canonical id of a current
  /// worker. When provided:
  ///  - records that don't belong to any current worker are skipped, and
  ///  - all documents for the same worker are grouped together even when their
  ///    stored identity fields differ (workerId vs email vs name).
  String? Function(Map<String, dynamic> record)? workerIdResolver,
}) {
  final latestByWorker = <String, Map<String, dynamic>>{};
  final referenceDate = now ?? DateTime.now();

  for (final record in records) {
    final workerId = (record['workerId'] ?? '').toString().trim();
    final email = (record['email'] ?? '').toString().trim().toLowerCase();
    final name = (record['name'] ?? record['workerName'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final recordId = (record['id'] ?? '').toString().trim();

    String? workerKey;
    if (workerIdResolver != null) {
      final resolvedId = workerIdResolver(record);
      if (resolvedId == null || resolvedId.isEmpty) continue;
      workerKey = 'id:$resolvedId';
    } else {
      workerKey = workerId.isNotEmpty
          ? 'id:$workerId'
          : email.isNotEmpty
          ? 'email:$email'
          : name.isNotEmpty
          ? 'name:$name'
          : 'record:$recordId';
    }

    final bucketKey = period == null
        ? ''
        : _attendanceBucketKey(record, period, referenceDate);
    final groupedKey = bucketKey == null ? workerKey : '$workerKey|$bucketKey';

    final existing = latestByWorker[groupedKey];
    if (existing == null) {
      latestByWorker[groupedKey] = record;
      continue;
    }

    if (_isNewerAttendanceRecord(record, existing)) {
      latestByWorker[groupedKey] = record;
    }
  }

  return latestByWorker.values.toList();
}

String? _attendanceBucketKey(
  Map<String, dynamic> record,
  String period,
  DateTime now,
) {
  final date = _dashboardAttendanceDate(record);
  if (date == null) return null;

  return '${date.year}-${date.month}-${date.day}';
}

NiceChartRange getNiceRange(double rawMax) {
  if (rawMax <= 0) {
    return NiceChartRange(5, 1);
  }
  if (rawMax <= 5) {
    return NiceChartRange(5, 1);
  } else if (rawMax <= 7) {
    return NiceChartRange(7, 1);
  } else if (rawMax <= 10) {
    return NiceChartRange(10, 2);
  } else if (rawMax <= 15) {
    return NiceChartRange(15, 3);
  } else if (rawMax <= 20) {
    return NiceChartRange(20, 4);
  } else if (rawMax <= 30) {
    return NiceChartRange(30, 5);
  } else if (rawMax <= 40) {
    return NiceChartRange(40, 8);
  } else if (rawMax <= 50) {
    return NiceChartRange(50, 10);
  } else if (rawMax <= 75) {
    return NiceChartRange(75, 15);
  } else if (rawMax <= 100) {
    return NiceChartRange(100, 20);
  } else if (rawMax <= 150) {
    return NiceChartRange(150, 30);
  } else if (rawMax <= 200) {
    return NiceChartRange(200, 40);
  } else if (rawMax <= 250) {
    return NiceChartRange(250, 50);
  } else if (rawMax <= 300) {
    return NiceChartRange(300, 50);
  } else if (rawMax <= 400) {
    return NiceChartRange(400, 100);
  } else if (rawMax <= 500) {
    return NiceChartRange(500, 100);
  } else if (rawMax <= 600) {
    return NiceChartRange(600, 100);
  } else if (rawMax <= 800) {
    return NiceChartRange(800, 200);
  } else if (rawMax <= 1000) {
    return NiceChartRange(1000, 200);
  } else if (rawMax <= 1500) {
    return NiceChartRange(1500, 300);
  } else if (rawMax <= 2000) {
    return NiceChartRange(2000, 400);
  } else if (rawMax <= 2500) {
    return NiceChartRange(2500, 500);
  } else if (rawMax <= 3000) {
    return NiceChartRange(3000, 500);
  } else if (rawMax <= 4000) {
    return NiceChartRange(4000, 1000);
  } else if (rawMax <= 5000) {
    return NiceChartRange(5000, 1000);
  } else {
    double roughStep = rawMax / 5.0;
    double log10Val = (roughStep.truncate().toString().length - 1).toDouble();
    double power = 1.0;
    for (int i = 0; i < log10Val; i++) {
      power *= 10;
    }
    double normalized = roughStep / power;
    double step;
    if (normalized < 1.5) {
      step = 1.0 * power;
    } else if (normalized < 3.5) {
      step = 2.0 * power;
    } else if (normalized < 7.5) {
      step = 5.0 * power;
    } else {
      step = 10.0 * power;
    }
    double maxY = ((rawMax / step).ceil() * step);
    return NiceChartRange(maxY, step);
  }
}

ChartData getChartData(
  String period,
  List<Map<String, dynamic>> docs,
  bool isGuest,
  String locale,
) {
  final now = DateTime.now();
  final normalizedPeriod = switch (period.trim()) {
    'Weekly' || 'This Week' => 'Week',
    'Monthly' || 'This Month' => 'Month',
    '6 Months' || '6 Monthly' || 'Last 6 Months' => '6 Month',
    'This Year' => 'Yearly',
    final value => value,
  };

  if (docs.isEmpty) {
    switch (normalizedPeriod) {
      case 'Today':
        final labels = <String>[];
        for (int i = 6; i >= 0; i--) {
          final date = now.subtract(Duration(days: i));
          labels.add(DateFormat('E', locale).format(date).toUpperCase());
        }
        return ChartData(labels, List.filled(7, 0.0));

      case 'Week':
        final labels = <String>[];
        final startOfWeek = AppDateUtils.periodStart('Week', now);
        for (int i = 0; i < 7; i++) {
          final date = startOfWeek.add(Duration(days: i));
          labels.add(DateFormat('E', locale).format(date).toUpperCase());
        }
        return ChartData(labels, List.filled(7, 0.0));

      case 'Month':
        return ChartData([
          'week_label_1'.tr(),
          'week_label_2'.tr(),
          'week_label_3'.tr(),
          'week_label_4'.tr(),
        ], List.filled(4, 0.0));

      case '6 Month':
        final labels = <String>[];
        for (int i = 5; i >= 0; i--) {
          final date = DateTime(now.year, now.month - i, 1);
          labels.add(DateFormat('MMM', locale).format(date).toUpperCase());
        }
        return ChartData(labels, List.filled(6, 0.0));

      case 'Yearly':
      default:
        final labels = <String>[];
        for (int i = 0; i < 12; i++) {
          final date = DateTime(now.year, i + 1, 1);
          labels.add(DateFormat('MMM', locale).format(date).toUpperCase());
        }
        return ChartData(labels, List.filled(12, 0.0));
    }
  }

  final parsedRecords = <DateTime>[];
  for (final doc in docs) {
    // Dashboard charts use only the canonical attendanceDate. createdAt is
    // metadata and must not move a historical record into today's chart.
    final dt = _dashboardAttendanceDate(doc);
    if (dt != null) {
      parsedRecords.add(dt);
    }
  }

  if (normalizedPeriod == 'All Time' && parsedRecords.isNotEmpty) {
    return _buildAllTimeMonthlyChartData(parsedRecords, locale);
  }

  final start = AppDateUtils.periodStart(normalizedPeriod, now);
  final end = AppDateUtils.periodEnd(normalizedPeriod, now);

  switch (normalizedPeriod) {
    case 'Today':
      final labels = <String>[];
      final values = List.filled(7, 0.0);
      for (int i = 6; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        labels.add(DateFormat('E', locale).format(date).toUpperCase());
      }
      for (final dt in parsedRecords) {
        if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
          values[6] += 1.0;
        }
      }
      return ChartData(labels, values);

    case 'Week':
      final labels = <String>[];
      final values = List.filled(7, 0.0);

      // Values use Monday as index 0, so labels must use the same order.
      for (int i = 0; i < 7; i++) {
        final date = start.add(Duration(days: i));
        labels.add(DateFormat('E', locale).format(date).toUpperCase());
      }

      for (final dt in parsedRecords) {
        final difference = dt.difference(start).inDays;
        if (difference >= 0 && difference < 7) {
          values[difference] += 1.0;
        }
      }
      return ChartData(labels, values);

    case 'Month':
      final labels = [
        'week_label_1'.tr(),
        'week_label_2'.tr(),
        'week_label_3'.tr(),
        'week_label_4'.tr(),
      ];
      final values = List.filled(4, 0.0);
      final totalDays = end.difference(start).inDays + 1;

      for (final dt in parsedRecords) {
        final difference = dt.difference(start).inDays;
        if (difference >= 0 && difference < totalDays) {
          final weekIdx = difference * 4 ~/ totalDays;
          if (weekIdx >= 0 && weekIdx < 4) {
            values[weekIdx] += 1.0;
          }
        }
      }
      return ChartData(labels, values);

    case '6 Month':
      final labels = <String>[];
      final values = List.filled(6, 0.0);

      for (int i = 5; i >= 0; i--) {
        final date = DateTime(now.year, now.month - i, 1);
        labels.add(DateFormat('MMM', locale).format(date).toUpperCase());
      }

      for (final dt in parsedRecords) {
        for (int i = 0; i < 6; i++) {
          final targetDate = DateTime(now.year, now.month - (5 - i), 1);
          if (dt.year == targetDate.year && dt.month == targetDate.month) {
            values[i] += 1.0;
            break;
          }
        }
      }
      return ChartData(labels, values);

    case 'Yearly':
    default:
      final labels = <String>[];
      final values = List.filled(12, 0.0);

      for (int i = 0; i < 12; i++) {
        final date = DateTime(now.year, i + 1, 1);
        labels.add(DateFormat('MMM', locale).format(date).toUpperCase());
      }

      for (final dt in parsedRecords) {
        if (dt.year == now.year && dt.month <= 12) {
          values[dt.month - 1] += 1.0;
        }
      }
      return ChartData(labels, values);
  }
}

/// Groups the complete attendance history by its actual month and year.
/// Only months that have records become points, so a single recorded month
/// produces one label/point instead of repeated synthetic buckets.
ChartData _buildAllTimeMonthlyChartData(
  List<DateTime> parsedRecords,
  String locale,
) {
  final sorted = [...parsedRecords]..sort();
  final totalsByMonth = <int, double>{};
  for (final date in sorted) {
    final monthKey = date.year * 12 + date.month - 1;
    totalsByMonth[monthKey] = (totalsByMonth[monthKey] ?? 0) + 1;
  }

  final monthKeys = totalsByMonth.keys.toList()..sort();
  final labels = <String>[];
  final values = <double>[];
  for (final monthKey in monthKeys) {
    final year = monthKey ~/ 12;
    final month = monthKey % 12 + 1;
    labels.add(
      DateFormat(
        'MMM yy',
        locale,
      ).format(DateTime(year, month, 1)).toUpperCase(),
    );
    values.add(totalsByMonth[monthKey]!);
  }

  return ChartData(
    labels,
    values,
    isAdaptive: true,
    rangeStart: DateTime(
      sorted.first.year,
      sorted.first.month,
      sorted.first.day,
    ),
    rangeEnd: DateTime(sorted.last.year, sorted.last.month, sorted.last.day),
  );
}
