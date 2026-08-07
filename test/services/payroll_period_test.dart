import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/payroll_service.dart';
import 'package:hrms/services/time_off_service.dart';

void main() {
  group('payPeriodStart / payPeriodEnd (salary day boundaries)', () {
    test('before pay day the current period is the one that just started', () {
      
      final start = PayrollService.payPeriodStart(DateTime(2026, 8, 5), 6);
      final end = PayrollService.payPeriodEnd(DateTime(2026, 8, 5), 6);
      expect(start, DateTime(2026, 7, 6));
      expect(end, DateTime(2026, 8, 6));
    });

    test('on the pay day itself the just-ended period is still shown', () {
      
      
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

    
    final threeDayRecord = {
      'workerId': 'w1',
      'action': 'Annual Leave',
      'status': 'Approved',
      'selectedDates': [
        DateTime(2026, 8, 10),
        DateTime(2026, 8, 11),
        DateTime(2026, 8, 12),
      ],
    };

    test('on 10 Aug the 10th does NOT count yet (leave counts AFTER the day)', () {
      final counts = TimeOffService.monthlyLeaveCounts(
        worker,
        [threeDayRecord],
        month: DateTime(2026, 8, 1),
        referenceDate: DateTime(2026, 8, 10),
      );
      expect(counts['paidLeaves'], 0,
          reason: '10 Aug has not yet passed; no leaves counted yet');
    });

    test('after 12 Aug only the 10th and 11th count (3 leaves 10–12 Aug)', () {
      final counts = TimeOffService.monthlyLeaveCounts(
        worker,
        [threeDayRecord],
        month: DateTime(2026, 8, 1),
        referenceDate: DateTime(2026, 8, 12),
      );
      expect(counts['paidLeaves'], 2,
          reason: '10 and 11 Aug have passed; 12 Aug not yet');
    });

    test('August payroll shows Paid Leave = 3 for the full month', () {
      final counts = TimeOffService.monthlyLeaveCounts(
        worker,
        [threeDayRecord],
        month: DateTime(2026, 8, 1),
        referenceDate: DateTime(2026, 8, 31),
      );
      expect(counts['paidLeaves'], 3,
          reason: 'All 3 days have passed by end of August');
    });

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

    test('a leave day does NOT count on the same day, only after it passes', () {
      final counts = TimeOffService.monthlyLeaveCounts(
        worker,
        [record],
        month: DateTime(2026, 8, 1),
        referenceDate: DateTime(2026, 8, 10),
      );
      expect(counts['paidLeaves'], 0,
          reason: '10 Aug has not yet passed; leave not counted yet');
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

    test('calculateNetFromTotals deducts unpaid leave days like manual payroll', () {
      final net = PayrollService.calculateNetFromTotals(
        salary: 'Rs 90,000',
        absentDeduction: '',
        leaveDeduction: '3333.33',
        customDeduction: '0',
        salaryType: 'Monthly',
      );
      expect(net, closeTo(90000 - 3333.33, 0.01));
    });

    test('calculatePayroll deducts unpaid leaves at the daily rate (auto payroll parity)', () {
      final result = PayrollService.calculatePayroll(
        salary: 'Rs 90,000',
        totalWorkDays: '27',
        daysWorked: '24',
        absents: '0',
        leaves: '3',
        salaryType: 'Monthly',
      );
      final dailyRate = 90000 / 27;
      expect(result['netSalary'] as num, closeTo(90000 - 3 * dailyRate, 0.001));
      expect(result['leaveDeduction'] as num, closeTo(3 * dailyRate, 0.001));
    });
  });

  group('previousPayrollCheckMonth (pay day boundary)', () {
    final activeMonth = DateTime(2026, 8, 1); 

    test('on the pay day the active month itself must be complete', () {
      
      expect(
        PayrollService.previousPayrollCheckMonth(
          activeMonth,
          6,
          referenceDate: DateTime(2026, 8, 6),
        ),
        DateTime(2026, 8, 1),
      );
    });

    test('after the pay day the ended period is still the one to check', () {
      expect(
        PayrollService.previousPayrollCheckMonth(
          activeMonth,
          6,
          referenceDate: DateTime(2026, 8, 20),
        ),
        DateTime(2026, 8, 1),
      );
    });

    test('when the active period is still running the previous month is checked', () {
      expect(
        PayrollService.previousPayrollCheckMonth(
          activeMonth,
          6,
          referenceDate: DateTime(2026, 8, 1),
        ),
        DateTime(2026, 7, 1),
      );
    });

    test('an advanced active month checks the month whose period just ended', () {
      
      
      expect(
        PayrollService.previousPayrollCheckMonth(
          DateTime(2026, 9, 1),
          6,
          referenceDate: DateTime(2026, 8, 7),
        ),
        DateTime(2026, 8, 1),
      );
    });

    test('null salary day falls back to calendar-month boundaries', () {
      
      
      expect(
        PayrollService.previousPayrollCheckMonth(
          activeMonth,
          null,
          referenceDate: DateTime(2026, 8, 10),
        ),
        DateTime(2026, 7, 1),
      );
    });
  });

  group('workerJoinedBeforePeriodEnd (first cycle = next period)', () {
    
    final month = DateTime(2026, 8, 1);

    test('worker who joined before the period end belongs to this period', () {
      expect(
        PayrollService.workerJoinedBeforePeriodEnd(
          {'joiningDate': '2026-07-20'},
          month,
          6,
        ),
        isTrue,
      );
    });

    test('worker who joined ON the period end belongs to the NEXT cycle', () {
      
      
      expect(
        PayrollService.workerJoinedBeforePeriodEnd(
          {'joiningDate': DateTime(2026, 8, 6)},
          month,
          6,
        ),
        isFalse,
      );
    });

    test('worker who joined after the period end is excluded too', () {
      expect(
        PayrollService.workerJoinedBeforePeriodEnd(
          {'joiningDate': '2026-08-10'},
          month,
          6,
        ),
        isFalse,
      );
    });

    test('no joining date means the worker is expected for the period', () {
      expect(
        PayrollService.workerJoinedBeforePeriodEnd({'name': 'A'}, month, 6),
        isTrue,
      );
    });

    test('dateOfJoining fallback field is honoured', () {
      expect(
        PayrollService.workerJoinedBeforePeriodEnd(
          {'dateOfJoining': DateTime(2026, 8, 6)},
          month,
          6,
        ),
        isFalse,
      );
    });
  });

  group('allWorkersHavePayrollRecords (records mandatory, payment optional)', () {
    final workers = <Map<String, dynamic>>[
      {'workerId': 'w1', 'email': 'a@x.com', 'name': 'A'},
      {'workerId': 'w2', 'email': 'b@x.com', 'name': 'B'},
      {'workerId': 'w3', 'email': 'c@x.com', 'name': 'C'},
    ];
    final month = DateTime(2026, 8, 1);

    Map<String, dynamic> record(String id, {bool paid = false}) => {
      'workerId': id,
      'totalWorkDays': '22',
      'status': paid ? 'Paid' : 'Unpaid',
      'createdAt': DateTime(2026, 8, 10),
      'payrollMonth': month,
    };

    test('all workers with records passes even when nobody is paid yet', () {
      final docs = [record('w1'), record('w2'), record('w3')];
      expect(
        PayrollService.allWorkersHavePayrollRecords(
          workers,
          docs,
          month,
          salaryDay: 6,
        ),
        isTrue,
        reason: 'Saved-but-unpaid payrolls must not block the next period',
      );
    });

    test('a worker missing a record fails the gate', () {
      final docs = [record('w1'), record('w2')];
      expect(
        PayrollService.allWorkersHavePayrollRecords(
          workers,
          docs,
          month,
          salaryDay: 6,
        ),
        isFalse,
      );
    });

    test('worker who joined on the period end does not block the gate', () {
      final workersWithLateJoiner = [
        ...workers,
        {'workerId': 'w4', 'email': 'd@x.com', 'name': 'D',
         'joiningDate': DateTime(2026, 8, 6)},
      ];
      final docs = [record('w1'), record('w2'), record('w3')];
      expect(
        PayrollService.allWorkersHavePayrollRecords(
          workersWithLateJoiner,
          docs,
          month,
          salaryDay: 6,
        ),
        isTrue,
        reason: 'w4 first cycle is 6 Aug – 6 Sep, not 6 Jul – 6 Aug',
      );
    });

    test('ineligible workers are ignored by the gate', () {
      final docs = [record('w1'), record('w2')];
      expect(
        PayrollService.allWorkersHavePayrollRecords(
          [
            ...workers,
            {'workerId': 'w9', 'email': 'z@x.com', 'name': 'Z',
             'employmentStatus': 'Inactive'},
          ],
          docs,
          month,
          salaryDay: 6,
        ),
        isFalse,
      );
    });

    test('empty worker list trivially passes', () {
      expect(
        PayrollService.allWorkersHavePayrollRecords(
          [],
          const [],
          month,
          salaryDay: 6,
        ),
        isTrue,
      );
    });
  });

  group('absence deduction (per-day field drives the deduction)', () {
    test('empty per-day absence deduction means NO deduction', () {
      final result = PayrollService.calculatePayroll(
        salary: 'Rs 90,000',
        totalWorkDays: '30',
        daysWorked: '29',
        absents: '1',
        leaves: '0',
        salaryType: 'Monthly',
      );
      expect(result['absentDeduction'] as num, 0);
      expect(result['netSalary'] as num, 90000);
    });

    test('explicit 0 per-day absence deduction gives no deduction', () {
      final result = PayrollService.calculatePayroll(
        salary: 'Rs 90,000',
        totalWorkDays: '30',
        daysWorked: '29',
        absents: '1',
        leaves: '0',
        absentDeductionPerDay: '0',
        salaryType: 'Monthly',
      );
      expect(result['absentDeduction'] as num, 0);
    });

    test('configured per-day absence deduction still deducts', () {
      final result = PayrollService.calculatePayroll(
        salary: 'Rs 90,000',
        totalWorkDays: '30',
        daysWorked: '29',
        absents: '1',
        leaves: '0',
        absentDeductionPerDay: '1000',
        salaryType: 'Monthly',
      );
      expect(result['absentDeduction'] as num, 1000);
      expect(result['netSalary'] as num, 89000);
    });

    test('empty per-day leave deduction keeps the daily-rate fallback', () {
      final result = PayrollService.calculatePayroll(
        salary: 'Rs 90,000',
        totalWorkDays: '30',
        daysWorked: '29',
        absents: '0',
        leaves: '1',
        salaryType: 'Monthly',
      );
      final dailyRate = 90000 / 30;
      expect(result['leaveDeduction'] as num, closeTo(dailyRate, 0.01));
      expect(result['netSalary'] as num, closeTo(90000 - dailyRate, 0.01));
    });
  });

  group('combinePayroll excludes workers joining on the period end', () {
    final workers = <Map<String, dynamic>>[
      {'workerId': 'w1', 'email': 'a@x.com', 'name': 'A'},
      {
        'workerId': 'w2',
        'email': 'b@x.com',
        'name': 'B',
        'joiningDate': DateTime(2026, 8, 6),
      },
    ];
    
    final month = DateTime(2026, 8, 1);

    test('late joiner is not listed in the previous period payroll', () {
      final combined = PayrollService.combinePayroll(
        workers,
        const [],
        month: month,
        salaryDay: 6,
      );
      expect(
        combined.map((w) => w['workerId']),
        ['w1'],
        reason: 'w2 joined on the period end so their first cycle is next month',
      );
    });

    test('late joiner appears in the next period (6 Aug – 6 Sep)', () {
      final combined = PayrollService.combinePayroll(
        workers,
        const [],
        month: DateTime(2026, 9, 1),
        salaryDay: 6,
      );
      expect(combined.length, 2);
      expect(combined.map((w) => w['workerId']), contains('w2'));
    });

    test('worker who joined before the period end stays in the list', () {
      final combined = PayrollService.combinePayroll(
        [
          ...workers,
          {
            'workerId': 'w3',
            'email': 'c@x.com',
            'name': 'C',
            'joiningDate': DateTime(2026, 7, 20),
          },
        ],
        const [],
        month: month,
        salaryDay: 6,
      );
      expect(combined.length, 2);
      expect(combined.map((w) => w['workerId']), contains('w3'));
    });
  });
}
