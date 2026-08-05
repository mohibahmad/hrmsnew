import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/widgets/amount_text.dart';

void main() {
  group('AmountText.formatFull', () {
    test('parses Arabic-script symbols with dots correctly (AED)', () {
      // The 'د.إ' symbol contains a dot; before the fix the dot leaked into
      // the numeric parse and turned 5000 into 0.5.
      expect(AmountText.formatFull('د.إ 5000'), 'د.إ5,000');
      expect(
        AmountText.formatFull('د.إ 300000000000000.0'),
        'د.إ300,000,000,000,000',
      );
    });

    test('keeps Arabic-script symbols with dots intact (OMR)', () {
      expect(AmountText.formatFull('ر.ع. 500'), 'ر.ع.500');
      expect(AmountText.formatFull('ر.ق 1200'), 'ر.ق1,200');
    });

    test('formats plain numbers with comma separators', () {
      expect(AmountText.formatFull(r'$ 5000'), r'$5,000');
      expect(AmountText.formatFull('Rs 5000'), 'Rs5,000');
      expect(AmountText.formatFull('5000'), '5,000');
    });

    test('preserves the minus sign on negative amounts', () {
      expect(AmountText.formatFull(r'-$ 454.55'), r'$-454.55');
      expect(AmountText.formatCompact(r'-$ 454.55'), r'$-454.55');
    });

    test('handles empty and non-numeric input', () {
      expect(AmountText.formatFull(''), '0');
      expect(AmountText.formatFull('   '), '0');
    });
  });

  group('AmountText.formatCompact', () {
    test('keeps symbols and compacts large values', () {
      expect(AmountText.formatCompact(r'$ 50,000'), r'$50.0K');
    });
  });
}
