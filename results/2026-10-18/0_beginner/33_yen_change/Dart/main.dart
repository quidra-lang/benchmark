import 'dart:io';

void main() {
  final out = StringBuffer();
  const denominations = [10000, 5000, 1000, 500, 100, 50, 10, 5, 1];
  for (final amount in [3780, 15420, 99999, 506, 48263]) {
    var remaining = amount, total = 0;
    out.write('$amount yen:');
    for (final denom in denominations) {
      final count = remaining ~/ denom;
      remaining %= denom;
      total += count;
      if (count > 0) out.write(' ${denom}x$count');
    }
    out.writeln(' ($total pieces)');
  }
  stdout.write(out);
}
