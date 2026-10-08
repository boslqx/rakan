/// 12450 → "12,450" (rounded to a whole number).
String formatThousands(num value) {
  final digits = value.round().toString();
  final out = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// A weight without a pointless decimal: 20.0 → "20", 22.5 → "22.5".
String formatKg(double weight) => weight == weight.roundToDouble()
    ? weight.toStringAsFixed(0)
    : weight.toStringAsFixed(1);
