import 'dart:math' as math;
import 'kmeans.dart';

List<List<double>> distanceTable(List<List<double>> points) {
  final table = List.generate(points.length, (_) => List.filled(points.length, 0.0));
  for (var first = 0; first < points.length; first++) {
    for (var second = first + 1; second < points.length; second++) {
      table[first][second] = math.sqrt(squaredDistance(points[first], points[second]));
      table[second][first] = table[first][second];
    }
  }
  return table;
}

List<double> silhouettes(List<List<double>> table, List<int> labels, List<int> sizes) {
  final values = List.filled(labels.length, 0.0);
  for (var index = 0; index < labels.length; index++) {
    final own = labels[index];
    if (sizes[own] == 1) continue;
    final totals = List.filled(sizes.length, 0.0);
    for (var other = 0; other < labels.length; other++) {
      if (index != other) totals[labels[other]] += table[index][other];
    }
    final inner = totals[own] / (sizes[own] - 1);
    var outer = double.infinity;
    for (var segment = 0; segment < sizes.length; segment++) {
      if (segment != own) outer = math.min(outer, totals[segment] / sizes[segment]);
    }
    final largest = math.max(inner, outer);
    values[index] = largest == 0 ? 0 : (outer - inner) / largest;
  }
  return values;
}

double calinskiHarabasz(List<List<double>> points, List<List<double>> centers, List<int> sizes, double within) {
  final overall = meanPoint(points);
  var between = 0.0;
  for (var index = 0; index < centers.length; index++) {
    between += sizes[index] * squaredDistance(centers[index], overall);
  }
  return (between / (centers.length - 1)) / (within / (points.length - centers.length));
}

double daviesBouldin(List<List<double>> points, List<int> labels, List<List<double>> centers, List<int> sizes) {
  final spreads = List.filled(centers.length, 0.0);
  for (var index = 0; index < points.length; index++) {
    spreads[labels[index]] += math.sqrt(squaredDistance(points[index], centers[labels[index]]));
  }
  for (var index = 0; index < centers.length; index++) {
    spreads[index] /= sizes[index];
  }
  var total = 0.0;
  for (var first = 0; first < centers.length; first++) {
    var worst = 0.0;
    for (var second = 0; second < centers.length; second++) {
      if (first != second) {
        worst = math.max(worst, (spreads[first] + spreads[second]) / math.sqrt(squaredDistance(centers[first], centers[second])));
      }
    }
    total += worst;
  }
  return total / centers.length;
}

double elbow(int k, int first, int last, double within, double withinFirst, double withinLast) {
  final x = (k - first) / (last - first), y = (within - withinLast) / (withinFirst - withinLast);
  return ((1 - x) - y) / math.sqrt(2);
}
double hartigan(double within, double next, int count, int k) => (within / next - 1) * (count - k - 1);
int pairCount(int size) => size * (size - 1) ~/ 2;

double adjustedRand<X, Y>(List<X> first, List<Y> second) {
  final joint = <(X, Y), int>{}, xs = <X, int>{}, ys = <Y, int>{};
  for (var index = 0; index < first.length; index++) {
    final a = first[index], b = second[index];
    joint[(a, b)] = (joint[(a, b)] ?? 0) + 1;
    xs[a] = (xs[a] ?? 0) + 1;
    ys[b] = (ys[b] ?? 0) + 1;
  }
  final z = pairCount(first.length);
  int pairs(Iterable<int> values) => values.fold(0, (total, value) => total + pairCount(value));
  final shared = pairs(joint.values), sx = pairs(xs.values), sy = pairs(ys.values);
  final numerator = 2 * (z * shared - sx * sy), denominator = z * (sx + sy) - 2 * sx * sy;
  return denominator == 0 ? 1 : numerator / denominator;
}
