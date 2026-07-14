import '../services/dummy_data.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';

class LeaveBalanceHelper {
  /// Maps a leave type label to its running-balance field name.
  static const Map<String, String> availKeyForType = {
    'Sick Leave': 'availableSickLeaves',
    'Casual Leave': 'availableCasualLeaves',
    'Annual Leave': 'availableAnnualLeaves',
  };

  /// Maps a leave type label to its configured allowance field name.
  static const Map<String, String> configKeyForType = {
    'Sick Leave': 'sickLeaves',
    'Casual Leave': 'casualLeaves',
    'Annual Leave': 'annualLeaves',
  };

  static int _toInt(dynamic v) => int.tryParse(v?.toString() ?? '0') ?? 0;

  /// Total leave allowance (annual + casual + sick) as configured when the
  /// worker was added individually or imported via bulk upload.
  static int totalLeaveAllowance(Map<String, dynamic> worker) {
    final annual = _toInt(worker['annualLeaves']);
    final casual = _toInt(worker['casualLeaves']);
    final sick = _toInt(worker['sickLeaves']);
    return annual + casual + sick;
  }

  /// Remaining paid leave balance for a specific [leaveType]. Prefers the
  /// stored running counter (e.g. `availableSickLeaves`) and falls back to the
  /// configured allowance for that type.
  static int remainingForType(Map<String, dynamic> worker, String leaveType) {
    final availKey = availKeyForType[leaveType];
    if (availKey != null) {
      final raw = worker[availKey];
      if (raw != null) {
        final parsed = int.tryParse(raw.toString());
        if (parsed != null) return parsed.clamp(0, 999999);
      }
    }
    final configKey = configKeyForType[leaveType];
    if (configKey != null) return _toInt(worker[configKey]);
    return 0;
  }

  /// Configured allowance for a specific [leaveType].
  static int totalForType(Map<String, dynamic> worker, String leaveType) {
    final configKey = configKeyForType[leaveType];
    if (configKey != null) return _toInt(worker[configKey]);
    return 0;
  }

  /// True when the worker has no paid leave remaining for any type.
  static bool allLeavesExhausted(Map<String, dynamic> worker) {
    return remainingForType(worker, 'Sick Leave') <= 0 &&
        remainingForType(worker, 'Casual Leave') <= 0 &&
        remainingForType(worker, 'Annual Leave') <= 0;
  }

  static Future<int> getAvailableLeaveBalance(
    String email,
    FirestoreService firestore,
    List<Map<String, dynamic>> todayAttendance,
  ) async {
    try {
      final isGuest = AuthService().currentUser?.isAnonymous ?? false;
      if (isGuest) {
        final worker = DummyData.workers.firstWhere(
          (w) => (w['email']?.toString() ?? '').toLowerCase() == email.toLowerCase(),
          orElse: () => {},
        );
        if (worker.isEmpty) return 0;
        final annual = int.tryParse(worker['annualLeaves']?.toString() ?? '0') ?? 0;
        final casual = int.tryParse(worker['casualLeaves']?.toString() ?? '0') ?? 0;
        final sick = int.tryParse(worker['sickLeaves']?.toString() ?? '0') ?? 0;
        final usedLeaves = DummyData.attendance.where((att) =>
            (att['email']?.toString() ?? '').toLowerCase() == email.toLowerCase() &&
            att['status'] == 'Leave').length;
        final totalBalance = annual + casual + sick;
        return (totalBalance - usedLeaves).clamp(0, totalBalance);
      } else {
        final snapshot = await firestore.getWorkersOnce();
        final worker = snapshot.docs.firstWhere(
          (doc) => (doc['email'] ?? '').toString().toLowerCase() == email.toLowerCase(),
          orElse: () => throw Exception('Worker not found'),
        );
        final annual = int.tryParse(worker['annualLeaves']?.toString() ?? '0') ?? 0;
        final casual = int.tryParse(worker['casualLeaves']?.toString() ?? '0') ?? 0;
        final sick = int.tryParse(worker['sickLeaves']?.toString() ?? '0') ?? 0;
        final usedLeaves = todayAttendance.where((att) =>
            (att['email']?.toString() ?? '').toLowerCase() == email.toLowerCase() &&
            att['status'] == 'Leave').length;
        final totalBalance = annual + casual + sick;
        return (totalBalance - usedLeaves).clamp(0, totalBalance);
      }
    } catch (e) {
      return 999;
    }
  }
}
