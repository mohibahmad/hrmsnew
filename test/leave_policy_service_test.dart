import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/leave_policy_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const policy = <String, dynamic>{
    'policyName': 'Company Leave Policy 2026',
    'leaveType': 'Casual',
    'allowedLeaves': '10',
    'paidUnpaid': 'Paid',
    'applicableTo': 'All Workers',
    'startDate': '2026-08-01',
    'carryForward': false,
    'approvalRequired': true,
  };

  test('formatted policy text is ready for messaging apps', () {
    final text = LeavePolicyService.formattedText(policy);

    expect(text, contains('Company Leave Policy 2026'));
    expect(text, contains('Casual Leave: 10 days (Paid)'));
    expect(text, contains('Effective From: 1 August 2026'));
    expect(text, contains('Approval Required: Yes'));
  });

  test('leave policy PDF is generated as a valid PDF document', () async {
    final bytes = await LeavePolicyService.generatePdf(
      policy,
      companyName: 'Example Company',
      companyId: 'COMP-101',
    );

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('PDF file names are safe and idempotent', () {
    final first = LeavePolicyService.safeFileName('Company Leave Policy 2026');

    expect(first, 'Company_Leave_Policy_2026_leave_policy.pdf');
    expect(LeavePolicyService.safeFileName(first), first);
  });
}
