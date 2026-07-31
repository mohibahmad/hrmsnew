import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AmountText extends StatelessWidget {
  final String amount;
  final TextStyle? style;
  final TextAlign? textAlign;

  const AmountText(this.amount, {super.key, this.style, this.textAlign});

  static String formatCompact(String input) {
    try {
      if (input.trim().isEmpty) return '0';
      if (RegExp(r'[KMBTkmbt]$').hasMatch(input.trim())) {
        return input;
      }
      final cleaned = input.replaceAll(RegExp(r"[^0-9.\-]"), '');
      if (cleaned.isEmpty) return '0';
      final val = double.tryParse(cleaned);
      if (val == null) return input;
      final symbolMatch = RegExp(r"^\s*([^0-9\s.-]+)").firstMatch(input);
      final symbol = symbolMatch != null ? symbolMatch.group(1) ?? '' : '';
      final abs = val.abs();
      if (abs >= 1e12) return '$symbol${(val / 1e12).toStringAsFixed(1)}T';
      if (abs >= 1e9) return '$symbol${(val / 1e9).toStringAsFixed(1)}B';
      if (abs >= 1e6) return '$symbol${(val / 1e6).toStringAsFixed(1)}M';
      if (abs >= 1e3) return '$symbol${(val / 1e3).toStringAsFixed(1)}K';
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

  static String formatFull(String input) {
    try {
      if (input.trim().isEmpty) return '0';
      final cleaned = input.replaceAll(RegExp(r"[^0-9.\-]"), '');
      if (cleaned.isEmpty) return '0';
      final val = double.tryParse(cleaned);
      if (val == null) return input;
      final symbolMatch = RegExp(r"^\s*([^0-9\s.-]+)").firstMatch(input);
      final symbol = symbolMatch != null ? symbolMatch.group(1) ?? '' : '';
      final hasDecimals = val != val.roundToDouble();
      final formatted = NumberFormat.currency(
        locale: 'en_US',
        symbol: '',
        decimalDigits: hasDecimals ? 2 : 0,
      ).format(val);
      return symbol + formatted.trim();
    } catch (_) {
      return input;
    }
  }

  @override
  Widget build(BuildContext context) {
    final display = formatCompact(amount);
    return Text(
      display,
      style: style,
      textAlign: textAlign ?? TextAlign.right,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
