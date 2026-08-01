import 'payroll_service.dart';
import 'time_off_service.dart';

class DashboardChartPoint {
  final DateTime date;
  final double value;

  const DashboardChartPoint({required this.date, required this.value});
}

class DashboardChartSeries {
  final List<DashboardChartPoint> points;
  final double total;

  const DashboardChartSeries({required this.points, required this.total});
}

class DashboardChartService {
  DashboardChartService._();

  static String _normalizePeriod(String period) {
    final normalized = period.trim();
    return switch (normalized) {
      'Weekly' => 'Week',
      'Monthly' => 'Month',
      '6 Monthly' => '6 Month',
      _ => normalized,
    };
  }

  static DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static DashboardChartSeries buildSeries({
    required List<Map<String, dynamic>> records,
    required double Function(Map<String, dynamic> record) valueOf,
    required String period,
    DateTime? Function(Map<String, dynamic> record)? dateOf,
    DateTime? now,
    bool placeUndatedInCurrentPeriod = false,
  }) {
    final current = now ?? DateTime.now();
    final currentDay = _dateOnly(current);
    final normalizedPeriod = _normalizePeriod(period);
    final datedValues = <({DateTime date, double value})>[];

    for (final record in records) {
      if ((record['status'] ?? '').toString().trim().toLowerCase() ==
          'cancelled') {
        continue;
      }

      final value = valueOf(record);
      if (!value.isFinite || value == 0) continue;

      final date = (dateOf ?? salaryRecordDate)(record);
      if (date != null) {
        datedValues.add((date: date, value: value));
      } else if (placeUndatedInCurrentPeriod) {
        datedValues.add((date: current, value: value));
      }
    }

    if (normalizedPeriod == 'Today') {
      final points = List.generate(6, (index) {
        final startHour = index * 4;
        final value = datedValues
            .where(
              (item) =>
                  _sameDay(item.date, currentDay) &&
                  item.date.hour >= startHour &&
                  item.date.hour < startHour + 4,
            )
            .fold<double>(0, (sum, item) => sum + item.value);
        return DashboardChartPoint(
          date: currentDay.add(Duration(hours: startHour)),
          value: value,
        );
      });
      return DashboardChartSeries(points: points, total: _sum(points));
    }

    if (normalizedPeriod == 'Week') {
      final start = currentDay.subtract(const Duration(days: 6));
      final points = List.generate(7, (index) {
        final day = start.add(Duration(days: index));
        return DashboardChartPoint(
          date: day,
          value: datedValues
              .where((item) => _sameDay(item.date, day))
              .fold<double>(0, (sum, item) => sum + item.value),
        );
      });
      return DashboardChartSeries(points: points, total: _sum(points));
    }

    if (normalizedPeriod == 'Month') {
      final start = DateTime(current.year, current.month, 1);
      final dayCount = current.day;
      double runningTotal = 0;
      final points = List.generate(dayCount, (index) {
        final day = start.add(Duration(days: index));
        runningTotal += datedValues
            .where((item) => _sameDay(item.date, day))
            .fold<double>(0, (sum, item) => sum + item.value);
        return DashboardChartPoint(date: day, value: runningTotal);
      });
      return DashboardChartSeries(points: points, total: runningTotal);
    }

    final monthCount = normalizedPeriod == '6 Month' ? 6 : 12;
    final firstMonth = normalizedPeriod == '6 Month'
        ? DateTime(current.year, current.month - 5, 1)
        : DateTime(current.year, 1, 1);
    final points = List.generate(monthCount, (index) {
      final month = DateTime(firstMonth.year, firstMonth.month + index, 1);
      return DashboardChartPoint(
        date: month,
        value: datedValues
            .where(
              (item) =>
                  item.date.year == month.year &&
                  item.date.month == month.month,
            )
            .fold<double>(0, (sum, item) => sum + item.value),
      );
    });
    return DashboardChartSeries(points: points, total: _sum(points));
  }

  static bool isDateWithinPeriod(
    DateTime date,
    String period, {
    DateTime? now,
  }) {
    final currentValue = now ?? DateTime.now();
    final current = _dateOnly(currentValue);
    final target = _dateOnly(date);
    if (target.isAfter(current)) return false;

    final normalizedPeriod = _normalizePeriod(period);
    final start = switch (normalizedPeriod) {
      'Today' => current,
      'Week' => current.subtract(const Duration(days: 6)),
      'Month' => DateTime(current.year, current.month, 1),
      '6 Month' => DateTime(current.year, current.month - 5, 1),
      'Yearly' => DateTime(current.year, 1, 1),
      _ => DateTime(current.year, 1, 1),
    };
    return !target.isBefore(start);
  }

  static List<Map<String, dynamic>> leaveDaysForPeriod({
    required List<Map<String, dynamic>> records,
    required String period,
    DateTime? now,
  }) {
    final leaveDays = <Map<String, dynamic>>[];
    for (final record in records) {
      if (!TimeOffService.isActiveRecord(record)) continue;
      final type = TimeOffService.leaveType(record);
      for (final date in TimeOffService.selectedDatesForRecord(record)) {
        if (!isDateWithinPeriod(date, period, now: now)) continue;
        leaveDays.add({
          'status': 'leave',
          'type': type,
          'date': date,
          'workerId': record['workerId'],
        });
      }
    }
    return leaveDays;
  }

