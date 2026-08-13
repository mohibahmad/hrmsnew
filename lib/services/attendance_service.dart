import '../utils/worker_identity.dart';
import '../utils/date_time_utils.dart';
import 'time_off_service.dart';

class AttendanceService {
  static final AttendanceService _instance = AttendanceService._();
  factory AttendanceService() => _instance;
  AttendanceService._();

  static String workerIdFor(Map<String, dynamic> data) {
    return (data['workerId'] ?? data['id'] ?? '').toString().trim();
  }

  static const Set<String> _ineligibleAttendanceStatuses = {
    'inactive',
    'terminated',
    'deleted',
    'archived',
  };

  static bool isEligibleForAttendance(Map<String, dynamic> worker) {
    final status = (worker['status'] ?? 'Active')
        .toString()
        .trim()
        .toLowerCase();
    return !_ineligibleAttendanceStatuses.contains(status);
  }

  static bool workerExistedOnDate(Map<String, dynamic> worker, DateTime date) {
    final employmentStart = AppDateUtils.dateFromValue(
      worker['joiningDate'] ?? worker['dateOfJoining'],
    );
    if (employmentStart == null) return true;

    final startDay = DateTime(
      employmentStart.year,
      employmentStart.month,
      employmentStart.day,
    );
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

  static bool isRecordForDate(
    Map<String, dynamic> record,
    DateTime requestedDate,
  ) {
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
    final timeOffId = (timeOffRecord['id'] ?? timeOffRecord['timeOffId'] ?? '')
        .toString()
        .trim();
    return {
      ...attendanceRecord,
      'status': 'Leave',
      'type': leaveType,
      'desc': automaticDescription,
      'source': 'auto_leave',
      if (timeOffId.isNotEmpty) 'timeOffId': timeOffId,
    };
  }

  static bool _recordMatchesWorkerIdentity(
    Map<String, dynamic> worker,
    Map<String, dynamic> record, {
    bool allowNameFallback = true,
  }) {
    final workerId = (worker['workerId'] ?? worker['id'] ?? '')
        .toString()
        .trim();
    final recordWorkerId = (record['workerId'] ?? '').toString().trim();

    if (recordWorkerId.isNotEmpty) {
      return workerId.isNotEmpty && recordWorkerId == workerId;
    }

    final workerEmail = WorkerIdentity.normalizeEmail(worker['email']);
    final recordEmail = WorkerIdentity.normalizeEmail(record['email']);

    if (recordEmail.isNotEmpty) {
      return workerEmail.isNotEmpty && recordEmail == workerEmail;
    }

    if (!allowNameFallback) return false;

    final workerName = WorkerIdentity.normalizeName(worker['name']);
    final recordName = WorkerIdentity.normalizeName(
      record['name'] ?? record['workerName'],
    );
    return workerName.isNotEmpty && recordName == workerName;
  }

  static DateTime? _recordRevisionDate(Map<String, dynamic> record) {
    for (final key in ['updatedAt', 'createdAt']) {
      final date = AppDateUtils.dateFromValue(record[key]);
      if (date != null) return date;
    }
    return null;
  }

  static bool _candidateIsNewer(
    Map<String, dynamic> existing,
    Map<String, dynamic> candidate,
  ) {
    final existingRevision = _recordRevisionDate(existing);
    final candidateRevision = _recordRevisionDate(candidate);

    if (candidateRevision != null && existingRevision == null) return true;
    if (candidateRevision == null && existingRevision != null) return false;

    if (candidateRevision != null && existingRevision != null) {
      final comparison = candidateRevision.compareTo(existingRevision);
      if (comparison != 0) return comparison > 0;
    }

    return (candidate['id'] ?? '').toString().compareTo(
          (existing['id'] ?? '').toString(),
        ) >
        0;
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
      if (!_recordMatchesWorkerIdentity(
        worker,
        record,
        allowNameFallback: allowNameFallback,
      )) {
        continue;
      }

      if (!workerExistedOnRecordDate(
        worker: worker,
        attendanceRecord: record,
      )) {
        continue;
      }

      final date = AppDateUtils.attendanceRecordDate(record);
      final key = date == null
          ? 'undated:${(record['id'] ?? recordsByDay.length).toString()}'
          : _dateKey(date);
      final existing = recordsByDay[key];
      if (existing == null || _candidateIsNewer(existing, record)) {
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

      final dateComparison = bDate.compareTo(aDate);
      if (dateComparison != 0) return dateComparison;

      if (_candidateIsNewer(a, b)) return 1;
      if (_candidateIsNewer(b, a)) return -1;
      return 0;
    });

    return records;
  }

