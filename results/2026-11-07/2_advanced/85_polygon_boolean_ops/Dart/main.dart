import 'dart:io';
import 'dart:math';
part 'rational.dart';
part 'intersections.dart';
part 'greiner_hormann.dart';
part 'rings.dart';
part 'render.dart';

class Polygon {
  final List<Ring> input, rings;
  Polygon(this.input, this.rings);
}

class Result {
  final List<Polygon> polygons;
  final Polygon? a, b;
  Result(this.polygons, {this.a, this.b});
}

class SourceLine {
  final int number;
  final String text;
  SourceLine(this.number, this.text);
}

final unsignedWord = RegExp(r'^[0-9]{1,9}$'),
    integerWord = RegExp(r'^-?[0-9]{1,9}$'),
    nameWord = RegExp(r'^[a-z0-9_]{1,16}$');
const kinds = [
  'UNION',
  'INTERSECTION',
  'DIFFERENCE',
  'XOR',
  'CLIP',
  'AREA',
  'MOVE',
  'ROTATE',
  'MIRROR',
  'SNAP',
  'LOCATE',
  'RENDER',
];
List<String> lines(String path) => File(path).readAsLinesSync();
bool ignored(String line) => line.isEmpty || line.startsWith('#');
(List<Ring>?, int) parseBlock(List<SourceLine> content, int end) {
  final rings = <Ring>[];
  var at = 0;
  while (at < content.length) {
    var line = content[at];
    final a = line.text.split(' ');
    if (a.length != 2 ||
        (a[0] != 'OUTER' && a[0] != 'HOLE') ||
        !unsignedWord.hasMatch(a[1]) ||
        int.parse(a[1]) < 1 ||
        (a[0] == 'OUTER' && rings.isNotEmpty) ||
        (a[0] == 'HOLE' && rings.isEmpty))
      return (null, line.number);
    final n = int.parse(a[1]);
    at++;
    final ring = <Point>[];
    for (var k = 0; k < n; k++) {
      if (at == content.length) return (null, end);
      line = content[at];
      final v = line.text.split(' ');
      if (v.length != 2 ||
          !integerWord.hasMatch(v[0]) ||
          !integerWord.hasMatch(v[1]))
        return (null, line.number);
      ring.add(point(int.parse(v[0]), int.parse(v[1])));
      at++;
    }
    rings.add(ring);
  }
  return rings.isEmpty ? (null, end) : (rings, 0);
}

bool inRange(Point p) =>
    p.x.compare(rational(0)) >= 0 &&
    p.x.compare(rational(1000)) <= 0 &&
    p.y.compare(rational(0)) >= 0 &&
    p.y.compare(rational(1000)) <= 0;
String checkPolygon(List<Ring> rings) {
  for (var k = 0; k < rings.length; k++) {
    final ring = rings[k], n = ring.length;
    if (n < 3) return 'too_few_vertices ring ${k + 1}';
    for (final p in ring) {
      if (!inRange(p)) return 'out_of_range ring ${k + 1} $p';
    }
    final seen = <Point>{};
    for (final p in ring) {
      if (!seen.add(p)) return 'duplicate_vertex ring ${k + 1} $p';
    }
    for (var i = 0; i < n; i++) {
      if (cross(ring[(i + n - 1) % n], ring[i], ring[(i + 1) % n]).sign == 0)
        return 'collinear ring ${k + 1} ${ring[i]}';
    }
    for (var i = 0; i < n; i++) {
      final a = ring[i], b = ring[(i + 1) % n];
      for (var j = i + 1; j < n; j++) {
        if (j == i + 1 || (i == 0 && j == n - 1)) continue;
        final c = ring[j], d = ring[(j + 1) % n];
        if (touching(a, b, c, d))
          return 'self_intersection ring ${k + 1} ${segmentText(a, b)} ${segmentText(c, d)}';
      }
    }
  }
  for (var i = 0; i < rings.length; i++) {
    final first = rings[i];
    for (var j = i + 1; j < rings.length; j++) {
      final second = rings[j];
      for (var e = 0; e < first.length; e++) {
        final a = first[e], b = first[(e + 1) % first.length];
        for (var f = 0; f < second.length; f++) {
          final c = second[f], d = second[(f + 1) % second.length];
          if (touching(a, b, c, d))
            return 'rings_touch rings ${i + 1} ${j + 1} ${segmentText(a, b)} ${segmentText(c, d)}';
        }
      }
    }
  }
  for (var k = 1; k < rings.length; k++) {
    if (!insideRing(rings[k].first, rings.first))
      return 'hole_outside ring ${k + 1} ${rings[k].first}';
  }
  for (var i = 1; i < rings.length; i++) {
    for (var j = i + 1; j < rings.length; j++) {
      if (insideRing(rings[j].first, rings[i]))
        return 'hole_in_hole rings ${i + 1} ${j + 1} ${rings[j].first}';
      if (insideRing(rings[i].first, rings[j]))
        return 'hole_in_hole rings ${i + 1} ${j + 1} ${rings[i].first}';
    }
  }
  return '';
}

