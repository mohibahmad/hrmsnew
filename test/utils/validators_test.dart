import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/utils/validators.dart';

void main() {
  group('Validators.isValidNationalId', () {
    test('accepts IDs with 6 or more digits', () {
      expect(Validators.isValidNationalId('123456'), isTrue);
      expect(Validators.isValidNationalId('12345678'), isTrue);
      expect(Validators.isValidNationalId('3740512345671'), isTrue);
    });

    test('accepts formatted IDs with dashes and spaces', () {
      expect(Validators.isValidNationalId('12345-1234567-1'), isTrue);
      expect(Validators.isValidNationalId('123 456 789'), isTrue);
      expect(Validators.isValidNationalId('37405-1234567-1'), isTrue);
    });

    test('rejects short IDs (3-5 digits)', () {
      expect(Validators.isValidNationalId('348'), isFalse);
      expect(Validators.isValidNationalId('1234'), isFalse);
      expect(Validators.isValidNationalId('12345'), isFalse);
      expect(Validators.isValidNationalId('12-34'), isFalse);
    });

    test('rejects non-numeric and empty values', () {
      expect(Validators.isValidNationalId(''), isFalse);
      expect(Validators.isValidNationalId(null), isFalse);
      expect(Validators.isValidNationalId('   '), isFalse);
      expect(Validators.isValidNationalId('abc123'), isFalse);
      expect(Validators.isValidNationalId('--'), isFalse);
    });
  });

  group('Validators.isValidEmail', () {
    test('accepts valid emails', () {
      expect(Validators.isValidEmail('worker@gmail.com'), isTrue);
      expect(Validators.isValidEmail('john.doe@company.co.uk'), isTrue);
    });

    test('rejects invalid emails', () {
      expect(Validators.isValidEmail('plainaddress'), isFalse);
      expect(Validators.isValidEmail('a@b'), isFalse);
      expect(Validators.isValidEmail(''), isFalse);
      expect(Validators.isValidEmail(null), isFalse);
      expect(Validators.isValidEmail('a@b.c d'), isFalse);
    });
  });

  group('Validators.isPlaceholderEmailDomain', () {
    test('rejects the placeholder @example.com domain', () {
      expect(
        Validators.isPlaceholderEmailDomain('worker@example.com'),
        isTrue,
      );
    });

    test('accepts real email domains', () {
      expect(
        Validators.isPlaceholderEmailDomain('worker@gmail.com'),
        isFalse,
      );
      expect(
        Validators.isPlaceholderEmailDomain('john.doe@company.co.uk'),
        isFalse,
      );
    });

    test('handles case-insensitive domains and malformed input', () {
      expect(
        Validators.isPlaceholderEmailDomain('Worker@EXAMPLE.com'),
        isTrue,
      );
      expect(Validators.isPlaceholderEmailDomain('plainaddress'), isFalse);
      expect(Validators.isPlaceholderEmailDomain(''), isFalse);
    });
  });

  group('Validators.isValidPhone', () {
    test('accepts valid phone numbers', () {
      expect(Validators.isValidPhone('+1 234 567 8900'), isTrue);
      expect(Validators.isValidPhone('1234567890'), isTrue);
      expect(Validators.isValidPhone('03001234567'), isTrue);
      expect(Validators.isValidPhone('+92 300 1234567'), isTrue);
    });

    test('rejects all-zeros phone numbers', () {
      expect(Validators.isValidPhone('000000'), isFalse);
      expect(Validators.isValidPhone('00000000000'), isFalse);
      expect(Validators.isValidPhone('000 000 0000'), isFalse);
    });

    test('rejects all-same-digit phone numbers', () {
      expect(Validators.isValidPhone('111111'), isFalse);
      expect(Validators.isValidPhone('2222222222'), isFalse);
      expect(Validators.isValidPhone('9999999999'), isFalse);
    });

    test('rejects empty and null values', () {
      expect(Validators.isValidPhone(''), isFalse);
      expect(Validators.isValidPhone(null), isFalse);
      expect(Validators.isValidPhone('   '), isFalse);
    });

    test('accepts phone numbers with mixed digits', () {
      expect(Validators.isValidPhone('123450'), isTrue);
      expect(Validators.isValidPhone('012345'), isTrue);
      expect(Validators.isValidPhone('123000'), isTrue);
    });
  });

  group('Validators.validateWorker salary', () {
    test('rejects a missing salary amount', () {
      expect(
        () => Validators.validateWorker({'name': 'Urwa'}),
        throwsA(
          isA<ValidationException>().having(
            (error) => error.field,
            'field',
            'salaryAmount',
          ),
        ),
      );
    });

    test('rejects a zero salary amount', () {
      expect(
        () => Validators.validateWorker({
          'name': 'Urwa',
          'salaryAmount': 0,
        }),
        throwsA(isA<ValidationException>()),
      );
    });

    test('accepts a valid salary amount', () {
      expect(
        () => Validators.validateWorker({
          'name': 'Urwa',
          'salaryAmount': Validators.minSalaryAmount,
        }),
        returnsNormally,
      );
    });
  });
}
