import '../utils/worker_identity.dart';

class AttendanceService {
  static final AttendanceService _instance = AttendanceService._();
  factory AttendanceService() => _instance;
  AttendanceService._();

  
  static List<Map<String, dynamic>> recordsForWorker({
    required Map<String, dynamic> worker,
    required List<Map<String, dynamic>> attendanceRecords,
  }) {
    final workerId = (worker['workerId'] ?? worker['id'] ?? '')
        .toString()
        .trim();
    final workerEmail = WorkerIdentity.normalizeEmail(worker['email']);
    final workerName = WorkerIdentity.normalizeName(worker['name']);

    return attendanceRecords.where((record) {
      final recordWorkerId = (record['workerId'] ?? '').toString().trim();
      if (workerId.isNotEmpty && recordWorkerId.isNotEmpty) {
        return recordWorkerId == workerId;
      }

      final recordEmail = WorkerIdentity.normalizeEmail(record['email']);
      if (workerEmail.isNotEmpty && recordEmail.isNotEmpty) {
        return recordEmail == workerEmail;
      }

      final recordName = WorkerIdentity.normalizeName(record['name']);
      return workerName.isNotEmpty && recordName == workerName;
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

    final idMap = <String, Map<String, dynamic>>{};
    final emailMap = <String, Map<String, dynamic>>{};
    final nameMap = <String, Map<String, dynamic>>{};

    for (var att in rawAttendanceDocs) {
      final attId = (att['workerId'] ?? '').toString().trim().toLowerCase();
      final attEmail = WorkerIdentity.normalizeEmail(att['email']);
      final attName = WorkerIdentity.normalizeName(att['name']);
      if (attId.isNotEmpty) {
        idMap.putIfAbsent(attId, () => att);
      }
      if (attEmail.isNotEmpty) {
        emailMap.putIfAbsent(attEmail, () => att);
      }
      if (attName.isNotEmpty) {
        nameMap.putIfAbsent(attName, () => att);
      }
    }

    for (var worker in workersList) {
      final wId = (worker['id'] ?? '').toString().trim().toLowerCase();
      final wEmail = WorkerIdentity.normalizeEmail(worker['email']);
      final wName = WorkerIdentity.normalizeName(worker['name']);

      final matched = <String, dynamic>{};
      if (wId.isNotEmpty && idMap.containsKey(wId)) {
        matched.addAll(idMap[wId]!);
      } else if (wEmail.isNotEmpty && emailMap.containsKey(wEmail)) {
        matched.addAll(emailMap[wEmail]!);
      } else if (wName.isNotEmpty && nameMap.containsKey(wName)) {
        matched.addAll(nameMap[wName]!);
      }

      if (matched.isNotEmpty) {
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
