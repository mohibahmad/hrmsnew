import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/invoice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('payroll logo falls back to the bundled app icon', () async {
    final logoBytes = await InvoiceService.resolveCompanyLogoBytes(null);

    expect(logoBytes, isNotNull);
    expect(logoBytes, isNotEmpty);
    expect(logoBytes!.sublist(1, 4), [0x50, 0x4E, 0x47]);
  });

  test('uploaded company profile image replaces the app icon', () async {
    const onePixelPng =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
    final customDataUri = 'data:image/png;base64,$onePixelPng';
    final customBytes = await InvoiceService.resolveCompanyLogoBytes(
      customDataUri,
    );
    final fallbackBytes = await InvoiceService.resolveCompanyLogoBytes(null);

    expect(customBytes, isNotNull);
    expect(customBytes, isNotEmpty);
    expect(base64Encode(customBytes!), isNot(base64Encode(fallbackBytes!)));
  });

  test('invoice leaves include paid leave days from payroll review', () {
    expect(
      InvoiceService.resolveInvoiceLeaveDays(
        leaves: '2',
        paidLeaves: '2',
        unpaidLeaves: '0',
      ),
      '2',
    );

    expect(
      InvoiceService.resolveInvoiceLeaveDays(
        leaves: '0',
        paidLeaves: '2',
        unpaidLeaves: '0',
      ),
      '2',
    );
  });
}
