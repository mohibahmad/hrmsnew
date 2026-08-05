import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/utils/bulk_worker_validator.dart';

import '../helpers/localization.dart';

Map<String, dynamic> _validWorker() => {
      'name': 'John Doe',
      'phone': '+1 234 567 8900',
      'email': 'john@example.com',
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
}
