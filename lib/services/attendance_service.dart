import '../utils/worker_identity.dart';
import '../utils/date_utils.dart';

class AttendanceService {
  static final AttendanceService _instance = AttendanceService._();
  factory AttendanceService() => _instance;
  AttendanceService._();

  static String workerIdFor(Map<String, dynamic> data) {
    return (data['workerId'] ?? data['id'] ?? '').toString().trim();
  }

  static bool workerExistedOnDate(Map<String, dynamic> worker, DateTime date) {
    final createdAt = AppDateUtils.dateFromValue(worker['createdAt']);
    if (createdAt == null) return true;

    final creationDay = DateTime(
      createdAt.year,
      createdAt.month,
      createdAt.day,
    );
    final targetDay = DateTime(date.year, date.month, date.day);
    return !targetDay.isBefore(creationDay);
  }

  static bool recordIsOnOrAfterWorkerCreation({
    required Map<String, dynamic> worker,
    required Map<String, dynamic> attendanceRecord,
  }) {
    final attendanceDate = AppDateUtils.attendanceRecordDate(attendanceRecord);
    return attendanceDate == null ||
        workerExistedOnDate(worker, attendanceDate);
  }

  static bool _recordMatchesWorkerIdentity(
    Map<String, dynamic> worker,
    Map<String, dynamic> record,
  ) {
    final workerId = (worker['workerId'] ?? worker['id'] ?? '')
        .toString()
        .trim();
    final recordWorkerId = (record['workerId'] ?? '').toString().trim();
    if (workerId.isNotEmpty && recordWorkerId.isNotEmpty) {
      return recordWorkerId == workerId;
    }

    final workerEmail = WorkerIdentity.normalizeEmail(worker['email']);
    final recordEmail = WorkerIdentity.normalizeEmail(record['email']);
    if (workerEmail.isNotEmpty && recordEmail.isNotEmpty) {
      return recordEmail == workerEmail;
    }

    final workerName = WorkerIdentity.normalizeName(worker['name']);
    final recordName = WorkerIdentity.normalizeName(record['name']);
    return workerName.isNotEmpty && recordName == workerName;
  }

  static List<Map<String, dynamic>> recordsForWorker({
    required Map<String, dynamic> worker,
    required List<Map<String, dynamic>> attendanceRecords,
  }) {
    return attendanceRecords.where((record) {
      return _recordMatchesWorkerIdentity(worker, record) &&
          recordIsOnOrAfterWorkerCreation(
            worker: worker,
            attendanceRecord: record,
          );
    }).toList();
  }

  static List<Map<String, dynamic>> combineAttendance({
    required List<Map<String, dynamic>> workersList,
    required List<Map<String, dynamic>> rawAttendanceDocs,
  }) {
    if (workersList.isEmpty && rawAttendanceDocs.isEmpty) {
      return [];
    }

    final combined = <Map<String, dynamic>>[];

    for (var worker in workersList) {
      final wEmail = WorkerIdentity.normalizeEmail(worker['email']);
      final matched = rawAttendanceDocs
          .cast<Map<String, dynamic>?>()
          .firstWhere(
            (record) =>
                record != null &&
                _recordMatchesWorkerIdentity(worker, record) &&
                recordIsOnOrAfterWorkerCreation(
                  worker: worker,
                  attendanceRecord: record,
                ),
            orElse: () => null,
          );

      if (matched != null) {
        combined.add({
          ...matched,
          'workerId': worker['id'] ?? matched['workerId'],
          'name': worker['name'] ?? matched['name'],
          'role': worker['position'] ?? matched['role'] ?? '',
          'profileImage': worker['profileImage'],
          'phone': worker['phone'] ?? '',
        });
      } else {
        combined.add({
          'id': 'norecord_${worker['id'] ?? wEmail}',
          'workerId': worker['id'],
          'name': worker['name'] ?? 'Worker',
          'email': worker['email'] ?? '',
          'role': worker['position'] ?? '',
          'attendanceType': worker['type2'] ?? 'On-Site',
          'workType': worker['type1'] ?? 'Full Time',
          'profileImage': worker['profileImage'],
          'phone': worker['phone'] ?? '',
          'createdAt': null,
          'status': '',
        });
      }
    }

    combined.sort((a, b) {
      final aTime = a['createdAt'];
      final bTime = b['createdAt'];
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      final aStr = aTime.toString();
      final bStr = bTime.toString();
      return bStr.compareTo(aStr);
    });

    return combined;
  }
}
