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
}
