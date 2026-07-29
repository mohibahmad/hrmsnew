import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/dummy_data.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';

class LeaveBalanceHelper {
  
  
  static const Map<String, String> availKeyForType = {
    'Sick Leave': 'availableAnnualLeaves',
    'Casual Leave': 'availableAnnualLeaves',
    'Annual Leave': 'availableAnnualLeaves',
    'Medical Leave': 'availableAnnualLeaves',
  };

  
  static const Map<String, String> configKeyForType = {
    'Sick Leave': 'annualLeaves',
    'Casual Leave': 'annualLeaves',
    'Annual Leave': 'annualLeaves',
    'Medical Leave': 'annualLeaves',
  };

  static int _toInt(dynamic v) => int.tryParse(v?.toString() ?? '0') ?? 0;

  
  static int totalLeaveAllowance(Map<String, dynamic> worker) {
    return _toInt(worker['annualLeaves']);
  }

  
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

  
  static int totalForType(Map<String, dynamic> worker, String leaveType) {
    final configKey = configKeyForType[leaveType];
    if (configKey != null) return _toInt(worker[configKey]);
    return 0;
  }

  
  static bool allLeavesExhausted(Map<String, dynamic> worker) {
    return remainingForType(worker, 'Annual Leave') <= 0;
  }

  
  static bool shouldBlockTimeOffForm(
    Map<String, dynamic> worker, {
    required bool isEditing,
  }) {
    return !isEditing && allLeavesExhausted(worker);
  }

  
  static ({int remaining, int used}) balanceAfterRequest({
    required int availableBeforeSave,
    required int usedBeforeSave,
    required int requestedDays,
  }) {
    return (
      remaining: (availableBeforeSave - requestedDays).clamp(0, 999999),
      used: usedBeforeSave + requestedDays,
    );
  }

  static Future<int> getAvailableLeaveBalance(
    BuildContext context,
    String email,
    FirestoreService firestore,
    List<Map<String, dynamic>> todayAttendance,
  ) async {
    try {
      final isGuest = context.read<AuthService>().currentUser?.isAnonymous ?? false;
      if (isGuest) {
        final worker = DummyData.workers.firstWhere(
          (w) =>
              (w['email']?.toString() ?? '').toLowerCase() ==
              email.toLowerCase(),
          orElse: () => {},
        );
        if (worker.isEmpty) return 0;
        final annual =
            int.tryParse(worker['annualLeaves']?.toString() ?? '0') ?? 0;
        final usedLeaves = DummyData.attendance
            .where(
              (att) =>
                  (att['email']?.toString() ?? '').toLowerCase() ==
                      email.toLowerCase() &&
                  att['status'] == 'Leave',
            )
            .length;
        final totalBalance = annual;
        return (totalBalance - usedLeaves).clamp(0, totalBalance);
      } else {
        final snapshot = await firestore.getWorkersOnce();
        final worker = snapshot.docs.firstWhere(
          (doc) =>
              (doc['email'] ?? '').toString().toLowerCase() ==
              email.toLowerCase(),
          orElse: () => throw Exception('Worker not found'),
        );
        final annual =
            int.tryParse(worker['annualLeaves']?.toString() ?? '0') ?? 0;
        final usedLeaves = todayAttendance
            .where(
              (att) =>
                  (att['email']?.toString() ?? '').toLowerCase() ==
                      email.toLowerCase() &&
                  att['status'] == 'Leave',
            )
            .length;
        final totalBalance = annual;
        return (totalBalance - usedLeaves).clamp(0, totalBalance);
      }
    } catch (e) {
      return 999;
    }
  }
}
