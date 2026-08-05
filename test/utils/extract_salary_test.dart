import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/payroll_service.dart';

void main() {
  group('PayrollService.extractSalary', () {
    test('parses Arabic-script symbols containing dots correctly', () {
      // 'د.إ' has a dot; before the fix 'د.إ 5000' parsed as 0.5.
      expect(PayrollService.extractSalary('د.إ 5000'), 5000);
      expect(PayrollService.extractSalary('د.إ 300000000000000.0'), 3e14);
      expect(PayrollService.extractSalary('ر.ع. 1200'), 1200);
    });

    test('parses standard symbol prefixes', () {
      expect(PayrollService.extractSalary(r'$ 5,000'), 5000);
      expect(PayrollService.extractSalary('Rs 5000'), 5000);
      expect(PayrollService.extractSalary('5000'), 5000);
      expect(PayrollService.extractSalary('5,000.50'), 5000.50);
    });

    test('handles compact suffixes', () {
      expect(PayrollService.extractSalary(r'$ 50K'), 50000);
      expect(PayrollService.extractSalary('AED 2M'), 2000000);
    });

    test('does not mistake letters in the currency code for a K/M/B suffix', () {
      // The old parser matched 'B' inside 'GBP' and multiplied by 1e9.
      expect(PayrollService.extractSalary('GBP 5000'), 5000);
    });

    test('handles empty input', () {
      expect(PayrollService.extractSalary(''), 0);
    });
  });
}
