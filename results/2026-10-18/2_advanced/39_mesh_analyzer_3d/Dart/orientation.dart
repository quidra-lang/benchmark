part of 'main.dart';

bool hasDirected(List<int> triangle, int start, int end) =>
    triangleEdges(triangle).contains((start, end));
void flip(Face f) {
  final temp = f.vertices[1];
  f.vertices[1] = f.vertices[2];
  f.vertices[2] = temp;
}

List<Edge> inconsistentEdges(
  List<Face> faces,
  Map<Edge, List<int>> edges,
  List<Edge> order,
) => [
  for (final e in order)
    if (edges[e]!.length == 2 &&
        hasDirected(faces[edges[e]![0] - 1].vertices, e.$1, e.$2) ==
            hasDirected(faces[edges[e]![1] - 1].vertices, e.$1, e.$2))
      e,
];
void repairOrientation(List<Face> faces, Map<Edge, List<int>> edges) {
  final visited = <int>{};
  for (var seed = 1; seed <= faces.length; seed++) {
    if (!visited.add(seed)) continue;
    final queue = [seed];
    for (var head = 0; head < queue.length; head++) {
      final current = queue[head];
      for (final (u, v) in triangleEdges(faces[current - 1].vertices)) {
        final adjacent = edges[keyEdge(u, v)]!;
        if (adjacent.length != 2) continue;
        final other = adjacent[0] == current ? adjacent[1] : adjacent[0];
        if (visited.contains(other)) continue;
        if (hasDirected(faces[other - 1].vertices, u, v))
          flip(faces[other - 1]);
        visited.add(other);
        queue.add(other);
      }
    }
  }
}

Map<int, bool> orientableComponents(List<Face> faces, Mesh mesh) {
  final copied = faces.map((f) => f.copy()).toList();
  repairOrientation(copied, mesh.edges);
  final violations = inconsistentEdges(
    copied,
    mesh.edges,
    mesh.edgeOrder,
  ).toSet();
  return {
    for (final c in mesh.components)
      c.number: !c.edges.any(violations.contains),
  };
}
