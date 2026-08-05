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
}
