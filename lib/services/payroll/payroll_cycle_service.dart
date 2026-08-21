import 'package:hrms/core/utils/utils.dart';
import 'package:hrms/services/payroll/payroll_service.dart';

/// Lifecycle state of a payroll cycle (requirement #10).
enum PayrollCycleState {
  /// today < dueDate — normal active payroll cannot be processed yet.
  upcoming,

  /// dueDate - 3 <= today <= dueDate && hasUnpaidWorkers — show reminder.
  reminder,

  /// today is the same calendar day as dueDate — processing allowed.
  due,

  /// today > dueDate && hasUnpaidWorkers — persists indefinitely until paid.
  overdue,

  /// Every required worker for the cycle has been paid/resolved.
  settled,
}

/// Result of the shared Pay Day gate used by Pay All, Process Payroll and any
/// other action that creates/completes payment for a payroll cycle.
class PayrollProcessCheck {
  final bool allowed;

  /// The cycle's due (pay) date, normalized to calendar-day precision.
  final DateTime? dueDate;

  const PayrollProcessCheck({required this.allowed, this.dueDate});
}

/// Single source of truth for every payroll-cycle date calculation:
/// cycle start/end, due date, Pay Day anchoring, reminder window, overdue
/// state and payment availability. Screens must never compute these dates
/// independently.
class PayrollCycleService {
  /// How many days before the due date the payroll reminder starts.
  static const int reminderLeadDays = 3;

  // ---------------------------------------------------------------------
  // Date normalization (requirement #11)
  // ---------------------------------------------------------------------

