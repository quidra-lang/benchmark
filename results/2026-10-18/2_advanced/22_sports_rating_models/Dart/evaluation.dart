import 'dart:math' as math;
import 'report.dart';

double sigma(double value) => 1 / (1 + math.exp(-value));
(double, double) fitLink(List<double> features, List<double> results, int iterations) {
  var alpha = 0.0;
  var beta = 0.0;
  for (var iteration = 0; iteration < iterations; iteration++) {
    var g0 = 0.0;
    var g1 = 0.0;
    var h00 = 0.0;
    var h01 = 0.0;
    var h11 = 0.0;
    for (var k = 0; k < features.length; k++) {
      final z = features[k];
      final p = sigma(alpha + beta * z);
      final w = p * (1 - p);
      g0 += results[k] - p;
      g1 += (results[k] - p) * z;
      h00 += w;
      h01 += w * z;
      h11 += w * z * z;
    }
    final det = h00 * h11 - h01 * h01;
    final nextAlpha = alpha + (h11 * g0 - h01 * g1) / det;
    beta += (h00 * g1 - h01 * g0) / det;
    alpha = nextAlpha;
  }
  return (alpha, beta);
}

double logLoss(double p, int result2) {
  if (result2 == 2) return -math.log(p);
  if (result2 == 0) return -math.log(1 - p);
  return -(math.log(p) / 2 + math.log(1 - p) / 2);
}
double brierScore(double p, double y) => (p - y) * (p - y);
int correctness2(double p, int result2) {
  if (result2 == 1) return 1;
  return p > 0.5 && result2 == 2 || p < 0.5 && result2 == 0 ? 2 : 0;
}

List<int> averageRanks2(List<Fraction> values) => [
  for (final value in values)
    2 * values.where((other) => other.compareTo(value) > 0).length +
        values.where((other) => other.compareTo(value) == 0).length + 1
];

Fraction kendallTau(List<Fraction> first, List<Fraction> second) {
  var balance = 0;
  for (var t = 0; t < first.length; t++) {
    for (var u = t + 1; u < first.length; u++) {
      final agreement = first[t].compareTo(first[u]) * second[t].compareTo(second[u]);
      if (agreement > 0) balance++;
      if (agreement < 0) balance--;
    }
  }
  return Fraction(balance, first.length * (first.length - 1) ~/ 2);
}

Fraction spearmanRho(List<Fraction> first, List<Fraction> second) {
  final a = averageRanks2(first);
  final b = averageRanks2(second);
  var squares = 0;
  for (var i = 0; i < a.length; i++) {
    final difference = a[i] - b[i];
    squares += difference * difference;
  }
  final denominator = 4 * a.length * (a.length * a.length - 1);
  return Fraction(denominator - 6 * squares, denominator);
}
