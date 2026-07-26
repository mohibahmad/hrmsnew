# HRMS QA Handoff Report

**Date:** 26 July 2026  
**Test environment:** macOS 26.5.2, Flutter 3.41.9, Dart 3.11.5  
**Available targets:** macOS desktop and Chrome web

## 1. Current Status

The macOS debug build compiles successfully. Backend OTP unit tests pass. The
Flutter test suite currently has one failing test, and static analysis reports
warnings and informational findings. Manual end-to-end testing must still be
completed before release sign-off.

| Check | Result |
|---|---|
| macOS debug build | PASS |
| Firebase Functions OTP tests | PASS — 4/4 |
| Flutter automated tests | FAIL — 46 passed, 1 failed |
| Flutter static analysis | NEEDS REVIEW — 179 warnings/info |
| Manual smoke test | NOT YET RECORDED |
| Manual end-to-end test | NOT YET RECORDED |

## 2. Product Logic Summary

The worker record is the central entity.

```text
Worker
 ├─ Attendance
 ├─ Time Off ── updates leave balance and attendance state
 ├─ Payroll ─── reads attendance and creates a salary expense + PDF invoice
 ├─ Documents
 └─ Assets

All modules ──> Dashboard totals, charts, holidays and notifications
```

There are two data modes:

- Authenticated user: data is stored in Firebase under
  `hrms_user/{uid}/...` subcollections.
- Guest user: sample/local data is loaded from `DummyData` and
  `SharedPreferences`; many write actions are restricted.

Free authenticated users are limited to two entries in selected modules.
Premium status removes that limit.

## 3. How to Run

```bash
cd /Users/macbookpro/hrms
flutter pub get
flutter run -d macos
```

Chrome alternative:

```bash
flutter run -d chrome
```

Use `r` for hot reload, `R` for restart, and `q` to stop the app.

## 4. Test Data

Use a dedicated test account, not a real employee account.

```text
Admin name: QA Test Admin
Email: <tester>+hrms-qa@gmail.com
Password: Test@123456

Worker name: QA Worker One
Worker email: <tester>+worker1@gmail.com
Phone: +92 300 0000001
National ID: QA-0000001
Position: QA Engineer
Salary: 100000 PKR, Monthly
Annual leave: 12
```

Every additional test worker must have a unique email, phone and national ID.

## 5. Manual Smoke Test

Record each item as PASS or FAIL and attach a screenshot for every failure.

| ID | Test | Expected result | Status |
|---|---|---|---|
| SM-01 | Launch application | Splash screen opens without crash | NOT RUN |
| SM-02 | Continue as Guest | Demo dashboard loads | NOT RUN |
| SM-03 | Open each sidebar item | Every screen opens without blank/error state | NOT RUN |
| SM-04 | Open notification panel | Panel opens and closes correctly | NOT RUN |
| SM-05 | Open profile | Profile screen loads | NOT RUN |
| SM-06 | Change language | Visible labels change and remain after restart | NOT RUN |
| SM-07 | Logout/back to login | Session ends and Login screen opens | NOT RUN |

## 6. End-to-End Functional Test

### Authentication

| ID | Test | Expected result | Status |
|---|---|---|---|
| AU-01 | Create email/password account | Account and Firestore profile are created | NOT RUN |
| AU-02 | Log out and log in again | Same account and data load | NOT RUN |
| AU-03 | Incorrect password | Clear error; no login | NOT RUN |
| AU-04 | Forgot password OTP flow | OTP verifies and new password works | NOT RUN |
| AU-05 | Google login | Account opens or cancellation exits safely | NOT RUN |
| AU-06 | Deleted account login | Login is blocked | NOT RUN |

### Worker

| ID | Test | Expected result | Status |
|---|---|---|---|
| WK-01 | Add valid worker | Worker appears in list and dashboard count increases | NOT RUN |
| WK-02 | Add duplicate email/name/ID | Save is blocked with useful error | NOT RUN |
| WK-03 | Edit worker salary/profile | Updated values appear everywhere | NOT RUN |
| WK-04 | Upload ID front/back and CV | Files upload and preview correctly | NOT RUN |
| WK-05 | CSV bulk import | Valid rows import; invalid/duplicate rows are reported | NOT RUN |
| WK-06 | Delete worker | Worker is removed after confirmation | NOT RUN |

### Attendance and Time Off

| ID | Test | Expected result | Status |
|---|---|---|---|
| AT-01 | Mark worker Present | Attendance list and dashboard update | NOT RUN |
| AT-02 | Mark worker Absent | Absent count updates | NOT RUN |
| AT-03 | Edit same-day attendance | Existing record updates without duplicate | NOT RUN |
| TO-01 | Assign approved leave | Time-off record is created | NOT RUN |
| TO-02 | Check leave balance | Requested days are deducted once | NOT RUN |
| TO-03 | Attendance on leave date | Worker is shown/handled as On Leave | NOT RUN |
| TO-04 | Request more than balance | Save is blocked | NOT RUN |

