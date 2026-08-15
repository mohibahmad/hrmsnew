import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/payroll_service.dart';

String _d(DateTime dt) => dt.toIso8601String().substring(0, 10);

void main() {
  group('PayrollService pay-day cycle logic', () {
    const payDay = 3;

    test('nextPayDayPeriod advances exactly one cycle with no +1 day',
        () {
      var p = PayrollPeriod(
        start: DateTime(2026, 7, 3),
        end: DateTime(2026, 8, 3),
      );
      p = PayrollService.nextPayDayPeriod(p, payDay);
      expect(_d(p.start), '2026-08-03');
      expect(_d(p.end), '2026-09-03');

      p = PayrollService.nextPayDayPeriod(p, payDay);
      expect(_d(p.start), '2026-09-03');
      expect(_d(p.end), '2026-10-03');
    });

    test('payDayPeriodContaining returns active period when after pay day',
        () {
      final p = PayrollService.payDayPeriodContaining(
        DateTime(2026, 7, 10),
        payDay,
      );
      expect(_d(p.start), '2026-07-03');
      expect(_d(p.end), '2026-08-03');
    });

    test('payDayPeriodContaining returns active period when before pay day',
        () {
      final p = PayrollService.payDayPeriodContaining(
        DateTime(2026, 7, 1),
        payDay,
      );
      expect(_d(p.start), '2026-06-03');
      expect(_d(p.end), '2026-07-03');
    });

    test('payDayPeriodContaining on the pay day starts current-month period',
        () {
      final p = PayrollService.payDayPeriodContaining(
        DateTime(2026, 8, 3),
        payDay,
      );
      expect(_d(p.start), '2026-08-03');
      expect(_d(p.end), '2026-09-03');
    });
  });
}
