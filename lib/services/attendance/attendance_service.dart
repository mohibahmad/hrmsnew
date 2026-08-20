import 'package:hrms/core/utils/utils.dart';
import 'package:hrms/services/time_off/time_off_service.dart';

class AttendanceService {
  AttendanceService._();

  static const Set<String> _ineligibleStatuses = {
    'inactive',
    'terminated',
    'deleted',
    'archived',
  };

  static bool isEligibleForAttendance(Map<String, dynamic> worker) {
    final status = (worker['status'] ?? 'Active').toString().trim().toLowerCase();
    return !_ineligibleStatuses.contains(status);
  }

  static bool workerExistedOnDate(Map<String, dynamic> worker, DateTime date) {
    final employmentStart = AppDateUtils.dateFromValue(
      worker['joiningDate'] ?? worker['dateOfJoining'],
    );
    if (employmentStart == null) return true;

    final startDay = DateTime(employmentStart.year, employmentStart.month, employmentStart.day);
    final targetDay = DateTime(date.year, date.month, date.day);
    return !targetDay.isBefore(startDay);
  }

  static bool workerExistedOnRecordDate({
    required Map<String, dynamic> worker,
    required Map<String, dynamic> attendanceRecord,
  }) {
    final recordDate = AppDateUtils.attendanceRecordDate(attendanceRecord);
    if (recordDate == null) return true;
    return workerExistedOnDate(worker, recordDate);
  }

  static bool isRecordForDate(Map<String, dynamic> record, DateTime requestedDate) {
    final recordDate = AppDateUtils.attendanceRecordDate(record);
    if (recordDate == null) return false;
    return recordDate.year == requestedDate.year &&
        recordDate.month == requestedDate.month &&
        recordDate.day == requestedDate.day;
  }

  static Map<String, dynamic> applyApprovedTimeOff({
    required Map<String, dynamic> attendanceRecord,
    required Map<String, dynamic> timeOffRecord,
    required String automaticDescription,
  }) {
    final leaveType = TimeOffService.normalizeLeaveType(
      (timeOffRecord['action'] ?? timeOffRecord['type'] ?? 'Leave').toString(),
    );
    final timeOffId = (timeOffRecord['id'] ?? timeOffRecord['timeOffId'] ?? '').toString().trim();

    return {
      ...attendanceRecord,
      'status': 'Leave',
      'type': leaveType,
      'desc': automaticDescription,
      'source': 'auto_leave',
      if (timeOffId.isNotEmpty) 'timeOffId': timeOffId,
    };
  }

  static bool _isNewer(Map<String, dynamic> existing, Map<String, dynamic> candidate) {
    final existingDate = AppDateUtils.recordRevisionDate(existing);
    final candidateDate = AppDateUtils.recordRevisionDate(candidate);

    if (candidateDate != null && existingDate == null) return true;
    if (candidateDate == null && existingDate != null) return false;

    if (candidateDate != null && existingDate != null) {
      final compare = candidateDate.compareTo(existingDate);
      if (compare != 0) return compare > 0;
    }

    return (candidate['id'] ?? '').toString().compareTo(
          (existing['id'] ?? '').toString(),
        ) > 0;
  }

  static String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static List<Map<String, dynamic>> recordsForWorker({
    required Map<String, dynamic> worker,
    required List<Map<String, dynamic>> attendanceRecords,
    bool allowNameFallback = true,
  }) {
    final recordsByDay = <String, Map<String, dynamic>>{};

    for (final record in attendanceRecords) {
      if (!WorkerIdentity.recordsMatch(record, worker, allowName: allowNameFallback)) {
        continue;
      }
      if (!workerExistedOnRecordDate(worker: worker, attendanceRecord: record)) continue;

      final date = AppDateUtils.attendanceRecordDate(record);
      final key = date == null
          ? 'undated:${(record['id'] ?? recordsByDay.length).toString()}'
          : _dateKey(date);

      final existing = recordsByDay[key];
      if (existing == null || _isNewer(existing, record)) {
        recordsByDay[key] = Map<String, dynamic>.from(record);
      }
    }

    final records = recordsByDay.values.toList();
    records.sort((a, b) {
      final aDate = AppDateUtils.attendanceRecordDate(a);
      final bDate = AppDateUtils.attendanceRecordDate(b);

      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;

      final dateCompare = bDate.compareTo(aDate);
      if (dateCompare != 0) return dateCompare;

      if (_isNewer(a, b)) return 1;
      if (_isNewer(b, a)) return -1;
      return 0;
    });

    return records;
  }

  static bool _isNameUnique(Map<String, dynamic> worker, List<Map<String, dynamic>> workersList) {
    final targetName = WorkerIdentity.normalizeName(worker['name']);
    if (targetName.isEmpty) return false;

    var matches = 0;
    for (final item in workersList) {
      if (WorkerIdentity.normalizeName(item['name']) == targetName) {
        matches++;
        if (matches > 1) return false;
      }
    }
    return matches == 1;
  }

  static String _asString(dynamic value) => (value ?? '').toString().trim();

  static dynamic _pick(dynamic primary, dynamic fallback) {
    if (primary == null) return fallback;
    if (primary is String && primary.trim().isEmpty) return fallback;
    return primary;
  }

