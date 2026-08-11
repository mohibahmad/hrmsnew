import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/time_off_service.dart';
import 'package:hrms/utils/time_off_unsaved_changes.dart';
import 'package:hrms/utils/time_off_draft.dart';

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

  test('editing restores allocation only for the record own leave type', () {
    final worker = {
      'annualLeaves': 14,
      'availableAnnualLeaves': 0,
      'sickLeaves': 8,
      'availableSickLeaves': 8,
    };
    final editingRecord = {
      'action': 'Annual Leave',
      'status': 'Approved',
      'startDate': DateTime(2026, 8, 10),
      'endDate': DateTime(2026, 8, 23),
    };

    expect(
      TimeOffService.availableBalanceForEditingRecord(
        worker,
        'Annual Leave',
        editingRecord,
      ),
      14,
    );
    expect(
      TimeOffService.availableBalanceForEditingRecord(
        worker,
        'Sick Leave',
        editingRecord,
      ),
      8,
    );
  });

  test('dropdown leave type loads its own assigned Firebase record', () {
    final worker = {'id': 'worker-1', 'email': 'worker@example.com'};
    final records = [
      {
        'id': 'annual-1',
        'workerId': 'worker-1',
        'action': 'Annual Leave',
        'status': 'Approved',
        'selectedDates': [DateTime(2026, 8, 20)],
      },
      {
        'id': 'sick-1',
        'workerId': 'worker-1',
        'action': 'Sick Leave',
        'status': 'Approved',
        'selectedDates': [DateTime(2026, 8, 21)],
      },
    ];

    final annual = TimeOffService.recordForWorkerLeaveType(
      worker,
      records,
      'Annual Leave',
      referenceDate: DateTime(2026, 8, 10),
    );
    final sick = TimeOffService.recordForWorkerLeaveType(
      worker,
      records,
      'Sick Leave',
      referenceDate: DateTime(2026, 8, 10),
    );

    expect(annual?['id'], 'annual-1');
    expect(TimeOffService.leaveType(annual!), 'Annual Leave');
    expect(sick?['id'], 'sick-1');
    expect(TimeOffService.leaveType(sick!), 'Sick Leave');
    expect(TimeOffService.recordHasLeaveType(annual, 'Sick Leave'), isFalse);
    expect(TimeOffService.recordHasLeaveType(sick, 'Sick Leave'), isTrue);
  });

  test('summary includes assigned days from every record of the type', () {
    final worker = {'annualLeaves': 22, 'availableAnnualLeaves': 0};
    final openAnnualRecord = {
      'action': 'Annual Leave',
      'selectedDates': List.generate(
        21,
        (index) => DateTime(2026, 9, index + 1),
      ),
    };

    final assigned = TimeOffService.projectedAssignedDaysForEditingRecord(
      worker,
      'Annual Leave',
      openAnnualRecord,
      21,
    );

    expect(assigned, 22);
    expect(22 - assigned, 0);
  });

  test('assigned leave dates stay separated by their persisted type', () {
    final worker = {'id': 'worker-1'};
    final records = [
      {
        'id': 'annual-1',
        'workerId': 'worker-1',
        'action': 'Annual Leave',
        'status': 'Approved',
        'selectedDates': [DateTime(2026, 8, 11), DateTime(2026, 9, 2)],
      },
      {
        'id': 'sick-1',
        'workerId': 'worker-1',
        'action': 'Sick Leave',
        'status': 'Approved',
        'selectedDates': [DateTime(2026, 8, 18)],
      },
    ];

    final dates = TimeOffService.leaveDatesByTypeForWorker(worker, records);

    expect(dates['Annual Leave'], hasLength(2));
    expect(dates['Sick Leave'], hasLength(1));
    expect(dates['Casual Leave'], isEmpty);
    expect(dates['Medical Leave'], isEmpty);
  });

  test('pending dates stay attached to their selected leave type', () {
    final medicalDraft = PendingTimeOffDraft(
      leaveType: 'Medical Leave',
      editingId: null,
      editingRecord: null,
      selectedDates: {DateTime(2026, 8, 12)},
      notes: '',
      typeChanged: false,
      datesChanged: true,
      notesChanged: false,
    );
    final sickDraft = PendingTimeOffDraft(
      leaveType: 'Sick Leave',
      editingId: null,
      editingRecord: null,
      selectedDates: {DateTime(2026, 8, 13)},
      notes: '',
      typeChanged: false,
      datesChanged: true,
      notesChanged: false,
    );

    final drafts = {
      medicalDraft.leaveType: medicalDraft,
      sickDraft.leaveType: sickDraft,
    };

    expect(drafts.values.every((draft) => draft.hasChanges), isTrue);
    expect(drafts['Medical Leave']!.selectedDates, {DateTime(2026, 8, 12)});
    expect(drafts['Sick Leave']!.selectedDates, {DateTime(2026, 8, 13)});
  });
}
