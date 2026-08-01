import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/payroll_service.dart';

void main() {
  test('Today payroll uses the actual paid date', () {
    final record = {
      'status': 'Paid',
      'payPeriod': DateTime(2026, 7, 1),
      'paidAt': DateTime(2026, 8, 1, 14, 30),
    };

    expect(PayrollService.wasPaidOn(record, DateTime(2026, 8, 1)), isTrue);
    expect(PayrollService.wasPaidOn(record, DateTime(2026, 7, 1)), isFalse);
    expect(
      PayrollService.wasPaidOn({
        'status': 'Unpaid',
        'createdAt': DateTime(2026, 8, 1),
      }, DateTime(2026, 8, 1)),
      isFalse,
    );
  });

  test('leave allowance is not used as the payroll leave count', () {
    final counts = PayrollService.attendanceCounts({
      'annualLeaves': '100',
      'availableAnnualLeaves': '100',
      'leavesUsed': '0',
    });

    expect(counts['absents'], 0);
    expect(counts['leaves'], 0);
  });

  test('saved payroll attendance counts are preserved until refresh', () {
    final counts = PayrollService.attendanceCounts({
      'annualLeaves': '100',
      'absents': '2',
      'leaves': '3',
    });

    expect(counts['absents'], 2);
    expect(counts['leaves'], 3);
  });

  test('current worker salary overrides an older payroll snapshot', () {
    final combined = PayrollService.combinePayroll(
      const [
        {
          'id': 'worker-1',
          'name': 'Ali',
          'email': 'ali@example.com',
          'salaryAmount': '125000',
          'currency': 'PKR',
        },
      ],
      [
        {
          'id': 'payroll-july',
          'name': 'Ali',
          'email': 'ali@example.com',
          'salary': r'$ 900',
          'salaryAmount': '900',
          'currency': 'USD',
        },
      ],
      month: DateTime(2026, 7, 1),
      allowUndatedRecords: true,
    );

    expect(combined.single['salaryAmount'], '125000');
    expect(combined.single['currency'], 'PKR');
    expect(combined.single['salary'], 'Rs 125000');
  });

  test('company currency overrides mixed worker currencies in payroll', () {
    final combined = PayrollService.combinePayroll(
      const [
        {
          'id': 'worker-pk',
          'name': 'Ali',
          'email': 'ali@example.com',
          'salaryAmount': '125000',
          'currency': 'PKR',
        },
        {
          'id': 'worker-uk',
          'name': 'Sara',
          'email': 'sara@example.com',
          'salary': '£ 3500',
          'currency': 'GBP',
        },
      ],
      const [],
      month: DateTime(2026, 8, 1),
      companyCurrency: 'USD',
    );

    expect(combined.map((worker) => worker['currency']).toSet(), {'USD'});
    expect(combined[0]['salary'], r'$ 125000');
    expect(combined[1]['salary'], r'$ 3,500');
  });

  test('company currency also normalizes historical payroll amounts', () {
    final combined = PayrollService.combinePayroll(
      const [
        {'id': 'worker-1', 'name': 'Ali', 'email': 'ali@example.com'},
      ],
      const [
        {
          'workerId': 'worker-1',
          'email': 'ali@example.com',
          'salary': 'Rs 125000',
          'netSalary': 'Rs 120500.25',
          'currency': 'PKR',
        },
      ],
      month: DateTime(2026, 8, 1),
      allowUndatedRecords: true,
      companyCurrency: 'EUR',
    );

    expect(combined.single['currency'], 'EUR');
    expect(combined.single['salary'], '€ 125,000');
    expect(combined.single['netSalary'], '€ 120,500.25');
  });

  test('worker ID keeps payroll connected after email changes', () {
    final combined = PayrollService.combinePayroll(
      const [
        {'id': 'worker-1', 'name': 'Ali Updated', 'email': 'new@example.com'},
      ],
      [
        {
          'id': 'payroll-july',
          'workerId': 'worker-1',
          'name': 'Ali',
          'email': 'old@example.com',
          'status': 'Paid',
          'totalWorkDays': '22',
        },
      ],
      month: DateTime(2026, 7, 1),
      allowUndatedRecords: true,
    );

    expect(combined.single['hasPayrollRecord'], isTrue);
    expect(combined.single['workerId'], 'worker-1');
  });

  test('saved payroll salary is used when worker salary is unavailable', () {
    expect(PayrollService.currentSalaryDisplay({'salary': r'$ 900'}), r'$ 900');
  });

  test('previous month payroll does not mark current month as paid', () {
    final combined = PayrollService.combinePayroll(
      const [
        {'id': 'worker-1', 'name': 'Ali', 'email': 'ali@example.com'},
      ],
      [
        {
          'id': 'payroll-june',
          'name': 'Ali',
          'email': 'ali@example.com',
          'status': 'Paid',
          'totalWorkDays': '22',
          'createdAt': DateTime(2026, 6, 30),
        },
      ],
      month: DateTime(2026, 7, 1),
    );

    expect(combined.single['hasPayrollRecord'], isFalse);
  });

  test('current month payroll marks worker as paid', () {
    final combined = PayrollService.combinePayroll(
      const [
        {'id': 'worker-1', 'name': 'Ali', 'email': 'ali@example.com'},
      ],
      [
        {
          'id': 'payroll-july',
          'name': 'Ali',
          'email': 'ali@example.com',
          'status': 'Paid',
          'totalWorkDays': '22',
          'createdAt': DateTime(2026, 7, 2),
        },
      ],
      month: DateTime(2026, 7, 1),
    );

    expect(combined.single['hasPayrollRecord'], isTrue);
    expect(combined.single['status'], 'Paid');
  });

  test('deleted workers are not recreated from historical payroll records', () {
    final combined = PayrollService.combinePayroll(const [], [
      {
        'id': 'payroll-july',
        'workerId': 'deleted-worker',
        'name': 'Deleted Worker',
        'status': 'Paid',
        'payPeriod': '2026-07-01',
      },
    ], month: DateTime(2026, 7, 1));

    expect(combined, isEmpty);
  });

  test('dashboard payroll records only include active workers', () {
    final records = PayrollService.payrollRecordsForActiveWorkers(
      const [
        {
          'id': 'active-worker',
          'name': 'Active Worker',
          'email': 'active@example.com',
        },
      ],
      const [
        {
          'workerId': 'active-worker',
          'name': 'Active Worker',
          'netSalary': 5000,
        },
        {
          'workerId': 'deleted-worker',
          'name': 'Deleted Worker',
          'netSalary': 7000,
        },
      ],
    );

    expect(records, hasLength(1));
    expect(records.single['workerId'], 'active-worker');
  });

  test('dashboard payroll is empty when every worker is deleted', () {
    final records = PayrollService.payrollRecordsForActiveWorkers(
      const [],
      const [
        {'workerId': 'deleted-worker', 'netSalary': 7000},
      ],
    );

    expect(records, isEmpty);
  });

  test('dashboard payroll supports legacy active workers without IDs', () {
    final records = PayrollService.payrollRecordsForActiveWorkers(
      const [
        {'name': 'Legacy Worker', 'email': 'legacy@example.com'},
      ],
      const [
        {
          'workerId': 'legacy-generated-id',
          'workerName': 'Legacy Worker',
          'netSalary': 4000,
        },
      ],
    );

    expect(records, hasLength(1));
  });

  test('Firestore timestamp is filtered by payroll month', () {
    final record = {'createdAt': Timestamp.fromDate(DateTime(2026, 6, 15))};

    expect(
      PayrollService.isRecordInMonth(record, DateTime(2026, 7, 1)),
      isFalse,
    );
    expect(
      PayrollService.isRecordInMonth(record, DateTime(2026, 6, 1)),
      isTrue,
    );
  });

  test('absence deduction is 0 when no custom deduction per day is set', () {
    final result = PayrollService.calculatePayroll(
      salary: 'Rs 100000',
      totalWorkDays: '20',
      daysWorked: '18',
      absents: '2',
      leaves: '0',
    );

    expect(result['grossSalary'], 100000);
    expect(result['absentDays'], 2);
    expect(result['workedDays'], 18);
    expect(result['absentDeduction'], 0);
    expect(result['netSalary'], 100000);
  });

  test('net salary display does not auto-deduct detected absences', () {
    final netSalary = PayrollService.getNetSalaryDisplay(
      salary: 'Rs 100000',
      totalWorkDays: '20',
      absents: '2',
    );

    expect(netSalary, 'Rs 100.0K');
  });

  test(
    'unpaid leave deduction is 0 when no custom deduction per day is set',
    () {
      final result = PayrollService.calculatePayroll(
        salary: 'Rs 100000',
        totalWorkDays: '20',
        daysWorked: '19',
        absents: '0',
        leaves: '1',
      );

      expect(result['leaveDeduction'], 0);
      expect(result['netSalary'], 100000);
    },
  );

  test('custom deduction is an override rather than a second penalty', () {
    final result = PayrollService.calculatePayroll(
      salary: 'Rs 100000',
      totalWorkDays: '20',
      daysWorked: '19',
      absents: '1',
      leaves: '0',
      absentDeductionPerDay: '3000',
    );

    expect(result['absentDeduction'], 3000);
    expect(result['netSalary'], 97000);
  });

  test('flat deductions update net payment even when attendance is zero', () {
    final netPayment = PayrollService.calculateNetFromTotals(
      salary: 'Rs 55000',
      absentDeduction: '3,000',
      leaveDeduction: '2,000',
    );

    expect(netPayment, 50000);
  });

  test('salary parser supports grouped commas and decimal commas', () {
    expect(PayrollService.extractSalary('Rs 123,123'), 123123);
    expect(PayrollService.extractSalary('€ 1.234,56'), 1234.56);
  });

  test('salary parser preserves compact K M B and T suffix values', () {
    expect(PayrollService.extractSalary('Rs 30K'), 30000);
    expect(PayrollService.extractSalary(r'$ 2.5M'), 2500000);
    expect(PayrollService.extractSalary('1.25B'), 1250000000);
    expect(PayrollService.extractSalary('0.5T'), 500000000000);
  });

  test('full number formatter does not abbreviate payroll totals', () {
    expect(PayrollService.formatFullNumber(123100), '123,100');
    expect(PayrollService.formatFullNumber(123100.25), '123,100.25');
  });

  test('compact formatter supports payroll totals through trillions', () {
    expect(PayrollService.formatNumber(30000), '30.0K');
    expect(PayrollService.formatNumber(55000000), '55.0M');
    expect(PayrollService.formatNumber(2500000000), '2.5B');
    expect(PayrollService.formatNumber(123123123203077.33), '123.1T');
  });

  test('overtime is added after flat deductions', () {
    final netPayment = PayrollService.calculateNetFromTotals(
      salary: 'Rs 55000',
      overtimeAmount: '5,000',
      absentDeduction: '3,000',
      leaveDeduction: '2,000',
    );

    expect(netPayment, 55000);
  });

  test('annual salary is converted to a monthly payroll period', () {
    final result = PayrollService.calculatePayroll(
      salary: r'$ 120000',
      totalWorkDays: '20',
      absents: '0',
      leaves: '0',
      salaryType: 'Annual',
    );

    expect(result['grossSalary'], 10000);
    expect(result['netSalary'], 10000);
    expect(result['dailyRate'], 500);
  });

  test('explicit paid and unpaid leave counts remain separate', () {
    final counts = PayrollService.attendanceCounts({
      'absents': 1,
      'paidLeaves': 3,
      'unpaidLeaves': 2,
      'leaves': 5,
    });

    expect(counts, {
      'absents': 1,
      'paidLeaves': 3,
      'unpaidLeaves': 2,
      'leaves': 5,
    });
  });

  test('legacy leave count removes explicitly paid days from deductions', () {
    final counts = PayrollService.attendanceCounts({
      'absents': 0,
      'paidLeaves': 3,
      'leaves': 5,
    });

    expect(counts['paidLeaves'], 3);
    expect(counts['unpaidLeaves'], 2);
    expect(counts['leaves'], 5);
  });

  test('completed payroll month handles the January year boundary', () {
    final month = PayrollService.completedPayrollMonth(
      referenceDate: DateTime(2026, 1, 15),
    );

    expect(month, DateTime(2025, 12, 1));
    expect(PayrollService.payrollPeriodLabel(month), '2025-12');
  });

  test('current payroll month uses the active calendar month', () {
    final month = PayrollService.currentPayrollMonth(
      referenceDate: DateTime(2026, 7, 30),
    );

    expect(month, DateTime(2026, 7, 1));
    expect(PayrollService.payrollPeriodLabel(month), '2026-07');
  });

  test('month-end reminder starts during the final three calendar days', () {
    expect(PayrollService.isMonthEnding(DateTime(2026, 7, 28)), isFalse);
    expect(PayrollService.isMonthEnding(DateTime(2026, 7, 29)), isTrue);
    expect(PayrollService.isMonthEnding(DateTime(2026, 7, 31)), isTrue);
    expect(PayrollService.isMonthEnding(DateTime(2026, 2, 26)), isTrue);
  });

  test('payroll period labels parse and advance across a year boundary', () {
    final december = PayrollService.parsePayrollPeriodLabel('2026-12');

    expect(december, DateTime(2026, 12, 1));
    expect(PayrollService.nextPayrollMonth(december!), DateTime(2027, 1, 1));
    expect(PayrollService.parsePayrollPeriodLabel('invalid'), isNull);
  });

  test('period completes only when every worker has a paid payroll record', () {
    const workers = [
      {'id': 'worker-1', 'name': 'Ali', 'email': 'ali@example.com'},
      {'id': 'worker-2', 'name': 'Sara', 'email': 'sara@example.com'},
    ];
    final onePaid = [
      {'workerId': 'worker-1', 'status': 'Paid', 'payPeriod': '2026-07-01'},
    ];
    final allPaid = [
      ...onePaid,
      {'workerId': 'worker-2', 'status': 'Paid', 'payPeriod': '2026-07-01'},
    ];

    expect(
      PayrollService.unpaidWorkerCountForMonth(
        workers,
        onePaid,
        DateTime(2026, 7),
      ),
      1,
    );
    expect(
      PayrollService.allWorkersPaidForMonth(
        workers,
        onePaid,
        DateTime(2026, 7),
      ),
      isFalse,
    );
    expect(
      PayrollService.allWorkersPaidForMonth(
        workers,
        allPaid,
        DateTime(2026, 7),
      ),
      isTrue,
    );
  });

  test(
    'isPayrollDue returns true only on exact salary day and clamps short months',
    () {
      expect(PayrollService.isPayrollDue(DateTime(2026, 7, 9), 10), isFalse);
      expect(PayrollService.isPayrollDue(DateTime(2026, 7, 10), 10), isTrue);
      expect(PayrollService.effectiveSalaryDay(DateTime(2026, 2), 31), 28);
      expect(PayrollService.isPayrollDue(DateTime(2026, 2, 28), 31), isTrue);
    },
  );

  test('pay period takes priority over the later database creation date', () {
    final date = PayrollService.payrollRecordDate({
      'payPeriod': DateTime(2026, 6, 1),
      'createdAt': DateTime(2026, 7, 10),
    });

    expect(date, DateTime(2026, 6, 1));
  });

  test('payroll key supplies the period for older records', () {
    final date = PayrollService.payrollRecordDate({
      'payrollKey': 'worker-1_2026-06',
    });

    expect(date, DateTime(2026, 6, 1));
  });

  test('same-name workers do not share payroll when IDs differ', () {
    final combined = PayrollService.combinePayroll(
      const [
        {'id': 'worker-1', 'name': 'Ali Khan', 'email': ''},
        {'id': 'worker-2', 'name': 'Ali Khan', 'email': ''},
      ],
      [
        {
          'workerId': 'worker-1',
          'name': 'Ali Khan',
          'status': 'Paid',
          'payPeriod': '2026-06-01',
        },
      ],
      month: DateTime(2026, 6),
    );

    expect(combined[0]['hasPayrollRecord'], isTrue);
    expect(combined[1]['hasPayrollRecord'], isFalse);
  });

  test('cancelled payroll restores the worker to unpaid state', () {
    final combined = PayrollService.combinePayroll(
      const [
        {'id': 'worker-1', 'name': 'Ali', 'email': 'ali@example.com'},
      ],
      [
        {
          'workerId': 'worker-1',
          'status': 'Cancelled',
          'payPeriod': '2026-06-01',
          'totalWorkDays': '22',
        },
      ],
      month: DateTime(2026, 6),
    );

    expect(combined.single['hasPayrollRecord'], isFalse);
    expect(combined.single['status'], 'Active');
  });

  test('editing canonical pay period updates Paid to Pay in real time', () {
    final combined = PayrollService.combinePayroll(
      const [
        {'id': 'worker-1', 'name': 'Carlos Garcia', 'email': 'carlos@test.com'},
      ],
      [
        {
          'id': 'worker-1_2026-06',
          'workerId': 'worker-1',
          'payrollKey': 'worker-1_2026-06',
          'payPeriod': '2026-07-01',
          'status': 'Paid',
          'totalWorkDays': '22',
        },
        {
          'id': 'old-random-duplicate',
          'workerId': 'worker-1',
          'payPeriod': '2026-06-01',
          'status': 'Paid',
          'totalWorkDays': '22',
        },
      ],
      month: DateTime(2026, 6),
    );

    expect(combined.single['hasPayrollRecord'], isFalse);
  });

  test('manually edited payrollDate overrides its original run month', () {
    final date = PayrollService.payrollRecordDate({
      'payPeriod': '2026-06-01',
      'payrollDate': DateTime(2026, 8, 10),
      'createdAt': DateTime(2026, 7, 10),
    });

    expect(date, DateTime(2026, 8, 10));
  });
}