  /// Combines approved time-off dates with attendance rows marked as Leave.
  /// A worker/date pair is counted once, preferring the explicit time-off type.
  static List<Map<String, dynamic>> mergedLeaveDaysForPeriod({
    required List<Map<String, dynamic>> timeOffRecords,
    required List<Map<String, dynamic>> attendanceRecords,
    required String period,
    DateTime? now,
  }) {
    final merged = <String, Map<String, dynamic>>{};

    for (final leave in leaveDaysForPeriod(
      records: timeOffRecords,
      period: period,
      now: now,
    )) {
      final date = leave['date'] as DateTime;
      merged[_leaveIdentity(leave, date)] = leave;
    }

    for (final attendance in attendanceRecords) {
      final status = (attendance['status'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (status != 'leave') continue;

      final date = TimeOffService.parseDate(
        attendance['attendanceDate'] ??
            attendance['date'] ??
            attendance['createdAt'],
      );
      if (date == null || !isDateWithinPeriod(date, period, now: now)) {
        continue;
      }

      final type = _attendanceLeaveType(attendance);
      if (!TimeOffService.paidLeaveTypes.contains(type)) continue;

      final normalized = <String, dynamic>{
        ...attendance,
        'status': 'leave',
        'type': type,
        'date': date,
      };
      merged.putIfAbsent(_leaveIdentity(normalized, date), () => normalized);
    }

    final result = merged.values.toList();
    result.sort(
      (a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime),
    );
    return result;
  }

  static String _attendanceLeaveType(Map<String, dynamic> record) {
    final explicit = TimeOffService.normalizeLeaveType(
      (record['type'] ?? record['leaveType'] ?? record['action'] ?? '')
          .toString(),
    );
    if (TimeOffService.paidLeaveTypes.contains(explicit)) return explicit;

    final reason = (record['reason'] ?? record['desc'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (reason.contains('sick')) return 'Sick Leave';
    if (reason.contains('medical')) return 'Medical Leave';
    if (reason.contains('casual') || reason.contains('vacation')) {
      return 'Casual Leave';
    }
    return 'Annual Leave';
  }

  static String _leaveIdentity(Map<String, dynamic> record, DateTime date) {
    final worker =
        (record['workerId'] ?? record['email'] ?? record['name'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    return '$worker:${date.year}-${date.month}-${date.day}';
  }

  static bool _sameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  static DateTime? salaryRecordDate(Map<String, dynamic> record) {
    for (final key in ['paidAt', 'paymentDate', 'payrollDate', 'createdAt']) {
      final parsed = PayrollService.payrollRecordDate({'date': record[key]});
      if (parsed != null) return parsed;
    }
    return PayrollService.payrollRecordDate(record);
  }

  static DateTime? expenseRecordDate(Map<String, dynamic> record) {
    final enteredDate = PayrollService.payrollRecordDate({
      'date': record['date'],
    });
    return enteredDate ?? PayrollService.payrollRecordDate(record);
  }

  static DashboardChartSeries buildDummySalarySeries({
    required List<Map<String, dynamic>> expenses,
    required double totalSalary,
    required String period,
    DateTime? now,
  }) {
    final expenseTotal = expenses.fold<double>(0, (sum, record) {
      final amount = record['amount'];
      return sum + (amount is num ? amount.toDouble() : 0);
    });
    if (expenseTotal <= 0 || totalSalary <= 0) {
      return buildSeries(
        records: const [],
        valueOf: (_) => 0,
        period: period,
        now: now,
      );
    }

    return buildSeries(
      records: expenses,
      valueOf: (record) {
        final amount = record['amount'];
        final expenseValue = amount is num ? amount.toDouble() : 0;
        return totalSalary * (expenseValue / expenseTotal);
      },
      period: period,
      dateOf: expenseRecordDate,
      now: now,
      placeUndatedInCurrentPeriod: true,
    );
  }

  static DashboardChartSeries buildGuestSalarySeries({
    required List<Map<String, dynamic>> salaryRecords,
    required List<Map<String, dynamic>> expenses,
    required double totalSalary,
    required String period,
    DateTime? now,
  }) {
    if (period == 'Yearly') {
      return buildDummySalarySeries(
        expenses: expenses,
        totalSalary: totalSalary,
        period: period,
        now: now,
      );
    }

    return buildSeries(
      records: salaryRecords,
      valueOf: (record) => ((record['netSalary'] ?? 0) as num).toDouble(),
      period: period,
      dateOf: salaryRecordDate,
      now: now,
      placeUndatedInCurrentPeriod: true,
    );
  }

  static double _sum(List<DashboardChartPoint> points) =>
      points.fold<double>(0, (sum, point) => sum + point.value);
}
