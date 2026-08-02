class CurrencyUtils {
  CurrencyUtils._();

  static const String defaultCode = 'USD';

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

  static const Map<String, String> _symbols = {
    'USD': r'$',
    'EUR': '€',
    'GBP': '£',
    'JPY': '¥',
    'INR': '₹',
    'PKR': 'Rs',
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
    return supportedCodes.contains(code) ? code : defaultCode;
  }

  static String symbolFor(dynamic value) =>
      _symbols[normalize(value)] ?? _symbols[defaultCode]!;
}
