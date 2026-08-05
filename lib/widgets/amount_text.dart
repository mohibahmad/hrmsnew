import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AmountText extends StatelessWidget {
  final String amount;
  final TextStyle? style;
  final TextAlign? textAlign;

  const AmountText(this.amount, {super.key, this.style, this.textAlign});

  /// Extracts the currency prefix (everything before the first digit) from a
  /// formatted amount. Unlike the old regex, this keeps multi-character
  /// symbols intact (e.g. 'د.إ', 'ر.ع.', 'CA$') instead of truncating them at
  /// the first '.'. The prefix is also excluded from numeric parsing so a
  /// symbol's dot (as in 'د.إ') never turns 5000 into 0.5.
  static String _numericPart(String input) {
    final trimmed = input.trim();
    final firstDigit = RegExp(r'\d').firstMatch(trimmed);
    if (firstDigit == null) return trimmed;
    final sign = trimmed.startsWith('-') ? '-' : '';
    return sign + trimmed.substring(firstDigit.start);
  }
  static String _extractSymbol(String input) {
    final trimmed = input.trim();
    if (trimmed.startsWith('-')) {
      final stripped = trimmed.substring(1).trimLeft();
      final firstDigit = RegExp(r'\d').firstMatch(stripped);
      return firstDigit == null ? '' : stripped.substring(0, firstDigit.start).trim();
    }
    final firstDigit = RegExp(r'\d').firstMatch(trimmed);
    return firstDigit == null ? '' : trimmed.substring(0, firstDigit.start).trim();
  }

  static String formatCompact(String input) {
    try {
      if (input.trim().isEmpty) return '0';
      if (RegExp(r'[KMBTkmbt]$').hasMatch(input.trim())) {
        return input;
      }
      final cleaned = _numericPart(input).replaceAll(RegExp(r"[^0-9.\-]"), '');
      if (cleaned.isEmpty) return '0';
      final val = double.tryParse(cleaned);
      if (val == null) return input;
      final symbol = _extractSymbol(input);
      final abs = val.abs();
      if (abs >= 1e12) return '$symbol${(val / 1e12).toStringAsFixed(1)}T';
      if (abs >= 1e9) return '$symbol${(val / 1e9).toStringAsFixed(1)}B';
      if (abs >= 1e6) return '$symbol${(val / 1e6).toStringAsFixed(1)}M';
      if (abs >= 1e3) return '$symbol${(val / 1e3).toStringAsFixed(1)}K';
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

  static String formatFull(String input) {
    try {
      if (input.trim().isEmpty) return '0';
      final cleaned = _numericPart(input).replaceAll(RegExp(r"[^0-9.\-]"), '');
      if (cleaned.isEmpty) return '0';
      final val = double.tryParse(cleaned);
      if (val == null) return input;
      final symbol = _extractSymbol(input);
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
