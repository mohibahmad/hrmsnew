import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/utils/date_utils.dart';
import 'package:hrms/utils/validators.dart';

void main() {
  test('holiday date prefers canonical date over stale derived fields', () {
    final result = AppDateUtils.holidayRecordDate({
      'date': DateTime(2025, 8, 14),
      'day': 14,
      'month': 'August',
      'year': 2026,
      'dayOfWeek': 'Friday',
    });

    expect(result, DateTime(2025, 8, 14));
    expect(result!.weekday, DateTime.thursday);
  });

  test('holiday date keeps legacy day month and year readable', () {
    final result = AppDateUtils.holidayRecordDate({
      'day': '14',
      'month': 'August',
      'year': '2025',
    });

    expect(result, DateTime(2025, 8, 14));
  });

  test('All Time includes records from any year', () {
    expect(
      AppDateUtils.isTimestampWithinPeriod(DateTime(1999, 1, 1), 'All Time'),
      isTrue,
    );
    expect(
      AppDateUtils.isTimestampWithinPeriod(DateTime(2025, 8, 14), 'All Time'),
      isTrue,
    );
  });

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

  test('bulk date normalization preserves the calendar day in UTC', () {
    final dob = AppDateUtils.parseDdMmYyyy('08/06/1998')!;
    final joiningDate = AppDateUtils.parseDdMmYyyy('06/08/2026')!;

    expect(
      AppDateUtils.asUtcDateOnly(dob),
      DateTime.utc(1998, DateTime.june, 8),
    );
    expect(
      AppDateUtils.asUtcDateOnly(joiningDate),
      DateTime.utc(2026, DateTime.august, 6),
    );
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