  static bool _workerNameIsUnique(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> workersList,
  ) {
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

  static String _stringValue(dynamic value) {
    return (value ?? '').toString().trim();
  }

  static dynamic _preferValue(dynamic primary, dynamic fallback) {
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
      final workerId = _stringValue(worker['id'] ?? worker['workerId']);
      final workerEmail = WorkerIdentity.normalizeEmail(worker['email']);
      final workerName = WorkerIdentity.normalizeName(worker['name']);
      final allowNameFallback = _workerNameIsUnique(worker, workersList);

      final matchedRecords = recordsForWorker(
        worker: worker,
        attendanceRecords: rawAttendanceDocs,
        allowNameFallback: allowNameFallback,
      );
      final matched = matchedRecords.isEmpty ? null : matchedRecords.first;

      if (matched != null) {
        combined.add({
          ...matched,
          'workerId': workerId.isNotEmpty
              ? workerId
              : _stringValue(matched['workerId']),
          'name': _preferValue(worker['name'], matched['name']),
          'email': _preferValue(worker['email'], matched['email']),
          'role': _preferValue(
            worker['position'] ?? worker['role'],
            matched['role'],
          ),
          'profileImage': _preferValue(
            worker['profileImage'],
            matched['profileImage'],
          ),
          'phone': _preferValue(
            worker['phone'] ?? worker['contact'],
            matched['phone'] ?? matched['contact'],
          ),
        });
      } else {
        final placeholderIdentity = workerId.isNotEmpty
            ? workerId
            : workerEmail.isNotEmpty
            ? workerEmail
            : workerName.isNotEmpty
            ? workerName
            : index.toString();

        combined.add({
          'id': 'norecord_$placeholderIdentity',
          'workerId': workerId,
          'name': _preferValue(worker['name'], 'Worker'),
          'email': worker['email'] ?? '',
          'role': worker['position'] ?? worker['role'] ?? '',
          'attendanceType':
              worker['type2'] ?? worker['attendanceType'] ?? 'On-Site',
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
        return _stringValue(
          a['name'],
        ).toLowerCase().compareTo(_stringValue(b['name']).toLowerCase());
      }
      if (aDate == null) return 1;
      if (bDate == null) return -1;

      final dateComparison = bDate.compareTo(aDate);
      if (dateComparison != 0) return dateComparison;

      return _stringValue(
        a['name'],
      ).toLowerCase().compareTo(_stringValue(b['name']).toLowerCase());
    });

    return combined;
  }

  static Map<String, int> countRecordsByStatus(
    List<Map<String, dynamic>> records,
    List<Map<String, dynamic>> timeOffRecords,
  ) {
    final latestByWorkerAndDay = <String, Map<String, dynamic>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final record in records) {
      final workerId = (record['workerId'] ?? '').toString().trim();
      final email = WorkerIdentity.normalizeEmail(record['email']);
      final name = WorkerIdentity.normalizeName(
        record['name'] ?? record['workerName'],
      );
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
        final recordDay = DateTime(
          recordDate.year,
          recordDate.month,
          recordDate.day,
        );
        if (recordDay.isAfter(today)) continue;
      }
      final dayKey = recordDate == null
          ? 'undated:$recordId'
          : _dateKey(recordDate);
      final key = '$workerKey|$dayKey';
      final existing = latestByWorkerAndDay[key];
      if (existing == null || _candidateIsNewer(existing, record)) {
        latestByWorkerAndDay[key] = record;
      }
    }

    int present = 0;
    int absent = 0;
    int leave = 0;
    for (final record in latestByWorkerAndDay.values) {
      final recordDate = AppDateUtils.attendanceRecordDate(record);
      final isOnLeave =
          recordDate != null &&
          TimeOffService.isWorkerOnLeave(
            record,
            timeOffRecords,
            onDate: recordDate,
          );
      final status = (record['status'] ?? '').toString().trim().toLowerCase();
      if (isOnLeave ||
          status == 'leave' ||
          status == 'l' ||
          status == 'approved') {
        leave++;
      } else if (status == 'present' || status == 'p') {
        present++;
      } else if (status == 'absent' || status == 'a') {
        absent++;
      }
    }
    return {'present': present, 'absent': absent, 'leave': leave};
  }
}
