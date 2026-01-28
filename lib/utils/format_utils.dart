/// Formatting utilities - Türkçe para ve sayı formatları
library;

/// Türkçe formatla: 1000.50 → "1.000,50"
String _formatDecimal(num value, {int decimals = 2}) {
  final parts = value.toStringAsFixed(decimals).split('.');
  final intPart = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );
  return parts.length == 2 ? '$intPart,${parts[1]}' : intPart;
}

/// Türk Lirası format: 1000.50 → "₺1.000,50"
String formatTL(num value, {int decimals = 2}) {
  return '₺${_formatDecimal(value.toDouble(), decimals: decimals)}';
}

/// Sayı format: 1000.50 → "1.000,50"
String formatNumber(num value, {int decimals = 2}) {
  return _formatDecimal(value.toDouble(), decimals: decimals);
}

/// Format Decimal: 1000.50 → "1.000,50"
String formatDecimal(num value, {int decimals = 2}) {
  return _formatDecimal(value.toDouble(), decimals: decimals);
}

/// Türkçe formatlanmış string'i double'a çevir: "1.000,50" → 1000.50
double parseFormatted(String text) {
  if (text.trim().isEmpty) return 0;
  final cleaned = text.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(cleaned) ?? 0.0;
}

/// Türkçe formatlanmış string'i int'e çevir: "1.000" → 1000
int parseFormattedInt(String text) {
  return parseFormatted(text).toInt();
}
