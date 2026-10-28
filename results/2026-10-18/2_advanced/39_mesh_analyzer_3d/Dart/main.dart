import 'dart:io';
import 'dart:math' as math;
part 'obj_io.dart';
part 'topology.dart';
part 'orientation.dart';
part 'measure.dart';
part 'repair.dart';

List<String> readLines(String path) => File(path).readAsLinesSync();
String yes(bool value) => value ? 'yes' : 'no';
String listing(List<int> values) => values.isEmpty ? '-' : values.join(' ');
String stringList(List<String> values) =>
    values.isEmpty ? '-' : values.join(' ');
String vecText(Vec p) => '${p.$1} ${p.$2} ${p.$3}';
String edgeText(Edge e) => '${e.$1} ${e.$2}';
String optional(int value) => value == 0 ? '-' : '$value';
List<int> sortedInts(Iterable<int> values) => values.toSet().toList()..sort();

class Settings {
  int snap = 1, fillHoles = 0;
  bool merge = true,
      degenerate = true,
      duplicates = true,
      orient = true,
      outward = true,
      keepUnused = true;
  List<String> sections = ['summary', 'components'];
  final queries = <(String, List<int>)>[];
}

Settings readParameters() {
  final s = Settings();
  for (final line in readLines('input/params.txt')) {
    if (line.isEmpty || line.startsWith('#')) continue;
    final words = line.split(' '), key = words[0], args = words.sublist(1);
    switch (key) {
      case 'query':
        s.queries.add((args[0], args.skip(1).map(int.parse).toList()));
      case 'sections':
        s.sections = args;
      case 'snap':
        s.snap = int.parse(args[0]);
      case 'fill_holes':
        s.fillHoles = int.parse(args[0]);
      case 'merge':
        s.merge = args[0] == 'on';
      case 'degenerate':
        s.degenerate = args[0] == 'on';
      case 'duplicates':
        s.duplicates = args[0] == 'on';
      case 'orient':
        s.orient = args[0] == 'on';
      case 'outward':
        s.outward = args[0] == 'on';
      case 'keep_unused':
        s.keepUnused = args[0] == 'on';
    }
  }
  return s;
}

bool polygonNonplanar(Polygon p, List<Vec> snapped) {
  final first = snapped[p.vertices.first];
  var total = (0, 0, 0);
  for (var i = 1; i < p.vertices.length - 1; i++) {
    final n = cross(
      subtract(snapped[p.vertices[i]], first),
      subtract(snapped[p.vertices[i + 1]], first),
    );
    total = (total.$1 + n.$1, total.$2 + n.$2, total.$3 + n.$3);
  }
  return p.vertices.any((v) => dot(subtract(snapped[v], first), total) != 0);
}

String edgeShape(
  Edge edge,
  List<Face> faces,
  List<Vec> points,
  List<int> adjacent,
) {
  if (adjacent.length != 2) return '-';
  final a = edge.$1,
      b = edge.$2,
      first = faces[adjacent[0] - 1],
      second = faces[adjacent[1] - 1];
  if (hasDirected(first.vertices, a, b) == hasDirected(second.vertices, a, b))
    return 'inconsistent';
  final third = second.vertices.firstWhere((v) => v != a && v != b),
      origin = points[first.vertices[0]];
  final signed = dot(subtract(points[third], origin), normal(first, points));
  return signed < 0
      ? 'convex'
      : signed > 0
      ? 'concave'
      : 'flat';
}

bool componentConsistency(TopologyComponent c, List<Edge> inconsistent) {
  final bad = inconsistent.toSet();
  return !c.edges.any(bad.contains);
}

Map<int, bool> preliminarySolids(List<Face> faces, Mesh m) {
  final bad = inconsistentEdges(faces, m.edges, m.edgeOrder);
  return {
    for (final c in m.components)
      c.number:
          c.boundary.isEmpty &&
          c.nonmanifold.isEmpty &&
          c.nonmanifoldVertices.isEmpty &&
          componentConsistency(c, bad),
  };
}

