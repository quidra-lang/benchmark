part of 'main.dart';

List<int> positions(List<List<int>> orders, int count) {
  final out = List.filled(count, 0);
  for (final row in orders) {
    for (var i = 0; i < row.length; i++) {
      out[row[i]] = i;
    }
  }
  return out;
}

int gapCrossings(
  List<Segment> segments,
  List<int> indices,
  List<int> pos,
  int width,
) {
  final pairs =
      [
        for (final index in indices)
          (pos[segments[index].upper], pos[segments[index].lower]),
      ]..sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c != 0 ? c : a.$2.compareTo(b.$2);
      });
  var capacity = 1;
  while (capacity < width) {
    capacity *= 2;
  }
  final tree = List.filled(2 * capacity - 1, 0);
  var crossings = 0;
  for (final pair in pairs) {
    var k = pair.$2 + capacity - 1;
    tree[k]++;
    while (k > 0) {
      if (k % 2 == 1) crossings += tree[k + 1];
      k = (k - 1) ~/ 2;
      tree[k]++;
    }
  }
  return crossings;
}

int totalCrossings(Layout g, List<List<int>> orders) {
  final pos = positions(orders, g.vertices.length);
  var sum = 0;
  for (var i = 0; i < g.gaps.length; i++) {
    sum += gapCrossings(g.segments, g.gaps[i], pos, orders[i + 1].length);
  }
  return sum;
}

int bruteCrossings(Layout g, List<List<int>> orders, bool countEdges) {
  final pos = positions(orders, g.vertices.length);
  var sum = 0;
  for (final indices in g.gaps) {
    for (var i = 0; i < indices.length; i++) {
      final a = g.segments[indices[i]];
      for (final other in indices.skip(i + 1)) {
        final b = g.segments[other];
        if ((pos[a.upper] - pos[b.upper]) * (pos[a.lower] - pos[b.lower]) < 0) {
          sum++;
          if (countEdges) {
            g.edges[a.edge].crossings++;
            g.edges[b.edge].crossings++;
          }
        }
      }
    }
  }
  return sum;
}

int adjacentCost(Layout g, int v, int w, List<int> pos) {
  var count = 0;
  for (var side = 0; side < 2; side++) {
    final a = side == 0 ? g.vertices[v].upper : g.vertices[v].lower,
        b = side == 0 ? g.vertices[w].upper : g.vertices[w].lower;
    for (final u in a) {
      for (final q in b) {
        if (pos[u] > pos[q]) count++;
      }
    }
  }
  return count;
}
