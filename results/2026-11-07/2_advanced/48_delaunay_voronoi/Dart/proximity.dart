part of 'main.dart';

class DisjointSets {
  final List<int> parent, size;
  int count;
  DisjointSets(int n)
    : parent = List.generate(n + 1, (i) => i),
      size = List.filled(n + 1, 1),
      count = n;
  int find(int site) {
    while (parent[site] != site) {
      parent[site] = parent[parent[site]];
      site = parent[site];
    }
    return site;
  }

  bool union(int a, int b) {
    a = find(a);
    b = find(b);
    if (a == b) {
      return false;
    }
    if (size[a] < size[b]) {
      final old = a;
      a = b;
      b = old;
    }
    parent[b] = a;
    size[a] += size[b];
    count--;
    return true;
  }
}

List<int> nearestNeighbors(List<Point> points, List<List<int>> neighbors) {
  final nearest = List.filled(points.length, 0);
  for (var s = 1; s < points.length; s++) {
    var best = neighbors[s].first;
    for (final t in neighbors[s].skip(1)) {
      final a = d2(points[s], points[t]), b = d2(points[s], points[best]);
      if (a < b || a == b && t < best) {
        best = t;
      }
    }
    nearest[s] = best;
  }
  return nearest;
}

List<List<int>> nearestComponents(List<int> nearest) {
  final sets = DisjointSets(nearest.length - 1), groups = <int, List<int>>{};
  for (var s = 1; s < nearest.length; s++) {
    sets.union(s, nearest[s]);
  }
  for (var s = 1; s < nearest.length; s++) {
    groups.putIfAbsent(sets.find(s), () => []).add(s);
  }
  return groups.values.toList()..sort((a, b) => a.first.compareTo(b.first));
}

List<Edge> kruskal(List<Point> points, List<Edge> edges) {
  final ordered = List<Edge>.of(edges)
    ..sort((a, b) {
      final c = d2(
        points[a.$1],
        points[a.$2],
      ).compareTo(d2(points[b.$1], points[b.$2]));
      return c != 0 ? c : compareEdges(a, b);
    });
  final sets = DisjointSets(points.length - 1), adopted = <Edge>[];
  for (final edge in ordered) {
    if (sets.union(edge.$1, edge.$2)) {
      adopted.add(edge);
      if (sets.count == 1) {
        break;
      }
    }
  }
  return adopted;
}

bool isGabriel(List<Point> points, Edge edge, Map<Edge, int> directed) {
  for (final d in [edge, (edge.$2, edge.$1)]) {
    final q = directed[d];
    if (q != null && dot(points[q], points[edge.$1], points[edge.$2]) <= 0) {
      return false;
    }
  }
  return true;
}

bool isRelativeNeighbor(List<Point> points, Edge edge) {
  final length = d2(points[edge.$1], points[edge.$2]);
  for (final p in points.skip(1)) {
    if (d2(points[edge.$1], p) < length && d2(points[edge.$2], p) < length) {
      return false;
    }
  }
  return true;
}

(List<int>, double) greedyRoute(
  List<Point> points,
  List<List<int>> neighbors,
  int start,
  int target,
) {
  final path = <int>[start];
  var length = 0.0, current = start;
  while (current != target) {
    var best = neighbors[current].first;
    for (final t in neighbors[current].skip(1)) {
      final a = d2(points[t], points[target]),
          b = d2(points[best], points[target]);
      if (a < b || a == b && t < best) {
        best = t;
      }
    }
    length += sqrt(d2(points[current], points[best]));
    path.add(best);
    current = best;
  }
  return (path, length);
}

class ShortestPaths {
  final List<double> distances;
  final List<int> previous;
  ShortestPaths(this.distances, this.previous);
}

ShortestPaths dijkstra(
  List<Point> points,
  List<List<int>> neighbors,
  int start,
) {
  final n = points.length,
      distances = List.filled(points.length, double.infinity),
      previous = List.filled(points.length, 0),
      visited = List.filled(points.length, false);
  distances[start] = 0;
  for (var step = 1; step < n; step++) {
    var site = 0;
    for (var i = 1; i < n; i++) {
      if (!visited[i] && (site == 0 || distances[i] < distances[site])) {
        site = i;
      }
    }
    if (site == 0) {
      break;
    }
    visited[site] = true;
    for (final other in neighbors[site]) {
      final candidate = distances[site] + sqrt(d2(points[site], points[other]));
      if (candidate < distances[other]) {
        distances[other] = candidate;
        previous[other] = site;
      }
    }
  }
  return ShortestPaths(distances, previous);
}
