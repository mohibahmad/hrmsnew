class AttendanceService {
  static final AttendanceService _instance = AttendanceService._();
  factory AttendanceService() => _instance;
  AttendanceService._();

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
      final attId = (att['id'] ?? att['workerId'] ?? '').toString().trim().toLowerCase();
      final attEmail = (att['email'] ?? '').toString().trim().toLowerCase();
      final attName = (att['name'] ?? '').toString().trim().toLowerCase();
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
      final wEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
      final wName = (worker['name'] ?? '').toString().trim().toLowerCase();

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
          'name': worker['name'] ?? matched['name'],
          'role': worker['position'] ?? matched['role'] ?? '',
          'profileImage': worker['profileImage'],
          'phone': worker['phone'] ?? '',
        });
      } else {
        combined.add({
          'id': 'norecord_${worker['id'] ?? wEmail}',
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

    for (var att in rawAttendanceDocs) {
      final attId = (att['id'] ?? att['workerId'] ?? '').toString().trim().toLowerCase();
      final attEmail = (att['email'] ?? '').toString().trim().toLowerCase();
      final attName = (att['name'] ?? '').toString().trim().toLowerCase();
      final idMatch = attId.isNotEmpty && idMap.containsKey(attId);
      final emailMatch = attEmail.isNotEmpty && emailMap.containsKey(attEmail);
      final nameMatch = attName.isNotEmpty && nameMap.containsKey(attName);
      if (!idMatch && !emailMatch && !nameMatch) {
        combined.add(att);
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
