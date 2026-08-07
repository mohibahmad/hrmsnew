import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/invoice_service.dart';
import 'package:hrms/services/payroll_service.dart';
import 'package:hrms/utils/currency_utils.dart';

import '../helpers/localization.dart';









String pdfText(List<int> bytes) {
  final buffer = StringBuffer();
  
  final data = latin1.decode(Uint8List.fromList(bytes));

  
  
  final fontObjByResource = <String, int>{};
  for (final m in RegExp(r'/Font\s*<<(.*?)>>', dotAll: true).allMatches(data)) {
    for (final fr in RegExp(
      r'/(F\d+)\s+(\d+)\s+\d+\s+R',
    ).allMatches(m.group(1)!)) {
      fontObjByResource[fr.group(1)!] = int.parse(fr.group(2)!);
    }
  }

  
  
  final fontObjToToUnicode = <int, int>{};
  final objectRe = RegExp(r'(\d+)\s+\d+\s+obj(.*?)endobj', dotAll: true);
  for (final om in objectRe.allMatches(data)) {
    final body = om.group(2)!;
    final tu = RegExp(r'/ToUnicode\s+(\d+)\s+\d+\s+R').firstMatch(body);
    if (tu != null) {
      fontObjToToUnicode[int.parse(om.group(1)!)] = int.parse(tu.group(1)!);
    }
  }

  
  final toUnicodeMaps = <int, Map<int, String>>{};
  for (final toUnicodeObj in fontObjToToUnicode.values.toSet()) {
    final objMatch = RegExp(
      '$toUnicodeObj \\d+ obj(.*?)endobj',
      dotAll: true,
    ).firstMatch(data);
    if (objMatch == null) continue;
    final streamMatch = RegExp(
      r'stream\r?\n(.*?)\r?\nendstream',
      dotAll: true,
    ).firstMatch(objMatch.group(1)!);
    if (streamMatch == null) continue;
    try {
      final inflated = ZLibDecoder().decodeBytes(
        latin1.encode(streamMatch.group(1)!),
      );
      toUnicodeMaps[toUnicodeObj] = _parseToUnicodeMap(latin1.decode(inflated));
    } catch (_) {
      
    }
  }

  final streamRe = RegExp(r'stream\r?\n(.*?)\r?\nendstream', dotAll: true);
  for (final m in streamRe.allMatches(data)) {
    try {
      final inflated = ZLibDecoder().decodeBytes(latin1.encode(m.group(1)!));
      _extractContentText(
        latin1.decode(inflated),
        buffer,
        fontObjByResource,
        fontObjToToUnicode,
        toUnicodeMaps,
      );
    } catch (_) {
      
    }
  }
  return buffer.toString();
}




void _extractContentText(
  String content,
  StringBuffer buffer,
  Map<String, int> fontObjByResource,
  Map<int, int> fontObjToToUnicode,
  Map<int, Map<int, String>> toUnicodeMaps,
) {
  int? currentFontObj;
  final matches = <RegExpMatch>[
    ...RegExp(r'/(F\d+|\d+)\s+[\d.]+\s+Tf').allMatches(content),
    ...RegExp(r'<([0-9A-Fa-f\s]+)>\s*Tj').allMatches(content),
    ...RegExp(r'\(((?:\\.|[^()\\])*)\)\s*Tj').allMatches(content),
    ...RegExp(
      r'\[\s*((?:<[0-9A-Fa-f\s]+>|[-+]?\d+(?:\.\d+)?\s*)*)\]\s*TJ',
    ).allMatches(content),
  ]..sort((a, b) => a.start.compareTo(b.start));

  for (final m in matches) {
    final token = content.substring(m.start, m.end);
    if (token.contains('Tf')) {
      final name = RegExp(r'/(F\d+|\d+)').firstMatch(token)!.group(1)!;
      currentFontObj = int.tryParse(name) ?? fontObjByResource[name];
      continue;
    }
    if (token.startsWith('<')) {
      buffer
        ..write(
          _decodeHex(
            m.group(1)!,
            _cmapFor(currentFontObj, fontObjToToUnicode, toUnicodeMaps),
          ),
        )
        ..write(' ');
    } else if (token.startsWith('(')) {
      buffer
        ..write(_unescapePdfLiteral(m.group(1)!))
        ..write(' ');
    } else if (token.startsWith('[')) {
      final cmap = _cmapFor(currentFontObj, fontObjToToUnicode, toUnicodeMaps);
      for (final hm in RegExp(r'<([0-9A-Fa-f\s]+)>').allMatches(m.group(1)!)) {
        buffer.write(_decodeHex(hm.group(1)!, cmap));
      }
      buffer.write(' ');
    }
  }
}

Map<int, String>? _cmapFor(
  int? fontObj,
  Map<int, int> fontObjToToUnicode,
  Map<int, Map<int, String>> toUnicodeMaps,
) {
  if (fontObj == null) return null;
  final toUnicodeObj = fontObjToToUnicode[fontObj];
  if (toUnicodeObj == null) return null;
  return toUnicodeMaps[toUnicodeObj];
}



