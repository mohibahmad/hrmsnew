import '../services/preferences_service.dart';

String formatMoney(double amount, String symbol) {
  return '$symbol${amount.toStringAsFixed(0)}';
}

class CurrencyUtils {
  CurrencyUtils._();

  /// Returns a plain number string without a trailing ".0".
  /// e.g. 50000.0 -> "50000", "50000.5" -> "50000.5", 50000 -> "50000".
  static String amountText(dynamic value) {
    final text = (value ?? '').toString().trim();
    if (RegExp(r'^-?\d+\.0+$').hasMatch(text)) {
      return text.replaceAll(RegExp(r'\.0+$'), '');
    }
    return text;
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
    'en': ['USD', 'EUR', 'GBP', 'JPY', 'INR', 'PKR', 'CAD', 'AUD', 'SAR', 'AED', 'QAR', 'KWD', 'OMR', 'RUB', 'BRL'],
    'es': ['EUR', 'USD', 'GBP', 'JPY', 'INR', 'PKR', 'CAD', 'AUD', 'SAR', 'AED', 'QAR', 'KWD', 'OMR', 'RUB', 'BRL'],
    'fr': ['EUR', 'USD', 'GBP', 'JPY', 'INR', 'PKR', 'CAD', 'AUD', 'SAR', 'AED', 'QAR', 'KWD', 'OMR', 'RUB', 'BRL'],
    'pt': ['BRL', 'EUR', 'USD', 'GBP', 'JPY', 'INR', 'PKR', 'CAD', 'AUD', 'SAR', 'AED', 'QAR', 'KWD', 'OMR', 'RUB'],
    'ru': ['RUB', 'EUR', 'USD', 'GBP', 'JPY', 'INR', 'PKR', 'CAD', 'AUD', 'SAR', 'AED', 'QAR', 'KWD', 'OMR', 'BRL'],
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
}