String generalPosition(Polygon a, Polygon b, String aName, String bName) {
  final vertices = {for (final ring in b.rings) ...ring};
  for (final ring in a.rings) {
    for (final p in ring) {
      if (vertices.contains(p)) return 'shared_vertex $p';
    }
  }
  for (final first in a.rings) {
    for (var e = 0; e < first.length; e++) {
      final p = first[e], q = first[(e + 1) % first.length];
      for (final second in b.rings) {
        for (var f = 0; f < second.length; f++) {
          final r = second[f], s = second[(f + 1) % second.length];
          if (overlapping(p, q, r, s))
            return 'overlapping_edges ${segmentText(p, q)} ${segmentText(r, s)}';
        }
      }
    }
  }
  for (final (first, second, firstName, secondName) in [
    (a, b, aName, bName),
    (b, a, bName, aName),
  ]) {
    for (final ring in first.rings) {
      for (final p in ring) {
        for (final other in second.rings) {
          for (var e = 0; e < other.length; e++) {
            final q = other[e], r = other[(e + 1) % other.length];
            if (onSegment(p, q, r))
              return 'vertex_on_edge $firstName $p $secondName ${segmentText(q, r)}';
          }
        }
      }
    }
  }
  return '';
}

bool numeric(String s, int low, int high) =>
    integerWord.hasMatch(s) && int.parse(s) >= low && int.parse(s) <= high;
bool validArguments(List<String> a) {
  const required = {
    'UNION': 3,
    'INTERSECTION': 3,
    'DIFFERENCE': 3,
    'XOR': 3,
    'CLIP': 3,
    'SNAP': 3,
    'AREA': 2,
    'LOCATE': 4,
    'MOVE': 5,
    'MIRROR': 5,
    'ROTATE': 6,
    'RENDER': 8,
  };
  if (a.length != required[a[0]]) return false;
  switch (a[0]) {
    case 'LOCATE':
      return numeric(a[2], 0, 1000) && numeric(a[3], 0, 1000);
    case 'MOVE':
      return numeric(a[2], -1000, 1000) &&
          numeric(a[3], -1000, 1000) &&
          nameWord.hasMatch(a[4]);
    case 'ROTATE':
      return numeric(a[2], 0, 1000) &&
          numeric(a[3], 0, 1000) &&
          numeric(a[4], 1, 3) &&
          nameWord.hasMatch(a[5]);
    case 'MIRROR':
      return (a[2] == 'x' || a[2] == 'y') &&
          numeric(a[3], 0, 1000) &&
          nameWord.hasMatch(a[4]);
    case 'SNAP':
      return nameWord.hasMatch(a[2]);
    case 'RENDER':
      for (var i = 2; i < 8; i++) {
        var low = 0, high = 1000;
        if (i == 4 || i == 5 || i == 6) {
          low = 1;
          high = 100;
        }
        if (i == 7) {
          low = 1;
          high = 60;
        }
        if (!numeric(a[i], low, high)) return false;
      }
      return int.parse(a[2]) + int.parse(a[4]) * int.parse(a[6]) <= 1000 &&
          int.parse(a[3]) + int.parse(a[5]) * int.parse(a[7]) <= 1000;
  }
  return true;
}

