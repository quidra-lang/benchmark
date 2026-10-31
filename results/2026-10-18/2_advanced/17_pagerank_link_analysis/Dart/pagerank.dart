typedef WeightedEdge = (int, int);
class PageRankResult {
  final List<double> values, changes;
  final int? convergedAt;
  PageRankResult(this.values, this.changes, this.convergedAt);
}
PageRankResult powerIteration(List<List<WeightedEdge>> inEdges, List<int> teleport,
    double damping, int iterations, double tolerance) {
  final count = inEdges.length, outWeight = List.filled(inEdges.length, 0);
  for (final edges in inEdges) {
    for (final (source, weight) in edges) {
      outWeight[source] += weight;
    }
  }
  final inTeleport = List.filled(count, false);
  for (final node in teleport) {
    inTeleport[node] = true;
  }
  var values = [for (var node = 0; node < count; node++) inTeleport[node] ? 1 / teleport.length : 0.0];
  final changes = <double>[];
  int? convergedAt;
  for (var step = 1; step <= iterations; step++) {
    var mass = 0.0;
    for (var node = 0; node < count; node++) {
      if (outWeight[node] == 0) mass += values[node];
    }
    final base = ((1 - damping) + damping * mass) / teleport.length;
    final updated = <double>[];
    var change = 0.0;
    for (var node = 0; node < count; node++) {
      var inflow = 0.0;
      for (final (source, weight) in inEdges[node]) {
        inflow += values[source] * weight / outWeight[source];
      }
      updated.add(inTeleport[node] ? damping * inflow + base : damping * inflow);
      change += (updated[node] - values[node]).abs();
    }
    changes.add(change);
    if (convergedAt == null && change < tolerance) convergedAt = step;
    values = updated;
  }
  return PageRankResult(values, changes, convergedAt);
}
