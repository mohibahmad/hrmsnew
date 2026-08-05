class CurrencyUtils {
  CurrencyUtils._();

  static const String defaultCode = 'USD';

  /// Short list of the most commonly used currencies, shown in dropdowns that
  /// should not overwhelm the user with every supported option.
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
