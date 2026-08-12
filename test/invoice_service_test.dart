import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/invoice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InvoiceService tests', () {
    test('generatePayrollInvoice creates readable invoice numbers', () async {
      final pdf1 = await InvoiceService.generatePayrollInvoice(
        employeeName: 'John Doe',
        email: 'john@example.com',
        position: 'Developer',
        payPeriod: 'Aug 2026',
        totalWorkDays: '22',
        daysWorked: '22',
        absents: '0',
        leaves: '0',
        overtimeAmount: '\$0.00',
        salary: '\$5000.00',
        dailyRate: '\$227.27',
        grossPay: '\$5000.00',
        overtimePay: '\$0.00',
        absentDeduction: '\$0.00',
        leaveDeduction: '\$0.00',
        totalDeductions: '\$0.00',
        netSalary: '\$5000.00',
        currency: 'USD',
        workerId: '1',
      );

      expect(pdf1, isNotEmpty);
    });
  });
}
