import 'dart:math' as math;
import 'distances.dart';

double correlation(List<double> xs, List<double> ys) {
  final mx = sequentialSum(xs) / xs.length;
  final my = sequentialSum(ys) / ys.length;
  var xy = 0.0;
  var xx = 0.0;
  var yy = 0.0;
  for (var i = 0; i < xs.length; i++) {
    final dx = xs[i] - mx;
    final dy = ys[i] - my;
    xy += dx * dy;
    xx += dx * dx;
    yy += dy * dy;
  }
  return xy / math.sqrt(xx * yy);
}
List<List<int>> contingencyTable(List<int> first, List<int> second, int rows, int columns) {
  final table = List.generate(rows, (_) => List.filled(columns, 0));
  for (var i = 0; i < first.length; i++) { table[first[i]][second[i]]++; }
  return table;
}
class Fraction {
  final int p;
  final int q;
  Fraction(this.p, this.q);
  double get value => p / q;
  bool greater(Fraction other) => p * other.q > other.p * q;
}
int pairCount(int value) => value * (value - 1) ~/ 2;
Fraction adjustedRandIndex(List<List<int>> table) {
  var count = 0;
  var same = 0;
  var rowPairs = 0;
  var columnPairs = 0;
  final columns = List.filled(table[0].length, 0);
  for (final row in table) {
    var total = 0;
    for (var j = 0; j < row.length; j++) {
      total += row[j];
      same += pairCount(row[j]);
      columns[j] += row[j];
    }
    count += total;
    rowPairs += pairCount(total);
  }
  for (final total in columns) { columnPairs += pairCount(total); }
  final total = pairCount(count);
  var p = 2 * (total * same - rowPairs * columnPairs);
  var q = total * (rowPairs + columnPairs) - 2 * rowPairs * columnPairs;
  if (q == 0) return Fraction(1, 1);
  if (q < 0) {
    p = -p;
    q = -q;
  }
  final divisor = p.abs().gcd(q);
  return Fraction(p ~/ divisor, q ~/ divisor);
}
List<double> silhouetteValues(List<int> partition, int groups, List<List<double>> delta) {
  final sizes = List.filled(groups + 1, 0);
  for (final number in partition) { sizes[number]++; }
  final values = List.filled(partition.length, 0.0);
  for (var i = 0; i < partition.length; i++) {
    final own = partition[i];
    if (sizes[own] == 1) continue;
    final sums = List.filled(groups + 1, 0.0);
    for (var j = 0; j < partition.length; j++) { if (j != i) sums[partition[j]] += delta[i][j]; }
    final inner = sums[own] / (sizes[own] - 1);
    var outer = double.infinity;
    for (var g = 1; g <= groups; g++) { if (g != own) outer = math.min(outer, sums[g] / sizes[g]); }
    values[i] = (outer - inner) / math.max(inner, outer);
  }
  return values;
}
