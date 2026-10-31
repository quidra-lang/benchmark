import 'baskets.dart';

class Fraction implements Comparable<Fraction> {
  final int numerator, denominator;
  Fraction._(this.numerator, this.denominator);
  factory Fraction(int numerator, [int denominator = 1]) {
    if (denominator < 0) { numerator = -numerator; denominator = -denominator; }
    var a = numerator.abs(), b = denominator;
    while (b != 0) { final remainder = a % b; a = b; b = remainder; }
    return Fraction._(numerator ~/ a, denominator ~/ a);
  }
  factory Fraction.parse(String text) { final fields = text.split('/'); return Fraction(int.parse(fields[0]), int.parse(fields[1])); }
  @override
  int compareTo(Fraction other) => (numerator * other.denominator).compareTo(other.numerator * denominator);
  Fraction operator -(Fraction other) => Fraction(numerator * other.denominator - other.numerator * denominator, denominator * other.denominator);
  Fraction times(int numerator, [int denominator = 1]) => Fraction(this.numerator * numerator, this.denominator * denominator);
}

class Rule {
  final Itemset itemset, antecedent, consequent;
  final int count;
  final Fraction support, confidence, lift, leverage;
  final Fraction? conviction;
  Fraction improvement = Fraction(0);
  int rank = 0;
  Rule(this.itemset, this.antecedent, this.consequent, this.count, int total, int first, int second)
      : support = Fraction(count, total), confidence = Fraction(count, first), lift = Fraction(total * count, first * second),
        leverage = Fraction(total * count - first * second, total * total), conviction = first == count ? null : Fraction((total - second) * first, total * (first - count));
}

bool meetsThresholds(Fraction confidence, Fraction lift, Fraction minConfidence, Fraction minLift) => confidence.compareTo(minConfidence) >= 0 && lift.compareTo(minLift) >= 0;
int compareRules(Rule a, Rule b) {
  for (final comparison in [b.confidence.compareTo(a.confidence), b.lift.compareTo(a.lift), b.count.compareTo(a.count), compareSets(a.antecedent, b.antecedent), compareSets(a.consequent, b.consequent)]) { if (comparison != 0) return comparison; }
  return 0;
}
