import 'dart:io';
import 'dart:math' hide Point;

part 'predicates.dart';
part 'triangulation.dart';
part 'voronoi.dart';
part 'proximity.dart';
part 'plot.dart';

class Params {
  int width = 61, height = 31;
  List<String> layers = ['edges', 'hull', 'sites'], sections = ['summary'];
  final alpha = <int>[], queries = <String>[];
}

List<String> readLines(String path) => File(path).readAsLinesSync();
(List<Point>, int, List<String>) readPoints() {
  final lines = readLines('input/points.txt'),
      points = <Point>[Point(0, 0)],
      accepted = <Point, int>{},
      rejected = <String>[];
  final word = RegExp(r'^-?[0-9]+$');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    final fields = line.split(' ');
    if (fields.length != 2 || fields.any((f) => !word.hasMatch(f))) {
      rejected.add('reject ${i + 1} format');
      continue;
    }
    final point = Point(int.parse(fields[0]), int.parse(fields[1]));
    if (point.x < 0 || point.x > 1000 || point.y < 0 || point.y > 1000) {
      rejected.add('reject ${i + 1} range');
      continue;
    }
    if (accepted.containsKey(point)) {
      rejected.add('reject ${i + 1} duplicate ${accepted[point]}');
      continue;
    }
    accepted[point] = points.length;
    points.add(point);
  }
  return (points, lines.length, rejected);
}

Params readParams() {
  final p = Params();
  for (final line in readLines('input/params.txt')) {
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    final f = line.split(' ');
    switch (f[0]) {
      case 'plot':
        p.width = int.parse(f[1]);
        p.height = int.parse(f[2]);
      case 'plot_layers':
        p.layers = f.sublist(1);
      case 'sections':
        p.sections = f.sublist(1);
      case 'alpha':
        p.alpha.addAll(f.skip(1).map(int.parse));
      case 'query':
        p.queries.add(line.substring(6));
    }
  }
  return p;
}

String number(double value) {
  final text = value.toStringAsFixed(3);
  return text == '-0.000' ? '0.000' : text;
}

String words(List<int> values) => values.join(' ');
String edgeWords(Edge e) => '${e.$1} ${e.$2}';
String triangleWords(Triangle t) => '${t.$1} ${t.$2} ${t.$3}';
String triangleNumber(int? n) => n == null ? '-' : '$n';
String yes(bool value) => value ? 'yes' : 'no';

class Cell {
  final List<int> vertices;
  final double? area;
  final double clip;
  final Point? incoming, outgoing;
  Cell(this.vertices, this.area, this.clip, this.incoming, this.outgoing);
}

class Report {
  final List<Point> points;
  final int lineCount;
  final List<String> rejected;
  final Params params;
  final sections = <String, List<String>>{}, paths = <int, ShortestPaths>{};
  late final Triangulation mesh;
  final insertions = <Insertion>[];
  late final List<Triangle> triangles;
  final edges = <Edge>[], hullEdges = <Edge>[];
  final edgeTriangles = <Edge, int>{}, length2 = <Edge, int>{};
  final hull = <int>[], hullNext = <int, int>{}, hullPrev = <int, int>{};
  late final List<List<int>> neighbors;
  final centers = <Center>[Center(0, 0, 1)],
      radius2 = <double>[0],
      positions = <String>[''];
  final areas = <int>[0],
      kinds = <String>[''],
      minimumAngles = <double>[0],
      maximumAngles = <double>[0];
  final cells = <Cell?>[null];
  final gabriel = <Edge>{}, rng = <Edge>{}, mstSet = <Edge>{};
  late final List<Edge> mst;
  late final List<int> nearest, componentNumber, depth;
  late final List<List<int>> components;
  final layers = <List<int>>[], graphDegrees = <String, List<int>>{};
  final emptyCandidates = <int>[];
  int emptyVertex = 0;
  int get n => points.length - 1;
  Report(this.points, this.lineCount, this.rejected, this.params);
  void addLine(String section, String line) {
    sections.putIfAbsent(section, () => []).add(line);
  }

