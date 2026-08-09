class LeaveBalanceHelper {
  
  
  static const Map<String, String> availKeyForType = {
    'Sick Leave': 'availableSickLeaves',
    'Casual Leave': 'availableCasualLeaves',
    'Annual Leave': 'availableAnnualLeaves',
    'Medical Leave': 'availableMedicalLeaves',
  };

  
  static const Map<String, String> configKeyForType = {
    'Sick Leave': 'sickLeaves',
    'Casual Leave': 'casualLeaves',
    'Annual Leave': 'annualLeaves',
    'Medical Leave': 'medicalLeaves',
  };

  static int _toInt(dynamic v) => int.tryParse(v?.toString() ?? '0') ?? 0;

  
  
  
  
  static String leaveDaysText(dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return '';
    final parsed = num.tryParse(text);
    if (parsed == null) return text;
    return parsed.toInt().toString();
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

  static bool allLeavesExhausted(Map<String, dynamic> worker) {
    return remainingForType(worker, 'Annual Leave') <= 0;
  }

}
