import 'dart:io';

void main() {
  const values = [48, 73, 56, 91, 35, 62, 84];
  var total = 0;
  for (final value in values) {
    total += value;
  }
  final mean = total / values.length;
  final hundredths = (mean * 100 + 0.5).floor();
  final fraction = (hundredths % 100).toString().padLeft(2, '0');
  stdout.write('${hundredths ~/ 100}.$fraction\n');
}