### Payroll and Expenses

| ID | Test | Expected result | Status |
|---|---|---|---|
| PY-01 | Open worker payroll | Current salary and attendance counts load | NOT RUN |
| PY-02 | Add deductions/overtime | Net salary calculation is correct | NOT RUN |
| PY-03 | Save payroll | Payroll is marked Paid | NOT RUN |
| PY-04 | Invoice generation | PDF preview/download works | NOT RUN |
| PY-05 | Salary expense side effect | One Salary expense is created with net amount | NOT RUN |
| PY-06 | Pay All | Eligible workers process without duplicates | NOT RUN |
| EX-01 | Add/edit/delete manual expense | List, totals and dashboard update | NOT RUN |

### Assets, Holidays, Documents and Notifications

| ID | Test | Expected result | Status |
|---|---|---|---|
| AS-01 | Add/edit/delete asset | Asset list updates correctly | NOT RUN |
| HO-01 | Set company work days | Selection persists after restart | NOT RUN |
| HO-02 | Add enabled holiday | Holiday appears in list and dashboard | NOT RUN |
| DO-01 | Replace worker document | New document uploads and previews | NOT RUN |
| NO-01 | Create records in each module | Correct notifications are generated | NOT RUN |
| NO-02 | Click each notification | Correct destination screen opens | NOT RUN |

### Subscription and Limits

| ID | Test | Expected result | Status |
|---|---|---|---|
| SU-01 | Free user adds first two entries | Entries are allowed | NOT RUN |
| SU-02 | Free user attempts third entry | Upgrade dialog opens | NOT RUN |
| SU-03 | Complete subscription | Payment must be verified before premium access | NOT RUN |
| SU-04 | Restart premium account | Premium status remains correct | NOT RUN |

## 7. Current Findings Requiring Senior Review

### High — Premium access is enabled without payment verification

The Continue button in `lib/screens/pricing_screen.dart` directly sets local and
Firestore `isPremium` to `true`. No payment provider, receipt validation or
server-side entitlement check is present in this flow. If this is intended for
production, premium can currently be activated without payment.

### High — Payroll notification appears to route to Expenses

In `lib/screens/home_screen.dart`, `payroll_added` sets `_selectedIndex = 3`.
Sidebar index 3 is Expenses; Payroll is Workforce index 2, sub-index 1. This
must be manually reproduced and the route corrected if confirmed.

### Medium — One Flutter test is failing

`test/dummy_data_persistence_test.dart` fails the test:

```text
load restores empty records and saved holidays exactly
```

Expected guest time-off data to be empty, but default dummy time-off records
remain. Guest persistence/version handling needs investigation.

### Medium — Static analysis has 179 findings

The list includes unused imports/elements, deprecated file-picker APIs,
asynchronous `BuildContext` usage, dead code and style warnings. These are not
all release blockers, but async-context and deprecated-API findings should be
triaged.

### Medium — Firebase security configuration must be confirmed

The repository contains Firestore indexes but does not contain/reference a
Firestore rules file or Storage rules file. Confirm that secure per-user rules
are deployed in the Firebase project before production release.

### Medium — No integration test suite is present

Unit/widget tests exist, but no `integration_test` suite currently verifies
the complete Worker → Attendance → Time Off → Payroll → Expense workflow.

## 8. Evidence to Give With the Handoff

Create a folder named `HRMS_QA_EVIDENCE` containing:

1. One screen recording of the full happy path.
2. Screenshots for every FAIL result.
3. Terminal output of `flutter test`.
4. Terminal output of `npm run check`.
5. Terminal output of `flutter analyze`.
6. This completed report with every `NOT RUN` changed to PASS or FAIL.
7. Exact test account email and Firebase environment used.

For a failed test, report:

```text
Bug ID:
Title:
Module:
Environment:
Preconditions:
Steps to reproduce:
Expected:
Actual:
Frequency: Always / Sometimes / Once
Severity: Critical / High / Medium / Low
Screenshot/video:
Console error:
```

## 9. Commands Used for Verification

```bash
cd /Users/macbookpro/hrms
flutter build macos --debug
flutter test
flutter analyze

cd /Users/macbookpro/hrms/functions
npm run check
```

## 10. Recommended Sign-Off Rule

Do not mark the app release-ready until:

- all High findings are fixed or formally accepted;
- the Flutter test suite is green;
- authentication and complete payroll flow pass manually;
- Firebase Auth, Firestore, Storage and Cloud Functions are tested in the
  intended environment;
- the completed evidence pack is reviewed by the senior.

