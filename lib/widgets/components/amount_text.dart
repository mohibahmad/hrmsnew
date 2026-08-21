import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hrms/core/utils/utils.dart';

class AmountText extends StatelessWidget {
  final String amount;
  final TextStyle? style;
  final TextAlign? textAlign;

  const AmountText(this.amount, {super.key, this.style, this.textAlign});

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
      return firstDigit == null
          ? ''
          : stripped.substring(0, firstDigit.start).trim();
    }
    final firstDigit = RegExp(r'\d').firstMatch(trimmed);
    return firstDigit == null
        ? ''
        : trimmed.substring(0, firstDigit.start).trim();
  }

  static String _spacingForSymbol(String symbol) {
    if (symbol.isEmpty ||
        symbol.endsWith(' ') ||
        RegExp(r'[$\u00A3\u20AC\u00A5\u20B9]').hasMatch(symbol)) {
      return '';
    }
    return ' ';
  }

  static String formatCompact(String input, {String locale = 'en_US'}) {
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
      final space = _spacingForSymbol(symbol);

      if (abs >= 1e3) {
        final compact = CurrencyUtils.formatCompactLocale(
          val,
          locale,
          symbol: '',
        );
        return symbol.isEmpty ? compact : '$symbol$space$compact';
      }

      final hasDecimals = val != val.roundToDouble();
      final formatted = NumberFormat.currency(
        locale: locale,
        symbol: '',
        decimalDigits: hasDecimals ? 2 : 0,
      ).format(val);

      return symbol.isEmpty
          ? formatted.trim()
          : '$symbol$space${formatted.trim()}';
    } catch (_) {
      return input;
    }
  }

  static String formatFull(String input, {String locale = 'en_US'}) {
    try {
      if (input.trim().isEmpty) return '0';
      final cleaned = _numericPart(input).replaceAll(RegExp(r"[^0-9.\-]"), '');
      if (cleaned.isEmpty) return '0';

      final val = double.tryParse(cleaned);
      if (val == null) return input;

      final symbol = _extractSymbol(input);
      final hasDecimals = val != val.roundToDouble();
      final formatted = NumberFormat.currency(
        locale: locale,
        symbol: '',
        decimalDigits: hasDecimals ? 2 : 0,
      ).format(val.abs());

      final prefix = symbol.isEmpty ? '' : '$symbol ';
      return val < 0
          ? '-$prefix${formatted.trim()}'
          : '$prefix${formatted.trim()}';
    } catch (_) {
      return input;
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final display = formatCompact(amount, locale: locale);

    return Text(
      display,
      style: style,
      textAlign: textAlign ?? TextAlign.right,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
