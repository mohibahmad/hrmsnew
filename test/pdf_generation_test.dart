import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/invoice_service.dart';
import 'package:hrms/services/worker_profile_service.dart';

Future<void> _pumpLocalizedApp(WidgetTester tester, Locale locale) async {
  await tester.pumpWidget(
    EasyLocalization(
      key: const ValueKey('pdf-generation-test'),
      saveLocale: false,
      supportedLocales: const [Locale('en'), Locale('es'), Locale('fr'), Locale('pt'), Locale('ru')],
      path: 'assets/translations',
      startLocale: locale,
      fallbackLocale: const Locale('en'),
      child: const MaterialApp(
        home: Scaffold(body: SizedBox.shrink()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'payroll PDF renders exact values with uploaded authorization',
    (tester) async {
      await _pumpLocalizedApp(tester, const Locale('en'));

      final bytes = await InvoiceService.generatePayrollInvoice(
        employeeName: 'Carlos Garcia',
        email: 'carlos@example.com',
        position: 'Developer',
        payPeriod: '2026-08',
        totalWorkDays: '22',
        daysWorked: '21',
        absents: '1',
        leaves: '0',
        overtimeAmount: 'Rs 123.456',
        salary: 'Rs 9,500.75',
        dailyRate: 'Rs 431.85',
        grossPay: 'Rs 9,500.75',
        overtimePay: 'Rs 123.46',
        absentDeduction: 'Rs 431.85',
        leaveDeduction: 'Rs 0.00',
        totalDeductions: 'Rs 431.85',
        netSalary: 'Rs 9,192.36',
        currency: 'Rs',
        companyName: 'Example HRMS Limited',
        companyId: 'COMP-101',
        companyStampImageUrl: 'assets/app_icon.png',
      );

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    },
  );

  testWidgets('worker profile PDF renders the uploaded company stamp', (tester) async {
    await _pumpLocalizedApp(tester, const Locale('en'));

    final bytes = await WorkerProfileService.generateWorkerProfile(
      name: 'Carlos Garcia',
      email: 'carlos@example.com',
      phone: '+92 300 0000000',
      fatherHusbandName: 'Luis Garcia',
      position: 'Developer',
      nationalId: '12345-1234567-1',
      attendanceType: 'On-Site',
      workType: 'Full Time',
      experienceLevel: 'Senior',
      gender: 'Male',
      joiningDate: '2026-01-01',
      salary: 'Rs 9,500.75',
      education: 'Bachelor',
      salaryType: 'Monthly',
      religion: '-',
      dateOfBirth: '1990-01-01',
      relationshipStatus: 'Single',
      address: 'Karachi',
      companyName: 'Example HRMS Limited',
      companyId: 'COMP-101',
      companyStampImageUrl: 'assets/app_icon.png',
    );

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}

