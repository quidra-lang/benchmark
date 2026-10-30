part of 'main.dart';

class BKVariant {
  final String name;
  final List<int> root, aligned;
  final int blocks;
  int width = 0, low = 0, high = 0;
  BKVariant(this.name, this.root, this.blocks, int count)
    : aligned = List.filled(count, 0);
}

class Coordinates {
  final Set<(int, int)> marked = {};
  final List<BKVariant> variants = [];
  int smallest = 0;
}

(int, int) segmentKey(int a, int b) => a < b ? (a, b) : (b, a);
int separation(Layout g, int a, int b) =>
    g.vertices[a].right +
    g.vertices[b].left +
    1 +
    (a < g.n && b < g.n ? g.block.settings.nodeSep : g.block.settings.dummySep);
int floorDiv(int a, int b) {
  var q = a ~/ b;
  if (a < 0 && a % b != 0) q--;
  return q;
}

Coordinates coordinates(Layout g) {
  final result = Coordinates(),
      count = g.vertices.length,
      pos = positions(g.orders, g.vertices.length);
  for (var i = 0; i + 1 < g.orders.length; i++) {
    final upper = g.orders[i], lower = g.orders[i + 1];
    var k0 = 0, start = 0;
    for (var end = 0; end < lower.length; end++) {
      final v = lower[end],
          inner = v >= g.n && g.vertices[v].upper.first >= g.n;
      if (!inner && end != lower.length - 1) continue;
      final k1 = inner ? pos[g.vertices[v].upper.first] : upper.length - 1;
      for (final w in lower.sublist(start, end + 1)) {
        for (final u in g.vertices[w].upper) {
          if (pos[u] < k0 || pos[u] > k1) result.marked.add(segmentKey(u, w));
        }
      }
      start = end + 1;
      k0 = k1;
    }
  }
  for (final name in ['ul', 'ur', 'dl', 'dr']) {
    final right = name[1] == 'r',
        down = name[0] == 'd',
        root = List.generate(count, (i) => i),
        align = List.generate(count, (i) => i);
    int rank(int v) =>
        right ? g.orders[g.vertices[v].layer].length - 1 - pos[v] : pos[v];
    var layerOrder = List.generate(g.orders.length, (i) => i);
    if (down) layerOrder = layerOrder.reversed.toList();
    for (final i in layerOrder.skip(1)) {
      var rho = -1;
      var scan = List<int>.of(g.orders[i]);
      if (right) scan = scan.reversed.toList();
      for (final v in scan) {
        var reference = List<int>.of(
          down ? g.vertices[v].lower : g.vertices[v].upper,
        );
        if (reference.isEmpty) continue;
        reference.sort((a, b) => rank(a).compareTo(rank(b)));
        for (final median in [
          (reference.length - 1) ~/ 2,
          reference.length ~/ 2,
        ]) {
          final u = reference[median];
          if (align[v] == v &&
              !result.marked.contains(segmentKey(u, v)) &&
              rho < rank(u)) {
            align[u] = v;
            root[v] = root[u];
            align[v] = root[v];
            rho = rank(u);
          }
        }
      }
    }
    final constraints = <(int, int), int>{};
    for (final row in g.orders) {
      var scan = List<int>.of(row);
      if (right) scan = scan.reversed.toList();
      for (var i = 0; i + 1 < scan.length; i++) {
        final a = scan[i],
            b = scan[i + 1],
            delta = right ? separation(g, b, a) : separation(g, a, b),
            key = (root[a], root[b]);
        constraints[key] = max(constraints[key] ?? 0, delta);
      }
    }
    final incoming = <int, List<(int, int)>>{},
        outgoing = <int, List<(int, int)>>{},
        keys = constraints.keys.toList()
          ..sort((a, b) {
            final c = a.$1.compareTo(b.$1);
            return c != 0 ? c : a.$2.compareTo(b.$2);
          });
    for (final key in keys) {
      final weight = constraints[key]!;
      outgoing.putIfAbsent(key.$1, () => []).add((key.$2, weight));
      incoming.putIfAbsent(key.$2, () => []).add((key.$1, weight));
    }
    final y1 = <int, int>{}, y2 = <int, int>{};
    int leftmost(int r) {
      final known = y1[r];
      if (known != null) return known;
      var value = 0;
      for (final edge in incoming[r] ?? <(int, int)>[]) {
        value = max(value, leftmost(edge.$1) + edge.$2);
      }
      y1[r] = value;
      return value;
    }

    int rightmost(int r) {
      final known = y2[r];
      if (known != null) return known;
      var value = leftmost(r);
      final edges = outgoing[r] ?? <(int, int)>[];
      if (edges.isNotEmpty) {
        var minimum = 0x7fffffffffffffff;
        for (final edge in edges) {
          minimum = min(minimum, rightmost(edge.$1) - edge.$2);
        }
        value = max(value, minimum);
      }
      y2[r] = value;
      return value;
    }

    final variant = BKVariant(name, root, root.toSet().length, count);
    for (var v = 0; v < count; v++) {
      final x = right ? -rightmost(root[v]) : rightmost(root[v]),
          low = x - g.vertices[v].left,
          high = x + g.vertices[v].right;
      variant.aligned[v] = x;
      if (v == 0 || low < variant.low) variant.low = low;
      if (v == 0 || high > variant.high) variant.high = high;
    }
    variant.width = variant.high - variant.low + 1;
    result.variants.add(variant);
  }
  for (var k = 1; k < 4; k++) {
    if (result.variants[k].width < result.variants[result.smallest].width)
      result.smallest = k;
  }
  final best = result.variants[result.smallest];
  for (final variant in result.variants) {
    final shift = variant.name[1] == 'r'
        ? best.high - variant.high
        : best.low - variant.low;
    for (var v = 0; v < count; v++) {
      variant.aligned[v] += shift;
    }
  }
  for (var v = 0; v < count; v++) {
    final values = [for (final variant in result.variants) variant.aligned[v]]
      ..sort();
    g.vertices[v].x = floorDiv(values[1] + values[2], 2);
  }
  var minimum = g.vertices.first.x - g.vertices.first.left;
  for (final v in g.vertices) {
    minimum = min(minimum, v.x - v.left);
  }
  for (final v in g.vertices) {
    v.x -= minimum;
  }
  return result;
}
