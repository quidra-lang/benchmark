part of 'main.dart';

class Fraction {
  final int n, d;
  const Fraction._(this.n, this.d);
  factory Fraction(int n, [int d = 1]) {
    if (n == 0) return zero;
    if (d < 0) {
      n = -n;
      d = -d;
    }
    final g = n.abs().gcd(d);
    return Fraction._(n ~/ g, d ~/ g);
  }
  Fraction add(Fraction b) => Fraction(n * b.d + b.n * d, d * b.d);
  Fraction sub(Fraction b) => add(b.neg());
  Fraction mul(Fraction b) => Fraction(n * b.n, d * b.d);
  Fraction div(Fraction b) => Fraction(n * b.d, d * b.n);
  Fraction neg() => Fraction(-n, d);
  Fraction abs() => n < 0 ? neg() : this;
  int cmp(Fraction b) => (n * b.d).compareTo(b.n * d);
  int floor() => n ~/ d - (n < 0 && n % d != 0 ? 1 : 0);
  int ceil() => -neg().floor();
  bool get whole => d == 1;
  @override
  String toString() => d == 1 ? '$n' : '$n/$d';
  String approx() {
    final t = (2 * n.abs() * 1000000 + d) ~/ (2 * d),
        sign = n < 0 && t > 0 ? '-' : '';
    return '$sign${t ~/ 1000000}.${(t % 1000000).toString().padLeft(6, '0')}';
  }
}

const zero = Fraction._(0, 1), one = Fraction._(1, 1);
final numberPattern = RegExp(r'^[0-9]+(?:\.[0-9]+|/[0-9]+)?$');
Fraction? readNumber(String word, bool signed) {
  var sign = 1;
  if (signed && word.startsWith('-')) {
    sign = -1;
    word = word.substring(1);
  }
  if (!numberPattern.hasMatch(word)) return null;
  if (word.contains('/')) {
    final a = word.split('/'), d = int.parse(a[1]);
    return d == 0 ? null : Fraction(sign * int.parse(a[0]), d);
  }
  if (word.contains('.')) {
    final a = word.split('.');
    var d = 1;
    for (var i = 0; i < a[1].length; i++) {
      d *= 10;
    }
    return Fraction(sign * int.parse(a.join()), d);
  }
  return Fraction(sign * int.parse(word));
}

String boundText(Fraction? value, bool lower) =>
    value?.toString() ?? (lower ? '-inf' : 'inf');
