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
