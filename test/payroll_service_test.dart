import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/payroll_service.dart';
import 'package:hrms/services/salary_day_scheduler.dart';

void main() {
  test('payroll period uses the selected calendar month', () {
    final start = PayrollService.payPeriodStart(DateTime(2026, 8, 10));
    final end = PayrollService.payPeriodEnd(DateTime(2026, 8, 10));

    expect(
      PayrollService.formatPayPeriodRange(start, end, locale: 'en'),
      'Aug 1 – Aug 31, 2026',
    );
    expect(
      PayrollService.payrollKeyForPeriod('Worker-1', start, end),
      'worker-1_2026-08-01_2026-08-31',
    );
  });

  test('current payroll month is not gated by a salary date', () {
    expect(
      PayrollService.currentPayrollMonth(referenceDate: DateTime(2026, 8, 10)),
      DateTime(2026, 8, 1),
    );
  });

  test('payroll review uses the worker saved employment type', () {
    expect(
      PayrollService.workerEmploymentType({
        'type1': 'Part-Time',
        'workType': 'Full-Time',
      }),
      'Part-Time',
    );
    expect(
      PayrollService.workerEmploymentType({'workType': 'Contract'}),
      'Contract',
    );
  });

  test('Pay All builds the canonical Firestore payroll schema', () {
    final periodStart = DateTime(2026, 8, 1);
    final periodEnd = DateTime(2026, 8, 31);
    final runDate = DateTime(2026, 8, 10, 9, 30);
    final result = AutoPayrollResult(
      workerId: 'avery-1',
      workerName: 'Avery Morgan',
      email: 'avery@example.com',
      netSalary: '£ 4,800',
      rawNetSalaryValue: 4800,
      success: true,
      totalWorkDays: '26',
      absents: 0,
      paidLeaves: 2,
      unpaidLeaves: 0,
      leaves: 2,
      overtimeAmount: '0',
      absentDeduction: '0',
      leaveDeduction: '0',
      salary: '£ 4,800',
      currency: 'GBP',
    );
    final payrollKey = PayrollService.payrollKeyForPeriod(
      result.workerId,
      periodStart,
      periodEnd,
    );

    final record = result.toCanonicalPayrollRecord(
      payrollKey: payrollKey,
      periodStart: periodStart,
      periodEnd: periodEnd,
      runDate: runDate,
    );

    expect(record['payrollKey'], 'avery-1_2026-08-01_2026-08-31');
    expect(record['payPeriod'], periodEnd);
    expect(record['payPeriodStart'], periodStart);
    expect(record['payPeriodEnd'], periodEnd);
    expect(record.containsKey('salaryPaymentDay'), isFalse);
    expect(record['totalWorkDays'], isA<int>());
    expect(record['absents'], isA<int>());
    expect(record['paidLeaves'], isA<int>());
    expect(record['unpaidLeaves'], isA<int>());
    expect(record['leaves'], isA<int>());
    expect(record['overtimeAmount'], isA<double>());
    expect(record['absentDeduction'], isA<double>());
    expect(record['leaveDeduction'], isA<double>());
  });

  test('26 working days do not prorate a monthly base salary', () {
    final result = PayrollService.calculatePayroll(
      salary: '£4,800',
      totalWorkDays: '26',
      daysWorked: '26',
      absents: '0',
      leaves: '0',
      overtimeAmount: '0',
      absentDeductionPerDay: '0',
      salaryType: 'Monthly',
    );

    expect(result['grossSalary'], 4800.0);
    expect(result['absentDeduction'], 0.0);
    expect(result['overtimePay'], 0.0);
    expect(result['netSalary'], 4800.0);
  });

  test('cancelled payroll does not seed a fresh pay period form', () {
    final payroll = PayrollService.combinePayroll(
      [
        {
          'id': 'worker-1',
          'name': 'Noah Wilson',
          'email': 'noah@example.com',
          'status': 'Active',
          'salaryAmount': 4800,
          'currency': 'GBP',
        },
      ],
      [
        {
          'id': 'payroll-1',
          'workerId': 'worker-1',
          'name': 'Noah Wilson',
          'email': 'noah@example.com',
          'status': 'Unpaid',
          'cancelledAt': DateTime(2026, 8, 10),
          'payPeriod': DateTime(2026, 8, 31),
          'payPeriodStart': DateTime(2026, 8, 1),
          'payPeriodEnd': DateTime(2026, 8, 31),
          'payrollKey': 'worker-1_2026-08-01_2026-08-31',
          'totalWorkDays': 26,
          'absentDeduction': 1.0,
        },
      ],
      month: DateTime(2026, 8, 10),
    );

    expect(payroll, hasLength(1));
    expect(payroll.single['hasPayrollRecord'], isFalse);
    expect(payroll.single['totalWorkDays'], isEmpty);
    expect(payroll.single.containsKey('absentDeduction'), isFalse);
  });

  test('Pay All only includes unpaid workers with a positive salary', () {
    final workers = [
      {
        'id': 'payable',
        'name': 'Payable Worker',
        'email': 'payable@example.com',
        'status': 'Active',
        'salaryAmount': 1000,
      },
      {
        'id': 'no-salary',
        'name': 'No Salary Worker',
        'email': 'no-salary@example.com',
        'status': 'Active',
        'salaryAmount': 0,
      },
    ];

    final payable = PayrollService.payableWorkersForPeriod(
      workers,
      const [],
      month: DateTime(2026, 8, 1),
    );

    expect(payable.map((worker) => worker['id']), ['payable']);
  });
}