String _decodeHex(String hex, Map<int, String>? cmap) {
  final clean = hex.replaceAll(RegExp(r'\s'), '');
  if (clean.isEmpty || clean.length.isOdd) return '';
  final out = StringBuffer();
  if (cmap != null) {
    for (var i = 0; i + 3 < clean.length; i += 4) {
      out.write(cmap[int.parse(clean.substring(i, i + 4), radix: 16)] ?? '');
    }
  } else {
    for (var i = 0; i + 3 < clean.length; i += 4) {
      out.writeCharCode(int.parse(clean.substring(i, i + 4), radix: 16));
    }
  }
  return out.toString();
}



Map<int, String> _parseToUnicodeMap(String cmap) {
  final map = <int, String>{};

  for (final m in RegExp(
    r'beginbfchar(.*?)endbfchar',
    dotAll: true,
  ).allMatches(cmap)) {
    for (final p in RegExp(
      r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>',
    ).allMatches(m.group(1)!)) {
      map[int.parse(p.group(1)!, radix: 16)] = _hexStringToText(p.group(2)!);
    }
  }

  for (final m in RegExp(
    r'beginbfrange(.*?)endbfrange',
    dotAll: true,
  ).allMatches(cmap)) {
    final body = m.group(1)!;
    
    for (final r in RegExp(
      r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>',
    ).allMatches(body)) {
      final lo = int.parse(r.group(1)!, radix: 16);
      final hi = int.parse(r.group(2)!, radix: 16);
      final dst = int.parse(r.group(3)!, radix: 16);
      for (var code = lo; code <= hi; code++) {
        map[code] = String.fromCharCode(dst + (code - lo));
      }
    }
    
    for (final a in RegExp(
      r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*\[(.*?)\]',
      dotAll: true,
    ).allMatches(body)) {
      final lo = int.parse(a.group(1)!, radix: 16);
      var code = lo;
      for (final d in RegExp(r'<([0-9A-Fa-f]+)>').allMatches(a.group(3)!)) {
        map[code] = _hexStringToText(d.group(1)!);
        code++;
      }
    }
  }
  return map;
}


String _hexStringToText(String hex) {
  if (hex.length == 2) {
    return String.fromCharCode(int.parse(hex, radix: 16));
  }
  final out = StringBuffer();
  for (var i = 0; i + 3 < hex.length; i += 4) {
    out.writeCharCode(int.parse(hex.substring(i, i + 4), radix: 16));
  }
  return out.toString();
}

String _unescapePdfLiteral(String s) {
  return s
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '\r')
      .replaceAll(r'\t', '\t')
      .replaceAll(r'\(', '(')
      .replaceAll(r'\)', ')')
      .replaceAll(r'\\', '\\');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<int>> generateInvoice({
    required String currency,
    String? salary,
  }) async {
    final symbol = CurrencyUtils.symbolFor(currency);
    final calc = PayrollService.calculatePayroll(
      salary: salary ?? '$symbol 100,000',
      totalWorkDays: '26',
      daysWorked: '26',
      absents: '0',
      leaves: '0',
      overtimeAmount: '',
      absentDeductionPerDay: '',
      leaveDeductionPerDay: '',
      salaryType: 'Monthly',
    );
    return InvoiceService.generatePayrollInvoice(
      employeeName: 'John Doe',
      email: 'john@example.com',
      position: 'Developer',
      payPeriod: '06/2026',
      totalWorkDays: '26',
      daysWorked: '26',
      absents: '0',
      leaves: '0',
      overtimeAmount: '',
      salary: salary ?? '$symbol 100,000',
      dailyRate: (calc['formattedDailyRate'] as String? ?? ''),
      grossPay: (calc['formattedGross'] as String? ?? ''),
      overtimePay: (calc['formattedOvertime'] as String? ?? ''),
      absentDeduction: (calc['formattedAbsentDeduct'] as String? ?? ''),
      leaveDeduction: (calc['formattedLeaveDeduct'] as String? ?? ''),
      totalDeductions: (calc['formattedTotalDeductions'] as String? ?? ''),
      netSalary: (calc['formattedNet'] as String? ?? ''),
      currency: currency,
      companyName: 'Test Corp',
      companyId: 'TEST123',
    );
  }

  testWidgets('payroll invoice embeds the currency symbol for every currency', (
    tester,
  ) async {
    await initLocalization(tester);
    await tester.runAsync(() async {
      final cases = <String, String>{
        'PKR': 'PKR',
        'USD': r'$',
        'INR': '₹',
        'EUR': '€',
        'GBP': '£',
        'RUB': '₽',
        'JPY': '¥',
        'AED': 'AED',
      };
      for (final entry in cases.entries) {
        final bytes = await generateInvoice(currency: entry.key);
        final text = pdfText(bytes);
        expect(
          text.contains(entry.value),
          isTrue,
          reason:
              'Expected ${entry.key} symbol (${entry.value}) in PDF '
              'text: "$text"',
        );
      }
    });
  });

  testWidgets('payroll invoice shows salary amount with currency', (
    tester,
  ) async {
    await initLocalization(tester);
    await tester.runAsync(() async {
      final bytes = await generateInvoice(currency: 'PKR', salary: '100000');
      final text = pdfText(bytes);
      expect(
        text.contains('PKR'),
        isTrue,
        reason: 'PKR symbol missing in invoice text: "$text"',
      );
    });
  });
}