List<Ring> transformed(Polygon p, List<String> a) {
  final out = <Ring>[];
  for (final ring in p.input) {
    final next = <Point>[];
    for (final v in ring) {
      var x = v.x.numerator.toInt(), y = v.y.numerator.toInt();
      switch (a[0]) {
        case 'MOVE':
          x += int.parse(a[2]);
          y += int.parse(a[3]);
          break;
        case 'ROTATE':
          final cx = int.parse(a[2]), cy = int.parse(a[3]);
          for (var q = 0; q < int.parse(a[4]); q++) {
            final nextX = cx - (y - cy), nextY = cy + (x - cx);
            x = nextX;
            y = nextY;
          }
          break;
        case 'MIRROR':
          if (a[2] == 'x') {
            x = 2 * int.parse(a[3]) - x;
          } else {
            y = 2 * int.parse(a[3]) - y;
          }
          break;
      }
      next.add(point(x, y));
    }
    out.add(next);
  }
  return out;
}

bool convex(Polygon p) {
  if (p.rings.length != 1) return false;
  final r = p.rings.first;
  for (var i = 0; i < r.length; i++) {
    if (cross(
          r[(i + r.length - 1) % r.length],
          r[i],
          r[(i + 1) % r.length],
        ).sign <=
        0)
      return false;
  }
  return true;
}

bool cyclicEqual(Ring a, Ring b) {
  if (a.length != b.length) return false;
  for (var offset = 0; offset < b.length; offset++) {
    if (a.first != b[offset]) continue;
    var same = true;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[(offset + i) % b.length]) {
        same = false;
        break;
      }
    }
    if (same) return true;
  }
  return false;
}

(String, int, int) sutherland(
  Polygon subject,
  Polygon window,
  List<Polygon> result,
) {
  final clipped = <Ring>[];
  for (final ring in subject.rings) {
    var list = ring;
    for (var j = 0; j < window.rings.first.length; j++) {
      final c1 = window.rings.first[j],
          c2 = window.rings.first[(j + 1) % window.rings.first.length],
          next = <Point>[];
      for (var i = 0; i < list.length; i++) {
        final cur = list[i],
            prev = list[(i + list.length - 1) % list.length],
            insidePrev =
                cross(c1, c2, list[(i + list.length - 1) % list.length]).sign >
                0,
            insideCur = cross(c1, c2, list[i]).sign > 0;
        if (insidePrev != insideCur)
          next.add(lineIntersection(prev, cur, c1, c2));
        if (insideCur) next.add(cur);
      }
      list = next;
    }
    final deduplicated = [
      for (var i = 0; i < list.length; i++)
        if (list[i] != list[(i + list.length - 1) % list.length]) list[i],
    ];
    if (deduplicated.length >= 3) clipped.add(deduplicated);
  }
  var vertices = 0;
  for (final ring in clipped) {
    vertices += ring.length;
  }
  final rings = flatten(result);
  var match = rings.length == clipped.length;
  if (match) {
    for (final r in rings) {
      if (!clipped.any((other) => cyclicEqual(r, other))) {
        match = false;
        break;
      }
    }
  }
  return (match ? 'match' : 'mismatch', clipped.length, vertices);
}

String location(Result result, Point p) {
  for (var k = 0; k < result.polygons.length; k++) {
    final polygon = result.polygons[k];
    for (var j = 0; j < polygon.rings.length; j++) {
      if (boundary(p, polygon.rings[j]))
        return j == 0 ? 'boundary outer ${k + 1}' : 'boundary hole ${k + 1} $j';
    }
  }
  for (var k = 0; k < result.polygons.length; k++) {
    final polygon = result.polygons[k];
    if (insideRing(p, polygon.rings.first) &&
        !polygon.rings.skip(1).any((r) => insideRing(p, r)))
      return 'inside polygon ${k + 1}';
  }
  return 'outside';
}

String operandLocation(Point p, Polygon polygon) {
  if (polygon.rings.any((r) => boundary(p, r))) return 'boundary';
  return interior(p, polygon.rings) ? 'inside' : 'outside';
}

Rational exactArea(Ring ring) {
  var sum = rational(0);
  for (var i = 0; i < ring.length; i++) {
    final p = ring[i], q = ring[(i + 1) % ring.length];
    sum = sum.add(p.x.mul(q.y).sub(q.x.mul(p.y)));
  }
  return sum.div(rational(2));
}

Ring hull(Ring ring) {
  final sorted = List<Point>.of(ring)
    ..sort((a, b) {
      final c = a.x.compare(b.x);
      return c != 0 ? c : a.y.compare(b.y);
    });
  final lower = <Point>[], upper = <Point>[];
  for (final p in sorted) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower.last, p).sign <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  for (final p in sorted.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper.last, p).sign <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  return [...lower.take(lower.length - 1), ...upper.take(upper.length - 1)];
}

