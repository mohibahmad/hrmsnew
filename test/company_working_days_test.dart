import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hrms/services/preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('company working days default to Monday through Friday', () async {
    final days = await PreferencesService.getCompanyWorkingDays();

    expect(days, {
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
    });
  });

  test('selected company working days persist for guest users', () async {
    await PreferencesService.setCompanyWorkingDays({
      DateTime.monday,
      DateTime.friday,
      DateTime.sunday,
    });

    final days = await PreferencesService.getCompanyWorkingDays();
    expect(days, {DateTime.monday, DateTime.friday, DateTime.sunday});
  });

  test('at least one company working day is required', () async {
    expect(
      () => PreferencesService.setCompanyWorkingDays(const <int>{}),
      throwsArgumentError,
    );
  });
}
