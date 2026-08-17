import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/attendance_service.dart';
import 'package:hrms/utils/utils.dart';

void main() {
  group('AppDateUtils.effectivePeriodEnd — future dates excluded from stats', () {
    final now = DateTime(2026, 8, 17);

    test('end is clamped to today when the range extends into the future', () {
      // Last 6 Months → end of current month (Aug 31) → clamped to Aug 17.
      expect(AppDateUtils.effectivePeriodEnd('6 Month', now), DateTime(2026, 8, 17));
      // This Month → end of month → clamped to today.
      expect(AppDateUtils.effectivePeriodEnd('Month', now), DateTime(2026, 8, 17));
      // This Year → Dec 31 → clamped to today.
      expect(AppDateUtils.effectivePeriodEnd('Yearly', now), DateTime(2026, 8, 17));
      // All Time → clamped to today.
      expect(AppDateUtils.effectivePeriodEnd('All Time', now), DateTime(2026, 8, 17));
      // Today → today.
      expect(AppDateUtils.effectivePeriodEnd('Today', now), DateTime(2026, 8, 17));
      // Week (Monday Aug 17 → Sunday Aug 23) → clamped to today (Aug 17).
      expect(AppDateUtils.effectivePeriodEnd('Week', now), DateTime(2026, 8, 17));
    });

    test('isDateWithinEffectivePeriod counts dates <= today only', () {
      // Last 6 Months window: Mar 1–Aug 17 effective (Aug minus 5 months).
      expect(
        AppDateUtils.isDateWithinEffectivePeriod(DateTime(2026, 8, 17), '6 Month', now: now),
        isTrue,
      );
      expect(
        AppDateUtils.isDateWithinEffectivePeriod(DateTime(2026, 3, 1), '6 Month', now: now),
        isTrue,
      );
      // Future approved Time Off (September) must NOT be counted.
      expect(
        AppDateUtils.isDateWithinEffectivePeriod(DateTime(2026, 9, 5), '6 Month', now: now),
        isFalse,
      );
      // Before the window start → excluded.
      expect(
        AppDateUtils.isDateWithinEffectivePeriod(DateTime(2026, 2, 28), '6 Month', now: now),
        isFalse,
      );
    });

    test('isTimestampWithinPeriod inherits the future-date rule', () {
      // Far-future date is always beyond today, so never counted in any period.
      expect(
        AppDateUtils.isTimestampWithinPeriod(DateTime(2099, 9, 10), '6 Month'),
        isFalse,
      );
      expect(
        AppDateUtils.isTimestampWithinPeriod(DateTime(2099, 9, 10), 'All Time'),
        isFalse,
      );
    });

    test('attendance counts ignore future leave dates in the selected period', () {
      final worker = {
        'workerId': 'w1',
        'id': 'w1',
        'name': 'Aisha Hill',
        'email': 'aisha@example.com',
      };

      final attendanceRecords = [
        {
          'id': 'att-1',
          'workerId': 'w1',
          'name': 'Aisha Hill',
          'email': 'aisha@example.com',
          'attendanceDate': '2026-08-10',
          'status': 'Present',
        },
        {
          'id': 'att-2',
          'workerId': 'w1',
          'name': 'Aisha Hill',
          'email': 'aisha@example.com',
          'attendanceDate': '2026-09-05',
          'status': 'Leave',
        },
      ];

      final timeOffRecords = [
        {
          'id': 'leave-1',
          'workerId': 'w1',
          'name': 'Aisha Hill',
          'email': 'aisha@example.com',
          'type': 'Annual Leave',
          'status': 'Approved',
          'startDate': '2026-08-10',
          'endDate': '2026-08-10',
          'selectedDates': ['2026-08-10'],
          'isPaidLeave': true,
        },
        {
          'id': 'leave-2',
          'workerId': 'w1',
          'name': 'Aisha Hill',
          'email': 'aisha@example.com',
          'type': 'Annual Leave',
          'status': 'Approved',
          'startDate': '2026-09-05',
          'endDate': '2026-09-15',
          'selectedDates': ['2026-09-05', '2026-09-06', '2026-09-07', '2026-09-08', '2026-09-09', '2026-09-10', '2026-09-11', '2026-09-12', '2026-09-13', '2026-09-14', '2026-09-15'],
          'isPaidLeave': true,
        },
      ];

      final counts = AttendanceService.countRecordsByStatus(
        attendanceRecords,
        timeOffRecords,
        period: '6 Month',
        referenceDate: DateTime(2026, 8, 17),
      );

      expect(counts['present'], 0);
      expect(counts['absent'], 0);
      expect(counts['leave'], 1);
    });
  });
}
