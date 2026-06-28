import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/utils/validators.dart';

void main() {
  group('isValidEmail', () {
    test('accepts well-formed addresses', () {
      expect(Validators.isValidEmail('john.smith@stark.com'), isTrue);
      expect(Validators.isValidEmail('  a@b.co  '), isTrue);
    });

    test('rejects malformed or empty addresses', () {
      expect(Validators.isValidEmail(null), isFalse);
      expect(Validators.isValidEmail(''), isFalse);
      expect(Validators.isValidEmail('no-at-sign'), isFalse);
      expect(Validators.isValidEmail('no@domain'), isFalse);
      expect(Validators.isValidEmail('a b@c.com'), isFalse);
    });
  });

  group('parseAmount', () {
    test('parses numbers and currency strings', () {
      expect(Validators.parseAmount(124.5), 124.5);
      expect(Validators.parseAmount('124.50'), 124.5);
      expect(Validators.parseAmount(r'$ 95,000'), 95000);
      expect(Validators.parseAmount('1,200.50'), 1200.50);
    });

    test('returns null for unparseable input', () {
      expect(Validators.parseAmount(null), isNull);
      expect(Validators.parseAmount('abc'), isNull);
      expect(Validators.parseAmount(''), isNull);
    });
  });

  group('email validator', () {
    test('optional empty is allowed', () {
      expect(Validators.email(''), isNull);
      expect(Validators.email(null), isNull);
    });

    test('required empty fails', () {
      expect(Validators.email('', required: true), isNotNull);
    });

    test('invalid fails regardless of required', () {
      expect(Validators.email('bad'), isNotNull);
    });
  });

  group('requiredField', () {
    test('passes for non-empty', () {
      expect(Validators.requiredField('x'), isNull);
    });

    test('fails for empty/whitespace/null', () {
      expect(Validators.requiredField(null), isNotNull);
      expect(Validators.requiredField('   '), isNotNull);
    });
  });

  group('validateWorker', () {
    test('accepts a valid worker', () {
      expect(
        () => Validators.validateWorker({
          'name': 'John Smith',
          'email': 'john@stark.com',
        }),
        returnsNormally,
      );
    });

    test('accepts a worker with no email (email optional)', () {
      expect(
        () => Validators.validateWorker({'name': 'John'}),
        returnsNormally,
      );
    });

    test('rejects missing name', () {
      expect(
        () => Validators.validateWorker({'email': 'john@stark.com'}),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects malformed email', () {
      expect(
        () => Validators.validateWorker({'name': 'John', 'email': 'nope'}),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('validateExpense', () {
    test('accepts a valid expense', () {
      expect(
        () => Validators.validateExpense({
          'name': 'John',
          'category': 'Client Dinner',
          'amount': 124.50,
        }),
        returnsNormally,
      );
    });

    test('rejects zero or negative amount', () {
      expect(
        () => Validators.validateExpense({
          'name': 'John',
          'category': 'X',
          'amount': 0,
        }),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => Validators.validateExpense({
          'name': 'John',
          'category': 'X',
          'amount': -5,
        }),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects missing category', () {
      expect(
        () => Validators.validateExpense({'name': 'John', 'amount': 10}),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects unparseable amount', () {
      expect(
        () => Validators.validateExpense({
          'name': 'John',
          'category': 'X',
          'amount': 'free',
        }),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('validateTimeOff', () {
    test('accepts valid', () {
      expect(
        () => Validators.validateTimeOff({
          'name': 'John',
          'action': 'Annual Leave',
          'startDate': '2023-10-01',
          'endDate': '2023-10-05',
        }),
        returnsNormally,
      );
    });

    test('rejects missing action', () {
      expect(
        () => Validators.validateTimeOff({'name': 'John'}),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('validateAsset', () {
    test('accepts valid', () {
      expect(
        () => Validators.validateAsset({'name': 'Laptop', 'type': 'Laptop'}),
        returnsNormally,
      );
    });

    test('rejects missing type', () {
      expect(
        () => Validators.validateAsset({'name': 'X'}),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('validateHoliday', () {
    test('accepts valid', () {
      expect(
        () => Validators.validateHoliday({'name': 'Labour Day'}),
        returnsNormally,
      );
    });

    test('rejects missing name', () {
      expect(
        () => Validators.validateHoliday({'day': 1}),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
