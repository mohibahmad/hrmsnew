import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/payroll_service.dart';
import 'package:hrms/services/time_off_service.dart';

void main() {
  group('payPeriodStart / payPeriodEnd (salary day boundaries)', () {
    test('before pay day the current period is the one that just started', () {
      // Salary day 6, reference 5 Aug: period is 6 Jul – 6 Aug.
      final start = PayrollService.payPeriodStart(DateTime(2026, 8, 5), 6);
      final end = PayrollService.payPeriodEnd(DateTime(2026, 8, 5), 6);
      expect(start, DateTime(2026, 7, 6));
      expect(end, DateTime(2026, 8, 6));
    });

    test('on the pay day itself the just-ended period is still shown', () {
      // 6 Aug is the pay day and the first day of the next cycle, so the
      // displayed current period stays 6 Jul – 6 Aug (6 Aug excluded).
      final start = PayrollService.payPeriodStart(DateTime(2026, 8, 6), 6);
      final end = PayrollService.payPeriodEnd(DateTime(2026, 8, 6), 6);
      expect(start, DateTime(2026, 7, 6));
      expect(end, DateTime(2026, 8, 6));
    });

    test('after the pay day the next cycle starts', () {
      final start = PayrollService.payPeriodStart(DateTime(2026, 8, 7), 6);
      final end = PayrollService.payPeriodEnd(DateTime(2026, 8, 7), 6);
      expect(start, DateTime(2026, 8, 6));
      expect(end, DateTime(2026, 9, 6));
    });

    test('period always spans one full salary-day cycle', () {
      final start = PayrollService.payPeriodStart(DateTime(2026, 8, 20), 3);
      final end = PayrollService.payPeriodEnd(DateTime(2026, 8, 20), 3);
      expect(start, DateTime(2026, 8, 3));
      expect(end, DateTime(2026, 9, 3));
      expect(end.difference(start).inDays, 31);
    });

    test('invalid salary day falls back to the calendar month', () {
      final start = PayrollService.payPeriodStart(DateTime(2026, 8, 10), null);
      final end = PayrollService.payPeriodEnd(DateTime(2026, 8, 10), null);
      expect(start, DateTime(2026, 8, 1));
      expect(end, DateTime(2026, 8, 31));
    });
  });

  group('monthlyLeaveCounts (leave counts in payroll only after the day)', () {
    final worker = {'workerId': 'w1', 'email': 'a@x.com', 'name': 'A'};
    final record = {
      'workerId': 'w1',
      'action': 'Annual Leave',
      'status': 'Approved',
      'selectedDates': [
        DateTime(2026, 8, 10),
        DateTime(2026, 8, 20),
      ],
    };

    test('future assigned leave does not count in the current month', () {
      final counts = TimeOffService.monthlyLeaveCounts(
        worker,
        [record],
        month: DateTime(2026, 8, 1),
        referenceDate: DateTime(2026, 8, 15),
      );
      expect(counts['paidLeaves'], 1,
          reason: 'Only 10 Aug has arrived; 20 Aug must not count yet');
      expect(counts['leaves'], 1);
    });

    test('a leave day that has arrived counts that same day', () {
      final counts = TimeOffService.monthlyLeaveCounts(
        worker,
        [record],
        month: DateTime(2026, 8, 1),
        referenceDate: DateTime(2026, 8, 10),
      );
      expect(counts['paidLeaves'], 1,
          reason: 'Today the worker is On Leave, so payroll shows +1');
    });

    test('all elapsed leave dates count when the month is over', () {
      final counts = TimeOffService.monthlyLeaveCounts(
        worker,
        [record],
        month: DateTime(2026, 8, 1),
        referenceDate: DateTime(2026, 8, 31),
      );
      expect(counts['paidLeaves'], 2);
    });

    test('future months still count nothing', () {
      final counts = TimeOffService.monthlyLeaveCounts(
        worker,
        [record],
        month: DateTime(2026, 9, 1),
        referenceDate: DateTime(2026, 8, 15),
      );
      expect(counts['paidLeaves'], 0);
    });
  });

  group('prorationFactor (no pay before the joining date)', () {
    final periodStart = DateTime(2026, 7, 3);
    final periodEnd = DateTime(2026, 8, 3);

    test('worker who joined before the period gets the full factor', () {
      final factor = PayrollService.prorationFactor(
        joiningDate: DateTime(2026, 6, 1),
        periodStart: periodStart,
        periodEnd: periodEnd,
        totalWorkDays: 27,
      );
      expect(factor, 1.0);
    });

    test('worker who joined mid period is prorated', () {
      // Joins 15 Jul, works Mon–Sat: working days in the period = 27,
      // days from 15 Jul to 2 Aug inclusive = 17.
      final workingDates = <DateTime>{
        for (var d = periodStart; d.isBefore(periodEnd);
            d = d.add(const Duration(days: 1)))
          if (d.weekday != DateTime.sunday) d,
      };
      final factor = PayrollService.prorationFactor(
        joiningDate: DateTime(2026, 7, 15),
        periodStart: periodStart,
        periodEnd: periodEnd,
        totalWorkDays: 27,
        workingDates: workingDates,
      );
      expect(factor, greaterThan(0.5));
      expect(factor, lessThan(0.75));
    });

    test('worker who joined after the period gets 0', () {
      final factor = PayrollService.prorationFactor(
        joiningDate: DateTime(2026, 9, 1),
        periodStart: periodStart,
        periodEnd: periodEnd,
        totalWorkDays: 27,
      );
      expect(factor, 0.0);
    });

    test('no joining date means full pay', () {
      final factor = PayrollService.prorationFactor(
        joiningDate: null,
        periodStart: periodStart,
        periodEnd: periodEnd,
        totalWorkDays: 27,
      );
      expect(factor, 1.0);
    });
  });

  group('prorated salary calculations', () {
    test('calculatePayroll prorates the gross and net salary', () {
      final full = PayrollService.calculatePayroll(
        salary: 'Rs 90,000',
        totalWorkDays: '27',
        daysWorked: '27',
        absents: '0',
        leaves: '0',
        salaryType: 'Monthly',
      );
      final prorated = PayrollService.calculatePayroll(
        salary: 'Rs 90,000',
        totalWorkDays: '27',
        daysWorked: '17',
        absents: '0',
        leaves: '0',
        salaryType: 'Monthly',
        prorationFactor: 17 / 27,
      );
      expect(full['netSalary'] as num, 90000);
      expect(prorated['netSalary'] as num, closeTo(90000 * 17 / 27, 0.001));
    });

    test('calculateNetFromTotals prorates with deductions', () {
      final prorated = PayrollService.calculateNetFromTotals(
        salary: 'Rs 90,000',
        absentDeduction: '3333.33',
        salaryType: 'Monthly',
        prorationFactor: 0.6,
      );
      expect(prorated, closeTo(90000 * 0.6 - 3333.33, 0.01));
    });
  });
}
