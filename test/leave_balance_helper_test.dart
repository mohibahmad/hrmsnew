import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/utils/leave_balance_helper.dart';

void main() {
  const exhaustedWorker = <String, dynamic>{
    'annualLeaves': '1',
    'sickLeaves': '0',
    'casualLeaves': '0',
    'availableAnnualLeaves': '0',
    'availableSickLeaves': '0',
    'availableCasualLeaves': '0',
  };

  test('exhausted balance blocks a new time off request', () {
    expect(
      LeaveBalanceHelper.shouldBlockTimeOffForm(
        exhaustedWorker,
        isEditing: false,
      ),
      isTrue,
    );
  });

  test('exhausted balance does not block editing assigned time off', () {
    expect(
      LeaveBalanceHelper.shouldBlockTimeOffForm(
        exhaustedWorker,
        isEditing: true,
      ),
      isFalse,
    );
  });

  test('new request is deducted exactly once from the saved balance', () {
    final balance = LeaveBalanceHelper.balanceAfterRequest(
      availableBeforeSave: 12,
      usedBeforeSave: 0,
      requestedDays: 3,
    );

    expect(balance.remaining, 9);
    expect(balance.used, 3);
  });
}