  void buildTriangulation() {
    mesh = Triangulation(points);
    for (var s = 4; s <= n; s++) {
      insertions.add(mesh.insert(s));
    }
    triangles = [(0, 0, 0), ...mesh.triangles()];
    for (var k = 1; k < triangles.length; k++) {
      for (final edge in triangleEdges(triangles[k])) {
        edgeTriangles[edge] = k;
        final pair = orderedEdge(edge.$1, edge.$2);
        length2[pair] = d2(points[pair.$1], points[pair.$2]);
      }
    }
    edges.addAll(length2.keys);
    edges.sort(compareEdges);
    var start = n + 1;
    for (final (u, v) in mesh.hullEdges()) {
      hullNext[u] = v;
      hullPrev[v] = u;
      start = min(start, u);
    }
    hull.add(start);
    while (hullNext[hull.last] != start) {
      hull.add(hullNext[hull.last]!);
    }
    var perimeter = 0.0, area = 0;
    for (var i = 0; i < hull.length; i++) {
      final u = hull[i],
          v = hull[(i + 1) % hull.length],
          a = points[u],
          b = points[v];
      hullEdges.add((u, v));
      perimeter += sqrt(d2(a, b));
      area += a.x * b.y - b.x * a.y;
    }
    sections['hull'] = [
      'hull_vertices ${hull.length}',
      'order ${words(hull)}',
      'perimeter ${number(perimeter)}',
      'area2 $area',
    ];
    final adjacent = List.generate(n + 1, (_) => <int>[]);
    for (final (a, b) in edges) {
      adjacent[a].add(b);
      adjacent[b].add(a);
    }
    neighbors = [
      <int>[],
      for (var s = 1; s <= n; s++)
        neighborOrder(s, adjacent[s], mesh.directed, hullNext),
    ];
    sections['insertions'] = ['init ${triangleWords(mesh.initial)}'];
    for (final v in insertions) {
      final description = v.containing == null
          ? 'outside ${v.visible}'
          : 'inside ${triangleWords(v.containing!)}';
      addLine(
        'insertions',
        'insert ${v.site} $description flips ${v.flips} triangles ${v.triangles} hull ${v.hull}',
      );
    }
  }

