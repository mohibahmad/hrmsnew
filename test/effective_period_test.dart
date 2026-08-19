import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/attendance_service.dart';
import 'package:hrms/utils/utils.dart';

void main() {
  group('AppDateUtils.effectivePeriodEnd — future dates excluded from stats', () {
    final now = DateTime(2026, 8, 17);

    test('end is clamped to today when the range extends into the future', () {

      expect(AppDateUtils.effectivePeriodEnd('6 Month', now), DateTime(2026, 8, 17));

      expect(AppDateUtils.effectivePeriodEnd('Month', now), DateTime(2026, 8, 17));

      expect(AppDateUtils.effectivePeriodEnd('Yearly', now), DateTime(2026, 8, 17));

      expect(AppDateUtils.effectivePeriodEnd('All Time', now), DateTime(2026, 8, 17));

      expect(AppDateUtils.effectivePeriodEnd('Today', now), DateTime(2026, 8, 17));

      expect(AppDateUtils.effectivePeriodEnd('Week', now), DateTime(2026, 8, 17));
    });

    test('isDateWithinEffectivePeriod counts dates <= today only', () {

      expect(
        AppDateUtils.isDateWithinEffectivePeriod(DateTime(2026, 8, 17), '6 Month', now: now),
        isTrue,
      );
      expect(
        AppDateUtils.isDateWithinEffectivePeriod(DateTime(2026, 3, 1), '6 Month', now: now),
        isTrue,
      );

      expect(
        AppDateUtils.isDateWithinEffectivePeriod(DateTime(2026, 9, 5), '6 Month', now: now),
        isFalse,
      );

      expect(
        AppDateUtils.isDateWithinEffectivePeriod(DateTime(2026, 2, 28), '6 Month', now: now),
        isFalse,
      );
    });

    test('isTimestampWithinPeriod inherits the future-date rule', () {

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
