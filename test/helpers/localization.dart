import 'dart:ui' show Locale;

import 'package:easy_localization/easy_localization.dart';
import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> initLocalization(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.runAsync(() async {
    await EasyLocalization.ensureInitialized();
    final loader = RootBundleAssetLoader();
    final data = await loader.load('assets/translations', const Locale('en'));
    if (data != null) {
      Localization.load(const Locale('en'), translations: Translations(data));
    }
  });
}
