import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/utils/validators.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Expense max amount validation test', () {
    test('validateExpense throws error when amount > 999,999,999', () {
      final invalidExpense = {
        'name': 'Test Expense',
        'category': 'Office',
        'amount': 1000000000,
      };

      expect(
        () => Validators.validateExpense(invalidExpense),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('amount_cannot_exceed_max'),
          ),
        ),
      );
    });

    test('validateExpense accepts amounts <= 999,999,999', () {
      final validExpense = {
        'name': 'Valid Expense',
        'category': 'Office',
        'amount': 999999999,
      };

      expect(() => Validators.validateExpense(validExpense), returnsNormally);
    });
  });
}
