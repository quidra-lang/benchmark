part of 'main.dart';

class Rational {
  final BigInt numerator, denominator;
  factory Rational(BigInt n, BigInt d) {
    if (d.isNegative) {
      n = -n;
      d = -d;
    }
    final g = n.gcd(d);
    return Rational._(n ~/ g, d ~/ g);
  }
  Rational._(this.numerator, this.denominator);
  Rational add(Rational b) => Rational(
    numerator * b.denominator + b.numerator * denominator,
    denominator * b.denominator,
  );
  Rational sub(Rational b) => Rational(
    numerator * b.denominator - b.numerator * denominator,
    denominator * b.denominator,
  );
  Rational mul(Rational b) =>
      Rational(numerator * b.numerator, denominator * b.denominator);
  Rational div(Rational b) =>
      Rational(numerator * b.denominator, denominator * b.numerator);
  int compare(Rational b) =>
      (numerator * b.denominator).compareTo(b.numerator * denominator);
  int get sign => numerator.sign;
  double get real => numerator.toDouble() / denominator.toDouble();
  int round() {
    final n = BigInt.from(2) * numerator + denominator,
        d = BigInt.from(2) * denominator;
    var q = n ~/ d;
    if (n.isNegative && n % d != BigInt.zero) q -= BigInt.one;
    return q.toInt();
  }

  @override
  bool operator ==(Object b) =>
      b is Rational && numerator == b.numerator && denominator == b.denominator;
  @override
  int get hashCode => Object.hash(numerator, denominator);
  @override
  String toString() =>
      denominator == BigInt.one ? '$numerator' : '$numerator/$denominator';
}

Rational rational(int n) => Rational(BigInt.from(n), BigInt.one);
Rational ratio(int n, int d) => Rational(BigInt.from(n), BigInt.from(d));

class Point {
  final Rational x, y;
  Point(this.x, this.y);
  @override
  bool operator ==(Object other) =>
      other is Point && x == other.x && y == other.y;
  @override
  int get hashCode => Object.hash(x, y);
  @override
  String toString() => '($x,$y)';
}

Point point(int x, int y) => Point(rational(x), rational(y));
int pointCompare(Point a, Point b) {
  final c = a.y.compare(b.y);
  return c != 0 ? c : a.x.compare(b.x);
}

Rational cross(Point o, Point a, Point b) =>
    a.x.sub(o.x).mul(b.y.sub(o.y)).sub(a.y.sub(o.y).mul(b.x.sub(o.x)));
Point along(Point a, Point b, Rational t) =>
    Point(a.x.add(t.mul(b.x.sub(a.x))), a.y.add(t.mul(b.y.sub(a.y))));
String segmentText(Point a, Point b) => '$a-$b';
