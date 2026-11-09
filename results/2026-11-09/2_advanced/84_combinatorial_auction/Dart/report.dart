part of 'main.dart';

class Fraction {
  final int numerator, denominator;
  Fraction(this.numerator, this.denominator);
  Fraction add(Fraction b) => fraction(
    numerator * b.denominator + b.numerator * denominator,
    denominator * b.denominator,
  );
  Fraction sub(Fraction b) => fraction(
    numerator * b.denominator - b.numerator * denominator,
    denominator * b.denominator,
  );
  Fraction mul(Fraction b) =>
      fraction(numerator * b.numerator, denominator * b.denominator);
  Fraction div(Fraction b) =>
      fraction(numerator * b.denominator, denominator * b.numerator);
  int compare(Fraction b) =>
      (numerator * b.denominator).compareTo(b.numerator * denominator);
  @override
  String toString() =>
      denominator == 1 ? '$numerator' : '$numerator/$denominator';
}

int gcd(int a, int b) {
  a = a.abs();
  while (b != 0) {
    final r = a % b;
    a = b;
    b = r;
  }
  return a;
}

Fraction fraction(int n, int d) {
  if (d < 0) {
    n = -n;
    d = -d;
  }
  final g = gcd(n, d);
  return Fraction(n ~/ g, d ~/ g);
}

Fraction whole(int n) => Fraction(n, 1);
String bundle(List<Item> items, int mask) {
  final names = [
    for (var i = 0; i < items.length; i++)
      if (mask & (1 << i) != 0) items[i].name,
  ];
  return names.isEmpty ? '-' : names.join('+');
}

String numberList(List<Bid> bids) =>
    bids.isEmpty ? '-' : bids.map((b) => b.number).join('+');
void writeLines(String name, List<String> lines) => File(
  'output/$name',
).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
int compareInts(List<int> a, List<int> b) {
  for (var i = 0; i < min(a.length, b.length); i++) {
    final c = a[i].compareTo(b[i]);
    if (c != 0) return c;
  }
  return a.length.compareTo(b.length);
}

int popcount(int n) {
  var count = 0;
  while (n != 0) {
    n &= n - 1;
    count++;
  }
  return count;
}
