import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AmountText extends StatelessWidget {
  final String amount;
  final TextStyle? style;
  final TextAlign? textAlign;

  const AmountText(this.amount, {super.key, this.style, this.textAlign});

  String _formatCompact(String input) {
    try {
      if (RegExp(r'[KMBTkmbt]$').hasMatch(input.trim())) {
        return input;
      }
      final cleaned = input.replaceAll(RegExp(r"[^0-9.\-]"), '');
      if (cleaned.isEmpty) return input;
      final val = double.tryParse(cleaned);
      if (val == null) return input;
      final symbolMatch = RegExp(r"^\s*([^0-9\s.-]+)").firstMatch(input);
      final symbol = symbolMatch != null ? symbolMatch.group(1) ?? '' : '';
      if (val >= 1000) {
        return symbol + NumberFormat.compact(locale: 'en_US').format(val);
      }
      final formatted = NumberFormat.currency(
        locale: 'en_US',
        symbol: '',
        decimalDigits: 2,
      ).format(val);
      return symbol + formatted.trim();
    } catch (_) {
      return input;
    }
  }

  @override
  Widget build(BuildContext context) {
    final display = _formatCompact(amount);
    return Text(
      display,
      style: style,
      textAlign: textAlign ?? TextAlign.right,
    );
  }
}