Map<int, List<int>> findNesting(
  Mesh m,
  Map<int, bool> solids,
  List<Face> faces,
  List<Vec> points,
) {
  final inside = <int, List<int>>{};
  for (final c in m.components) {
    if (!solids[c.number]!) continue;
    final parents = <int>[];
    for (final other in m.components) {
      if (other.number == c.number || !solids[other.number]!) continue;
      final otherVertices = other.vertices.toSet();
      int? test;
      for (final v in c.vertices) {
        if (!otherVertices.contains(v)) {
          test = v;
          break;
        }
      }
      if (test != null &&
          windingNumber(other.faces, faces, points, points[test]) != 0)
        parents.add(other.number);
    }
    inside[c.number] = parents;
  }
  return inside;
}

int applyOutward(
  List<Face> faces,
  List<Vec> points,
  Mesh m,
  Map<int, bool> solids,
  Map<int, List<int>> inside,
  bool enabled,
) {
  var count = 0;
  if (!enabled) return count;
  for (final c in m.components) {
    if (!solids[c.number]!) continue;
    final signed = volume6(c.faces, faces, points),
        depth = (inside[c.number] ?? []).length;
    if (signed != 0 &&
        (depth.isEven && signed < 0 || depth.isOdd && signed > 0)) {
      for (final id in c.faces) {
        flip(faces[id - 1]);
      }
      count++;
    }
  }
  return count;
}

class Component {
  final TopologyComponent topology;
  final bool orientable;
  final int loops;
  late final bool closed, manifold, consistent, solid;
  late final int euler, sixVolume, edgeMin, edgeMax, valenceMin, valenceMax;
  int? genus, crosscaps;
  late final double surfaceArea;
  List<String> center = [];
  Vec normalSum = (0, 0, 0);
  late final List<int> bounds, inside;
  final angles = <String, int>{}, shapes = <String, int>{};
  Component(
    this.topology,
    List<Face> faces,
    List<Vec> points,
    Mesh m,
    this.loops,
    this.orientable,
    List<int> parents,
  ) {
    final c = topology;
    closed = c.boundary.isEmpty;
    manifold = c.nonmanifold.isEmpty && c.nonmanifoldVertices.isEmpty;
    consistent = componentConsistency(
      c,
      inconsistentEdges(faces, m.edges, m.edgeOrder),
    );
    solid = closed && manifold && consistent;
    euler = c.vertices.length - c.edges.length + c.faces.length;
    if (manifold && orientable) {
      genus = floorDiv(2 - euler - loops, 2);
    } else if (manifold) {
      crosscaps = 2 - euler - loops;
    }
    sixVolume = volume6(c.faces, faces, points);
    inside = solid ? parents : [];
    if (solid && sixVolume != 0)
      center = centroid(c.faces, faces, points, sixVolume);
    final chosen = <Face>[];
    for (final id in c.faces) {
      final f = faces[id - 1], n = normal(faces[id - 1], points);
      chosen.add(f);
      normalSum = (
        normalSum.$1 + n.$1,
        normalSum.$2 + n.$2,
        normalSum.$3 + n.$3,
      );
      final angle = triangleAngle(f, points);
      angles[angle] = (angles[angle] ?? 0) + 1;
    }
    surfaceArea = area(chosen, points);
    bounds = bbox(c.vertices, points);
    final degree = <int, int>{}, lengths = <int>[];
    for (final e in c.edges) {
      degree[e.$1] = (degree[e.$1] ?? 0) + 1;
      degree[e.$2] = (degree[e.$2] ?? 0) + 1;
      lengths.add(edgeLengthSquared(e, points));
      final shape = edgeShape(e, faces, points, m.edges[e]!);
      shapes[shape] = (shapes[shape] ?? 0) + 1;
    }
    edgeMin = lengths.reduce(math.min);
    edgeMax = lengths.reduce(math.max);
    valenceMin = degree.values.reduce(math.min);
    valenceMax = degree.values.reduce(math.max);
  }
}

bool sameTriangle(List<int> a, List<int> b) =>
    a[0] == b[0] && a[1] == b[1] && a[2] == b[2];