  void analyzeTriangles() {
    final bins = List.filled(6, 0), counts = <String, int>{};
    var total = 0.0, minimum = 1, maximum = 1;
    for (var k = 1; k < triangles.length; k++) {
      final t = triangles[k],
          a = points[t.$1],
          b = points[t.$2],
          c = points[t.$3],
          area = orient(a, b, c);
      final products = [dot(a, b, c), dot(b, c, a), dot(c, a, b)],
          lengths = [d2(b, c), d2(c, a), d2(a, b)];
      final kind = products.contains(0)
          ? 'right'
          : products.any((v) => v < 0)
          ? 'obtuse'
          : 'acute';
      var shortest = 0, longest = 0;
      for (var j = 1; j < 3; j++) {
        if (lengths[j] < lengths[shortest]) {
          shortest = j;
        }
        if (lengths[j] > lengths[longest]) {
          longest = j;
        }
      }
      areas.add(area);
      kinds.add(kind);
      counts[kind] = (counts[kind] ?? 0) + 1;
      minimumAngles.add(atan2(area, products[shortest]) * 180 / pi);
      maximumAngles.add(atan2(area, products[longest]) * 180 / pi);
      total += minimumAngles[k];
      bins[(minimumAngles[k] / 10).floor()]++;
      if (minimumAngles[k] < minimumAngles[minimum]) {
        minimum = k;
      }
      if (maximumAngles[k] > maximumAngles[maximum]) {
        maximum = k;
      }
      addLine(
        'triangles',
        'tri $k ${triangleWords(t)} area2 $area $kind adj ${triangleNumber(edgeTriangles[(t.$3, t.$2)])} ${triangleNumber(edgeTriangles[(t.$1, t.$3)])} ${triangleNumber(edgeTriangles[(t.$2, t.$1)])}',
      );
    }
    sections['quality'] = [
      'min_angle ${number(minimumAngles[minimum])} tri $minimum',
      'max_angle ${number(maximumAngles[maximum])} tri $maximum',
      'mean_min_angle ${number(total / (triangles.length - 1))}',
      for (var j = 0; j < 6; j++) 'bin ${10 * j} ${10 * (j + 1)} ${bins[j]}',
    ];
    for (final edge in edges) {
      final left = edgeTriangles[edge],
          right = edgeTriangles[(edge.$2, edge.$1)],
          kind = left != null && right != null ? 'inner' : 'hull';
      addLine(
        'edges',
        'edge ${edgeWords(edge)} $kind len2 ${length2[edge]} left ${triangleNumber(left)} right ${triangleNumber(right)}',
      );
    }
    var flips = 0, outside = 0;
    Insertion? best;
    for (final v in insertions) {
      flips += v.flips;
      if (v.kind == 'outside') {
        outside++;
      }
      if (best == null || v.flips > best.flips) {
        best = v;
      }
    }
    final maxFlips = best == null
        ? 'max_flips none'
        : 'max_flips ${best.site} ${best.flips}';
    sections['summary'] = [
      'sites $n',
      'triangles ${triangles.length - 1}',
      'edges ${edges.length}',
      'hull_vertices ${hull.length}',
      'interior_sites ${n - hull.length}',
      'euler ${n - edges.length + triangles.length - 1}',
      'flips $flips',
      'outside_insertions $outside',
      maxFlips,
      for (final name in ['acute', 'right', 'obtuse'])
        '$name ${counts[name] ?? 0}',
    ];
  }

  String dual(Edge e) {
    final left = edgeTriangles[e], right = edgeTriangles[(e.$2, e.$1)];
    if (left != null && right != null) {
      return 'segment $left $right';
    }
    final u = left == null ? e.$2 : e.$1,
        v = left == null ? e.$1 : e.$2,
        k = left ?? right!;
    final d = outward(points, u, v);
    return 'ray $k ${d.x} ${d.y}';
  }

  void analyzeVoronoi() {
    final counts = <String, int>{};
    for (final t in triangles.skip(1)) {
      final a = points[t.$1],
          b = points[t.$2],
          c = points[t.$3],
          center = circumcenter(a, b, c),
          where = position(center, points, hull);
      centers.add(center);
      radius2.add(squaredRadius(a, b, c));
      positions.add(where);
      counts[where] = (counts[where] ?? 0) + 1;
    }
    sections['vertices'] = [
      for (final name in ['inside', 'on', 'outside'])
        '$name ${counts[name] ?? 0}',
    ];
    for (var k = 1; k < triangles.length; k++) {
      final c = centers[k];
      addLine(
        'vertices',
        'v $k ${fraction(c.x, c.d)} ${fraction(c.y, c.d)} r ${number(sqrt(radius2[k]))} ${positions[k]}',
      );
    }
    sections['voronoi_edges'] = [
      'segments ${edges.length - hull.length}',
      'rays ${hull.length}',
      for (final edge in edges) 've ${edgeWords(edge)} ${dual(edge)}',
    ];
    var areaTotal = 0.0, clipTotal = 0.0, largest = 0;
    final cellLines = <String>[];
    for (var s = 1; s <= n; s++) {
      final vertices = [
        for (final other in neighbors[s])
          if (edgeTriangles.containsKey((s, other))) edgeTriangles[(s, other)]!,
      ];
      final clip = clippedArea(points, s, neighbors[s]);
      Cell cell;
      if (hullNext.containsKey(s)) {
        final incoming = outward(points, s, hullNext[s]!),
            outgoing = outward(points, hullPrev[s]!, s);
        cell = Cell(vertices, null, clip, incoming, outgoing);
        cellLines.add(
          'cell $s unbounded ${vertices.length} clip ${number(clip)} from ${incoming.x} ${incoming.y} vertices ${words(vertices)} to ${outgoing.x} ${outgoing.y}',
        );
      } else {
        final area = boundedArea(points[s], [
          for (final k in vertices) centers[k],
        ]);
        cell = Cell(vertices, area, clip, null, null);
        areaTotal += area;
        if (largest == 0 || area > cells[largest]!.area!) {
          largest = s;
        }
        cellLines.add(
          'cell $s bounded ${vertices.length} area ${number(area)} clip ${number(clip)} vertices ${words(vertices)}',
        );
      }
      cells.add(cell);
      clipTotal += clip;
    }
    sections['cells'] = [
      'bounded ${n - hull.length}',
      'unbounded ${hull.length}',
      'total_area ${number(areaTotal)}',
      'clip_total ${number(clipTotal)}',
      largest == 0
          ? 'largest none'
          : 'largest $largest area ${number(cells[largest]!.area!)}',
      ...cellLines,
    ];
  }

