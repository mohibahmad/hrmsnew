import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/models/worker.dart';
import 'package:hrms/services/payroll_service.dart';
import 'package:hrms/utils/currency_utils.dart';
import 'package:hrms/utils/validators.dart';

void main() {
  test('invalid and empty currency values safely fall back to USD', () {
    expect(CurrencyUtils.normalize('Ijkljk'), 'USD');
    expect(CurrencyUtils.normalize(''), 'USD');
    expect(CurrencyUtils.normalize(null), 'USD');
    expect(PayrollService.getCurrencySymbol('Ijkljk'), r'$');
  });

  test('supported currency codes are normalized and PKR is available', () {
    expect(CurrencyUtils.normalize(' pkr '), 'PKR');
    expect(CurrencyUtils.isSupported('pkr'), isTrue);
    expect(CurrencyUtils.symbolFor('PKR'), 'Rs');
  });

  test('worker maps cannot expose a corrupt currency value', () {
    final worker = Worker.fromMap(const {'name': 'Ali', 'currency': 'Ijkljk'});

    expect(worker.currency, 'USD');
    expect(worker.toMap()['currency'], 'USD');
  });

  test('worker validation rejects unsupported currency codes', () {
    expect(
      () => Validators.validateWorker(const {
        'name': 'Ali',
        'currency': 'Ijkljk',
      }),
      throwsA(
        isA<ValidationException>().having(
          (error) => error.field,
          'field',
          'currency',
        ),
      ),
    );
    expect(
      () => Validators.validateWorker(const {'name': 'Ali', 'currency': 'PKR'}),
      returnsNormally,
    );
  });
}
