import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/invoice_service.dart';
import 'package:image/image.dart' as img;

import '../helpers/localization.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Distinctive dimensions (57x23) so we can tell the uploaded company logo
  // apart from the bundled app icon inside the generated PDF.
  Uint8List makeLogo({int width = 57, int height = 23}) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(20, 90, 200));
    return Uint8List.fromList(img.encodePng(image));
  }

  String dataUrl(Uint8List bytes) =>
      'data:image/png;base64,${base64Encode(bytes)}';

  Future<Uint8List> generate({required String logoUrl}) {
    return InvoiceService.generatePayrollInvoice(
      employeeName: 'John Doe',
      email: 'john@example.com',
      position: 'Developer',
      payPeriod: '06/2026',
      totalWorkDays: '26',
      daysWorked: '26',
      absents: '0',
      leaves: '0',
      overtimeAmount: '0',
      salary: 'Rs 100,000',
      dailyRate: 'Rs 3,846.15',
      grossPay: 'Rs 100,000',
      overtimePay: '0',
      absentDeduction: '0',
      leaveDeduction: '0',
      totalDeductions: '0',
      netSalary: 'Rs 100,000',
      currency: 'PKR',
      companyName: 'Test Corp',
      companyId: 'TEST123',
      companyLogoUrl: logoUrl,
    );
  }

  testWidgets('invoice embeds uploaded company logo when provided',
      (tester) async {
    await initLocalization(tester);
    late Uint8List pdf;
    await tester.runAsync(() async {
      pdf = await generate(logoUrl: dataUrl(makeLogo()));
    });

    final text = latin1.decode(pdf);
    expect(pdf.isNotEmpty, isTrue);
    expect(text.contains('/Width 57'), isTrue,
        reason: 'Uploaded 57px-wide company logo should be embedded');
    expect(text.contains('/Height 23'), isTrue,
        reason: 'Uploaded 23px-tall company logo should be embedded');
  });

  testWidgets('invoice falls back to app icon when no logo uploaded',
      (tester) async {
    await initLocalization(tester);
    late Uint8List pdf;
    await tester.runAsync(() async {
      pdf = await generate(logoUrl: '');
    });

    final text = latin1.decode(pdf);
    expect(pdf.isNotEmpty, isTrue);
    expect(text.contains('/Width 57'), isFalse,
        reason: 'App icon fallback should be used instead of a custom logo');
  });
}
