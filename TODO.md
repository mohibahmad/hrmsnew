# TODO - Fix Easy Localization Warnings in pdf_generation_test.dart

## Problem
`[🌎 Easy Localization] [WARNING] Localization key [...] not found` warnings appear when running tests. Root cause: `test/pdf_generation_test.dart` calls `WorkerProfileService.generateWorkerProfile()` via plain `test()` without initializing EasyLocalization, so the global `Localization.instance` singleton has no loaded translations and every `.tr()` call logs a warning (all keys DO exist in all 5 locale files).

## Steps
- [x] 1. Update `test/pdf_generation_test.dart`:
  - Convert plain `test()` cases to `testWidgets` and pump an `EasyLocalization` widget with `startLocale: Locale('en')` and `fallbackLocale: Locale('en')` so the singleton is populated.
  - Keep the PDF assertion logic unchanged.
- [ ] 2. Run `flutter test test/pdf_generation_test.dart` to verify tests pass without warnings.
- [ ] 3. Run the full suite of related tests (`worker_validation_test.dart`, `worker_identity_test.dart`, `leave_policy_service_test.dart`) to confirm no regressions.

