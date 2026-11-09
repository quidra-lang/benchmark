String dec(int numerator, int denominator, int places) {
  if (denominator == 0) return '-'; var scale = 1; for (var j = 0; j < places; j++) { scale *= 10; }
  final value = (2 * numerator * scale + denominator) ~/ (2 * denominator); return '${value ~/ scale}.${(value % scale).toString().padLeft(places, '0')}';
}
String frac(int numerator, int denominator) { if (denominator == 0) return '-'; final divisor = numerator.gcd(denominator); return '${numerator ~/ divisor}/${denominator ~/ divisor}'; }
int percentile(List<int> times, int q) => times[(q * times.length + 99) ~/ 100 - 1];
List<String> histogramLines(List<int> times, int width) {
  final first = times.first ~/ width, counts = List.filled(times.last ~/ width - times.first ~/ width + 1, 0);
  for (final time in times) { counts[time ~/ width - first]++; } var peak = 0; for (final count in counts) { if (count > peak) peak = count; }
  final lines = <String>[];
  for (var j = 0; j < counts.length; j++) { final low = (first + j) * width, stars = (80 * counts[j] + peak) ~/ (2 * peak); lines.add('  $low-${low + width - 1} ${counts[j]}${stars > 0 ? ' ${'*' * stars}' : ''}'); } return lines;
}
