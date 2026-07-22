import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/dummy_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late List<Map<String, dynamic>> originalTimeOff;
  late Map<String, List<Map<String, dynamic>>> originalHolidays;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    originalTimeOff = (jsonDecode(jsonEncode(DummyData.timeoff)) as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    originalHolidays = (jsonDecode(jsonEncode(DummyData.holidays)) as Map).map(
      (key, value) => MapEntry(
        key.toString(),
        (value as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(),
      ),
    );
  });

  tearDown(() {
    DummyData.timeoff
      ..clear()
      ..addAll(originalTimeOff);
    DummyData.holidays
      ..clear()
      ..addAll(originalHolidays);
  });

  test('load restores empty records and saved holidays exactly', () async {
    SharedPreferences.setMockInitialValues({
      'dummy_timeoff': '[]',
      'dummy_holidays': jsonEncode({
        'July': [
          {'day': 22, 'name': 'QA Day', 'isEnabled': true},
        ],
      }),
    });

    await DummyData.loadFromPrefs();

    expect(DummyData.timeoff, isEmpty);
    expect(DummyData.holidays.keys, ['July']);
    expect(DummyData.holidays['July']!.single['name'], 'QA Day');
  });

  test('save includes holidays in local persistence', () async {
    DummyData.holidays
      ..clear()
      ..addAll({
        'August': [
          {'day': 14, 'name': 'Company Day', 'isEnabled': false},
        ],
      });

    await DummyData.saveToPrefs();

    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('dummy_holidays')!) as Map;
    expect((saved['August'] as List).single['name'], 'Company Day');
  });
}
