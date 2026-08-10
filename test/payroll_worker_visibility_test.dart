import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/payroll_service.dart';

void main() {
  test('active workers appear before a payroll record has been created', () {
    final payroll = PayrollService.combinePayroll(
      [
        {
          'id': 'worker-without-status',
          'name': 'New Worker',
          'email': 'new@example.com',
          'joiningDate': DateTime(2026, 8, 31),
          'salaryAmount': 1000,
        },
      ],
      const [],
      month: DateTime(2026, 8, 1),
    );

    expect(payroll, hasLength(1));
    expect(payroll.single['id'], 'worker-without-status');
    expect(payroll.single['hasPayrollRecord'], isFalse);
    expect(payroll.single['isPaid'], isFalse);
  });
}