String real(double n, [int digits = 3]) => n.toStringAsFixed(digits);

class Laboratory {
  final Set<String> used = {};
  final Map<String, Polygon> polygons = {};
  final Map<int, Result> results = {};
  final List<String> output = [],
      areas = ['operation,rings,holes,vertices,area'],
      renderLines = [],
      polygonErrors = [],
      operationErrors = [];
  int blocks = 0,
      valid = 0,
      defined = 0,
      operationCount = 0,
      succeeded = 0,
      crossingCount = 0;
  final Map<String, int> attempted = {}, accepted = {};
  void readPolygons() {
    final source = lines('input/polygons.txt');
    for (var i = 0; i < source.length; i++) {
      if (ignored(source[i])) continue;
      final start = i + 1,
          name = source[i].split(' ')[1],
          content = <SourceLine>[];
      i++;
      while (source[i] != 'END') {
        if (!ignored(source[i])) content.add(SourceLine(i + 1, source[i]));
        i++;
      }
      final end = i + 1;
      blocks++;
      var reason = '';
      if (used.contains(name)) {
        reason = 'duplicate_name line $start';
      } else {
        used.add(name);
        final (rings, errorLine) = parseBlock(content, end);
        if (errorLine > 0) {
          reason = 'format line $errorLine';
        } else {
          final input = rings!;
          reason = checkPolygon(input);
          if (reason.isEmpty) {
            polygons[name] = canonical(input);
            valid++;
          }
        }
      }
      if (reason.isNotEmpty) polygonErrors.add('polygon $name $reason');
    }
  }

  (Polygon?, String) polygon(String name) {
    if (!used.contains(name)) return (null, 'unknown_polygon $name');
    final p = polygons[name];
    return p == null ? (null, 'invalid_polygon $name') : (p, '');
  }

  (Result?, String) target(String text) {
    if (text.startsWith('@')) {
      final number = text.substring(1);
      if (unsignedWord.hasMatch(number)) {
        final result = results[int.parse(number)];
        if (result != null) return (result, '');
      }
      return (null, 'bad_target $text');
    }
    final (p, reason) = polygon(text);
    return reason.isNotEmpty ? (null, reason) : (Result([p!]), '');
  }