  void analyzeProximity() {
    nearest = nearestNeighbors(points, neighbors);
    components = nearestComponents(nearest);
    componentNumber = List.filled(n + 1, 0);
    var mutual = 0;
    for (var s = 1; s <= n; s++) {
      if (s < nearest[s] && nearest[nearest[s]] == s) {
        mutual++;
      }
    }
    var closest = edges.first;
    for (final edge in edges.skip(1)) {
      if (length2[edge]! < length2[closest]!) {
        closest = edge;
      }
    }
    sections['nearest'] = [
      'mutual_pairs $mutual',
      'closest_pair ${edgeWords(closest)} d2 ${length2[closest]}',
      for (var s = 1; s <= n; s++)
        'nn $s ${nearest[s]} d2 ${d2(points[s], points[nearest[s]])} ${nearest[nearest[s]] == s ? 'mutual' : '-'}',
    ];
    sections['components'] = ['components ${components.length}'];
    for (var k = 0; k < components.length; k++) {
      final sites = components[k];
      var pair = (0, 0);
      for (final s in sites) {
        componentNumber[s] = k + 1;
        if (s < nearest[s] && nearest[nearest[s]] == s) {
          pair = (s, nearest[s]);
        }
      }
      addLine(
        'components',
        'component ${k + 1} size ${sites.length} pair ${edgeWords(pair)} sites ${words(sites)}',
      );
    }
    mst = kruskal(points, edges);
    mstSet.addAll(mst);
    var length = 0.0;
    for (final edge in mst) {
      length += sqrt(length2[edge]!);
    }
    sections['mst'] = [
      'edges ${n - 1}',
      'total_length ${number(length)}',
      'longest ${edgeWords(mst.last)} len2 ${length2[mst.last]}',
      for (final edge in mst) 'mst ${edgeWords(edge)} len2 ${length2[edge]}',
    ];
    for (final edge in edges) {
      if (isGabriel(points, edge, mesh.directed)) {
        gabriel.add(edge);
      }
      if (isRelativeNeighbor(points, edge)) {
        rng.add(edge);
      }
    }
    sections['proximity'] = [
      'delaunay ${edges.length}',
      'gabriel ${gabriel.length}',
      'rng ${rng.length}',
      'mst ${n - 1}',
      'nn ${n - mutual}',
      for (final edge in edges)
        if (rng.contains(edge) && !mstSet.contains(edge))
          'rng_extra ${edgeWords(edge)} len2 ${length2[edge]}',
    ];
    for (final entry in {'gg': gabriel, 'rng': rng, 'mst': mstSet}.entries) {
      final degrees = List.filled(n + 1, 0);
      for (final (a, b) in entry.value) {
        degrees[a]++;
        degrees[b]++;
      }
      graphDegrees[entry.key] = degrees;
    }
    final counts = <int, int>{};
    var smallest = n, largest = 0;
    for (final order in neighbors.skip(1)) {
      final degree = order.length;
      counts[degree] = (counts[degree] ?? 0) + 1;
      smallest = min(smallest, degree);
      largest = max(largest, degree);
    }
    sections['degrees'] = [
      'min $smallest',
      'max $largest',
      for (var d = smallest; d <= largest; d++)
        if (counts.containsKey(d)) 'degree $d count ${counts[d]}',
    ];
  }

