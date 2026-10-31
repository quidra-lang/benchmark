import 'dart:io';

class Fraction implements Comparable<Fraction> {
  final int p;
  final int q;
  factory Fraction(int p, [int q = 1]) {
    if (q < 0) {
      p = -p;
      q = -q;
    }
    final divisor = p.gcd(q);
    return Fraction._(p ~/ divisor, q ~/ divisor);
  }
  Fraction._(this.p, this.q);
  Fraction operator +(Fraction other) {
    final common = q.gcd(other.q);
    return Fraction(p * (other.q ~/ common) + other.p * (q ~/ common),
        (q ~/ common) * other.q);
  }
  Fraction operator *(Fraction other) {
    final x = p.gcd(other.q);
    final y = other.p.gcd(q);
    return Fraction((p ~/ x) * (other.p ~/ y), (q ~/ y) * (other.q ~/ x));
  }
  Fraction dividedBy(int value) => this * Fraction(1, value);
  double get real => p / q;
  @override
  int compareTo(Fraction other) => (p * other.q).compareTo(other.p * q);
  @override
  String toString() => '$p/$q';
}

String fixed(double value, [int places = 4]) {
  final text = value.toStringAsFixed(places);
  return double.parse(text) == 0 && text.startsWith('-') ? text.substring(1) : text;
}

String fixedFraction(Fraction value, [int places = 4]) {
  final numerator = value.p.abs();
  var whole = numerator ~/ value.q;
  var remainder = numerator % value.q;
  var digits = 0;
  var scale = 1;
  for (var i = 0; i < places; i++) {
    remainder *= 10;
    digits = digits * 10 + remainder ~/ value.q;
    remainder %= value.q;
    scale *= 10;
  }
  final last = places == 0 ? whole : digits;
  if (2 * remainder > value.q || 2 * remainder == value.q && last.isOdd) {
    digits++;
    if (digits == scale) {
      whole++;
      digits = 0;
    }
  }
  final sign = value.p < 0 && (whole != 0 || digits != 0) ? '-' : '';
  if (places == 0) return '$sign$whole';
  return '$sign$whole.${digits.toString().padLeft(places, '0')}';
}

String fractionWithReal(Fraction value) => '$value ${fixedFraction(value)}';
int decimalValue(double value, int places) {
  var scale = 1;
  for (var i = 0; i < places; i++) {
    scale *= 10;
  }
  return (value * scale).round();
}
void writeLines(String name, List<String> lines) =>
    File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
