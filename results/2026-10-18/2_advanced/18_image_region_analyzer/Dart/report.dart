import 'dart:io';

class Rational implements Comparable<Rational> {
  final int p;
  final int q;
  factory Rational(int numerator, [int denominator = 1]) {
    var first = numerator.abs();
    var second = denominator;
    while (second != 0) {
      final remainder = first % second;
      first = second;
      second = remainder;
    }
    return Rational._(numerator ~/ first, denominator ~/ first);
  }
  const Rational._(this.p, this.q);
  @override
  int compareTo(Rational other) => (p * other.q).compareTo(other.p * q);
}

String decimal(Rational value, int digits) {
  var scale = 1;
  for (var i = 0; i < digits; i++) {
    scale *= 10;
  }
  final rounded = (2 * scale * value.p.abs() + value.q) ~/ (2 * value.q);
  final sign = value.p < 0 && rounded > 0 ? '-' : '';
  return '$sign${rounded ~/ scale}.${(rounded % scale).toString().padLeft(digits, '0')}';
}

String hullAreaText(int doubled) => '${doubled ~/ 2}.${doubled.isEven ? 0 : 5}';

void writeFiles(String directory, Map<String, List<String>> files) {
  Directory(directory).createSync(recursive: true);
  for (final entry in files.entries) {
    File('$directory/${entry.key}').writeAsStringSync('${entry.value.join('\n')}\n');
  }
}