class Analysis {
  final Source source;
  final Settings settings;
  late final List<Vec> snapped, points;
  late final List<(int, Vec, Vec)> snappedList;
  late final List<int> representative;
  late final List<Face> triangles, faces, added;
  late final List<(Face, String)> removed;
  late final Map<int, int> renumber;
  late final int initialFaces, outwardComponents, flippedFaces;
  late final Mesh meshBefore, mesh;
  late final List<Edge> initialInconsistent, inconsistentAfter;
  late final List<BoundaryLoop> loopsBefore;
  late final List<Component> components;
  final nonplanar = <int>{},
      originalToReps = <int, List<int>>{},
      groupOrder = <String>[],
      groupFaces = <String, List<int>>{};
  Analysis(this.source, this.settings) {
    final s = settings;
    final snapResult = snappedVertices(source.vertices, s.snap);
    snapped = snapResult.$1;
    snappedList = snapResult.$2;
    representative = representatives(snapped, s.merge);
    triangles = splitPolygons(source.polygons);
    final (kept, removedFaces) = cleanedFaces(
      triangles,
      snapped,
      representative,
      s.degenerate,
      s.duplicates,
    );
    removed = removedFaces;
    final (mappedPoints, cleaned, newNumbers) = remapVertices(
      snapped,
      representative,
      kept,
      s.keepUnused,
    );
    points = mappedPoints;
    renumber = newNumbers;
    initialFaces = cleaned.length;
    final initial = cleaned.map((f) => [...f.vertices]).toList();
    meshBefore = analyzeMesh(cleaned);
    initialInconsistent = inconsistentEdges(
      cleaned,
      meshBefore.edges,
      meshBefore.edgeOrder,
    );
    if (s.orient) repairOrientation(cleaned, meshBefore.edges);
    inconsistentAfter = inconsistentEdges(
      cleaned,
      meshBefore.edges,
      meshBefore.edgeOrder,
    );
    loopsBefore = boundaryLoops(cleaned, meshBefore);
    final permitted = {
      for (final c in meshBefore.components)
        if (c.nonmanifold.isEmpty && componentConsistency(c, inconsistentAfter))
          c.number,
    };
    final fillResult = fillLoops(cleaned, loopsBefore, s.fillHoles, permitted);
    faces = fillResult.$1;
    added = fillResult.$2;
    mesh = analyzeMesh(faces);
    final solids = preliminarySolids(faces, mesh),
        inside = findNesting(mesh, solids, faces, points);
    outwardComponents = applyOutward(
      faces,
      points,
      mesh,
      solids,
      inside,
      s.outward,
    );
    var flips = 0;
    for (var i = 0; i < initialFaces; i++) {
      if (!sameTriangle(faces[i].vertices, initial[i])) flips++;
    }
    flippedFaces = flips;
    final orientable = orientableComponents(faces, mesh),
        loopsFinal = boundaryLoops(faces, mesh),
        loopCounts = <int, int>{};
    for (final loop in loopsFinal) {
      loopCounts[loop.component] = (loopCounts[loop.component] ?? 0) + 1;
    }
    components = [
      for (final c in mesh.components)
        Component(
          c,
          faces,
          points,
          mesh,
          loopCounts[c.number] ?? 0,
          orientable[c.number]!,
          inside[c.number] ?? [],
        ),
    ];
    final seen = <String>{};
    for (final p in source.polygons) {
      if (polygonNonplanar(p, snapped)) nonplanar.add(p.number);
      if (seen.add(p.group)) groupOrder.add(p.group);
    }
    if (added.isNotEmpty) groupOrder.add('fill');
    for (var number = 1; number < source.vertices.length; number++) {
      originalToReps.putIfAbsent(representative[number], () => []).add(number);
    }
    for (var i = 0; i < faces.length; i++) {
      groupFaces.putIfAbsent(faces[i].group, () => []).add(i + 1);
    }
  }
  int get mergedCount {
    var count = 0;
    for (var i = 1; i < representative.length; i++) {
      if (i != representative[i]) count++;
    }
    return count;
  }
}

