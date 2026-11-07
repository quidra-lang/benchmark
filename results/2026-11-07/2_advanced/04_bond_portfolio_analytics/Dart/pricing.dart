const basisPoint = 0.0001;
double bisection(double Function(double) function, double low, double high, double target) {
  for (var step = 0; step < 80; step++) { final middle = (low + high) / 2; if (function(middle) > target) low = middle; else high = middle; }
  return (low + high) / 2;
}
class Risk {
  final double macaulay, modified, convexity, dv01;
  Risk(this.macaulay, this.modified, this.convexity, this.dv01);
}
class YieldPricer {
  final List<int> flows;
  final double fraction;
  final int frequency, outstanding;
  YieldPricer(this.flows, this.fraction, this.frequency, this.outstanding);
  List<double> values(double rate) {
    final first = 1 + fraction * rate / frequency, growth = 1 + rate / frequency;
    var factor = 1.0;
    final values = <double>[];
    for (final flow in flows) { values.add(flow / (first * factor)); factor *= growth; }
    return values;
  }
  double dirty(double rate) { var sum = 0.0; for (final value in values(rate)) sum += value; return sum * 100 / outstanding; }
  double solve(double target) => bisection(dirty, 0.0, 1.0, target);
  bool inRange(double target) => dirty(0.0) > target && target > dirty(1.0);
  Risk risk(double rate) {
    final growth = 1 + rate / frequency, present = values(rate);
    var total = 0.0, weighted = 0.0, curvature = 0.0;
    for (var index = 0; index < present.length; index++) { final years = (index + fraction) / frequency, value = present[index]; total += value; weighted += years * value; curvature += years * (years + 1 / frequency) * value; }
    final macaulay = weighted / total;
    return Risk(macaulay, macaulay / growth, curvature / (total * growth * growth), (dirty(rate - basisPoint) - dirty(rate + basisPoint)) / 2);
  }
}
