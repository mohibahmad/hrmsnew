import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/payroll_service.dart';

void main() {
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

  test('absence reduces monthly salary exactly once', () {
    final result = PayrollService.calculatePayroll(
      salary: 'Rs 100000',
      totalWorkDays: '20',
      daysWorked: '18',
      absents: '2',
      leaves: '0',
    );

    expect(result['grossSalary'], 100000);
    expect(result['absentDeduction'], 10000);
    expect(result['netSalary'], 90000);
  });

  test('unpaid leave uses daily rate once when no override is entered', () {
    final result = PayrollService.calculatePayroll(
      salary: 'Rs 100000',
      totalWorkDays: '20',
      daysWorked: '19',
      absents: '0',
      leaves: '1',
    );

    expect(result['leaveDeduction'], 5000);
    expect(result['netSalary'], 95000);
  });

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
}
