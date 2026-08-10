import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/time_off_service.dart';
import 'package:hrms/utils/time_off_unsaved_changes.dart';

void main() {
  test('new form stays clean when nothing has been changed', () {
    expect(
      hasUnsavedTimeOffChanges(
        hasSelectedDates: false,
        hasNotes: false,
        isEditing: false,
        typeChanged: false,
        datesChanged: false,
      ),
      isFalse,
    );
  });

  test('reopened edit form stays clean without user changes', () {
    expect(
      hasUnsavedTimeOffChanges(
        hasSelectedDates: false,
        hasNotes: false,
        isEditing: true,
        typeChanged: false,
        datesChanged: false,
      ),
      isFalse,
    );
  });

  test(
    'new form becomes dirty when the user selects dates or changes type',
    () {
      expect(
        hasUnsavedTimeOffChanges(
          hasSelectedDates: true,
          hasNotes: false,
          isEditing: false,
          typeChanged: false,
          datesChanged: false,
        ),
        isTrue,
      );

      expect(
        hasUnsavedTimeOffChanges(
          hasSelectedDates: false,
          hasNotes: false,
          isEditing: false,
          typeChanged: true,
          datesChanged: false,
        ),
        isTrue,
      );
    },
  );

  test(
    'edit form becomes dirty when the selected dates differ from the original',
    () {
      expect(
        hasUnsavedTimeOffChanges(
          hasSelectedDates: false,
          hasNotes: true,
          isEditing: true,
          typeChanged: false,
          datesChanged: true,
        ),
        isTrue,
      );
    },
  );

  test('edit form becomes dirty when its leave type changes', () {
    expect(
      hasUnsavedTimeOffChanges(
        hasSelectedDates: false,
        hasNotes: false,
        isEditing: true,
        typeChanged: true,
        datesChanged: false,
      ),
      isTrue,
    );
  });

  test('future and today time off can be edited, past time off cannot', () {
    final today = DateTime(2026, 8, 10);

    expect(
      TimeOffService.isEditableRecord({
        'status': 'Approved',
        'selectedDates': [DateTime(2026, 8, 10), DateTime(2026, 8, 11)],
      }, referenceDate: today),
      isTrue,
    );
    expect(
      TimeOffService.isEditableRecord({
        'status': 'Approved',
        'selectedDates': [DateTime(2026, 8, 9), DateTime(2026, 8, 11)],
      }, referenceDate: today),
      isFalse,
    );
  });

  test('cancelled time off cannot be edited even when dates are future', () {
    expect(
      TimeOffService.isEditableRecord({
        'status': 'Cancelled',
        'selectedDates': [DateTime(2026, 8, 11)],
      }, referenceDate: DateTime(2026, 8, 10)),
      isFalse,
    );
  });

  test('one selected medical leave day previews balance 4 as 3', () {
    expect(projectedTimeOffBalance(availableDays: 4, requestedDays: 1), 3);
  });

  test('fully allocated edit record has zero days available for new dates', () {
    expect(projectedTimeOffBalance(availableDays: 21, requestedDays: 21), 0);
  });

  test('all leave totals stay separate from available balances', () {
    final worker = {
      'annualLeaves': 14,
      'availableAnnualLeaves': 12,
      'sickLeaves': 8,
      'availableSickLeaves': 7,
      'casualLeaves': 6,
      'availableCasualLeaves': 5,
      'medicalLeaves': 4,
      'availableMedicalLeaves': 3,
    };
    const expected = {
      'Annual Leave': (total: 14, available: 12),
      'Sick Leave': (total: 8, available: 7),
      'Casual Leave': (total: 6, available: 5),
      'Medical Leave': (total: 4, available: 3),
    };

    for (final entry in expected.entries) {
      expect(
        TimeOffService.configuredLimitForType(worker, entry.key),
        entry.value.total,
      );
      expect(
        TimeOffService.getLeaveBalance(worker, entry.key),
        entry.value.available,
      );
    }
  });
}