List<String> sectionSummary(Analysis a) {
  final source = a.source, sizes = <int, int>{}, removals = <String, int>{};
  for (final p in source.polygons) {
    sizes[p.vertices.length] = (sizes[p.vertices.length] ?? 0) + 1;
  }
  for (final (_, reason) in a.removed) {
    removals[reason] = (removals[reason] ?? 0) + 1;
  }
  var totalVolume = 0;
  for (final c in a.components) {
    if (c.solid) totalVolume += c.sixVolume;
  }
  final order = sizes.keys.toList()..sort();
  return [
    '[summary]',
    'lines ${source.lines}',
    'vertices ${source.vertices.length - 1}',
    'polygons ${source.polygons.length}',
    'errors ${source.errors.length}',
    'ignored ${source.ignored}',
    'nonplanar_polygons ${a.nonplanar.length}',
    for (final size in order) 'polygon_size $size ${sizes[size]}',
    'triangles ${a.triangles.length}',
    'snapped ${a.snappedList.length}',
    'merged ${a.mergedCount}',
    'removed_repeated ${removals['repeated'] ?? 0}',
    'removed_zero_area ${removals['zero_area'] ?? 0}',
    'removed_duplicate ${removals['duplicate'] ?? 0}',
    'faces ${a.initialFaces}',
    'inconsistent_before ${a.initialInconsistent.length}',
    'flipped_faces ${a.flippedFaces}',
    'outward_components ${a.outwardComponents}',
    'boundary_loops ${a.loopsBefore.length}',
    'holes_filled ${a.loopsBefore.where((loop) => loop.filled).length}',
    'fill_faces ${a.added.length}',
    'final_vertices ${a.points.length - 1}',
    'final_faces ${a.faces.length}',
    'components ${a.components.length}',
    'solids ${a.components.where((c) => c.solid).length}',
    'total_area ${real(area(a.faces, a.points))}',
    'total_volume ${fraction(totalVolume, 6)}',
  ];
}

List<String> sectionWarnings(Analysis a) => [
  '[warnings]',
  for (final (line, kind) in a.source.errors) 'line $line $kind',
];
List<String> sectionCleanup(Analysis a) {
  final reps = a.originalToReps.keys.toList()..sort();
  return [
    '[cleanup]',
    'snapped ${a.snappedList.length}',
    for (final (number, before, after) in a.snappedList)
      'snap $number ${vecText(before)} to ${vecText(after)}',
    'merged ${a.mergedCount}',
    for (final rep in reps)
      if (a.originalToReps[rep]!.length > 1)
        'merge ${optional(a.renumber[rep] ?? 0)} ${listing(a.originalToReps[rep]!)}',
    'removed ${a.removed.length}',
    for (final (face, reason) in a.removed)
      'remove ${face.triangle} polygon ${face.polygon} line ${face.line} $reason',
  ];
}

List<String> sectionComponents(Analysis a) {
  final lines = <String>[];
  for (final d in a.components) {
    final c = d.topology,
        present = {for (final id in d.topology.faces) a.faces[id - 1].group};
    lines.addAll([
      '[component ${c.number}]',
      'groups ${stringList(a.groupOrder.where(present.contains).toList())}',
      'faces ${c.faces.length}',
      'vertices ${c.vertices.length}',
      'edges ${c.edges.length}',
      'boundary_edges ${c.boundary.length}',
      'nonmanifold_edges ${c.nonmanifold.length}',
      'nonmanifold_vertices ${c.nonmanifoldVertices.length}',
      'boundary_loops ${d.loops}',
      'closed ${yes(d.closed)}',
      'manifold ${yes(d.manifold)}',
      'orientable ${yes(d.orientable)}',
      'consistent ${yes(d.consistent)}',
      'solid ${yes(d.solid)}',
      'euler ${d.euler}',
      d.genus != null
          ? 'genus ${d.genus}'
          : d.crosscaps != null
          ? 'crosscaps ${d.crosscaps}'
          : 'genus -',
      'volume ${d.solid ? fraction(d.sixVolume, 6) : '-'}',
      'area ${real(d.surfaceArea)}',
      'normal_sum ${vecText(d.normalSum)}',
      'bbox ${listing(d.bounds)}',
      'inside ${listing(d.inside)}',
      'centroid ${stringList(d.center)}',
      for (final name in ['convex', 'concave', 'flat'])
        '$name ${d.shapes[name] ?? 0}',
      for (final name in ['acute', 'right', 'obtuse'])
        '$name ${d.angles[name] ?? 0}',
      'edge_len2 ${d.edgeMin} ${d.edgeMax}',
      'valence ${d.valenceMin} ${d.valenceMax}',
    ]);
  }
  return lines;
}

