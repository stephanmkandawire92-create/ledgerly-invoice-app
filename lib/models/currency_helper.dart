import 'package:intl/intl.dart';

class CurrencyInfo {
  final String code;
  final String symbol;
  final String name;

  const CurrencyInfo({
    required this.code,
    required this.symbol,
    required this.name,
  });
}

class CurrencyHelper {
  static const List<CurrencyInfo> currencies = [
    CurrencyInfo(code: 'USD', symbol: '\$', name: 'US Dollar (\$)'),
    CurrencyInfo(code: 'EUR', symbol: '€', name: 'Euro (€)'),
    CurrencyInfo(code: 'GBP', symbol: '£', name: 'British Pound (£)'),
    CurrencyInfo(code: 'ZAR', symbol: 'R', name: 'South African Rand (R)'),
    CurrencyInfo(code: 'CAD', symbol: 'CA\$', name: 'Canadian Dollar (CA\$)'),
    CurrencyInfo(code: 'AUD', symbol: 'A\$', name: 'Australian Dollar (A\$)'),
    CurrencyInfo(code: 'JPY', symbol: '¥', name: 'Japanese Yen (¥)'),
    CurrencyInfo(code: 'CNY', symbol: '¥', name: 'Chinese Yuan (¥)'),
    CurrencyInfo(code: 'INR', symbol: '₹', name: 'Indian Rupee (₹)'),
    CurrencyInfo(code: 'BRL', symbol: 'R\$', name: 'Brazilian Real (R\$)'),
    CurrencyInfo(code: 'MXN', symbol: 'Mex\$', name: 'Mexican Peso (Mex\$)'),
    CurrencyInfo(code: 'CHF', symbol: 'CHF', name: 'Swiss Franc (CHF)'),
    CurrencyInfo(code: 'SGD', symbol: 'S\$', name: 'Singapore Dollar (S\$)'),
    CurrencyInfo(code: 'NZD', symbol: 'NZ\$', name: 'New Zealand Dollar (NZ\$)'),
    CurrencyInfo(code: 'HKD', symbol: 'HK\$', name: 'Hong Kong Dollar (HK\$)'),
    CurrencyInfo(code: 'SEK', symbol: 'kr', name: 'Swedish Krona (kr)'),
    CurrencyInfo(code: 'NOK', symbol: 'kr', name: 'Norwegian Krone (kr)'),
    CurrencyInfo(code: 'AED', symbol: 'AED', name: 'UAE Dirham (AED)'),
    CurrencyInfo(code: 'SAR', symbol: 'SAR', name: 'Saudi Riyal (SAR)'),
    CurrencyInfo(code: 'NGN', symbol: '₦', name: 'Nigerian Naira (₦)'),
    CurrencyInfo(code: 'KES', symbol: 'KSh', name: 'Kenyan Shilling (KSh)'),
    CurrencyInfo(code: 'GHS', symbol: 'GH₵', name: 'Ghanaian Cedi (GH₵)'),
    CurrencyInfo(code: 'EGP', symbol: 'E£', name: 'Egyptian Pound (E£)'),
    CurrencyInfo(code: 'TRY', symbol: '₺', name: 'Turkish Lira (₺)'),
    CurrencyInfo(code: 'RUB', symbol: '₽', name: 'Russian Ruble (₽)'),
    CurrencyInfo(code: 'KRW', symbol: '₩', name: 'South Korean Won (₩)'),
    CurrencyInfo(code: 'THB', symbol: '฿', name: 'Thai Baht (฿)'),
    CurrencyInfo(code: 'IDR', symbol: 'Rp', name: 'Indonesian Rupiah (Rp)'),
    CurrencyInfo(code: 'MYR', symbol: 'RM', name: 'Malaysian Ringgit (RM)'),
    CurrencyInfo(code: 'PHP', symbol: '₱', name: 'Philippine Peso (₱)'),
    CurrencyInfo(code: 'PKR', symbol: 'Rs', name: 'Pakistani Rupee (Rs)'),
    CurrencyInfo(code: 'PLN', symbol: 'zł', name: 'Polish Zloty (zł)'),
    CurrencyInfo(code: 'ILS', symbol: '₪', name: 'Israeli New Shekel (₪)'),
    CurrencyInfo(code: 'CLP', symbol: 'CLP\$', name: 'Chilean Peso (CLP\$)'),
    CurrencyInfo(code: 'COP', symbol: 'COP\$', name: 'Colombian Peso (COP\$)'),
    CurrencyInfo(code: 'PEN', symbol: 'S/', name: 'Peruvian Sol (S/)'),
    CurrencyInfo(code: 'TWD', symbol: 'NT\$', name: 'New Taiwan Dollar (NT\$)'),
  ];

  static CurrencyInfo getInfo(String code) {
    return currencies.firstWhere(
      (c) => c.code.toUpperCase() == code.toUpperCase(),
      orElse: () => CurrencyInfo(code: code, symbol: code, name: code),
    );
  }

  static String format(double amount, String currencyCode) {
    final info = getInfo(currencyCode);
    try {
      final formatted = NumberFormat('#,##0.00', 'en_US').format(amount);
      return '${info.symbol} $formatted';
    } catch (_) {
      return '${info.symbol} ${amount.toStringAsFixed(2)}';
    }
  }
}