  void reportRegion(
    int number,
    List<String> words,
    String line,
    Result result,
    Polygon? originA,
    Polygon? originB,
    Polygon? property,
    GHGraph? graph,
  ) {
    output.add('op $number $line');
    if (graph != null) {
      var relation = 'overlap';
      if (graph.crossings.isEmpty) {
        if (graph.nA == graph.rings[0].length && graph.nB == 0) {
          relation = 'within';
        } else if (graph.nB == graph.rings[1].length && graph.nA == 0) {
          relation = 'contains';
        } else if (graph.nA == 0 && graph.nB == 0) {
          relation = 'disjoint';
        }
      }
      final intersection = assemble(graph.traverse(false, false)),
          union = assemble(graph.traverse(true, true)),
          iou = totalArea(intersection) / totalArea(union);
      output.addAll([
        'relation $relation iou ${real(iou, 6)}',
        'crossings ${graph.crossings.length}',
      ]);
      for (final c in graph.crossings) {
        output.add('crossing ${c.point} ${c.first.entering ? 'in' : 'out'}');
      }
      crossingCount += graph.crossings.length;
    }
    final rings = flatten(result.polygons),
        ringCount = rings.length,
        holeCount = rings.length - result.polygons.length;
    var vertices = 0;
    for (final ring in rings) {
      vertices += ring.length;
    }
    final area = totalArea(result.polygons);
    output.add(
      'polygons ${result.polygons.length} rings $ringCount holes $holeCount vertices $vertices area ${real(area)}',
    );
    for (var k = 0; k < result.polygons.length; k++) {
      final p = result.polygons[k];
      for (var j = 0; j < p.rings.length; j++) {
        final r = p.rings[j],
            prefix = j == 0 ? 'outer ${k + 1}' : 'hole ${k + 1} $j';
        output.add('$prefix ${r.length} ${real(ringArea(r))} ${r.join(' ')}');
      }
    }
    var perimeter = 0.0, sx = 0.0, sy = 0.0;
    Point? low, high;
    for (final r in rings) {
      perimeter += ringPerimeter(r);
      for (var i = 0; i < r.length; i++) {
        final p = r[i], q = r[(i + 1) % r.length];
        if (low == null) {
          low = p;
          high = p;
        } else {
          final l = low, h = high!;
          low = Point(
            p.x.compare(l.x) < 0 ? p.x : l.x,
            p.y.compare(l.y) < 0 ? p.y : l.y,
          );
          high = Point(
            p.x.compare(h.x) > 0 ? p.x : h.x,
            p.y.compare(h.y) > 0 ? p.y : h.y,
          );
        }
        final x1 = p.x.real,
            y1 = p.y.real,
            x2 = q.x.real,
            y2 = q.y.real,
            c = x1 * y2 - x2 * y1;
        sx += (x1 + x2) * c;
        sy += (y1 + y2) * c;
      }
    }
    if (low != null) {
      output.addAll([
        'bbox $low $high',
        'centroid (${real(sx / (6 * area))},${real(sy / (6 * area))})',
      ]);
    } else {
      output.addAll(['bbox none', 'centroid none']);
    }
    output.add('perimeter ${real(perimeter)}');
    final aVertices = <Point>{}, bVertices = <Point>{};
    if (originA != null) {
      for (final r in originA.rings) {
        aVertices.addAll(r);
      }
    }
    if (originB != null) {
      for (final r in originB.rings) {
        bVertices.addAll(r);
      }
    }
    var aCount = 0, bCount = 0, cCount = 0;
    for (final r in rings) {
      for (final p in r) {
        if (aVertices.contains(p)) {
          aCount++;
        } else if (bVertices.contains(p)) {
          bCount++;
        } else {
          cCount++;
        }
      }
    }
    output.add('origins a $aCount b $bCount crossing $cCount');
    if (property != null) {
      final orientations = [
        for (final r in property.input) exactArea(r).sign > 0 ? 'ccw' : 'cw',
      ];
      var reflex = 0;
      for (final r in property.rings) {
        for (var i = 0; i < r.length; i++) {
          if (cross(
                r[(i + r.length - 1) % r.length],
                r[i],
                r[(i + 1) % r.length],
              ).sign <
              0)
            reflex++;
        }
      }
      final h = hull(property.rings.first), hullArea = exactArea(h).real;
      output.addAll([
        'input ${orientations.join(' ')}',
        'reflex $reflex',
        'hull ${h.length} ${real(hullArea)} solidity ${real(area / hullArea, 6)}',
      ]);
    }
    if (words[0] == 'CLIP') {
      final (judgment, k, v) = sutherland(
        result.a!,
        result.b!,
        result.polygons,
      );
      output.add('crosscheck $judgment rings $k vertices $v');
    }
    areas.add(
      '$number:${words.join(':')},$ringCount,$holeCount,$vertices,${real(area)}',
    );
  }