  int circleRelation(List<int> support, int site) {
    if (support.length == 1) {
      return support[0] == site ? 0 : -1;
    }
    if (support.length == 2) {
      return -dot(points[site], points[support[0]], points[support[1]]);
    }
    return incircle(
      points[support[0]],
      points[support[1]],
      points[support[2]],
      points[site],
    );
  }

  List<int> circleOrder(int a, int b, int c) =>
      orient(points[a], points[b], points[c]) > 0 ? [a, b, c] : [a, c, b];
  (Center, double, List<int>) enclosingCircle() {
    var support = <int>[];
    for (var i = 0; i < hull.length; i++) {
      final first = hull[i];
      if (support.isNotEmpty && circleRelation(support, first) >= 0) {
        continue;
      }
      support = [first];
      for (var j = 0; j < i; j++) {
        final second = hull[j];
        if (circleRelation(support, second) >= 0) {
          continue;
        }
        support = [first, second];
        for (var k = 0; k < j; k++) {
          final third = hull[k];
          if (circleRelation(support, third) < 0) {
            support = circleOrder(first, second, third);
          }
        }
      }
    }
    final boundary = [
      for (var s = 1; s <= n; s++)
        if (circleRelation(support, s) == 0) s,
    ];
    for (var i = 0; i < boundary.length; i++) {
      final a = boundary[i];
      for (final b in boundary.skip(i + 1)) {
        if (boundary.every((s) => dot(points[s], points[a], points[b]) == 0)) {
          final p = points[a], q = points[b];
          return (Center(p.x + q.x, p.y + q.y, 2), d2(p, q) / 4, boundary);
        }
      }
    }
    final ordered = circleOrder(boundary[0], boundary[1], boundary[2]),
        a = points[ordered[0]],
        b = points[ordered[1]],
        c = points[ordered[2]];
    return (circumcenter(a, b, c), squaredRadius(a, b, c), boundary);
  }

  void analyzeExtent() {
    for (var k = 1; k < triangles.length; k++) {
      if (positions[k] == 'inside') {
        emptyCandidates.add(k);
        if (emptyVertex == 0 || radius2[k] > radius2[emptyVertex]) {
          emptyVertex = k;
        }
      }
    }
    sections['empty_circle'] = ['candidates ${emptyCandidates.length}'];
    if (emptyVertex == 0) {
      addLine('empty_circle', 'none');
    } else {
      final k = emptyVertex, c = centers[emptyVertex];
      sections['empty_circle']!.addAll([
        'vertex $k',
        'center ${fraction(c.x, c.d)} ${fraction(c.y, c.d)}',
        'radius ${number(sqrt(radius2[k]))}',
        'sites ${triangleWords(triangles[k])}',
      ]);
    }
    var diameter = (0, 0), diameter2 = -1;
    for (var a = 1; a < n; a++) {
      for (var b = a + 1; b <= n; b++) {
        final length = d2(points[a], points[b]);
        if (length > diameter2) {
          diameter = (a, b);
          diameter2 = length;
        }
      }
    }
    var width = double.infinity, widthEdge = (0, 0);
    for (final edge in hullEdges) {
      var maximum = 0;
      for (final s in hull) {
        maximum = max(
          maximum,
          orient(points[edge.$1], points[edge.$2], points[s]),
        );
      }
      final value = maximum / sqrt(d2(points[edge.$1], points[edge.$2]));
      if (value < width) {
        width = value;
        widthEdge = edge;
      }
    }
    final (center, radius, sites) = enclosingCircle();
    sections['extent'] = [
      'diameter ${edgeWords(diameter)} d2 $diameter2',
      'width ${number(width)} edge ${edgeWords(widthEdge)}',
      'enclosing_center ${fraction(center.x, center.d)} ${fraction(center.y, center.d)}',
      'enclosing_radius ${number(sqrt(radius))}',
      'enclosing_sites ${words(sites)}',
    ];
  }

