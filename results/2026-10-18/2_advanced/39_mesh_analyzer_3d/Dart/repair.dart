part of 'main.dart';

class Face {
  final int triangle, polygon, line;
  final String group;
  List<int> vertices;
  Face(this.triangle, this.polygon, this.line, this.group, this.vertices);
  Face copy([List<int>? replacement]) =>
      Face(triangle, polygon, line, group, replacement ?? [...vertices]);
}

List<Face> splitPolygons(List<Polygon> polygons) {
  final triangles = <Face>[];
  for (final p in polygons) {
    for (var i = 1; i < p.vertices.length - 1; i++) {
      triangles.add(
        Face(triangles.length + 1, p.number, p.line, p.group, [
          p.vertices[0],
          p.vertices[i],
          p.vertices[i + 1],
        ]),
      );
    }
  }
  return triangles;
}

int floorDiv(int a, int b) => a ~/ b - (a < 0 && a.remainder(b) != 0 ? 1 : 0);
(List<Vec>, List<(int, Vec, Vec)>) snappedVertices(
  List<Vec> vertices,
  int spacing,
) {
  final points = <Vec>[(0, 0, 0)], changed = <(int, Vec, Vec)>[];
  for (var i = 1; i < vertices.length; i++) {
    final p = vertices[i],
        rounded = (
          spacing * floorDiv(2 * p.$1 + spacing, 2 * spacing),
          spacing * floorDiv(2 * p.$2 + spacing, 2 * spacing),
          spacing * floorDiv(2 * p.$3 + spacing, 2 * spacing),
        );
    points.add(rounded);
    if (p != rounded) changed.add((i, p, rounded));
  }
  return (points, changed);
}

List<int> representatives(List<Vec> points, bool merge) {
  final owner = <Vec, int>{}, result = List.filled(points.length, 0);
  for (var i = 1; i < points.length; i++) {
    result[i] = merge ? owner.putIfAbsent(points[i], () => i) : i;
  }
  return result;
}

(List<Face>, List<(Face, String)>) cleanedFaces(
  List<Face> triangles,
  List<Vec> points,
  List<int> representative,
  bool removeZero,
  bool removeDuplicate,
) {
  final faces = <Face>[], removed = <(Face, String)>[], seen = <String>{};
  for (final triangle in triangles) {
    final vertices = triangle.vertices.map((v) => representative[v]).toList();
    String? reason;
    if (vertices.toSet().length < 3) {
      reason = 'repeated';
    } else if (removeZero &&
        cross(
              subtract(points[vertices[1]], points[vertices[0]]),
              subtract(points[vertices[2]], points[vertices[0]]),
            ) ==
            (0, 0, 0)) {
      reason = 'zero_area';
    }
    if (reason == null) {
      final ordered = [...vertices]..sort();
      final key = ordered.join(',');
      if (removeDuplicate && seen.contains(key)) {
        reason = 'duplicate';
      } else {
        seen.add(key);
      }
    }
    if (reason != null) {
      removed.add((triangle, reason));
    } else {
      faces.add(triangle.copy(vertices));
    }
  }
  return (faces, removed);
}

(List<Vec>, List<Face>, Map<int, int>) remapVertices(
  List<Vec> snapped,
  List<int> representative,
  List<Face> faces,
  bool keepUnused,
) {
  final present = <int>{};
  if (keepUnused) {
    for (var i = 1; i < representative.length; i++) {
      if (representative[i] == i) present.add(i);
    }
  } else {
    for (final f in faces) {
      present.addAll(f.vertices);
    }
  }
  final old = present.toList()..sort(),
      points = <Vec>[(0, 0, 0)],
      renumber = <int, int>{};
  for (final v in old) {
    renumber[v] = points.length;
    points.add(snapped[v]);
  }
  final mapped = faces
      .map((f) => f.copy(f.vertices.map((v) => renumber[v]!).toList()))
      .toList();
  return (points, mapped, renumber);
}

(List<Face>, List<Face>) fillLoops(
  List<Face> faces,
  List<BoundaryLoop> loops,
  int maxLength,
  Set<int> permitted,
) {
  final added = <Face>[];
  for (final loop in loops) {
    final vertices = loop.vertices, length = loop.length;
    if (loop.kind != 'coherent' ||
        length < 3 ||
        length > maxLength ||
        vertices.toSet().length != length ||
        !permitted.contains(loop.component))
      continue;
    for (var i = 2; i < length; i++) {
      added.add(
        Face(0, 0, 0, 'fill', [vertices[0], vertices[i], vertices[i - 1]]),
      );
    }
    loop.filled = true;
  }
  return ([...faces, ...added], added);
}
