import 'dart:math' as math;
import 'minstd.dart';

int sumIntegers(Iterable<int> values) => values.fold(0, (total, value) => total + value);
double sequentialSum(Iterable<double> values) => values.fold(0.0, (total, value) => total + value);
List<int> orderedIntegers(List<int> values) => values.toList()..sort();
List<double> orderedReals(List<double> values) => values.toList()..sort();
double mean(List<int> values) => sumIntegers(values) / (100 * values.length);

int doubledMedian(List<int> values) {
  final ordered = orderedIntegers(values), count = values.length;
  return ordered[(count - 1) ~/ 2] + ordered[count ~/ 2];
}

double median(List<int> values) => doubledMedian(values) / 200;

double trimmedMean(List<int> values) {
  final ordered = orderedIntegers(values), count = values.length, trim = count ~/ 10;
  return sumIntegers(ordered.sublist(trim, count - trim)) / (100 * (count - 2 * trim));
}

double sd(List<int> values) {
  final center = mean(values);
  var squares = 0.0;
  for (final value in values) {
    final deviation = value / 100 - center;
    squares += deviation * deviation;
  }
  return math.sqrt(squares / (values.length - 1));
}

(double, double, double) centralMoments(List<int> values) {
  final center = mean(values);
  var second = 0.0, third = 0.0, fourth = 0.0;
  for (final value in values) {
    final e = value / 100 - center;
    second += e * e;
    third += e * e * e;
    fourth += e * e * e * e;
  }
  return (second / values.length, third / values.length, fourth / values.length);
}

double mad(List<int> values) {
  final center = doubledMedian(values);
  return doubledMedian([for (final value in values) (2 * value - center).abs()]) / 400;
}

int quantileNumerator(List<int> values, int percent) {
  final ordered = orderedIntegers(values), position = (values.length - 1) * percent;
  final index = position ~/ 100, fraction = position % 100;
  return 100 * ordered[index] + (fraction == 0 ? 0 : fraction * (ordered[index + 1] - ordered[index]));
}

List<int> winsorized(List<int> values) {
  final ordered = orderedIntegers(values), trim = values.length ~/ 10;
  final low = ordered[trim], high = ordered[values.length - trim - 1];
  return [for (final value in values) math.min(math.max(value, low), high)];
}

double meanDifference(List<int> x, List<int> y) =>
    (y.length * sumIntegers(x) - x.length * sumIntegers(y)) / (100 * x.length * y.length);
double medianRatio(List<int> x, List<int> y) => doubledMedian(x) / doubledMedian(y);
double hodgesLehmann(List<int> x, List<int> y) => doubledMedian([for (final first in x) for (final second in y) first - second]) / 200;

double pooledSD(List<int> x, List<int> y) {
  final first = sd(x), second = sd(y);
  final squares = (x.length - 1) * first * first + (y.length - 1) * second * second;
  return math.sqrt(squares / (x.length + y.length - 2));
}

double cohenD(List<int> x, List<int> y) => meanDifference(x, y) / pooledSD(x, y);

double correlation(List<int> x, List<int> y) {
  final firstCenter = mean(x), secondCenter = mean(y);
  var products = 0.0, firstSquares = 0.0, secondSquares = 0.0;
  for (var index = 0; index < x.length; index++) {
    final e = x[index] / 100 - firstCenter, f = y[index] / 100 - secondCenter;
    products += e * f;
    firstSquares += e * e;
    secondSquares += f * f;
  }
  return products / math.sqrt(firstSquares * secondSquares);
}

List<int> resampleIndices(Minstd generator, int size) => [for (var index = 0; index < size; index++) generator.below(size)];
List<List<int>> ordinaryIndices(Minstd generator, int size, int count) => [for (var index = 0; index < count; index++) resampleIndices(generator, size)];

List<List<int>> balancedIndices(Minstd generator, int size, int count) {
  final sequence = List.generate(size * count, (index) => index % size);
  generator.shuffle(sequence);
  return [for (var index = 0; index < count; index++) sequence.sublist(index * size, (index + 1) * size)];
}

List<int> without(List<int> values, int index) => [...values.take(index), ...values.skip(index + 1)];

(double, double) meanAndSE(List<double> values) {
  final average = sequentialSum(values) / values.length;
  var squares = 0.0;
  for (final value in values) {
    final d = value - average;
    squares += d * d;
  }
  return (average, math.sqrt(squares / (values.length - 1)));
}

double phi(double x) {
  if (x < 0) return 1 - phi(-x);
  final eta = 1 / (1 + 0.2316419 * x);
  final psi = eta * (0.319381530 + eta * (-0.356563782 + eta * (1.781477937 + eta * (-1.821255978 + eta * 1.330274429))));
  return 1 - 0.3989422804014327 * math.exp(-(x * x) / 2) * psi;
}

double phiInverse(double p) {
  if (p > 0.5) return -phiInverse(1 - p);
  final eta = math.sqrt(-2 * math.log(p));
  final numerator = 2.515517 + eta * (0.802853 + eta * 0.010328);
  final denominator = 1 + eta * (1.432788 + eta * (0.189269 + eta * 0.001308));
  return -(eta - numerator / denominator);
}
