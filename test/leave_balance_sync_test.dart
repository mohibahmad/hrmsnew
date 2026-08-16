import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/time_off_service.dart';

// Regression test for the Attendance-edit leave-balance double-restoration bug.
//
// Scenario: a worker has 1 Sick Leave day that is already assigned (available
// should be 0). After editing that attendance and unselecting Sick Leave, the
// available balance must restore to exactly 1 — not 2.
//
// Also covers removing an Attendance-created leave from Time Off when its Time
// Off document is already missing: the reconcile must not recreate the date on
// reopen and must restore the leave balance exactly once.
void main() {
  final today = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  final tomorrow = today.add(const Duration(days: 1));
  final todayKey =
      '${today.year.toString().padLeft(4, '0')}-'
      '${today.month.toString().padLeft(2, '0')}-'
      '${today.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> makeWorker() => {
    'workerId': 'olivia',
    'id': 'olivia',
    'name': 'Olivia',
    'email': 'olivia@example.com',
    'sickLeaves': 1, // total Sick Leave = 1
    'availableSickLeaves': 0,
    'sickLeavesUsed': 1,
    'annualLeaves': 15,
    'availableAnnualLeaves': 15,
    'annualLeavesUsed': 0,
    'casualLeaves': 5,
    'availableCasualLeaves': 5,
    'casualLeavesUsed': 0,
    'medicalLeaves': 1,
    'availableMedicalLeaves': 1,
    'medicalLeavesUsed': 0,
    'leaveBalances': <String, dynamic>{
      'annualLeave': 15,
      'sickLeave': 0,
      'casualLeave': 5,
      'medicalLeave': 1,
    },
  };

  Map<String, dynamic> sickRecord({
    required String id,
    required List<DateTime> dates,
  }) => {
    'id': id,
    'workerId': 'olivia',
    'name': 'Olivia',
    'email': 'olivia@example.com',
    'action': 'Sick Leave',
    'type': 'Sick Leave',
    'selectedDates': dates,
    'startDate': todayKey,
    'endDate': todayKey,
    'requestedDays': dates.length,
    'status': 'Approved',
    'isPaidLeave': true,
    'source': 'attendance',
  };

  Map<String, dynamic> attendanceLeave({
    required String id,
    String? timeOffId,
    String status = 'Leave',
    String source = 'manual',
  }) => {
    'id': id,
    'workerId': 'olivia',
    'name': 'Olivia',
    'email': 'olivia@example.com',
    'attendanceDate': todayKey,
    'status': status,
    'type': 'Sick Leave',
    'desc': 'Attendance leave',
    'source': source,
    if (timeOffId != null) 'timeOffId': timeOffId,
  };

  // The reconcile that runs when the Time Off doc is missing: a "fallback"
  // record (as passed from the Time Off screen) marked Cancelled, balances
  // recomputed against `currentTimeOffRecords` which no longer contains the
  // missing document.
  Map<String, dynamic> reconcileBalances({
    required List<Map<String, dynamic>> currentTimeOffRecords,
    required Map<String, dynamic> fallbackRecord,
  }) {
    final recordsAfterCancellation = currentTimeOffRecords
        .where((r) => r['id']?.toString() != fallbackRecord['id'])
        .toList()
      ..add({...fallbackRecord, 'status': 'Cancelled'});
    return TimeOffService.canonicalWorkerLeaveFields(
      makeWorker(),
      remainingBalances:
          TimeOffService.remainingBalancesFromAssignedRecords(
        makeWorker(),
        recordsAfterCancellation,
      ),
    );
  }

  test('before unselect: the 1 assigned day leaves available at 0', () {
    final records = [
      sickRecord(id: 't_sick_1', dates: [today]),
    ];
    expect(
      TimeOffService.remainingBalancesFromAssignedRecords(
        makeWorker(),
        records,
      )['sickLeave'],
      0,
    );
  });

  test('after unselect: available restores to exactly 1, not 2', () {
    final records = [
      sickRecord(id: 't_sick_1', dates: [today]),
    ];

    // 1) What the edit dialog advertises for Sick Leave while editing a Sick
    //    Leave attendance (fixed exclusion of the current record). The old
    //    blind "+1" could advertise 2 when the local records lacked the day.
    final advertisedAfterUnselect = TimeOffService.remainingForType(
      makeWorker(),
      <Map<String, dynamic>>[], // stale local list used by the dialog
      'Sick Leave',
      excludingRecordId: 't_sick_1',
    );
    expect(advertisedAfterUnselect, 1);

    // 2) What is actually written when unselecting (single restore).
    final projected = records
        .where((r) => (r['id'] ?? '').toString() != 't_sick_1')
        .toList();
    final written = TimeOffService.canonicalWorkerLeaveFields(
      makeWorker(),
      remainingBalances: TimeOffService.remainingBalancesFromAssignedRecords(
        makeWorker(),
        projected,
      ),
    );
    expect(written['availableSickLeaves'], 1);
    expect(written['sickLeaves'], 1);
    expect(written['sickLeavesUsed'], 0);
    final leaveBalances = written['leaveBalances'] as Map;
    expect(leaveBalances['sickLeave'], 1);
  });

  test('a second active record still owning the day prevents a restore', () {
    final records = [
      sickRecord(id: 't_sick_1', dates: [today]),
      sickRecord(id: 't_sick_2', dates: [today, tomorrow]),
    ];
    final projected = records
        .where((r) => (r['id'] ?? '').toString() != 't_sick_1')
        .toList();
    final written = TimeOffService.canonicalWorkerLeaveFields(
      makeWorker(),
      remainingBalances: TimeOffService.remainingBalancesFromAssignedRecords(
        makeWorker(),
        projected,
      ),
    );
    expect(written['availableSickLeaves'], 0);
  });

  test('a leftover Attendance leave is re-synthesized when the doc is missing',
      () {
    final attendanceRecords = [
      attendanceLeave(
        id: 'att_olivia_$todayKey',
        timeOffId: 'to_missing',
      ),
    ];
    final combined = TimeOffService.combineTimeOffAndAttendanceRecords(
      timeOffRecords: const [],
      attendanceRecords: attendanceRecords,
    );
    expect(combined, hasLength(1));
    final formattedDate =
        '${today.day.toString().padLeft(2, '0')}/'
        '${today.month.toString().padLeft(2, '0')}/${today.year}';
    expect(
      (combined.single['id'] ?? '').toString(),
      'att_leave_att_olivia_${todayKey}_$formattedDate',
    );
    expect(TimeOffService.selectedDatesForRecord(combined.single), [today]);
  });

  test('clearing the Attendance leave stops the date being re-created', () {
    // This mirrors what `cancelTimeOffWithWorkerBalance` writes to the
    // attendance record when the linked Time Off doc is already missing:
    // status reset to 'Present' and the stale `timeOffId` cleared.
    final cleared = attendanceLeave(
      id: 'att_olivia_$todayKey',
      timeOffId: 's_missing',
    );
    cleared['status'] = 'Present';
    cleared.remove('type');
    cleared.remove('desc');
    cleared.remove('timeOffId');

    final combined = TimeOffService.combineTimeOffAndAttendanceRecords(
      timeOffRecords: const [],
      attendanceRecords: [cleared],
    );
    expect(combined, isEmpty);
  });

  test('missing doc: balance restores to exactly 1 (not 2) and stays so', () {
    final fallback = attendanceLeave(
      id: 'att_olivia_$todayKey',
      timeOffId: 's_missing',
    );

    final balances = reconcileBalances(
      currentTimeOffRecords: const [],
      fallbackRecord: fallback,
    );
    expect(balances['availableSickLeaves'], 1); // restored
    expect(balances['sickLeavesUsed'], 0);
    expect((balances['leaveBalances'] as Map)['sickLeave'], 1);

    // Running the reconcile again must not double-restore.
    final rerun = reconcileBalances(
      currentTimeOffRecords: const [],
      fallbackRecord: fallback,
    );
    expect(rerun['availableSickLeaves'], 1);
    expect(rerun['sickLeavesUsed'], 0);
  });
}
