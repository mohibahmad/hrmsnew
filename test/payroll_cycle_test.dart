import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/payroll_service.dart';

void main() {
  const payDay = 16;

  final jul16 = DateTime(2026, 7, 16);
  final aug16 = DateTime(2026, 8, 16);
  final sep16 = DateTime(2026, 9, 16);

  Map<String, dynamic> worker(String id) => {
        'workerId': id,
        'id': id,
        'name': 'W$id',
        'email': '$id@example.com',
        'status': 'Active',
        'salaryAmount': '1000',
        'salary': '1000',
      };

  Map<String, dynamic> paidRecord({
    required String workerId,
    required DateTime start,
    required DateTime end,
    bool paid = true,
  }) => {
        'workerId': workerId,
        'email': '$workerId@example.com',
        'name': 'W$workerId',
        'payrollKey': PayrollService.payrollKeyForPeriod(workerId, start, end),
        'status': paid ? 'Paid' : 'Cancelled',
        'isPaid': paid,
        'payPeriodStart': start,
        'payPeriodEnd': end,
        'payrollDate': end,
        'createdAt': end,
        'salary': '1000',
        'salaryAmount': 1000,
      };

  PayrollPeriod resolve({
    required List<Map<String, dynamic>> workers,
    required List<Map<String, dynamic>> records,
    DateTime? referenceDate,
  }) =>
      PayrollService.resolveCurrentPayrollPeriod(
        workersList: workers,
        payrollRecords: records,
        payDay: payDay,
        referenceDate: referenceDate ?? aug16,
      );

  final workers4 = ['w1', 'w2', 'w3', 'w4'].map(worker).toList();

  List<Map<String, dynamic>> paidAll4() => workers4
      .map((w) =>
          paidRecord(workerId: w['workerId'] as String, start: jul16, end: aug16))
      .toList();

  test('A) 1/4 paid on Aug16 -> remain Jul16-Aug16', () {
    final records = [paidRecord(workerId: 'w1', start: jul16, end: aug16)];
    final p = resolve(workers: workers4, records: records);
    expect(PayrollService.periodDateKey(p.start), '2026-07-16');
    expect(PayrollService.periodDateKey(p.end), '2026-08-16');
  });

  test('A2) 1/4 paid before boundary (Jul 20) -> remain Jul16-Aug16', () {
    final records = [paidRecord(workerId: 'w1', start: jul16, end: aug16)];
    final p =
        resolve(workers: workers4, records: records, referenceDate: DateTime(2026, 7, 20));
    expect(PayrollService.periodDateKey(p.start), '2026-07-16');
    expect(PayrollService.periodDateKey(p.end), '2026-08-16');
  });

  test('B) 4/4 Paid on Aug 16 -> advance EXACTLY once to Aug16-Sep16', () {
    final p = resolve(workers: workers4, records: paidAll4());
    expect(PayrollService.periodDateKey(p.start), '2026-08-16');
    expect(PayrollService.periodDateKey(p.end), '2026-09-16');
  });

  test('C) Reopen/restart app -> still Aug16-Sep16', () {
    final first = resolve(workers: workers4, records: paidAll4());
    final second = resolve(workers: workers4, records: paidAll4());
    expect(PayrollService.periodDateKey(first.start), '2026-08-16');
    expect(PayrollService.periodDateKey(first.end), '2026-09-16');
    expect(PayrollService.payrollPeriodsEqual(first, second), isTrue);
  });

  test('D) Old historical Paid/Cancelled records never move cycle backward', () {
    final historical = <Map<String, dynamic>>[
      paidRecord(workerId: 'w1', start: DateTime(2026, 3, 16), end: DateTime(2026, 4, 16)),
      paidRecord(workerId: 'w2', start: DateTime(2026, 4, 16), end: DateTime(2026, 5, 16), paid: true),
      paidRecord(workerId: 'w3', start: DateTime(2026, 4, 16), end: DateTime(2026, 5, 16), paid: false),
      paidRecord(workerId: 'w4', start: DateTime(2026, 5, 16), end: DateTime(2026, 6, 16), paid: true),
    ];

    final due = resolve(
      workers: workers4,
      records: [
        paidRecord(workerId: 'w1', start: jul16, end: aug16),
        ...historical,
      ],
    );
    expect(PayrollService.periodDateKey(due.start), '2026-07-16');
    expect(PayrollService.periodDateKey(due.end), '2026-08-16');

    final done = resolve(workers: workers4, records: [...paidAll4(), ...historical]);
    expect(PayrollService.periodDateKey(done.start), '2026-08-16');
    expect(PayrollService.periodDateKey(done.end), '2026-09-16');
  });

  test('E) date around payday: no early/repeated advance, backward ok once',
      () {
    final records = paidAll4();

    final beforeBoundary =
        resolve(workers: workers4, records: records, referenceDate: DateTime(2026, 8, 15));
    expect(PayrollService.periodDateKey(beforeBoundary.start), '2026-08-16');

    final atBoundary = resolve(workers: workers4, records: records, referenceDate: aug16);
    expect(PayrollService.periodDateKey(atBoundary.start), '2026-08-16');

    final after = resolve(workers: workers4, records: records, referenceDate: DateTime(2026, 8, 20));
    expect(PayrollService.periodDateKey(after.start), '2026-08-16');
    expect(PayrollService.periodDateKey(after.end), '2026-09-16');

    final nextMonthDue = resolve(workers: workers4, records: records, referenceDate: sep16);
    expect(PayrollService.periodDateKey(nextMonthDue.start), '2026-08-16');
    expect(PayrollService.periodDateKey(nextMonthDue.end), '2026-09-16');

    final backdated =
        resolve(workers: workers4, records: records, referenceDate: DateTime(2026, 5, 20));
    expect(PayrollService.periodDateKey(backdated.start), '2026-08-16');
    expect(PayrollService.periodDateKey(backdated.end), '2026-09-16');

    final backdatedAgain =
        resolve(workers: workers4, records: records, referenceDate: DateTime(2026, 5, 20));
    expect(PayrollService.payrollPeriodsEqual(backdated, backdatedAgain), isTrue);
  });

  test('F) Firestore listener fires multiple times -> idempotent', () {
    final r1 = resolve(workers: workers4, records: paidAll4());
    final r2 = resolve(workers: workers4, records: paidAll4());
    final r3 = resolve(workers: workers4, records: paidAll4());
    expect(PayrollService.payrollPeriodsEqual(r1, r2), isTrue);
    expect(PayrollService.payrollPeriodsEqual(r2, r3), isTrue);
    expect(PayrollService.periodDateKey(r1.start), '2026-08-16');
  });

  test('G) Attendance changes never move the payroll cycle', () {
    final records = [paidRecord(workerId: 'w1', start: jul16, end: aug16)];
    final workersA = workers4.map((w) => {...w, 'absents': 0, 'leaves': 0}).toList();
    final workersB =
        workers4.map((w) => {...w, 'absents': 5, 'leaves': 2, 'halfDays': 3}).toList();

    final withAttendance = resolve(workers: workersA, records: records);
    final editedAttendance = resolve(workers: workersB, records: records);
    expect(PayrollService.payrollPeriodsEqual(withAttendance, editedAttendance), isTrue);
  });

  test('paid-flag record shape matches what Pay All writes', () {
    final payable = PayrollService.payableWorkersForPeriod(
      workers4,
      paidAll4(),
      month: aug16,
      periodStart: jul16,
      periodEnd: aug16,
    );
    expect(payable, isEmpty);
  });

    test('M) Ignore on overdue Jul8-Aug8 -> advance exactly to Aug8-Sep8', () {
    const pd = 8;
    final jul8 = DateTime(2026, 7, 8);
    final aug8 = DateTime(2026, 8, 8);

    Map<String, dynamic> w(String id) => {
          'workerId': id,
          'id': id,
          'name': 'W$id',
          'email': '$id@example.com',
          'status': 'Active',
          'salaryAmount': '1000',
          'salary': '1000',
        };

    final ws = ['a', 'b'].map(w).toList();

        final overdueCycle = PayrollPeriod(start: jul8, end: aug8);
    final nextCycle = PayrollService.nextPayDayPeriod(overdueCycle, pd);

    expect(PayrollService.periodDateKey(nextCycle.start), '2026-08-08');
    expect(PayrollService.periodDateKey(nextCycle.end), '2026-09-08');

        final p = PayrollService.resolveCurrentPayrollPeriod(
      workersList: ws,
      payrollRecords: [],
      payDay: pd,
      referenceDate: DateTime(2026, 8, 10),
      persistedCycle: nextCycle,
    );
    expect(PayrollService.periodDateKey(p.start), '2026-08-08');
    expect(PayrollService.periodDateKey(p.end), '2026-09-08');
  });

    test('N) After Ignore, resolver is idempotent across repeated calls', () {
    const pd = 16;
    final nextCycle = PayrollPeriod(start: aug16, end: sep16);

    final r1 = PayrollService.resolveCurrentPayrollPeriod(
      workersList: workers4,
      payrollRecords: paidAll4(),
      payDay: pd,
      referenceDate: aug16,
      persistedCycle: nextCycle,
    );
    final r2 = PayrollService.resolveCurrentPayrollPeriod(
      workersList: workers4,
      payrollRecords: paidAll4(),
      payDay: pd,
      referenceDate: aug16,
      persistedCycle: r1,
    );
    final r3 = PayrollService.resolveCurrentPayrollPeriod(
      workersList: workers4,
      payrollRecords: paidAll4(),
      payDay: pd,
      referenceDate: aug16,
      persistedCycle: r2,
    );
    expect(PayrollService.payrollPeriodsEqual(r1, r2), isTrue);
    expect(PayrollService.payrollPeriodsEqual(r2, r3), isTrue);
    expect(PayrollService.periodDateKey(r1.start), '2026-08-16');
    expect(PayrollService.periodDateKey(r1.end), '2026-09-16');
  });

    test('H/O) Aug 17 with unpaid workers from Jul16-Aug16 -> stay Jul16-Aug16 (overdue)', () {
    final records = [
      paidRecord(workerId: 'w1', start: jul16, end: aug16),
          ];
    final persisted = PayrollPeriod(start: jul16, end: aug16);
    final p = PayrollService.resolveCurrentPayrollPeriod(
      workersList: workers4,
      payrollRecords: records,
      payDay: payDay,
      referenceDate: DateTime(2026, 8, 17),
      persistedCycle: persisted,
    );
    expect(PayrollService.periodDateKey(p.start), '2026-07-16');
    expect(PayrollService.periodDateKey(p.end), '2026-08-16');
  });

    test('Aug 17 with ALL paid Jul16-Aug16 -> advance to Aug16-Sep16', () {
    final persisted = PayrollPeriod(start: jul16, end: aug16);
    final p = PayrollService.resolveCurrentPayrollPeriod(
      workersList: workers4,
      payrollRecords: paidAll4(),
      payDay: payDay,
      referenceDate: DateTime(2026, 8, 17),
      persistedCycle: persisted,
    );
    expect(PayrollService.periodDateKey(p.start), '2026-08-16');
    expect(PayrollService.periodDateKey(p.end), '2026-09-16');
  });

    test('Aug 23 with unpaid Jul16-Aug16 -> still Jul16-Aug16 (overdue)', () {
    final records = [
      paidRecord(workerId: 'w1', start: jul16, end: aug16),
      paidRecord(workerId: 'w2', start: jul16, end: aug16),
          ];
    final persisted = PayrollPeriod(start: jul16, end: aug16);

    for (int day = 17; day <= 23; day++) {
      final p = PayrollService.resolveCurrentPayrollPeriod(
        workersList: workers4,
        payrollRecords: records,
        payDay: payDay,
        referenceDate: DateTime(2026, 8, day),
        persistedCycle: persisted,
      );
      expect(PayrollService.periodDateKey(p.start), '2026-07-16',
          reason: 'Day $day: should remain on Jul16-Aug16 overdue cycle');
      expect(PayrollService.periodDateKey(p.end), '2026-08-16',
          reason: 'Day $day: should remain on Jul16-Aug16 overdue cycle');
    }
  });

    test('O) After Ignore to Aug16-Sep16, stale Jul16-Aug16 is not restored', () {
        final afterIgnore = PayrollPeriod(start: aug16, end: sep16);
    final p = PayrollService.resolveCurrentPayrollPeriod(
      workersList: workers4,
      payrollRecords: paidAll4(),
      payDay: payDay,
      referenceDate: DateTime(2026, 8, 17),
      persistedCycle: afterIgnore,
    );
        expect(PayrollService.periodDateKey(p.start), '2026-08-16');
    expect(PayrollService.periodDateKey(p.end), '2026-09-16');
  });

    test('N2) Pay Day 8: Ignore Jul8-Aug8 -> Aug8-Sep8, rebuild stays Sep8', () {
    const pd = 8;
    final aug8 = DateTime(2026, 8, 8);
    final sep8 = DateTime(2026, 9, 8);

    Map<String, dynamic> w(String id) => {
          'workerId': id,
          'id': id,
          'name': 'W$id',
          'email': '$id@example.com',
          'status': 'Active',
          'salaryAmount': '1000',
          'salary': '1000',
        };

    final ws = ['a', 'b'].map(w).toList();

    final afterIgnore = PayrollPeriod(start: aug8, end: sep8);
    final r1 = PayrollService.resolveCurrentPayrollPeriod(
      workersList: ws,
      payrollRecords: [],
      payDay: pd,
      referenceDate: DateTime(2026, 8, 10),
      persistedCycle: afterIgnore,
    );
    final r2 = PayrollService.resolveCurrentPayrollPeriod(
      workersList: ws,
      payrollRecords: [],
      payDay: pd,
      referenceDate: DateTime(2026, 8, 12),
      persistedCycle: r1,
    );
    final r3 = PayrollService.resolveCurrentPayrollPeriod(
      workersList: ws,
      payrollRecords: [],
      payDay: pd,
      referenceDate: DateTime(2026, 8, 15),
      persistedCycle: r2,
    );
    expect(PayrollService.periodDateKey(r1.start), '2026-08-08');
    expect(PayrollService.periodDateKey(r1.end), '2026-09-08');
    expect(PayrollService.payrollPeriodsEqual(r1, r2), isTrue);
    expect(PayrollService.payrollPeriodsEqual(r2, r3), isTrue);
  });

      test('Late joiner (after period end) is NOT payable for the cycle', () {
    final jul13 = DateTime(2026, 7, 13);
    final aug13 = DateTime(2026, 8, 13);

    Map<String, dynamic> w(String id) => {
          'workerId': id,
          'id': id,
          'name': 'W$id',
          'email': '$id@example.com',
          'status': 'Active',
          'salaryAmount': '1000',
          'salary': '1000',
        };

    final lateJoiner = w('ayesha')..['joiningDate'] = DateTime(2026, 8, 14);
    final others = [w('w2'), w('w3'), w('w4')];
    final workers = [lateJoiner, ...others];

            final payable = PayrollService.payableWorkersForPeriod(
      workers,
      const [],
      month: aug13,
      periodStart: jul13,
      periodEnd: aug13,
    );

    expect(payable.map((w) => w['workerId']).toList(), isNot(contains('ayesha')));
    expect(payable.length, others.length);

            final excluded = PayrollService.excludedLateJoinersForPeriod(
      workers,
      const [],
      month: aug13,
      periodStart: jul13,
      periodEnd: aug13,
    );
    expect(excluded.map((w) => w['workerId']).toList(), contains('ayesha'));
    expect(excluded.length, 1);
  });

  test('workerEmployedDuringPeriod: joining on period end IS employed', () {
    final onBoundary = worker('edge')..['joiningDate'] = aug16;
    final beforeBoundary = worker('early')..['joiningDate'] = jul16;
    expect(PayrollService.workerEmployedDuringPeriod(onBoundary, aug16), isTrue);
    expect(PayrollService.workerEmployedDuringPeriod(beforeBoundary, aug16), isTrue);
    expect(PayrollService.workerEmployedDuringPeriod(worker('noDate'), aug16), isTrue);
  });


  test('BUG) Missing profile fields + unpaid workers + Aug 17 -> Jul16-Aug16', () {
                    final p = PayrollService.resolveCurrentPayrollPeriod(
      workersList: workers4,
      payrollRecords: const [],       payDay: payDay,
      referenceDate: DateTime(2026, 8, 17),
      persistedCycle: null,     );
    expect(PayrollService.periodDateKey(p.start), '2026-07-16');
    expect(PayrollService.periodDateKey(p.end), '2026-08-16');
  });

  test('BUG) Missing profile fields + partial paid + Aug 17 -> Jul16-Aug16', () {
            final records = [
      paidRecord(workerId: 'w1', start: jul16, end: aug16),
      paidRecord(workerId: 'w2', start: jul16, end: aug16),
    ];
    final p = PayrollService.resolveCurrentPayrollPeriod(
      workersList: workers4,
      payrollRecords: records,
      payDay: payDay,
      referenceDate: DateTime(2026, 8, 17),
      persistedCycle: null,
    );
    expect(PayrollService.periodDateKey(p.start), '2026-07-16');
    expect(PayrollService.periodDateKey(p.end), '2026-08-16');
  });

      test('App start Aug 20 with persisted Jul16-Aug16 overdue -> stays Jul16-Aug16', () {
    final records = [
      paidRecord(workerId: 'w1', start: jul16, end: aug16),
          ];
    final persisted = PayrollPeriod(start: jul16, end: aug16);
    final p = PayrollService.resolveCurrentPayrollPeriod(
      workersList: workers4,
      payrollRecords: records,
      payDay: payDay,
      referenceDate: DateTime(2026, 8, 20),
      persistedCycle: persisted,
    );
    expect(PayrollService.periodDateKey(p.start), '2026-07-16');
    expect(PayrollService.periodDateKey(p.end), '2026-08-16');
  });

  test('BUG) Missing profile fields + ALL paid + Aug 17 -> advance to Aug16-Sep16', () {
            final p = PayrollService.resolveCurrentPayrollPeriod(
      workersList: workers4,
      payrollRecords: paidAll4(),
      payDay: payDay,
      referenceDate: DateTime(2026, 8, 17),
      persistedCycle: null,
    );
    expect(PayrollService.periodDateKey(p.start), '2026-08-16');
    expect(PayrollService.periodDateKey(p.end), '2026-09-16');
  });

  test('Test 1: No payroll history. No Pay Day => current calendar month', () {
    final refDate = DateTime(2026, 8, 20);
    final p = PayrollService.resolveCurrentPayrollPeriod(
      workersList: workers4,
      payrollRecords: const [],
      payDay: 0,
      referenceDate: refDate,
    );
    expect(PayrollService.periodDateKey(p.start), '2026-08-01');
    expect(PayrollService.periodDateKey(p.end), '2026-08-31');
  });

  test('Test 2: Set Pay Day = 10 before any payroll is Paid => previous 10 -> current 10', () {
    final refDate = DateTime(2026, 8, 20);
    final p = PayrollService.resolveCurrentPayrollPeriod(
      workersList: workers4,
      payrollRecords: const [],
      payDay: 10,
      referenceDate: refDate,
    );
    expect(PayrollService.periodDateKey(p.start), '2026-07-10');
    expect(PayrollService.periodDateKey(p.end), '2026-08-10');
  });

  test('Test 3: Change 10 -> 20 before any payroll is Paid => previous 20 -> current 20', () {
    final refDate = DateTime(2026, 8, 19);
    final p = PayrollService.resolveCurrentPayrollPeriod(
      workersList: workers4,
      payrollRecords: const [],
      payDay: 20,
      referenceDate: refDate,
    );
    expect(PayrollService.periodDateKey(p.start), '2026-07-20');
    expect(PayrollService.periodDateKey(p.end), '2026-08-20');
  });

  test('Test 4: Pay all workers for the cycle => next cycle becomes 20 -> next month 20', () {
    final start20 = DateTime(2026, 7, 20);
    final end20 = DateTime(2026, 8, 20);
    final records = workers4
        .map((w) => paidRecord(workerId: w['workerId'] as String, start: start20, end: end20))
        .toList();

    final p = PayrollService.resolveCurrentPayrollPeriod(
      workersList: workers4,
      payrollRecords: records,
      payDay: 20,
      referenceDate: DateTime(2026, 8, 21),
    );
    expect(PayrollService.periodDateKey(p.start), '2026-08-20');
    expect(PayrollService.periodDateKey(p.end), '2026-09-20');
  });

  test('Test 5: Try to change Pay Day after a Paid cycle exists => Existing Pay Day and current cycle unchanged', () {
    final start20 = DateTime(2026, 7, 20);
    final end20 = DateTime(2026, 8, 20);
    final records = workers4
        .map((w) => paidRecord(workerId: w['workerId'] as String, start: start20, end: end20))
        .toList();

    final p = PayrollService.resolveCurrentPayrollPeriod(
      workersList: workers4,
      payrollRecords: records,
      payDay: 10,
      referenceDate: DateTime(2026, 8, 21),
    );
    expect(PayrollService.periodDateKey(p.start), '2026-08-20');
    expect(PayrollService.periodDateKey(p.end), '2026-09-20');
  });

  test('Test 6: Try Clear Pay Day after a Paid cycle exists => blocked (cycle and pay day unchanged)', () {
    final start20 = DateTime(2026, 7, 20);
    final end20 = DateTime(2026, 8, 20);
    final records = workers4
        .map((w) => paidRecord(workerId: w['workerId'] as String, start: start20, end: end20))
        .toList();

    final p = PayrollService.resolveCurrentPayrollPeriod(
      workersList: workers4,
      payrollRecords: records,
      payDay: 0,
      referenceDate: DateTime(2026, 8, 21),
    );
    expect(PayrollService.periodDateKey(p.start), '2026-08-20');
    expect(PayrollService.periodDateKey(p.end), '2026-09-20');
  });

  test('Test H: After cancelling/resetting all processed payroll history, changing or clearing Pay Day should work normally again', () {
    final start20 = DateTime(2026, 7, 20);
    final end20 = DateTime(2026, 8, 20);
    final records = workers4
        .map((w) => paidRecord(workerId: w['workerId'] as String, start: start20, end: end20))
        .toList();

    final pLocked = PayrollService.resolveCurrentPayrollPeriod(
      workersList: workers4,
      payrollRecords: records,
      payDay: 10,
      referenceDate: DateTime(2026, 8, 21),
    );
    expect(PayrollService.periodDateKey(pLocked.start), '2026-08-20');
    expect(PayrollService.periodDateKey(pLocked.end), '2026-09-20');

    final cancelledRecords = workers4
        .map((w) => paidRecord(workerId: w['workerId'] as String, start: start20, end: end20, paid: false))
        .toList();

    final pChange = PayrollService.resolveCurrentPayrollPeriod(
      workersList: workers4,
      payrollRecords: cancelledRecords,
      payDay: 10,
      referenceDate: DateTime(2026, 8, 21),
    );
    expect(PayrollService.periodDateKey(pChange.start), '2026-07-10');
    expect(PayrollService.periodDateKey(pChange.end), '2026-08-10');

    final pClear = PayrollService.resolveCurrentPayrollPeriod(
      workersList: workers4,
      payrollRecords: cancelledRecords,
      payDay: 0,
      referenceDate: DateTime(2026, 8, 21),
    );
    expect(PayrollService.periodDateKey(pClear.start), '2026-08-01');
    expect(PayrollService.periodDateKey(pClear.end), '2026-08-31');
  });

  test('Test: Even one Paid worker counts as processed payroll history and blocks Pay Day change/clear', () {
    final start20 = DateTime(2026, 7, 20);
    final end20 = DateTime(2026, 8, 20);
    final records = [
      paidRecord(workerId: 'w1', start: start20, end: end20, paid: true),
    ];

    final p = PayrollService.resolveCurrentPayrollPeriod(
      workersList: workers4,
      payrollRecords: records,
      payDay: 10,
      referenceDate: DateTime(2026, 8, 21),
    );
    expect(PayrollService.periodDateKey(p.start), '2026-07-20');
    expect(PayrollService.periodDateKey(p.end), '2026-08-20');
  });
}