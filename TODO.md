# Fix Settings Screen Error

## Task
Remove the compile error in `lib/screens/settings_screen.dart`:
- `error: The method '_LeavePolicyListDialog' isn't defined` (line 418)
- `warning: Unused import: '../services/leave_policy_service.dart'` (line 10)

## Decision
Keep the Leave Policy feature in the settings screen, but as a **dummy** (static sample data, no Firestore integration).

## Steps
- [ ] 1. Remove the unused import `../services/leave_policy_service.dart`.
- [ ] 2. Update `_showLeavePolicyListDialog()` to show a new dummy dialog widget.
- [ ] 3. Add a `_DummyLeavePolicyDialog` widget with static sample policies and "coming soon" placeholder actions.
- [ ] 4. Run `flutter analyze lib/screens/settings_screen.dart` to verify no errors/warnings.

