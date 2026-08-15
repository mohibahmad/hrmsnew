import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/preferences_service.dart';

String formatMoney(double amount, String symbol) {
  return '$symbol${amount.toStringAsFixed(0)}';
}

class CurrencyUtils {
  CurrencyUtils._();

  static String amountText(dynamic value) {
    final text = (value ?? '').toString().trim();
    if (RegExp(r'^-?\d+\.0+$').hasMatch(text)) {
      return text.replaceAll(RegExp(r'\.0+$'), '');
    }
    return text;
  }

  static String formatWithCommas(dynamic value) {
    if (value == null) return '';
    final clean = amountText(value).replaceAll(',', '');
    if (clean.isEmpty) return '';
    final parts = clean.split('.');
    final intPart = parts[0];
    final parsed = int.tryParse(intPart);
    if (parsed == null) return clean;
    final formattedInt = NumberFormat('#,##0', 'en_US').format(parsed);
    return parts.length > 1 ? '$formattedInt.${parts[1]}' : formattedInt;
  }

  static const String defaultCode = 'USD';

  static String get companyCurrency =>
      PreferencesService.cachedCompanyCurrency ?? defaultCode;

  static String formatMoney(double amount, String symbol) {
    return '$symbol${amount.toStringAsFixed(0)}';
  }

  static const List<String> commonCodes = [
    'USD',
    'EUR',
    'GBP',
    'PKR',
    'INR',
    'AED',
  ];

  static const List<String> supportedCodes = [
    'USD',
    'EUR',
    'GBP',
    'JPY',
    'INR',
    'PKR',
    'RUB',
    'BRL',
    'SAR',
    'AED',
    'CAD',
    'AUD',
    'QAR',
    'KWD',
    'OMR',
  ];

  static const Map<String, List<String>> localeCurrencies = {
    'en': [
      'USD',
      'EUR',
      'GBP',
      'JPY',
      'INR',
      'PKR',
      'CAD',
      'AUD',
      'SAR',
      'AED',
      'QAR',
      'KWD',
      'OMR',
      'RUB',
      'BRL',
    ],
    'es': [
      'EUR',
      'USD',
      'GBP',
      'JPY',
      'INR',
      'PKR',
      'CAD',
      'AUD',
      'SAR',
      'AED',
      'QAR',
      'KWD',
      'OMR',
      'RUB',
      'BRL',
    ],
    'fr': [
      'EUR',
      'USD',
      'GBP',
      'JPY',
      'INR',
      'PKR',
      'CAD',
      'AUD',
      'SAR',
      'AED',
      'QAR',
      'KWD',
      'OMR',
      'RUB',
      'BRL',
    ],
    'pt': [
      'BRL',
      'EUR',
      'USD',
      'GBP',
      'JPY',
      'INR',
      'PKR',
      'CAD',
      'AUD',
      'SAR',
      'AED',
      'QAR',
      'KWD',
      'OMR',
      'RUB',
    ],
    'ru': [
      'RUB',
      'EUR',
      'USD',
      'GBP',
      'JPY',
      'INR',
      'PKR',
      'CAD',
      'AUD',
      'SAR',
      'AED',
      'QAR',
      'KWD',
      'OMR',
      'BRL',
    ],
  };

  static const Map<String, String> _symbols = {
    'USD': r'$',
    'EUR': '€',
    'GBP': '£',
    'JPY': '¥',
    'INR': '₹',
    'PKR': 'PKR',
    'RUB': '₽',
    'BRL': r'R$',
    'SAR': '﷼',
    'AED': 'د.إ',
    'CAD': r'CA$',
    'AUD': r'A$',
    'QAR': 'ر.ق',
    'KWD': 'د.ك',
    'OMR': 'ر.ع.',
  };

  static bool isSupported(dynamic value) {
    final code = value?.toString().trim().toUpperCase() ?? '';
    return supportedCodes.contains(code);
  }

  static String normalize(dynamic value) {
    final code = value?.toString().trim().toUpperCase() ?? '';
    return supportedCodes.contains(code) ? code : companyCurrency;
  }

  static String symbolFor(dynamic value) =>
      _symbols[normalize(value)] ?? _symbols[companyCurrency]!;

  static String formatCompactLocale(
    double value,
    String locale, {
    required String symbol,
  }) {
    final lang = locale.toLowerCase().split('_').first;
    final abs = value.abs();

    double unit;
    String suffix;
    if (abs >= 1e12) {
      unit = 1e12;
      suffix = switch (lang) {
        'ru' => 'трлн',
        'es' => 'B',
        'fr' => 'Bi',
        'pt' => 'tri',
        _ => 'T',
      };
    } else if (abs >= 1e9) {
      unit = 1e9;
      suffix = switch (lang) {
        'ru' => 'млрд',
        'es' => 'B',
        'fr' => 'Md',
        'pt' => 'bi',
        _ => 'B',
      };
    } else if (abs >= 1e6) {
      unit = 1e6;
      suffix = switch (lang) {
        'ru' => 'млн',
        'es' => 'M',
        'fr' => 'M',
        'pt' => 'mi',
        _ => 'M',
      };
    } else if (abs >= 1e3) {
      unit = 1e3;
      suffix = switch (lang) {
        'ru' => 'тыс.',
        'es' => 'mil',
        'fr' => 'k',
        'pt' => 'mil',
        _ => 'K',
      };
    } else {
      unit = 1;
      suffix = '';
    }

    final scaled = unit == 1 ? value : value / unit;
    String numberPart;
    try {
      numberPart = NumberFormat('0.##', locale).format(scaled);
    } catch (_) {
      numberPart = scaled.toStringAsFixed(2);
      if (numberPart.contains('.')) {
        numberPart = numberPart
            .replaceAll(RegExp(r'0+$'), '')
            .replaceAll(RegExp(r'\.$'), '');
      }
    }

    numberPart = numberPart.replaceFirst(RegExp(r'[,.]0+$'), '');
    if (suffix.isEmpty) return '$symbol$numberPart';

    return lang == 'en'
        ? '$symbol$numberPart$suffix'
        : '$symbol$numberPart $suffix';
  }
}

class CommaCurrencyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final clean = newValue.text.replaceAll(',', '');

    if (clean.isEmpty) return const TextEditingValue(text: '');

    if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(clean)) return oldValue;

    final dotIdx = clean.indexOf('.');
    final intPart = dotIdx == -1 ? clean : clean.substring(0, dotIdx);
    final decPart = dotIdx == -1 ? '' : clean.substring(dotIdx);

    final buf = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    final formatted = buf.toString() + decPart;

    int cleanCursor = 0;
    final cursorLimit = newValue.selection.baseOffset.clamp(
      0,
      newValue.text.length,
    );
    for (int i = 0; i < cursorLimit; i++) {
      if (newValue.text[i] != ',') cleanCursor++;
    }

    int newPos = 0;
    int cleanCount = 0;
    for (int i = 0; i < formatted.length && cleanCount < cleanCursor; i++) {
      newPos++;
      if (formatted[i] != ',') cleanCount++;
    }
    newPos = newPos.clamp(0, formatted.length);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newPos),
    );
  }
}
