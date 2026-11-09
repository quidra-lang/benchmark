part of 'main.dart';

typedef Edge = (int, int);
List<Edge> triangleEdges(List<int> v) => [
  (v[0], v[1]),
  (v[1], v[2]),
  (v[2], v[0]),
];
Edge keyEdge(int a, int b) => (math.min(a, b), math.max(a, b));
int compareEdges(Edge a, Edge b) =>
    a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2);
(Map<Edge, List<int>>, List<Edge>) edgeTable(List<Face> faces) {
  final edges = <Edge, List<int>>{};
  for (var i = 0; i < faces.length; i++) {
    for (final (u, v) in triangleEdges(faces[i].vertices)) {
      edges.putIfAbsent(keyEdge(u, v), () => []).add(i + 1);
    }
  }
  final order = edges.keys.toList()..sort(compareEdges);
  return (edges, order);
}

List<List<int>> connectedComponents(
  List<int> ids,
  Map<int, Set<int>> neighbors,
) {
  final unseen = ids.toSet(), components = <List<int>>[];
  for (final seed in ids) {
    if (!unseen.remove(seed)) continue;
    final queue = [seed];
    for (var head = 0; head < queue.length; head++) {
      final others = (neighbors[queue[head]] ?? <int>{}).toList()..sort();
      for (final other in others) {
        if (unseen.remove(other)) queue.add(other);
      }
    }
    queue.sort();
    components.add(queue);
  }
  return components;
}

List<List<int>> vertexFans(
  int vertex,
  List<Face> faces,
  Map<Edge, List<int>> edges,
  List<Edge> order,
) {
  final ids = [
        for (var i = 0; i < faces.length; i++)
          if (faces[i].vertices.contains(vertex)) i + 1,
      ],
      neighbors = <int, Set<int>>{};
  for (final e in order) {
    if (e.$1 != vertex && e.$2 != vertex) continue;
    for (final first in edges[e]!) {
      neighbors
          .putIfAbsent(first, () => {})
          .addAll(edges[e]!.where((second) => first != second));
    }
  }
  return connectedComponents(ids, neighbors);
}

class TopologyComponent {
  final int number;
  final List<int> faces, vertices;
  final edges = <Edge>[],
      boundary = <Edge>[],
      nonmanifold = <Edge>[],
      nonmanifoldVertices = <int>[];
  TopologyComponent(this.number, this.faces, this.vertices);
}

class Mesh {
  final Map<Edge, List<int>> edges;
  final List<Edge> edgeOrder;
  final components = <TopologyComponent>[],
      faceComponents = <int, int>{},
      fans = <int, List<List<int>>>{},
      nonmanifoldVertices = <int>[];
  Mesh(this.edges, this.edgeOrder);
}

Mesh analyzeMesh(List<Face> faces) {
  final (edges, order) = edgeTable(faces);
  final m = Mesh(edges, order),
      ids = List.generate(faces.length, (i) => i + 1),
      neighbors = <int, Set<int>>{};
  for (final adjacent in edges.values) {
    for (final a in adjacent) {
      neighbors.putIfAbsent(a, () => {}).addAll(adjacent.where((b) => b != a));
    }
  }
  final groups = connectedComponents(ids, neighbors);
  for (var number = 0; number < groups.length; number++) {
    final group = groups[number],
        vertices = {
          for (final id in groups[number]) ...faces[id - 1].vertices,
        }.toList()..sort();
    final c = TopologyComponent(number + 1, group, vertices);
    for (final id in group) {
      m.faceComponents[id] = number + 1;
    }
    for (final e in order) {
      if (m.faceComponents[edges[e]!.first] == number + 1) {
        c.edges.add(e);
        if (edges[e]!.length == 1) {
          c.boundary.add(e);
        } else if (edges[e]!.length >= 3) {
          c.nonmanifold.add(e);
        }
      }
    }
    m.components.add(c);
  }
  final used = {for (final f in faces) ...f.vertices}.toList()..sort();
  for (final v in used) {
    final fans = vertexFans(v, faces, edges, order);
    m.fans[v] = fans;
    if (fans.length >= 2) m.nonmanifoldVertices.add(v);
  }
  for (final c in m.components) {
    for (final v in c.vertices) {
      if (m.fans[v]!
              .where((fan) => m.faceComponents[fan.first] == c.number)
              .length >=
          2)
        c.nonmanifoldVertices.add(v);
    }
  }
  return m;
}

class BoundaryLoop {
  final int number, component, length;
  final List<int> vertices;
  final String kind;
  bool filled = false;
  BoundaryLoop(
    this.number,
    this.component,
    this.length,
    this.vertices,
    this.kind,
  );
}

List<BoundaryLoop> boundaryLoops(List<Face> faces, Mesh m) {
  final loops = <BoundaryLoop>[];
  for (final c in m.components) {
    final unused = c.boundary.toSet();
    for (final first in c.boundary) {
      if (!unused.remove(first)) continue;
      final a = first.$1, b = first.$2, sequence = [first.$1, first.$2];
      var current = b;
      while (current != a) {
        int? other;
        Edge? chosen;
        for (final e in unused) {
          if (e.$1 != current && e.$2 != current) continue;
          final v = e.$1 == current ? e.$2 : e.$1;
          if (other == null || v < other) {
            other = v;
            chosen = e;
          }
        }
        if (other == null) break;
        unused.remove(chosen!);
        sequence.add(other);
        current = other;
      }
      var kind = 'open', length = sequence.length - 1;
      if (sequence.last == a) {
        sequence.removeLast();
        length = sequence.length;
        var count = 0;
        for (var i = 0; i < length; i++) {
          final u = sequence[i],
              v = sequence[(i + 1) % length],
              e = keyEdge(sequence[i], sequence[(i + 1) % length]);
          if (hasDirected(faces[m.edges[e]!.first - 1].vertices, u, v)) count++;
        }
        kind = 'mixed';
        if (count == length) {
          kind = 'coherent';
        } else if (count == 0) {
          kind = 'coherent';
          final rest = sequence.skip(1).toList().reversed.toList();
          sequence.removeRange(1, sequence.length);
          sequence.addAll(rest);
        }
      }
      loops.add(
        BoundaryLoop(loops.length + 1, c.number, length, sequence, kind),
      );
    }
  }
  return loops;
}
