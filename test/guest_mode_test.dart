import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/dummy_data.dart';
import 'package:hrms/services/preferences_service.dart';
import 'package:hrms/utils/date_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'guest mode is available synchronously after preferences initialize',
    () async {
      SharedPreferences.setMockInitialValues({'is_guest': true});

      await PreferencesService.initFromPrefs();

      expect(PreferencesService.cachedIsGuest, isTrue);

      await PreferencesService.setGuest(false);
      expect(PreferencesService.cachedIsGuest, isFalse);
    },
  );

  test('guest reset restores every source dummy-data collection', () async {
    await DummyData.resetToDefaults();
    final expectedCounts = {
      'workers': DummyData.workers.length,
      'expenses': DummyData.expenses.length,
      'attendance': DummyData.attendance.length,
      'payroll': DummyData.payroll.length,
      'timeoff': DummyData.timeoff.length,
      'holidays': DummyData.holidays.values.expand((items) => items).length,
      'notifications': DummyData.notifications.length,
      'assets': DummyData.assets.length,
    };

    expect(expectedCounts.values, everyElement(greaterThan(0)));

    DummyData.workers.clear();
    DummyData.expenses.clear();
    DummyData.attendance.clear();
    DummyData.payroll.clear();
    DummyData.timeoff.clear();
    DummyData.holidays.clear();
    DummyData.notifications.clear();
    DummyData.assets.clear();

    await DummyData.resetToDefaults();

    expect(DummyData.workers.length, expectedCounts['workers']);
    expect(DummyData.expenses.length, expectedCounts['expenses']);
    expect(DummyData.attendance.length, expectedCounts['attendance']);
    expect(DummyData.payroll.length, expectedCounts['payroll']);
    expect(DummyData.timeoff.length, expectedCounts['timeoff']);
    expect(
      DummyData.holidays.values.expand((items) => items).length,
      expectedCounts['holidays'],
    );
    expect(DummyData.notifications.length, expectedCounts['notifications']);
    expect(DummyData.assets.length, expectedCounts['assets']);
  });

  test(
    'guest attendance populates every status tab with recent data',
    () async {
      await DummyData.resetToDefaults();
      final now = DateTime.now();
      final todayRecords = DummyData.attendance.where((record) {
        final date = AppDateUtils.attendanceRecordDate(record);
        return date != null &&
            date.year == now.year &&
            date.month == now.month &&
            date.day == now.day;
      }).toList();

      expect(DummyData.attendance.length, DummyData.workers.length * 7);
      expect(
        DummyData.attendance,
        everyElement(containsPair('excludeFromLeaveChart', true)),
      );
      expect(todayRecords.length, DummyData.workers.length);
      expect(
        todayRecords.map((record) => record['workerId']).toSet().length,
        DummyData.workers.length,
      );
      expect(
        todayRecords.where((record) => record['status'] == 'Present'),
        isNotEmpty,
      );
      expect(
        todayRecords.where((record) => record['status'] == 'Absent'),
        isNotEmpty,
      );
      expect(
        todayRecords.where((record) => record['status'] == 'Leave'),
        isNotEmpty,
      );
    },
  );
}
