import 'dart:math' as math;

void main() {
  const values = [72, 85, 64, 90, 85, 58, 77, 85, 69, 93, 71];
  final sorted = values.toList()..sort();
  final mean = values.reduce((a, b) => a + b) / values.length;
  var squares = 0.0;
  for (final v in values) {
    final d = v - mean;
    squares += d * d;
  }
  var mode = sorted.first, best = 0;
  for (final v in sorted.toSet()) {
    final count = values.where((x) => x == v).length;
    if (count > best) {
      best = count;
      mode = v;
    }
  }
  print(
    'mean: ${mean.toStringAsFixed(3)}\nmedian: ${sorted[values.length ~/ 2]}\nmode: $mode\nrange: ${sorted.last - sorted.first}\nstdev: ${math.sqrt(squares / values.length).toStringAsFixed(3)}',
  );
}
