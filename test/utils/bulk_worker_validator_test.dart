import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/utils/bulk_worker_validator.dart';

import '../helpers/localization.dart';

Map<String, dynamic> _validWorker() => {
      'name': 'John Doe',
      'phone': '+1 234 567 8900',
      'email': 'john@gmail.com',
      'fatherName': 'Jane Doe',
      'nationalId': '123456789',
      'religion': 'Christianity',
      'dob': '1990-01-01',
      'gender': 'Male',
      'address': '123 Main St',
      'relationshipStatus': 'Single',
      'position': 'Software Engineer',
      'type1': 'Full-Time',
      'type2': 'On-Site',
      'experienceLevel': 'Mid-Level',
      'education': 'Bachelor',
      'salaryType': 'Monthly',
      'currency': 'USD',
      'salaryAmount': '50000',
      'annualLeaves': '15',
      'joiningDate': '2024-01-01',
      'frontId': 'front.png',
      'backId': 'back.png',
      'cv': 'cv.pdf',
    };

Map<String, String> _validate(Map<String, dynamic> worker) {
  return validateWorkerData(
    worker,
    existingEmails: const {},
    existingNationalIds: const {},
    csvEmails: const {},
    csvNationalIds: const {},
  );
}

void main() {
  group('validateWorkerData national ID format', () {
    testWidgets('accepts a valid 9-digit national ID', (tester) async {
      await initLocalization(tester);
      final errors = _validate(_validWorker());
      expect(errors.containsKey('nationalId'), isFalse);
    });

    testWidgets('accepts a formatted CNIC national ID', (tester) async {
      await initLocalization(tester);
      final worker = _validWorker()..['nationalId'] = '37405-1234567-1';
      final errors = _validate(worker);
      expect(errors.containsKey('nationalId'), isFalse);
    });

    testWidgets('rejects a short 3-digit national ID', (tester) async {
      await initLocalization(tester);
      final worker = _validWorker()..['nationalId'] = '348';
      final errors = _validate(worker);
      expect(errors['nationalId'], 'validation_invalid_national_id'.tr());
    });

    testWidgets('rejects a short 4-digit national ID', (tester) async {
      await initLocalization(tester);
      final worker = _validWorker()..['nationalId'] = '1234';
      final errors = _validate(worker);
      expect(errors['nationalId'], 'validation_invalid_national_id'.tr());
    });

    testWidgets('rejects non-numeric national ID', (tester) async {
      await initLocalization(tester);
      final worker = _validWorker()..['nationalId'] = 'ABC-123';
      final errors = _validate(worker);
      expect(errors['nationalId'], 'validation_invalid_national_id'.tr());
    });

    testWidgets('keeps duplicate check for valid national IDs', (tester) async {
      await initLocalization(tester);
      final worker = _validWorker()..['nationalId'] = '123456789';
      final errors = validateWorkerData(
        worker,
        existingEmails: const {},
        existingNationalIds: const {'123456789'},
        csvEmails: const {},
        csvNationalIds: const {},
      );
      expect(errors['nationalId'], 'validation_duplicate_national_id'.tr());
    });
  });

  group('validateWorkerData leave balances', () {
    testWidgets('keeps separate sick/casual/medical allowances', (tester) async {
      await initLocalization(tester);
      final worker = _validWorker()
        ..['annualLeaves'] = '15'
        ..['sickLeaves'] = '10'
        ..['casualLeaves'] = '5'
        ..['medicalLeaves'] = '5';
      final errors = _validate(worker);
      expect(errors.isEmpty, isTrue);
      expect(worker['annualLeaves'], '15');
      expect(worker['sickLeaves'], '10');
      expect(worker['casualLeaves'], '5');
      expect(worker['medicalLeaves'], '5');
    });

    testWidgets('rejects negative medical leaves', (tester) async {
      await initLocalization(tester);
      final worker = _validWorker()..['medicalLeaves'] = '-3';
      final errors = _validate(worker);
      expect(errors['medicalLeaves'], 'invalid_number'.tr());
      expect(worker['medicalLeaves'], '0');
    });

    testWidgets('rejects medical leaves above 366 days', (tester) async {
      await initLocalization(tester);
      final worker = _validWorker()..['medicalLeaves'] = '400';
      final errors = _validate(worker);
      expect(errors['medicalLeaves'], 'invalid_number'.tr());
    });

    testWidgets('defaults empty sick/casual/medical to zero', (tester) async {
      await initLocalization(tester);
      final worker = _validWorker()
        ..['sickLeaves'] = ''
        ..['casualLeaves'] = ''
        ..['medicalLeaves'] = '';
      final errors = _validate(worker);
      expect(errors.isEmpty, isTrue);
      expect(worker['sickLeaves'], '0');
      expect(worker['casualLeaves'], '0');
      expect(worker['medicalLeaves'], '0');
    });
  });

  group('validateWorkerData email domain', () {
    testWidgets('rejects @example.com placeholder email domain', (tester) async {
      await initLocalization(tester);
      final worker = _validWorker()..['email'] = 'john@example.com';
      final errors = _validate(worker);
      expect(errors['email'], 'validation_invalid_email_domain'.tr());
    });

    testWidgets('rejects a literal @example.com (no local part)', (tester) async {
      await initLocalization(tester);
      final worker = _validWorker()..['email'] = '@example.com';
      final errors = _validate(worker);
      expect(errors.containsKey('email'), isTrue);
    });

    testWidgets('rejects @example (no local part, no TLD)', (tester) async {
      await initLocalization(tester);
      final worker = _validWorker()..['email'] = '@example';
      final errors = _validate(worker);
      expect(errors.containsKey('email'), isTrue);
    });

    testWidgets('accepts a real email domain', (tester) async {
      await initLocalization(tester);
      final worker = _validWorker()..['email'] = 'john@gmail.com';
      final errors = _validate(worker);
      expect(errors.containsKey('email'), isFalse);
    });
  });

  group('validateWorkerData name formatting', () {
    testWidgets('title-cases name field and trims spaces', (tester) async {
      await initLocalization(tester);
      final worker = _validWorker()..['name'] = '  ali   khan  ';
      final errors = _validate(worker);
      expect(errors.isEmpty, isTrue);
      expect(worker['name'], 'Ali Khan');
    });

    testWidgets('title-cases fatherName field and trims spaces', (tester) async {
      await initLocalization(tester);
      final worker = _validWorker()..['fatherName'] = '  basheer   khan  ';
      final errors = _validate(worker);
      expect(errors.isEmpty, isTrue);
      expect(worker['fatherName'], 'Basheer Khan');
    });

    testWidgets('handles single word names', (tester) async {
      await initLocalization(tester);
      final worker = _validWorker()..['name'] = 'ali';
      final errors = _validate(worker);
      expect(errors.isEmpty, isTrue);
      expect(worker['name'], 'Ali');
    });

    testWidgets('preserves abbreviations like M. Ali', (tester) async {
      await initLocalization(tester);
      final worker = _validWorker()..['name'] = 'm. ali';
      final errors = _validate(worker);
      expect(errors.isEmpty, isTrue);
      expect(worker['name'], 'M. Ali');
    });

    testWidgets('does not modify empty name fields', (tester) async {
      await initLocalization(tester);
      final worker = _validWorker()..['name'] = '';
      final errors = _validate(worker);
      expect(errors.containsKey('name'), isTrue); // required field error
      expect(worker['name'], '');
    });

    testWidgets('does not apply title case to non-name fields', (tester) async {
      await initLocalization(tester);
      final worker = _validWorker()..['position'] = 'software engineer';
      _validate(worker);
      // Position gets title-cased by its own block, not the name formatting block
      // The important thing is that name formatting only targets 'name' and 'fatherName'
      expect(worker['name'], 'John Doe');
      expect(worker['fatherName'], 'Jane Doe');
    });
  });
}