List<String> sectionGroups(Analysis a) {
  final lines = <String>[];
  for (final group in a.groupOrder) {
    final polygons = a.source.polygons.where((p) => p.group == group).toList(),
        triangles = a.triangles.where((t) => t.group == group).length,
        ids = a.groupFaces[group] ?? <int>[];
    final chosen = ids.map((id) => a.faces[id - 1]).toList(),
        components = sortedInts(ids.map((id) => a.mesh.faceComponents[id]!));
    lines.addAll([
      '[group $group]',
      'polygons ${polygons.length}',
      'triangles $triangles',
      'nonplanar ${polygons.where((p) => a.nonplanar.contains(p.number)).length}',
      'faces ${chosen.length}',
      'area ${real(area(chosen, a.points))}',
      'components ${listing(components)}',
    ]);
  }
  return lines;
}

bool intersectingBoxes(List<int> a, List<int> b) {
  for (var axis = 0; axis < 3; axis++) {
    if (a[axis] > b[axis + 3] || b[axis] > a[axis + 3]) return false;
  }
  return true;
}

List<String> sectionContacts(Analysis a) {
  final lines = ['[contacts]'];
  for (var i = 0; i < a.components.length; i++) {
    for (final second in a.components.skip(i + 1)) {
      final first = a.components[i];
      if (!intersectingBoxes(first.bounds, second.bounds)) continue;
      final set = first.topology.vertices.toSet(),
          shared = second.topology.vertices.where(set.contains).length;
      int? gap;
      for (final u in first.topology.vertices) {
        for (final v in second.topology.vertices) {
          if (u == v) continue;
          final d = subtract(a.points[u], a.points[v]), square = dot(d, d);
          if (gap == null || square < gap) gap = square;
        }
      }
      lines.add(
        'contact ${first.topology.number} ${second.topology.number} shared $shared gap2 $gap',
      );
    }
  }
  return lines;
}

List<String> sectionEdges(Analysis a) {
  final counts = <String, int>{}, shapes = <String, int>{};
  var maxFaces = 0,
      shortest = a.mesh.edgeOrder.first,
      longest = a.mesh.edgeOrder.first,
      shortDistance = edgeLengthSquared(a.mesh.edgeOrder.first, a.points),
      longDistance = edgeLengthSquared(a.mesh.edgeOrder.first, a.points);
  for (final e in a.mesh.edgeOrder) {
    final adjacent = a.mesh.edges[e]!,
        kind = adjacent.length == 1
            ? 'boundary'
            : adjacent.length == 2
            ? 'manifold'
            : 'nonmanifold',
        shape = edgeShape(e, a.faces, a.points, adjacent);
    counts[kind] = (counts[kind] ?? 0) + 1;
    shapes[shape] = (shapes[shape] ?? 0) + 1;
    maxFaces = math.max(maxFaces, adjacent.length);
    final distance = edgeLengthSquared(e, a.points);
    if (distance < shortDistance) {
      shortest = e;
      shortDistance = distance;
    }
    if (distance > longDistance) {
      longest = e;
      longDistance = distance;
    }
  }
  return [
    '[edges]',
    'edges ${a.mesh.edgeOrder.length}',
    'boundary ${counts['boundary'] ?? 0}',
    'manifold ${counts['manifold'] ?? 0}',
    'nonmanifold ${counts['nonmanifold'] ?? 0}',
    'max_faces $maxFaces',
    for (final name in ['convex', 'concave', 'flat', 'inconsistent'])
      '$name ${shapes[name] ?? 0}',
    'shortest ${edgeText(shortest)} len2 $shortDistance',
    'longest ${edgeText(longest)} len2 $longDistance',
  ];
}