  /// Strips time components so comparisons are always calendar-date based.
  static DateTime normalize(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static bool isSameCalendarDay(DateTime a, DateTime b) {
    final x = normalize(a);
    final y = normalize(b);
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  /// Real last day of a month, leap-year aware (requirement #9).

  /// Custom Pay Day mode: an anchored `D -> D` cycle that contains [today].
  ///
  /// The most recent anchor on or before today starts the cycle and the next
  /// anchor ends it, e.g. with Pay Day 23:
  ///   21 Aug -> 23 Jul - 23 Aug   (due 23 Aug)
  ///   24 Aug -> 23 Aug - 23 Sep   (previous cycle is now overdue/unpaid)
  /// And while working in August:
  ///   Pay Day 20 -> 20 Aug - 20 Sep
  ///   Pay Day 10 -> 10 Aug - 10 Sep
  ///   Pay Day 21 -> 21 Aug - 21 Sep
  static PayrollPeriod payDayCycleContaining(DateTime today, int payDay) {
    final t = normalize(today);
    final anchorThisMonth = anchorInMonth(t, payDay);
    if (!t.isBefore(anchorThisMonth)) {
      return PayrollPeriod(
        start: anchorThisMonth,
        end: anchorInMonth(DateTime(t.year, t.month + 1, 1), payDay),
      );
    }
    return PayrollPeriod(
      start: anchorInMonth(DateTime(t.year, t.month - 1, 1), payDay),
      end: anchorThisMonth,
    );
  }

  /// The anchored cycle immediately before [cycle] (ends where it starts).
  static PayrollPeriod previousAnchoredCycle(PayrollPeriod cycle, int payDay) {
    final start = normalize(cycle.start);
    return PayrollPeriod(
      start: anchorInMonth(DateTime(start.year, start.month - 1, 1), payDay),
      end: start,
    );
  }

  /// Due (pay) date of a cycle is always its end, normalized.
  static DateTime dueDateOf(PayrollPeriod cycle) => normalize(cycle.end);

  /// Next cycle after a completed one, keeping the same anchoring mode
  /// (requirement #3): 23 Jul - 23 Aug completed -> 23 Aug - 23 Sep.
  static PayrollPeriod nextCycleAfter(PayrollPeriod current, int? payDay) {
    final end = normalize(current.end);
    final start = normalize(current.start);
    final lastOfEndMonth = daysInMonth(end.year, end.month);
    final isCalendarMonth =
        start.day == 1 && end.day == lastOfEndMonth.day;

    if (payDay != null && payDay >= 1 && !isCalendarMonth) {
      return PayrollPeriod(
        start: end,
        end: anchorInMonth(DateTime(end.year, end.month + 1, 1), payDay),
      );
    }

    final nextStart = DateTime(end.year, end.month + 1, 1);
    return PayrollPeriod(
      start: nextStart,
      end: DateTime(nextStart.year, nextStart.month + 1, 0),
    );
  }

  static bool cyclesEqual(PayrollPeriod a, PayrollPeriod b) =>
      PayrollService.payrollPeriodsEqual(a, b);

  /// True when [cycle] is a genuine `D -> D` anchored cycle for [payDay]
  /// (both boundaries land on the clamped anchor day of their months).
  static bool isValidAnchoredCycle(PayrollPeriod cycle, int payDay) {
    final start = normalize(cycle.start);
    final end = normalize(cycle.end);
    if (!end.isAfter(start)) return false;
    if (start.day != anchorInMonth(start, payDay).day) return false;
    if (end.day != anchorInMonth(end, payDay).day) return false;
    // Roughly one month long.
    final monthDiff =
        (end.year * 12 + end.month) - (start.year * 12 + start.month);
    return monthDiff == 1 || monthDiff == 0;
  }

  static DateTime daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0);

  // ---------------------------------------------------------------------
  // Cycle construction
  // ---------------------------------------------------------------------

  /// Calendar-month mode: cycleStart = 1st, cycleEnd/dueDate = last day.
  static PayrollPeriod calendarMonthCycle(DateTime reference) {
    final r = normalize(reference);
    return PayrollPeriod(
      start: DateTime(r.year, r.month, 1),
      end: DateTime(r.year, r.month + 1, 0),
    );
  }

  /// The pay-day anchor inside [month], clamped to the month's real length.
  static DateTime anchorInMonth(DateTime month, int payDay) {
    final m = DateTime(month.year, month.month, 1);
    final lastDay = daysInMonth(m.year, m.month).day;
    return DateTime(m.year, m.month, payDay.clamp(1, lastDay));
  }

  // ---------------------------------------------------------------------
  // Active cycle resolution
  // ---------------------------------------------------------------------

  /// Resolves the single authoritative active cycle for [now].
  ///
  /// * No custom Pay Day -> calendar-month cycle of the current month,
  ///   regardless of any persisted custom cycle (Clear Pay Day restores
  ///   calendar mode immediately — requirement #9).
  /// * Custom Pay Day -> the anchored `D -> D` cycle containing today. A valid
  ///   persisted cycle is honoured when it is the containing cycle, exactly
  ///   one cycle ahead (HR explicitly skipped/advanced), or exactly one cycle
  ///   behind while still holding unpaid workers (overdue must never silently
  ///   disappear — requirements #1, #5, #6).
  static PayrollPeriod resolveActiveCycle({
    required int? salaryPayDay,
    required DateTime now,
    PayrollPeriod? persistedCycle,
    bool persistedHasUnpaidWorkers = false,
  }) {
    final today = normalize(now);

    if (salaryPayDay == null || salaryPayDay <= 0) {
      return calendarMonthCycle(today);
    }

    final containing = payDayCycleContaining(today, salaryPayDay);

    if (persistedCycle != null) {
      final persisted = PayrollPeriod(
        start: normalize(persistedCycle.start),
        end: normalize(persistedCycle.end),
      );
      if (isValidAnchoredCycle(persisted, salaryPayDay)) {
        if (cyclesEqual(persisted, containing)) return persisted;

        final next = nextCycleAfter(containing, salaryPayDay);
        if (cyclesEqual(persisted, next)) return persisted;

        final previous = previousAnchoredCycle(containing, salaryPayDay);
        if (persistedHasUnpaidWorkers && cyclesEqual(persisted, previous)) {
          return persisted;
        }
      }
    }

    return containing;
  }

  // ---------------------------------------------------------------------
  // State machine (requirement #10)
  // ---------------------------------------------------------------------

  /// True when [now] falls within the reminder window that starts exactly
  /// 3 days before the due date and runs through the due day (#4).
  static bool isReminderWindow({
    required DateTime now,
    required DateTime dueDate,
  }) {
    final today = normalize(now);
    final due = normalize(dueDate);
    return !today.isBefore(
          due.subtract(const Duration(days: reminderLeadDays)),
        ) &&
        !today.isAfter(due);
  }

  /// True once the due date has passed. There is deliberately **no** expiry:
  /// overdue stays true until the workers are actually paid (#5). The old
  /// "disappears after ~7 days" behaviour is removed for good.
  static bool isOverdue({required DateTime now, required DateTime dueDate}) =>
      normalize(now).isAfter(normalize(dueDate));

  static bool isDueToday({required DateTime now, required DateTime dueDate}) =>
      isSameCalendarDay(now, dueDate);

  static PayrollCycleState stateOf({
    required DateTime now,
    required PayrollPeriod cycle,
    required bool hasUnpaidWorkers,
  }) {
    final due = dueDateOf(cycle);
    if (hasUnpaidWorkers && isOverdue(now: now, dueDate: due)) {
      return PayrollCycleState.overdue;
    }
    if (isDueToday(now: now, dueDate: due)) return PayrollCycleState.due;
    if (hasUnpaidWorkers && isReminderWindow(now: now, dueDate: due)) {
      return PayrollCycleState.reminder;
    }
    if (normalize(now).isBefore(due)) return PayrollCycleState.upcoming;
    return PayrollCycleState.settled;
  }

  /// The ONE validation shared by Pay All, Process Payroll and every other
  /// action that creates/completes payment for a cycle (#2, #3, #8).
  ///
  /// Payment is blocked only while today is strictly before the cycle's due
  /// date. On the Pay Day itself, while overdue, and for historical/previous
  /// overdue cycles payment is allowed. A future cycle can never be processed
  /// early — HR must first change the Pay Day anchor instead.
  static PayrollProcessCheck canProcessPayment({
    required PayrollPeriod cycle,
    DateTime? now,
  }) {
    final today = normalize(now ?? DateTime.now());
    final due = dueDateOf(cycle);
    return PayrollProcessCheck(
      allowed: !today.isBefore(due),
      dueDate: due,
    );
  }

  // ---------------------------------------------------------------------
  // Outstanding previous cycles (requirements #5 & #6)
  // ---------------------------------------------------------------------

  /// Previous cycles (ended before the active cycle started) that still hold
  /// unpaid, payable workers. These coexist with the new active cycle and keep
  /// their original period/dates until they are fully resolved.
  static List<PayrollPeriod> getOutstandingPreviousCycles({
    required List<Map<String, dynamic>> workersList,
    required List<Map<String, dynamic>> rawPayrollDocs,
    required PayrollPeriod activeCycle,
    String? companyCurrency,
    bool allowUndatedRecords = false,
    List<PayrollPeriod> extraCandidates = const [],
  }) {
    final activeStart = normalize(activeCycle.start);
    final periods = <String, PayrollPeriod>{};

    void consider(DateTime start, DateTime end) {
      final s = normalize(start);
      final e = normalize(end);
      if (!s.isBefore(e)) return;
      if (!e.isBefore(activeStart)) return;
      periods[PayrollService.periodKeyPair(s, e)] = PayrollPeriod(
        start: s,
        end: e,
      );
    }

    for (final candidate in extraCandidates) {
      consider(candidate.start, candidate.end);
    }

    for (final record in rawPayrollDocs) {
      final start = AppDateUtils.dateFromValue(record['payPeriodStart']);
      final end = AppDateUtils.dateFromValue(record['payPeriodEnd']);
      if (start == null || end == null) continue;
      consider(start, end);
    }

    final outstanding = <PayrollPeriod>[];
    for (final period in periods.values) {
      final hasUnpaid = PayrollService.unpaidWorkersForPeriod(
        workersList,
        rawPayrollDocs,
        month: DateTime(period.end.year, period.end.month, 1),
        allowUndatedRecords: allowUndatedRecords,
        companyCurrency: companyCurrency,
        periodStart: period.start,
        periodEnd: period.end,
      ).any(
        (worker) => PayrollService.hasPayableSalary(
          worker,
          companyCurrency: companyCurrency,
        ),
      );
      if (hasUnpaid) outstanding.add(period);
    }

    // Most recently ended overdue cycle first.
    outstanding.sort((a, b) => b.end.compareTo(a.end));
    return outstanding;
  }
}