  void analyzeLayers() {
    var remaining = List.generate(n, (i) => i + 1);
    depth = List.filled(n + 1, 0);
    while (remaining.isNotEmpty) {
      var layer = List<int>.of(remaining);
      if (remaining.length > 2) {
        layer.sort((a, b) {
          final x = points[a].x.compareTo(points[b].x);
          return x != 0 ? x : points[a].y.compareTo(points[b].y);
        });
        final lower = <int>[], upper = <int>[];
        for (final s in layer) {
          while (lower.length >= 2 &&
              orient(
                    points[lower[lower.length - 2]],
                    points[lower.last],
                    points[s],
                  ) <=
                  0) {
            lower.removeLast();
          }
          lower.add(s);
        }
        for (final s in layer.reversed) {
          while (upper.length >= 2 &&
              orient(
                    points[upper[upper.length - 2]],
                    points[upper.last],
                    points[s],
                  ) <=
                  0) {
            upper.removeLast();
          }
          upper.add(s);
        }
        layer = [
          ...lower.take(lower.length - 1),
          ...upper.take(upper.length - 1),
        ];
        final start = layer.indexOf(layer.reduce(min));
        layer = [...layer.skip(start), ...layer.take(start)];
      }
      layers.add(layer);
      for (final s in layer) {
        depth[s] = layers.length;
      }
      remaining = remaining.where((s) => depth[s] == 0).toList();
    }
    sections['convex_layers'] = [
      'layers ${layers.length}',
      for (var k = 0; k < layers.length; k++)
        'layer ${k + 1} size ${layers[k].length} sites ${words(layers[k])}',
    ];
  }

  ShortestPaths shortestFrom(int s) =>
      paths.putIfAbsent(s, () => dijkstra(points, neighbors, s));
  void analyzeSpanner() {
    final pairs = n * (n - 1) ~/ 2;
    var total = 0.0,
        maximum = -1.0,
        length = 0.0,
        distance = 0.0,
        pair = (0, 0);
    for (var a = 1; a < n; a++) {
      final paths = shortestFrom(a);
      for (var b = a + 1; b <= n; b++) {
        final direct = sqrt(d2(points[a], points[b])),
            stretch = paths.distances[b] / direct;
        total += stretch;
        if (stretch > maximum) {
          maximum = stretch;
          pair = (a, b);
          length = paths.distances[b];
          distance = direct;
        }
      }
    }
    sections['spanner'] = [
      'pairs $pairs',
      'max_stretch ${number(maximum)} pair ${edgeWords(pair)} length ${number(length)} distance ${number(distance)}',
      'mean_stretch ${number(total / pairs)}',
    ];
  }

