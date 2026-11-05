/// Amounts are integers in minor units (paise, cents) to avoid rounding errors.
class Currency {
  final String code;
  final String symbol;
  const Currency(this.code, this.symbol);

  static const all = [
    Currency('INR', '₹'),
    Currency('USD', r'$'),
    Currency('EUR', '€'),
    Currency('GBP', '£'),
    Currency('AED', 'AED '),
    Currency('THB', '฿'),
    Currency('SGD', r'S$'),
  ];

  static Currency of(String code) => all.firstWhere((c) => c.code == code, orElse: () => Currency(code, '$code '));
}

String formatMoney(int minor, String currency) {
  final c = Currency.of(currency);
  final neg = minor < 0;
  final abs = minor.abs();
  final units = abs ~/ 100;
  final cents = abs % 100;
  final grouped = units.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${neg ? '-' : ''}${c.symbol}$grouped${cents == 0 ? '' : '.${cents.toString().padLeft(2, '0')}'}';
}

/// "500", "499.5", "1,200.75" → minor units; null when invalid.
int? parseMoney(String input) {
  final s = input.replaceAll(',', '').replaceAll(' ', '').trim();
  final m = RegExp(r'^(\d{1,10})(?:\.(\d{1,2}))?$').firstMatch(s);
  if (m == null) return null;
  final units = int.parse(m.group(1)!);
  final frac = m.group(2) == null ? 0 : int.parse(m.group(2)!.padRight(2, '0'));
  final v = units * 100 + frac;
  return v == 0 ? null : v;
}

/// Splits [amount] equally; the leftover paise go to the first members
/// (sorted by id) so every phone computes the same split.
Map<String, int> equalSplit(int amount, Iterable<String> memberIds) {
  final ids = memberIds.toSet().toList()..sort();
  if (ids.isEmpty) return const {};
  final base = amount ~/ ids.length;
  var rest = amount - base * ids.length;
  return {
    for (final id in ids) id: base + (rest-- > 0 ? 1 : 0),
  };
}
