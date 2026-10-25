import 'dart:math';
import 'dataset.dart';

typedef Neighbor = ({double gap, DataRow row});

double distance(List<double> a, List<double> b, String metric) {
  var total = 0.0, dot = 0.0, squaresA = 0.0, squaresB = 0.0;
  for (var j = 0; j < a.length; j++) {
    final x = a[j], y = b[j], difference = x - y;
    if (metric == 'squared_euclidean') { total += difference * difference; }
    else if (metric == 'manhattan') { total += difference.abs(); }
    else if (metric == 'chebyshev') { total = max(total, difference.abs()); }
    else { dot += x * y; squaresA += x * x; squaresB += y * y; }
  }
  if (metric != 'cosine') return total;
  final normA = sqrt(squaresA), normB = sqrt(squaresB);
  return normA == 0 || normB == 0 ? 1.0 : 1 - dot / (normA * normB);
}

List<Neighbor> sortNeighbors(List<Neighbor> neighbors) => neighbors..sort((a, b) {
  final comparison = a.gap.compareTo(b.gap);
  return comparison == 0 ? a.row.id.compareTo(b.row.id) : comparison;
});

class Tally {
  final String label;
  int count = 0;
  double distance = 0.0, weight = 0.0;
  Tally(this.label);
}

class Prediction {
  final String label;
  final String? runner;
  final double share, runnerShare, estimate;
  final List<Neighbor> neighbors;
  Prediction(this.label, this.share, this.runner, this.runnerShare, this.estimate, this.neighbors);
  factory Prediction.fromOrder(List<Neighbor> order, int k, String weighting, {bool retain = true}) {
    final nearest = order.take(k).toList(), tallies = <String, Tally>{};
    var weightTotal = 0.0, targetTotal = 0.0, weighted = 0.0;
    for (final neighbor in nearest) {
      final weight = 1 / (neighbor.gap + 0.000000001), row = neighbor.row;
      final tally = tallies.putIfAbsent(row.label!, () => Tally(row.label!));
      tally.count++; tally.distance += neighbor.gap; tally.weight += weight; weightTotal += weight;
      targetTotal += row.target!; weighted += weight * row.target!;
    }
    final uniform = weighting == 'uniform', ranked = tallies.values.toList();
    ranked.sort((a, b) {
      var comparison = uniform ? b.count.compareTo(a.count) : b.weight.compareTo(a.weight);
      if (comparison == 0) comparison = a.distance.compareTo(b.distance);
      return comparison == 0 ? a.label.compareTo(b.label) : comparison;
    });
    double share(Tally tally) => uniform ? tally.count / nearest.length : tally.weight / weightTotal;
    return Prediction(ranked.first.label, share(ranked.first), ranked.length > 1 ? ranked[1].label : null, ranked.length > 1 ? share(ranked[1]) : 0.0, uniform ? targetTotal / nearest.length : weighted / weightTotal, retain ? nearest : []);
  }
}
