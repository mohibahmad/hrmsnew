import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/utils/date_utils.dart';
import 'package:hrms/utils/validators.dart';

void main() {
  group('AppDateUtils.parseDdMmYyyy', () {
    test('parses valid worker dates without swapping day and month', () {
      expect(AppDateUtils.parseDdMmYyyy('27/09/1994'), DateTime(1994, 9, 27));
      expect(AppDateUtils.parseDdMmYyyy('05/08/2026'), DateTime(2026, 8, 5));
    });

    test('trims surrounding whitespace', () {
      expect(AppDateUtils.parseDdMmYyyy(' 05/08/2026 '), DateTime(2026, 8, 5));
    });

    test('rejects ISO, US, and impossible dates', () {
      expect(AppDateUtils.parseDdMmYyyy('2026-08-05'), isNull);
      expect(AppDateUtils.parseDdMmYyyy('08-05-2026'), isNull);
      expect(AppDateUtils.parseDdMmYyyy('31/02/2026'), isNull);
      expect(AppDateUtils.parseDdMmYyyy('5/8/2026'), isNull);
    });
  });

  test('general parser preserves DD/MM order for ambiguous dates', () {
    expect(AppDateUtils.parseDateString('05/08/2026'), DateTime(2026, 8, 5));
    expect(AppDateUtils.parseDateString('08/05/2026'), DateTime(2026, 5, 8));
  });

  group('Validators.validateWorker DOB handling', () {
    Map<String, dynamic> workerWithDob(dynamic dob) => {
      'name': 'Test Worker',
      'email': 'worker@company.com',
      'salaryAmount': 5000,
      'dob': dob,
    };

    test('accepts a Firestore Timestamp produced by Add Worker save', () {
      expect(
        () => Validators.validateWorker(
          workerWithDob(Timestamp.fromDate(DateTime(1994, 9, 27))),
        ),
        returnsNormally,
      );
    });

    test('accepts DateTime and DD/MM/YYYY string values', () {
      expect(
        () => Validators.validateWorker(workerWithDob(DateTime(1994, 9, 27))),
        returnsNormally,
      );
      expect(
        () => Validators.validateWorker(workerWithDob('27/09/1994')),
        returnsNormally,
      );
    });
  });
}