  String operation(int number, String line) {
    final a = line.split(' '), kind = a[0];
    if (!kinds.contains(kind)) return 'unknown_operation $kind';
    if (!validArguments(a)) return 'bad_arguments';
    final binary = [
          'UNION',
          'INTERSECTION',
          'DIFFERENCE',
          'XOR',
          'CLIP',
        ].contains(kind),
        definition = ['MOVE', 'ROTATE', 'MIRROR', 'SNAP'].contains(kind);
    Polygon? first, second, property;
    Result? resolvedTarget;
    if (binary || ['AREA', 'MOVE', 'ROTATE', 'MIRROR'].contains(kind)) {
      final found = polygon(a[1]);
      if (found.$2.isNotEmpty) return found.$2;
      first = found.$1;
      if (binary) {
        final found = polygon(a[2]);
        if (found.$2.isNotEmpty) return found.$2;
        second = found.$1;
      }
    } else {
      final found = target(a[1]);
      if (found.$2.isNotEmpty) return found.$2;
      resolvedTarget = found.$1;
    }
    var newName = '';
    if (definition) {
      newName = a.last;
      if (used.contains(newName)) return 'duplicate_name $newName';
    }
    if (kind == 'SNAP' && resolvedTarget!.polygons.length != 1)
      return 'not_single ${a[1]}';
    if (kind == 'CLIP' && !convex(second!)) return 'not_convex ${a[2]}';
    if (binary) {
      final reason = generalPosition(first!, second!, a[1], a[2]);
      if (reason.isNotEmpty) return reason;
    }
    if (definition) {
      List<Ring> input;
      if (kind == 'SNAP') {
        input = [
          for (final ring in resolvedTarget!.polygons.first.rings)
            [for (final p in ring) point(p.x.round(), p.y.round())],
        ];
        final reason = checkPolygon(input);
        if (reason.isNotEmpty) return 'invalid_result $reason';
      } else {
        input = transformed(first!, a);
        for (final ring in input) {
          for (final p in ring) {
            if (!inRange(p)) return 'out_of_range $newName';
          }
        }
      }
      final p = canonical(input);
      property = p;
      used.add(newName);
      polygons[newName] = p;
      defined++;
    }
    succeeded++;
    accepted[kind] = (accepted[kind] ?? 0) + 1;
    if (kind == 'LOCATE') {
      final target = resolvedTarget!,
          p = point(int.parse(a[2]), int.parse(a[3]));
      output.addAll(['op $number $line', 'location ${location(target, p)}']);
      if (target.a != null && target.b != null)
        output.add(
          'operands a ${operandLocation(p, target.a!)} b ${operandLocation(p, target.b!)}',
        );
      return '';
    }
    if (kind == 'RENDER') {
      final picture = render(
        resolvedTarget!,
        int.parse(a[2]),
        int.parse(a[3]),
        int.parse(a[4]),
        int.parse(a[5]),
        int.parse(a[6]),
        int.parse(a[7]),
      );
      renderLines.add(
        'render $number ${a[1]} cols ${int.parse(a[6])} rows ${int.parse(a[7])} result ${picture.result} a ${picture.a} b ${picture.b} both ${picture.both}',
      );
      renderLines.addAll(picture.rows);
      return '';
    }
    Result result;
    GHGraph? graph;
    var originA = first, originB = second;
    if (binary) {
      final left = first!,
          right = second!,
          g = GHGraph(left.rings, right.rings);
      graph = g;
      List<Polygon> regions;
      switch (kind) {
        case 'UNION':
          regions = assemble(g.traverse(true, true));
          break;
        case 'DIFFERENCE':
          regions = assemble(g.traverse(true, false));
          break;
        case 'XOR':
          regions =
              [
                ...assemble(g.traverse(true, false)),
                ...assemble(
                  GHGraph(right.rings, left.rings).traverse(true, false),
                ),
              ]..sort(
                (a, b) =>
                    pointCompare(a.rings.first.first, b.rings.first.first),
              );
          break;
        default:
          regions = assemble(g.traverse(false, false));
      }
      result = Result(regions, a: left, b: right);
    } else {
      if (!definition) property = first;
      originA = property;
      originB = null;
      result = Result([property!]);
    }
    results[number] = result;
    reportRegion(number, a, line, result, originA, originB, property, graph);
    return '';
  }
}

void writeLines(String name, List<String> lines) => File(
  'output/$name',
).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
void main() {
  final laboratory = Laboratory();
  laboratory.readPolygons();
  for (final line in lines('input/operations.txt')) {
    if (ignored(line)) continue;
    laboratory.operationCount++;
    final kind = line.split(' ')[0];
    laboratory.attempted[kind] = (laboratory.attempted[kind] ?? 0) + 1;
    final reason = laboratory.operation(laboratory.operationCount, line);
    if (reason.isNotEmpty)
      laboratory.operationErrors.add('op ${laboratory.operationCount} $reason');
  }
  laboratory.output.addAll([
    'summary polygons ${laboratory.blocks} valid ${laboratory.valid} invalid ${laboratory.blocks - laboratory.valid} defined ${laboratory.defined}',
    'summary operations ${laboratory.operationCount} succeeded ${laboratory.succeeded} rejected ${laboratory.operationErrors.length}',
    'summary crossings ${laboratory.crossingCount}',
  ]);
  for (final kind in kinds) {
    laboratory.output.add(
      'kind $kind ${laboratory.attempted[kind] ?? 0} ${laboratory.accepted[kind] ?? 0}',
    );
  }
  final rejections = [
    'rejections ${laboratory.polygonErrors.length + laboratory.operationErrors.length}',
    ...laboratory.polygonErrors,
    ...laboratory.operationErrors,
  ];
  Directory('output').createSync(recursive: true);
  writeLines('results.txt', laboratory.output);
  writeLines('areas.csv', laboratory.areas);
  writeLines('render.txt', laboratory.renderLines);
  writeLines('rejections.txt', rejections);
}