  void analyzeAlpha() {
    for (final alpha in params.alpha) {
      final incidence = <Edge, int>{};
      var faces = 0, area = 0;
      for (var k = 1; k < triangles.length; k++) {
        if (radius2[k] <= alpha) {
          faces++;
          area += areas[k];
          for (final e in triangleEdges(triangles[k])) {
            final pair = orderedEdge(e.$1, e.$2);
            incidence[pair] = (incidence[pair] ?? 0) + 1;
          }
        }
      }
      final selected = incidence.keys.toSet();
      for (final edge in gabriel) {
        if (length2[edge]! <= 4 * alpha) {
          selected.add(edge);
        }
      }
      final sets = DisjointSets(n), incident = List.filled(n + 1, false);
      var boundary = 0, dangling = 0, isolated = n;
      for (final edge in edges) {
        if (!selected.contains(edge)) {
          continue;
        }
        sets.union(edge.$1, edge.$2);
        for (final s in [edge.$1, edge.$2]) {
          if (!incident[s]) {
            incident[s] = true;
            isolated--;
          }
        }
        if (incidence[edge] == 1) {
          boundary++;
        }
        if ((incidence[edge] ?? 0) == 0) {
          dangling++;
        }
      }
      addLine(
        'alpha',
        'alpha $alpha triangles $faces edges ${selected.length} boundary $boundary dangling $dangling isolated $isolated components ${sets.count} holes ${sets.count - (n - selected.length + faces)} area2 $area',
      );
    }
  }

  String locate(Point query) {
    var nearest = 1, location = 'outside';
    for (var s = 1; s <= n; s++) {
      if (d2(points[s], query) < d2(points[nearest], query)) {
        nearest = s;
      }
      if (points[s] == query) {
        location = 'vertex $s';
      }
    }
    if (location == 'outside') {
      for (final e in edges) {
        if (orient(points[e.$1], points[e.$2], query) == 0 &&
            dot(query, points[e.$1], points[e.$2]) < 0) {
          location = 'edge ${edgeWords(e)}';
          break;
        }
      }
    }
    if (location == 'outside') {
      for (final t in triangles.skip(1)) {
        if (triangleEdges(
          t,
        ).every((e) => orient(points[e.$1], points[e.$2], query) > 0)) {
          location = 'triangle ${triangleWords(t)}';
          break;
        }
      }
    }
    return '$location nearest $nearest d2 ${d2(points[nearest], query)}';
  }

  String queryAnswer(String query) {
    final fields = query.split(' '),
        name = fields.first,
        args = fields.skip(1).map(int.parse).toList(),
        a = args[0],
        b = args.length > 1 ? args[1] : 0;
    if (['route', 'path', 'neighbors', 'edge'].contains(name)) {
      if (args.any((s) => s < 1 || s > n)) {
        return '$query error unknown_site';
      }
      if (name == 'edge' && a == b) {
        return '$query error same_site';
      }
    }
    final q = Point(a, b);
    String answer;
    switch (name) {
      case 'locate':
        answer = locate(q);
      case 'walk':
        final (path, outside) = mesh.visibilityWalk(
          q,
          triangles,
          edgeTriangles,
        );
        final stopping = outside == null
            ? 'triangle ${path.last}'
            : 'outside ${edgeWords(outside)}';
        answer = 'steps ${path.length - 1} $stopping path ${words(path)}';
      case 'natural':
        var count = 0;
        final sites = <int>{};
        for (final t in triangles.skip(1)) {
          if (incircle(points[t.$1], points[t.$2], points[t.$3], q) > 0) {
            count++;
            sites.addAll(triangleSites(t));
          }
        }
        final ordered = sites.toList()..sort();
        answer =
            'triangles $count sites ${ordered.isEmpty ? '-' : words(ordered)}';
      case 'route':
        final (path, length) = greedyRoute(points, neighbors, a, b);
        answer =
            'hops ${path.length - 1} length ${number(length)} path ${words(path)}';
      case 'path':
        final paths = shortestFrom(a), reversed = <int>[b];
        while (reversed.last != a) {
          reversed.add(paths.previous[reversed.last]);
        }
        final path = reversed.reversed.toList(),
            stretch = a == b
                ? '-'
                : number(paths.distances[b] / sqrt(d2(points[a], points[b])));
        answer =
            'length ${number(paths.distances[b])} stretch $stretch hops ${path.length - 1} sites ${words(path)}';
      case 'neighbors':
        answer = 'degree ${neighbors[a].length} sites ${words(neighbors[a])}';
      default:
        final edge = orderedEdge(a, b);
        if (length2.containsKey(edge)) {
          answer =
              'delaunay len2 ${length2[edge]} gabriel ${yes(gabriel.contains(edge))} rng ${yes(rng.contains(edge))} mst ${yes(mstSet.contains(edge))} dual ${dual(edge)}';
        } else {
          final crossings = <String>[], p = points[a], q = points[b];
          for (final e in edges) {
            final u = points[e.$1], v = points[e.$2];
            if (orient(p, q, u) * orient(p, q, v) < 0 &&
                orient(u, v, p) * orient(u, v, q) < 0) {
              crossings.add('${e.$1}-${e.$2}');
            }
          }
          answer =
              'missing crossings ${crossings.length}${crossings.isEmpty ? '' : ' ${crossings.join(' ')}'}';
        }
    }
    return '$query $answer';
  }

