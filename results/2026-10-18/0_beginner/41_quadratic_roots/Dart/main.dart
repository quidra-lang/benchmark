import 'dart:io';
import 'dart:math' as math;

void main() {
  final out = StringBuffer();
  for (final s in [
    [1, -3, -10],
    [-2, 5, 4],
    [3, 1, -2],
    [4, -12, 9],
    [1, 2, 5],
    [-2, 3, -4],
  ]) {
    final a = s[0], b = s[1], c = s[2], disc = b * b - 4 * a * c;
    final numerator = -b.toDouble(), denominator = 2.0 * a;
    out.write('$a $b $c: ');
    if (disc > 0) {
      final r1 = (numerator + math.sqrt(disc)) / denominator,
          r2 = (numerator - math.sqrt(disc)) / denominator;
      out.write(
        'x1 = ${math.max(r1, r2).toStringAsFixed(4)}, x2 = ${math.min(r1, r2).toStringAsFixed(4)}',
      );
    } else if (disc == 0) {
      out.write('x = ${(numerator / denominator).toStringAsFixed(4)}');
    } else {
      final p = numerator / denominator, q = math.sqrt(-disc) / (2 * a.abs());
      out.write(
        'x = ${p.toStringAsFixed(4)} + ${q.toStringAsFixed(4)}i, ${p.toStringAsFixed(4)} - ${q.toStringAsFixed(4)}i',
      );
    }
    out.writeln();
  }
  stdout.write(out);
}
