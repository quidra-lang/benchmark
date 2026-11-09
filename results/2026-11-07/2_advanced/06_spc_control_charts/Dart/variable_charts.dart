import 'dart:math';
import 'dataset.dart';

int integerSum(Iterable<int> values) => values.fold(0, (sum, value) => sum + value);
double realSum(Iterable<double> values) => values.fold(0.0, (sum, value) => sum + value);

class Subgroup {
  final List<int> values;
  final int total, range;
  final double mean, sd;
  Subgroup._(this.values, this.total, this.range, this.mean, this.sd);
  factory Subgroup(List<int> values) {
    final n = values.length, total = integerSum(values), squares = integerSum(values.map((x) => x * x));
    return Subgroup._(values, total, values.reduce(max) - values.reduce(min), total / n, sqrt((n * squares - total * total) / (n * (n - 1))));
  }
}

class Limits {
  final double lcl, cl, ucl;
  const Limits(this.lcl, this.cl, this.ucl);
  bool outside(double value) => value < lcl || value > ucl;
}

List<Subgroup> subgroupStatistics(List<int> values, int size) => [for (var start = 0; start < values.length; start += size) Subgroup(values.sublist(start, start + size))];
List<int> movingRanges(List<int> values) => [for (var i = 1; i < values.length; i++) (values[i] - values[i - 1]).abs()];

List<Limits> variableLimits(int family, List<int> points, List<Subgroup> groups, List<int> values, int size) {
  if (family == 2) {
    final selected = points.map((i) => values[i - 1]).toList(), ranges = movingRanges(selected);
    final mean = integerSum(selected) / selected.length, average = integerSum(ranges) / ranges.length, width = 3 * average / controlConstants[0][6];
    return [Limits(mean - width, mean, mean + width), Limits(controlConstants[0][4] * average, average, controlConstants[0][5] * average)];
  }
  final c = controlConstants[size - 2], mean = integerSum(points.map((i) => groups[i - 1].total)) / (points.length * size);
  if (family == 0) {
    final average = integerSum(points.map((i) => groups[i - 1].range)) / points.length;
    return [Limits(mean - c[0] * average, mean, mean + c[0] * average), Limits(c[4] * average, average, c[5] * average)];
  }
  final average = realSum(points.map((i) => groups[i - 1].sd)) / points.length;
  return [Limits(mean - c[1] * average, mean, mean + c[1] * average), Limits(c[2] * average, average, c[3] * average)];
}
