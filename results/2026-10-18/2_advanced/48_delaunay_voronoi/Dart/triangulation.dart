part of 'main.dart';

Triangle canonical(int a, int b, int c) {
  if (b < a && b < c) {
    return (b, c, a);
  }
  if (c < a && c < b) {
    return (c, a, b);
  }
  return (a, b, c);
}

class Insertion {
  final int site, visible, flips, triangles, hull;
  final String kind;
  final Triangle? containing;
  Insertion(
    this.site,
    this.kind,
    this.containing,
    this.visible,
    this.flips,
    this.triangles,
    this.hull,
  );
}

class Triangulation {
  final List<Point> points;
  final directed = <Edge, int>{};
  late final Triangle initial;
  Triangulation(this.points) {
    initial = orient(points[1], points[2], points[3]) > 0
        ? (1, 2, 3)
        : (1, 3, 2);
    add(initial);
  }
  void add(Triangle t) {
    final sites = triangleSites(t), edges = triangleEdges(t);
    for (var i = 0; i < 3; i++) {
      directed[edges[i]] = sites[(i + 2) % 3];
    }
  }

  void remove(Triangle t) {
    for (final edge in triangleEdges(t)) {
      directed.remove(edge);
    }
  }

  List<Triangle> triangles() {
    final result = <Triangle>[];
    for (final entry in directed.entries) {
      final (a, b) = entry.key;
      final c = entry.value;
      if (a < b && a < c) {
        result.add((a, b, c));
      }
    }
    result.sort((a, b) {
      final x = a.$1.compareTo(b.$1), y = a.$2.compareTo(b.$2);
      return x != 0
          ? x
          : y != 0
          ? y
          : a.$3.compareTo(b.$3);
    });
    return result;
  }

  List<Edge> hullEdges() =>
      directed.keys.where((e) => !directed.containsKey((e.$2, e.$1))).toList()
        ..sort(compareEdges);
  Insertion insert(int s) {
    Triangle? containing;
    final pending = <Edge>{};
    for (final t in triangles()) {
      if (triangleEdges(
        t,
      ).every((e) => orient(points[e.$1], points[e.$2], points[s]) > 0)) {
        containing = t;
        remove(t);
        pending.addAll(triangleEdges(t));
        break;
      }
    }
    var visible = 0, flips = 0;
    if (containing == null) {
      for (final (u, v) in hullEdges()) {
        if (orient(points[u], points[v], points[s]) < 0) {
          pending.add((v, u));
        }
      }
      visible = pending.length;
    }
    for (final (a, b) in pending) {
      add((a, b, s));
    }
    while (pending.isNotEmpty) {
      final edge = (pending.toList()..sort(compareEdges)).first;
      pending.remove(edge);
      final (a, b) = edge;
      final q = directed[(b, a)];
      if (q != null &&
          directed[edge] == s &&
          incircle(points[a], points[b], points[s], points[q]) > 0) {
        remove((a, b, s));
        remove((b, a, q));
        add((a, q, s));
        add((q, b, s));
        pending.addAll([(a, q), (q, b)]);
        flips++;
      }
    }
    return Insertion(
      s,
      containing == null ? 'outside' : 'inside',
      containing,
      visible,
      flips,
      directed.length ~/ 3,
      hullEdges().length,
    );
  }

  (List<int>, Edge?) visibilityWalk(
    Point query,
    List<Triangle> triangles,
    Map<Edge, int> edgeTriangles,
  ) {
    final path = <int>[1];
    while (true) {
      var following = 0;
      for (final (u, v) in triangleEdges(triangles[path.last])) {
        if (orient(points[u], points[v], query) < 0) {
          following = edgeTriangles[(v, u)] ?? 0;
          if (following == 0) {
            return (path, orderedEdge(u, v));
          }
          break;
        }
      }
      if (following == 0) {
        return (path, null);
      }
      path.add(following);
    }
  }
}
