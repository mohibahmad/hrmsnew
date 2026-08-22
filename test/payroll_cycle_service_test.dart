import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/payroll/payroll_cycle_service.dart';
import 'package:hrms/services/payroll/payroll_service.dart';

DateTime d(int year, int month, int day) => DateTime(year, month, day);

final debugWorkers = <Map<String, dynamic>>[
  {
    'id': 'w1',
    'name': 'Worker A',
    'email': 'a@x.com',
    'status': 'Active',
    'salary': '1000',
    'joiningDate': '2026-01-01',
  },
];
final debugDocs = <Map<String, dynamic>>[
  {
    'workerId': 'w1',
    'payPeriodStart': '2026-08-23T00:00:00.000',
    'payPeriodEnd': '2026-09-23T00:00:00.000',
    'isPaid': false,
    'salary': '1000',
    'name': 'Worker A',
  },
];

void main() {
  test('debug combinePayroll', () {
    final unpaid = PayrollService.unpaidWorkersForPeriod(
      debugWorkers,
      debugDocs,
      month: d(2026, 9, 1),
      periodStart: d(2026, 8, 23),
      periodEnd: d(2026, 9, 23),
    );
    // ignore: avoid_print
    print('unpaid count: \\u{1F680} ${unpaid.length}');
    for (final w in unpaid) {
      // ignore: avoid_print
      print('unpaid: ${w['name']} paid=${w['isPaid']} salary=${w['salary']}');
    }
    final payable = PayrollService.payableWorkersForPeriod(
      debugWorkers,
      debugDocs,
      month: d(2026, 9, 1),
      periodStart: d(2026, 8, 23),
      periodEnd: d(2026, 9, 23),
    );
    // ignore: avoid_print
    print('payable count: ${payable.length}');
    expect(unpaid, isNotEmpty);
  });
  group('PayrollCycleService — acceptance tests', () {
    test('Test 1 — before pay day (21 Aug, pay day 23)', () {
      final cycle = PayrollCycleService.payDayCycleContaining(
        d(2026, 8, 21),
        23,
      );
      expect(PayrollCycleService.dueDateOf(cycle), d(2026, 8, 23));
      final gate = PayrollCycleService.canProcessPayment(
        cycle: cycle,
        now: d(2026, 8, 21),
      );
      expect(gate.allowed, isFalse);
      expect(gate.dueDate, d(2026, 8, 23));
    });

    test('Test 2 — on pay day (23 Aug, pay day 23)', () {
      // Active cycle still the one ending today (persisted, unpaid).
      final persisted = PayrollPeriod(
        start: d(2026, 7, 23),
        end: d(2026, 8, 23),
      );
      final active = PayrollCycleService.resolveActiveCycle(
        salaryPayDay: 23,
        now: d(2026, 8, 23),
        persistedCycle: persisted,
        persistedHasUnpaidWorkers: true,
      );
      expect(PayrollCycleService.dueDateOf(active), d(2026, 8, 23));
      final gate = PayrollCycleService.canProcessPayment(
        cycle: active,
        now: d(2026, 8, 23),
      );
      expect(gate.allowed, isTrue);
    });

    test('Test 3 — next cycle after completing 23 Jul – 23 Aug', () {
      final next = PayrollCycleService.nextCycleAfter(
        PayrollPeriod(start: d(2026, 7, 23), end: d(2026, 8, 23)),
        23,
      );
      expect(next.start, d(2026, 8, 23));
      expect(next.end, d(2026, 9, 23));
    });

    test('nextCycleFromPaymentDate — payment on Aug 21, pay day 23', () {
      // Pay day 23, cycle Jul 23 – Aug 23, payment on Aug 21
      // -> next cycle Aug 21 – Sep 21 (pay day becomes 21)
      final next = PayrollCycleService.nextCycleFromPaymentDate(
        d(2026, 8, 21),
        23,
      );
      expect(next.start, d(2026, 8, 21));
      expect(next.end, d(2026, 9, 21));
    });

    test('nextCycleFromPaymentDate — payment on Aug 23 (exact pay day)', () {
      // Pay day 23, payment on Aug 23 -> next cycle Aug 23 – Sep 23
      final next = PayrollCycleService.nextCycleFromPaymentDate(
        d(2026, 8, 23),
        23,
      );
      expect(next.start, d(2026, 8, 23));
      expect(next.end, d(2026, 9, 23));
    });

    test('Test 4 — reminder starts exactly 3 days before due date', () {
      final due = d(2026, 9, 23);
      expect(
        PayrollCycleService.isReminderWindow(now: d(2026, 9, 19), dueDate: due),
        isFalse,
      );
      expect(
        PayrollCycleService.isReminderWindow(now: d(2026, 9, 20), dueDate: due),
        isTrue,
      );
      expect(
        PayrollCycleService.isReminderWindow(now: d(2026, 9, 22), dueDate: due),
        isTrue,
      );
      expect(
        PayrollCycleService.isReminderWindow(now: d(2026, 9, 23), dueDate: due),
        isTrue,
      );
      expect(
        PayrollCycleService.isReminderWindow(now: d(2026, 9, 24), dueDate: due),
        isFalse,
      );
    });

    test('Test 5 — overdue never expires (no 7-day cutoff)', () {
      final due = d(2026, 9, 23);
      for (final day in [24, 30, 31]) {
        expect(
          PayrollCycleService.isOverdue(now: d(2026, 9, day), dueDate: due),
          isTrue,
        );
      }
      for (final month in [10, 11, 12]) {
        expect(
          PayrollCycleService.isOverdue(now: d(2026, month, 15), dueDate: due),
          isTrue,
        );
      }
      expect(
        PayrollCycleService.isOverdue(now: d(2027, 9, 23), dueDate: due),
        isTrue,
      );
      final state = PayrollCycleService.stateOf(
        now: d(2026, 12, 1),
        cycle: PayrollPeriod(start: d(2026, 8, 23), end: due),
        hasUnpaidWorkers: true,
      );
      expect(state, PayrollCycleState.overdue);
    });

    test('Test 6 — overdue previous cycle coexists with new active cycle', () {
      final active = PayrollCycleService.resolveActiveCycle(
        salaryPayDay: 23,
        now: d(2026, 9, 25),
        persistedCycle: PayrollPeriod(
          start: d(2026, 8, 23),
          end: d(2026, 9, 23),
        ),
        // Previous cycle still unpaid -> it stays the active/overdue cycle.
        persistedHasUnpaidWorkers: true,
      );
      expect(active.start, d(2026, 8, 23));
      expect(active.end, d(2026, 9, 23));

      // After HR explicitly advances (persisted = new cycle), the old one is
      // still reported as an outstanding previous cycle.
      final advanced = PayrollCycleService.resolveActiveCycle(
        salaryPayDay: 23,
        now: d(2026, 9, 25),
        persistedCycle: PayrollPeriod(
          start: d(2026, 9, 23),
          end: d(2026, 10, 23),
        ),
        persistedHasUnpaidWorkers: false,
      );
      expect(advanced.start, d(2026, 9, 23));
      expect(advanced.end, d(2026, 10, 23));

      final outstanding = PayrollCycleService.getOutstandingPreviousCycles(
        workersList: debugWorkers,
        rawPayrollDocs: debugDocs,
        activeCycle: advanced,
        extraCandidates: [
          PayrollPeriod(start: d(2026, 8, 23), end: d(2026, 9, 23)),
        ],
      );
      expect(outstanding, hasLength(1));
      expect(outstanding.first.start, d(2026, 8, 23));
      expect(outstanding.first.end, d(2026, 9, 23));
    });

    test('Tests 7/8/9 — change pay day to 20 / 10 / 21 in August', () {
      final p20 = PayrollCycleService.payDayCycleContaining(d(2026, 8, 21), 20);
      expect(p20.start, d(2026, 8, 20));
      expect(p20.end, d(2026, 9, 20));

      final p10 = PayrollCycleService.payDayCycleContaining(d(2026, 8, 21), 10);
      expect(p10.start, d(2026, 8, 10));
      expect(p10.end, d(2026, 9, 10));

      final p21 = PayrollCycleService.payDayCycleContaining(d(2026, 8, 21), 21);
      expect(p21.start, d(2026, 8, 21));
      expect(p21.end, d(2026, 9, 21));
    });

    test('Tests 10/11 — clear pay day restores calendar month', () {
      final aug = PayrollCycleService.calendarMonthCycle(d(2026, 8, 21));
      expect(aug.start, d(2026, 8, 1));
      expect(aug.end, d(2026, 8, 31));

      final sep = PayrollCycleService.calendarMonthCycle(d(2026, 9, 5));
      expect(sep.start, d(2026, 9, 1));
      expect(sep.end, d(2026, 9, 30));

      final feb = PayrollCycleService.calendarMonthCycle(d(2028, 2, 10));
      expect(feb.end, d(2028, 2, 29)); // leap year
      final apr = PayrollCycleService.calendarMonthCycle(d(2026, 4, 2));
      expect(apr.end, d(2026, 4, 30));
    });

    test('Requirement 1/8 — pay day anchor is never silently changed', () {
      // 21 Aug with pay day 23 -> 23 Jul – 23 Aug (due 23 Aug), blocked.
      final active = PayrollCycleService.resolveActiveCycle(
        salaryPayDay: 23,
        now: d(2026, 8, 21),
      );
      expect(active.start, d(2026, 7, 23));
      expect(active.end, d(2026, 8, 23));
      expect(
        PayrollCycleService.canProcessPayment(
          cycle: active,
          now: d(2026, 8, 21),
        ).allowed,
        isFalse,
      );
      // On 23 Aug processing becomes available.
      expect(
        PayrollCycleService.canProcessPayment(
          cycle: active,
          now: d(2026, 8, 23),
        ).allowed,
        isTrue,
      );
    });

    test('Normalization — time-of-day cannot break pay day logic', () {
      final morning = DateTime(2026, 8, 23, 0, 5);
      final night = DateTime(2026, 8, 23, 23, 59);
      expect(PayrollCycleService.isSameCalendarDay(morning, night), isTrue);
      final gate = PayrollCycleService.canProcessPayment(
        cycle: PayrollPeriod(start: d(2026, 7, 23), end: d(2026, 8, 23)),
        now: night,
      );
      expect(gate.allowed, isTrue);
    });

    test('Anchor anchoring around short months', () {
      // 20 Feb 2027 with pay day 23 -> the containing cycle is Jan 23 – Feb 23.
      final cycle = PayrollCycleService.payDayCycleContaining(
        d(2027, 2, 20),
        23,
      );
      expect(cycle.start, d(2027, 1, 23));
      expect(cycle.end, d(2027, 2, 23));
    });

    test('No persisted cycle — pay day anchored containing cycle', () {
      // Aug 21, pay day 17, no persisted cycle → Jul 17 – Aug 17
      final active = PayrollCycleService.resolveActiveCycle(
        salaryPayDay: 17,
        now: d(2026, 8, 21),
      );
      expect(active.start, d(2026, 7, 17));
      expect(active.end, d(2026, 8, 17));

      // Aug 21, pay day 20 → Jul 20 – Aug 20
      final p20 = PayrollCycleService.resolveActiveCycle(
        salaryPayDay: 20,
        now: d(2026, 8, 21),
      );
      expect(p20.start, d(2026, 7, 20));
      expect(p20.end, d(2026, 8, 20));

      // Aug 21, pay day 10 → Jul 10 – Aug 10
      final p10 = PayrollCycleService.resolveActiveCycle(
        salaryPayDay: 10,
        now: d(2026, 8, 21),
      );
      expect(p10.start, d(2026, 7, 10));
      expect(p10.end, d(2026, 8, 10));
    });

    test('No persisted cycle — before pay day also pay-day anchored', () {
      // Aug 15, pay day 23, no persisted cycle → Jul 23 – Aug 23
      final active = PayrollCycleService.resolveActiveCycle(
        salaryPayDay: 23,
        now: d(2026, 8, 15),
      );
      expect(active.start, d(2026, 7, 23));
      expect(active.end, d(2026, 8, 23));
    });

    test('stateOf transitions', () {
      final cycle = PayrollPeriod(start: d(2026, 8, 23), end: d(2026, 9, 23));
      expect(
        PayrollCycleService.stateOf(
          now: d(2026, 9, 1),
          cycle: cycle,
          hasUnpaidWorkers: true,
        ),
        PayrollCycleState.upcoming,
      );
      expect(
        PayrollCycleService.stateOf(
          now: d(2026, 9, 21),
          cycle: cycle,
          hasUnpaidWorkers: true,
        ),
        PayrollCycleState.reminder,
      );
      expect(
        PayrollCycleService.stateOf(
          now: d(2026, 9, 23),
          cycle: cycle,
          hasUnpaidWorkers: true,
        ),
        PayrollCycleState.due,
      );
      expect(
        PayrollCycleService.stateOf(
          now: d(2026, 9, 24),
          cycle: cycle,
          hasUnpaidWorkers: true,
        ),
        PayrollCycleState.overdue,
      );
      // Reminder/overdue require unpaid workers.
      expect(
        PayrollCycleService.stateOf(
          now: d(2026, 9, 24),
          cycle: cycle,
          hasUnpaidWorkers: false,
        ),
        PayrollCycleState.settled,
      );
      expect(
        PayrollCycleService.stateOf(
          now: d(2026, 9, 21),
          cycle: cycle,
          hasUnpaidWorkers: false,
        ),
        PayrollCycleState.upcoming,
      );
    });
  });
}
