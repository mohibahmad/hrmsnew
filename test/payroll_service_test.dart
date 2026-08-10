import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/payroll_service.dart';
import 'package:hrms/services/salary_day_scheduler.dart';

void main() {
  test('salary-day invoice period uses the exact scheduled date range', () {
    final start = PayrollService.payPeriodStart(DateTime(2026, 8, 10), 10);
    final end = PayrollService.payPeriodEnd(DateTime(2026, 8, 10), 10);

    expect(
      PayrollService.formatPayPeriodRange(start, end, locale: 'en'),
      'Jul 10 – Aug 10, 2026',
    );
    expect(
      PayrollService.payrollKeyForPeriod('Worker-1', start, end),
      'worker-1_2026-07-10_2026-08-10',
    );
  });

  test('next salary cycle stays closed until its due date', () {
    final augustDueMonth = PayrollService.latestOpenPayrollMonth(
      DateTime(2026, 8, 10),
      10,
    );
    final beforeSeptemberDue = PayrollService.latestOpenPayrollMonth(
      DateTime(2026, 9, 9),
      10,
    );
    final septemberDueMonth = PayrollService.latestOpenPayrollMonth(
      DateTime(2026, 9, 10),
      10,
    );

    expect(augustDueMonth, DateTime(2026, 8, 1));
    expect(
      PayrollService.formatPayPeriodRange(
        PayrollService.payPeriodStart(augustDueMonth, 10),
        PayrollService.payPeriodEnd(augustDueMonth, 10),
        locale: 'en',
      ),
      'Jul 10 – Aug 10, 2026',
    );
    expect(beforeSeptemberDue, DateTime(2026, 8, 1));
    expect(septemberDueMonth, DateTime(2026, 9, 1));
    expect(
      PayrollService.isPayrollPeriodDue(
        DateTime(2026, 8, 10),
        DateTime(2026, 9, 1),
        10,
      ),
      isFalse,
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
    final periodStart = DateTime(2026, 7, 10);
    final periodEnd = DateTime(2026, 8, 10);
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
      salaryPaymentDay: 10,
    );

    expect(record['payrollKey'], 'avery-1_2026-07-10_2026-08-10');
    expect(record['payPeriod'], periodEnd);
    expect(record['payPeriodStart'], periodStart);
    expect(record['payPeriodEnd'], periodEnd);
    expect(record['salaryPaymentDay'], 10);
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
          'payPeriod': DateTime(2026, 8, 10),
          'payPeriodStart': DateTime(2026, 7, 10),
          'payPeriodEnd': DateTime(2026, 8, 10),
          'payrollKey': 'worker-1_2026-07-10_2026-08-10',
          'totalWorkDays': 26,
          'absentDeduction': 1.0,
        },
      ],
      month: DateTime(2026, 8, 10),
      salaryDay: 10,
    );

    expect(payroll, hasLength(1));
    expect(payroll.single['hasPayrollRecord'], isFalse);
    expect(payroll.single['totalWorkDays'], isEmpty);
    expect(payroll.single.containsKey('absentDeduction'), isFalse);
  });
}
