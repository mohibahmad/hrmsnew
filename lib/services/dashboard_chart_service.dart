import 'payroll_service.dart';
import 'time_off_service.dart';
import '../utils/worker_identity.dart';
import '../utils/date_utils.dart';

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

      final rawValue = valueOf(record);
      final value = (rawValue.isFinite && rawValue > 0)
          ? rawValue
          : 0.0;
      if (value == 0) continue;

      final date = (dateOf ?? salaryRecordDate)(record);
      if (date != null) {
        if (date.isAfter(current)) continue;
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
    final start = AppDateUtils.periodStart(period, currentValue);
    final end = AppDateUtils.periodEnd(period, currentValue);

    final target = _dateOnly(date);
    return !target.isBefore(_dateOnly(start)) && !target.isAfter(_dateOnly(end));
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
          'email': record['email'],
          'name': record['name'] ?? record['workerName'],
        });
      }
    }
    return leaveDays;
  }

  static List<Map<String, dynamic>> mergedLeaveDaysForPeriod({
    required List<Map<String, dynamic>> timeOffRecords,
    required List<Map<String, dynamic>> attendanceRecords,
    required String period,
    DateTime? now,
    List<Map<String, dynamic>> workers = const [],
  }) {
    final merged = <String, Map<String, dynamic>>{};

    final identityIndex = workers.isEmpty
        ? null
        : _buildWorkerIdentityIndex(workers);

    for (final leave in leaveDaysForPeriod(
      records: timeOffRecords,
      period: period,
      now: now,
    )) {
      final date = leave['date'] as DateTime;
      final key = _leaveIdentity(leave, date, identityIndex);
      merged.putIfAbsent(key, () => leave);
    }

    for (final attendance in attendanceRecords) {
      if (attendance['excludeFromLeaveChart'] == true) continue;

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

      if (type.isEmpty) continue;

      final normalized = <String, dynamic>{
        ...attendance,
        'status': 'leave',
        'type': type,
        'date': date,
      };
      merged[_leaveIdentity(normalized, date, identityIndex)] = normalized;
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

  static Map<String, String> _buildWorkerIdentityIndex(
    List<Map<String, dynamic>> workers,
  ) {
    final index = <String, String>{};
    final nameCounts = <String, int>{};

    for (final worker in workers) {
      final workerId = (worker['workerId'] ?? worker['id'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final email = WorkerIdentity.normalizeEmail(worker['email']);
      final name = WorkerIdentity.normalizeName(worker['name']);

      final canonical = workerId.isNotEmpty
          ? 'id:$workerId'
          : (email.isNotEmpty ? 'email:$email' : 'name:$name');
      if (workerId.isNotEmpty) index['id:$workerId'] = canonical;
      if (email.isNotEmpty) index['email:$email'] = canonical;
      if (name.isNotEmpty) {
        nameCounts[name] = (nameCounts[name] ?? 0) + 1;
      }
    }

    for (final worker in workers) {
      final name = WorkerIdentity.normalizeName(worker['name']);
      if (name.isEmpty || (nameCounts[name] ?? 0) != 1) continue;
      final workerId = (worker['workerId'] ?? worker['id'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final email = WorkerIdentity.normalizeEmail(worker['email']);
      final canonical = workerId.isNotEmpty
          ? 'id:$workerId'
          : (email.isNotEmpty ? 'email:$email' : 'name:$name');
      index['name:$name'] = canonical;
    }
    return index;
  }

  static String _canonicalWorkerKey(
    Map<String, dynamic> record,
    Map<String, String> index,
  ) {
    final recordWorkerId = (record['workerId'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (recordWorkerId.isNotEmpty && index.containsKey('id:$recordWorkerId')) {
      return index['id:$recordWorkerId']!;
    }
    final recordEmail = WorkerIdentity.normalizeEmail(record['email']);
    if (recordEmail.isNotEmpty && index.containsKey('email:$recordEmail')) {
      return index['email:$recordEmail']!;
    }
    final recordName = WorkerIdentity.normalizeName(
      record['name'] ?? record['workerName'],
    );
    if (recordName.isNotEmpty && index.containsKey('name:$recordName')) {
      return index['name:$recordName']!;
    }

    if (recordWorkerId.isNotEmpty) return 'id:$recordWorkerId';
    if (recordEmail.isNotEmpty) return 'email:$recordEmail';
    return 'name:$recordName';
  }

  static String _leaveIdentity(
    Map<String, dynamic> record,
    DateTime date,
    Map<String, String>? identityIndex,
  ) {
    final worker = identityIndex == null
        ? (record['workerId'] ?? record['email'] ?? record['name'] ?? '')
              .toString()
              .trim()
              .toLowerCase()
        : _canonicalWorkerKey(record, identityIndex);
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

  static double _salaryValue(Map<String, dynamic> record) {
    final raw =
        record['netSalaryAmount'] ??
        record['amount'] ??
        record['netSalary'] ??
        record['salary'];

    if (raw is num) return raw.toDouble();

    return PayrollService.extractSalary(raw?.toString() ?? '');
  }

  static DashboardChartSeries buildGuestSalarySeries({
    required List<Map<String, dynamic>> salaryRecords,
    required List<Map<String, dynamic>> expenses,
    required double totalSalary,
    required String period,
    DateTime? now,
  }) {
    return buildSeries(
      records: salaryRecords,
      valueOf: _salaryValue,
      period: period,
      dateOf: salaryRecordDate,
      now: now,
      placeUndatedInCurrentPeriod: true,
    );
  }

  static double _sum(List<DashboardChartPoint> points) =>
      points.fold<double>(0, (sum, point) => sum + point.value);
}