  void finish() {
    for (var s = 1; s <= n; s++) {
      final p = points[s], kind = hullNext.containsKey(s) ? 'hull' : 'inner';
      addLine(
        'sites',
        'site $s ${p.x} ${p.y} $kind dt ${neighbors[s].length} gg ${graphDegrees['gg']![s]} rng ${graphDegrees['rng']![s]} mst ${graphDegrees['mst']![s]} nn ${nearest[s]} comp ${componentNumber[s]} depth ${depth[s]}',
      );
    }
    sections['queries'] = params.queries.map(queryAnswer).toList();
    var canvas = Canvas(params.width, params.height);
    for (final layer in params.layers) {
      if (layer == 'sites') {
        for (final p in points.skip(1)) {
          canvas.mark(p.x, p.y, 1, 'o');
        }
      } else if (layer == 'circle') {
        if (emptyVertex > 0) {
          final c = centers[emptyVertex];
          canvas.mark(c.x, c.y, c.d, '@');
        }
      } else {
        final selected = layer == 'mst'
                ? mst
                : layer == 'hull'
                ? hullEdges
                : edges,
            ch = layer == 'mst'
                ? '*'
                : layer == 'hull'
                ? '#'
                : '.';
        for (final e in selected) {
          canvas.line(points[e.$1], points[e.$2], ch);
        }
      }
    }
    sections['delaunay_plot'] = canvas.framed();
    canvas = Canvas(params.width, params.height);
    canvas.drawVoronoi(points);
    sections['voronoi_plot'] = canvas.framed();
    sections['input'] = [
      'lines $lineCount',
      'accepted $n',
      'rejected ${rejected.length}',
      ...rejected,
    ];
    final owners = {
      'triangulation.txt': [
        'input',
        'summary',
        'insertions',
        'triangles',
        'edges',
        'hull',
        'convex_layers',
        'quality',
      ],
      'voronoi.txt': ['vertices', 'voronoi_edges', 'cells'],
      'derived.txt': [
        'nearest',
        'components',
        'mst',
        'proximity',
        'degrees',
        'empty_circle',
        'extent',
        'spanner',
        'alpha',
        'sites',
        'queries',
      ],
      'plot.txt': ['delaunay_plot', 'voronoi_plot'],
    };
    Directory('output').createSync(recursive: true);
    for (final entry in owners.entries) {
      final lines = <String>[];
      for (final section in params.sections) {
        if (entry.value.contains(section)) {
          lines.add('[$section]');
          lines.addAll(sections[section] ?? []);
        }
      }
      File(
        'output/${entry.key}',
      ).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
    }
  }
}

void main() {
  final (points, count, rejected) = readPoints();
  final report = Report(points, count, rejected, readParams());
  report.buildTriangulation();
  report.analyzeTriangles();
  report.analyzeVoronoi();
  report.analyzeProximity();
  report.analyzeExtent();
  report.analyzeLayers();
  report.analyzeSpanner();
  report.analyzeAlpha();
  report.finish();
}