List<String> sectionValence(Analysis a) {
  final degree = <int, int>{};
  for (final (u, v) in a.mesh.edgeOrder) {
    degree[u] = (degree[u] ?? 0) + 1;
    degree[v] = (degree[v] ?? 0) + 1;
  }
  final histogram = <int, int>{};
  var total = 0;
  for (final d in degree.values) {
    histogram[d] = (histogram[d] ?? 0) + 1;
    total += d;
  }
  final values = histogram.keys.toList()..sort();
  return [
    '[valence]',
    'used ${degree.length}',
    'isolated ${a.points.length - 1 - degree.length}',
    'min ${degree.values.reduce(math.min)}',
    'max ${degree.values.reduce(math.max)}',
    'mean ${fraction(total, degree.length)}',
    for (final d in values) 'degree $d ${histogram[d]}',
  ];
}

List<int>? findVertexPath(int start, int end, Mesh m) {
  final graph = <int, Set<int>>{};
  for (final (u, v) in m.edgeOrder) {
    graph.putIfAbsent(u, () => {}).add(v);
    graph.putIfAbsent(v, () => {}).add(u);
  }
  final parent = <int, int?>{start: null}, queue = [start];
  for (var head = 0; head < queue.length; head++) {
    final current = queue[head],
        neighbors = (graph[queue[head]] ?? <int>{}).toList()..sort();
    for (final neighbor in neighbors) {
      if (!parent.containsKey(neighbor)) {
        parent[neighbor] = current;
        queue.add(neighbor);
      }
    }
  }
  if (!parent.containsKey(end)) return null;
  final path = <int>[];
  int? cursor = end;
  while (cursor != null) {
    path.add(cursor);
    cursor = parent[cursor];
  }
  return path.reversed.toList();
}

String queryVertex(int v, Analysis a) {
  if (v < 1 || v >= a.points.length) return 'vertex $v invalid';
  final containing = [
        for (var i = 0; i < a.faces.length; i++)
          if (a.faces[i].vertices.contains(v)) i + 1,
      ],
      edges = a.mesh.edgeOrder.where((e) => e.$1 == v || e.$2 == v).toList();
  return 'vertex $v at ${vecText(a.points[v])} faces ${containing.length} valence ${edges.length} fans ${(a.mesh.fans[v] ?? []).length} boundary ${yes(edges.any((e) => a.mesh.edges[e]!.length == 1))} components ${listing(sortedInts(containing.map((id) => a.mesh.faceComponents[id]!)))}';
}

String queryFace(int number, Analysis a) {
  if (number < 1 || number > a.faces.length) return 'face $number invalid';
  final f = a.faces[number - 1], neighbors = <String>[];
  for (final (u, v) in triangleEdges(f.vertices)) {
    final participants = a.mesh.edges[keyEdge(u, v)]!;
    neighbors.add(
      participants.length == 1
          ? '-'
          : participants.length >= 3
          ? '*'
          : '${participants.firstWhere((id) => id != number)}',
    );
  }
  return 'face $number vertices ${listing(f.vertices)} group ${f.group} polygon ${optional(f.polygon)} line ${optional(f.line)} component ${a.mesh.faceComponents[number]} normal ${vecText(normal(f, a.points))} area ${real(area([f], a.points))} neighbors ${stringList(neighbors)}';
}

String queryEdge(int start, int end, Analysis a) {
  final e = keyEdge(start, end), adjacent = a.mesh.edges[e];
  if (adjacent == null) return 'edge ${edgeText(e)} none';
  final kind = adjacent.length == 1
      ? 'boundary'
      : adjacent.length == 2
      ? 'manifold'
      : 'nonmanifold';
  return 'edge ${edgeText(e)} faces ${listing(adjacent)} kind $kind shape ${edgeShape(e, a.faces, a.points, adjacent)} len2 ${edgeLengthSquared(e, a.points)}';
}

String queryPoint(Vec p, Analysis a) {
  final inside = <int>[];
  var total = 0;
  for (final c in a.components) {
    if (!c.solid) continue;
    final w = windingNumber(c.topology.faces, a.faces, a.points, p);
    if (w != 0) {
      inside.add(c.topology.number);
      total += w;
    }
  }
  return 'point ${vecText(p)} inside ${listing(inside)} winding $total';
}

