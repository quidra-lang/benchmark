import 'dart:math' as math;
import 'distances.dart';

class Merge {
  final int a;
  final int b;
  final double height;
  final int size;
  Merge(this.a, this.b, this.height, this.size);
}
class Edge {
  final int parent;
  final int child;
  final double weight;
  Edge(this.parent, this.child, this.weight);
}
(double, double, double, double) lanceWilliams(String method, int na, int nb, int nk) {
  switch (method) {
    case 'single': return (0.5, 0.5, 0.0, -0.5);
    case 'complete': return (0.5, 0.5, 0.0, 0.5);
    case 'average': return (na / (na + nb), nb / (na + nb), 0.0, 0.0);
    case 'weighted': return (0.5, 0.5, 0.0, 0.0);
    case 'centroid':
      final merged = na + nb;
      return (na / merged, nb / merged, -(na * nb) / (merged * merged), 0.0);
    case 'median': return (0.5, 0.5, -0.25, 0.0);
  }
  final total = na + nb + nk;
  return ((na + nk) / total, (nb + nk) / total, -nk / total, 0.0);
}
List<Merge> agglomerate(List<List<double>> delta, String method) {
  final count = delta.length;
  final squared = ['centroid', 'median', 'ward'].contains(method);
  final values = floatMatrix(2 * count - 1, 2 * count - 1);
  final sizes = List.filled(2 * count - 1, 0);
  var active = List.generate(count, (i) => i);
  for (var u = 0; u < count; u++) {
    sizes[u] = 1;
    for (var w = 0; w < count; w++) { values[u][w] = squared ? delta[u][w] * delta[u][w] : delta[u][w]; }
  }
  final merges = <Merge>[];
  for (var step = 0; step < count - 1; step++) {
    var a = active[0];
    var b = active[1];
    var best = values[a][b];
    for (var position = 0; position < active.length; position++) {
      for (var next = position + 1; next < active.length; next++) {
        final u = active[position];
        final w = active[next];
        if (values[u][w] < best) {
          a = u;
          b = w;
          best = values[u][w];
        }
      }
    }
    final node = count + step;
    sizes[node] = sizes[a] + sizes[b];
    merges.add(Merge(a, b, squared ? math.sqrt(best) : best, sizes[node]));
    for (final k in active) {
      if (k == a || k == b) continue;
      final (aa, ab, beta, gamma) = lanceWilliams(method, sizes[a], sizes[b], sizes[k]);
      final value = aa * values[a][k] + ab * values[b][k] + beta * values[a][b] + gamma * (values[a][k] - values[b][k]).abs();
      values[node][k] = value;
      values[k][node] = value;
    }
    active = [for (final id in active) if (id != a && id != b) id, node];
  }
  return merges;
}
List<Edge> minimumSpanningTree(List<List<double>> delta) {
  final count = delta.length;
  final inTree = List.filled(count, false);
  inTree[0] = true;
  final key = List<double>.of(delta[0]);
  final parent = List.filled(count, 0);
  final edges = <Edge>[];
  for (var step = 0; step < count - 1; step++) {
    var chosen = -1;
    for (var u = 0; u < count; u++) { if (!inTree[u] && (chosen < 0 || key[u] < key[chosen])) chosen = u; }
    inTree[chosen] = true;
    edges.add(Edge(parent[chosen], chosen, key[chosen]));
    for (var u = 0; u < count; u++) {
      if (!inTree[u] && delta[chosen][u] < key[u]) {
        key[u] = delta[chosen][u];
        parent[u] = chosen;
      }
    }
  }
  return edges;
}