  static List<Map<String, dynamic>> combineAttendance({
    required List<Map<String, dynamic>> workersList,
    required List<Map<String, dynamic>> rawAttendanceDocs,
  }) {
    if (workersList.isEmpty) return [];

    final combined = <Map<String, dynamic>>[];

    for (var index = 0; index < workersList.length; index++) {
      final worker = workersList[index];
      final workerId = _asString(worker['id'] ?? worker['workerId']);
      final workerEmail = WorkerIdentity.normalizeEmail(worker['email']);
      final workerName = WorkerIdentity.normalizeName(worker['name']);
      final allowName = _isNameUnique(worker, workersList);

      final matchedRecords = recordsForWorker(
        worker: worker,
        attendanceRecords: rawAttendanceDocs,
        allowNameFallback: allowName,
      );
      final matched = matchedRecords.isEmpty ? null : matchedRecords.first;

      if (matched != null) {
        combined.add({
          ...matched,
          'workerId': workerId.isNotEmpty ? workerId : _asString(matched['workerId']),
          'name': _pick(worker['name'], matched['name']),
          'email': _pick(worker['email'], matched['email']),
          'role': _pick(worker['position'] ?? worker['role'], matched['role']),
          'profileImage': _pick(worker['profileImage'], matched['profileImage']),
          'phone': _pick(worker['phone'] ?? worker['contact'], matched['phone'] ?? matched['contact']),
        });
      } else {
        final id = workerId.isNotEmpty
            ? workerId
            : workerEmail.isNotEmpty
            ? workerEmail
            : workerName.isNotEmpty
            ? workerName
            : index.toString();
        combined.add({
          'id': 'norecord_$id',
          'workerId': workerId,
          'name': _pick(worker['name'], 'Worker'),
          'email': worker['email'] ?? '',
          'role': worker['position'] ?? worker['role'] ?? '',
          'attendanceType': worker['type2'] ?? worker['attendanceType'] ?? 'On-Site',
          'workType': worker['type1'] ?? worker['workType'] ?? 'Full Time',
          'profileImage': worker['profileImage'],
          'phone': worker['phone'] ?? worker['contact'] ?? '',
          'createdAt': null,
          'status': '',
        });
      }
    }

    combined.sort((a, b) {
      final aDate = AppDateUtils.attendanceRecordDate(a);
      final bDate = AppDateUtils.attendanceRecordDate(b);

      if (aDate == null && bDate == null) {
        return _asString(a['name']).toLowerCase().compareTo(_asString(b['name']).toLowerCase());
      }
      if (aDate == null) return 1;
      if (bDate == null) return -1;

      final dateCompare = bDate.compareTo(aDate);
      if (dateCompare != 0) return dateCompare;

      return _asString(a['name']).toLowerCase().compareTo(_asString(b['name']).toLowerCase());
    });

    return combined;
  }

  static Map<String, int> countRecordsByStatus(
    List<Map<String, dynamic>> records,
    List<Map<String, dynamic>> timeOffRecords, {
    String? period,
    DateTime? referenceDate,
  }) {
    final latestByKey = <String, Map<String, dynamic>>{};
    final now = referenceDate ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final record in records) {
      final workerId = (record['workerId'] ?? '').toString().trim();
      final email = WorkerIdentity.normalizeEmail(record['email']);
      final name = WorkerIdentity.normalizeName(record['name'] ?? record['workerName']);
      final recordId = (record['id'] ?? '').toString().trim();

      final workerKey = workerId.isNotEmpty
          ? 'id:$workerId'
          : email.isNotEmpty
          ? 'email:$email'
          : name.isNotEmpty
          ? 'name:$name'
          : 'record:$recordId';

      final recordDate = AppDateUtils.attendanceRecordDate(record);
      if (recordDate != null) {
        final day = DateTime(recordDate.year, recordDate.month, recordDate.day);
        if (day.isAfter(today)) continue;
        if (period != null && !AppDateUtils.isDateWithinEffectivePeriod(day, period, now: now)) {
          continue;
        }
      }

      final dayKey = recordDate == null ? 'undated:$recordId' : _dateKey(recordDate);
      final key = '$workerKey|$dayKey';

      final existing = latestByKey[key];
      if (existing == null || _isNewer(existing, record)) {
        latestByKey[key] = record;
      }
    }

    int present = 0;
    int absent = 0;
    int leave = 0;

    for (final record in latestByKey.values) {
      final recordDate = AppDateUtils.attendanceRecordDate(record);
      final withinPeriod = recordDate == null ||
          (period == null || AppDateUtils.isDateWithinEffectivePeriod(recordDate, period, now: now));
      if (!withinPeriod) continue;

      final isOnLeave = recordDate != null &&
          !recordDate.isAfter(today) &&
          TimeOffService.isWorkerOnLeave(record, timeOffRecords, onDate: recordDate) &&
          (period == null || AppDateUtils.isDateWithinEffectivePeriod(recordDate, period, now: now));

      final status = normalizedAttendanceStatus(record);

      if (isOnLeave || status == 'leave') {
        leave++;
      } else if (status == 'present') {
        present++;
      } else if (status == 'absent') {
        absent++;
      }
    }
    return {'present': present, 'absent': absent, 'leave': leave};
  }
}