String queryPath(int start, int end, Analysis a) {
  if (start < 1 ||
      start >= a.points.length ||
      end < 1 ||
      end >= a.points.length)
    return 'path $start $end invalid';
  final path = findVertexPath(start, end, a.mesh);
  return path == null
      ? 'path $start $end none'
      : 'path $start $end hops ${path.length - 1} vertices ${listing(path)}';
}

String queryView(Vec direction, Analysis a) {
  final scores = a.faces
      .map((f) => dot(normal(f, a.points), direction))
      .toList();
  var silhouette = 0;
  for (final adjacent in a.mesh.edges.values) {
    if (adjacent.length != 2) continue;
    final x = scores[adjacent[0] - 1], y = scores[adjacent[1] - 1];
    if (x > 0 && y < 0 || x < 0 && y > 0) silhouette++;
  }
  return 'view ${vecText(direction)} front ${scores.where((v) => v > 0).length} back ${scores.where((v) => v < 0).length} side ${scores.where((v) => v == 0).length} silhouette $silhouette';
}

List<String> sectionQueries(Analysis a) {
  final lines = ['[queries]'];
  for (final (kind, v) in a.settings.queries) {
    switch (kind) {
      case 'vertex':
        lines.add(queryVertex(v[0], a));
      case 'face':
        lines.add(queryFace(v[0], a));
      case 'edge':
        lines.add(queryEdge(v[0], v[1], a));
      case 'point':
        lines.add(queryPoint((v[0], v[1], v[2]), a));
      case 'path':
        lines.add(queryPath(v[0], v[1], a));
      case 'view':
        lines.add(queryView((v[0], v[1], v[2]), a));
    }
  }
  return lines;
}

List<String> reportSections(Analysis a) {
  final actions = <String, List<String> Function(Analysis)>{
    'summary': sectionSummary,
    'warnings': sectionWarnings,
    'cleanup': sectionCleanup,
    'components': sectionComponents,
    'groups': sectionGroups,
    'contacts': sectionContacts,
    'edges': sectionEdges,
    'valence': sectionValence,
    'queries': sectionQueries,
  };
  return [for (final section in a.settings.sections) ...actions[section]!(a)];
}

List<String> csvComponents(Analysis a) => [
  'component,faces,vertices,closed,euler,genus,volume6,area',
  for (final c in a.components)
    '${c.topology.number},${c.topology.faces.length},${c.topology.vertices.length},${yes(c.closed)},${c.euler},${c.genus ?? '-'},${c.solid ? c.sixVolume : '-'},${real(c.surfaceArea)}',
];
List<String> boundariesReport(Analysis a) {
  final m = a.meshBefore,
      nonmanifold = a.meshBefore.edgeOrder
          .where((e) => a.meshBefore.edges[e]!.length >= 3)
          .toList();
  return [
    'loops ${a.loopsBefore.length}',
    for (final loop in a.loopsBefore)
      'loop ${loop.number} component ${loop.component} length ${loop.length} ${loop.kind} ${loop.filled ? 'filled' : 'kept'} vertices ${listing(loop.vertices)}',
    'nonmanifold_edges ${nonmanifold.length}',
    for (final e in nonmanifold)
      'edge ${edgeText(e)} faces ${listing(m.edges[e]!)}',
    'nonmanifold_vertices ${m.nonmanifoldVertices.length}',
    for (final v in m.nonmanifoldVertices)
      'vertex $v fans ${m.fans[v]!.length} components ${listing(sortedInts([for (final fan in m.fans[v]!)
        for (final f in fan) m.faceComponents[f]!]))}',
    'inconsistent_edges ${a.inconsistentAfter.length}',
    for (final e in a.inconsistentAfter)
      'edge ${edgeText(e)} faces ${listing(m.edges[e]!)}',
  ];
}

void writeLines(String name, List<String> lines) =>
    File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
void main() {
  final a = Analysis(readOBJ(), readParameters());
  Directory('output').createSync(recursive: true);
  writeLines('report.txt', reportSections(a));
  writeLines('components.csv', csvComponents(a));
  writeLines('boundaries.txt', boundariesReport(a));
  writeLines('repaired.obj', repairedOBJ(a.points, a.faces));
}
