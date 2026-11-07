import 'dart:io';
import 'dart:math' hide Point;

part 'pgm_io.dart';
part 'filters.dart';
part 'canny.dart';
part 'hough.dart';
part 'corners.dart';

class Circle {
  final int number;
  final CircleCell cell;
  final List<Point> offsets;
  int gap = 0, arcs = 0;
  late Shape shape;
  Circle(this.number, this.cell, this.offsets);
}

class Segment {
  final int number, theta;
  final Point start, end;
  final int length, pixels;
  Segment(
    this.number,
    this.theta,
    this.start,
    this.end,
    this.length,
    this.pixels,
  );
}

class Line {
  final int number;
  final LineCell cell;
  final segments = <Segment>[];
  Line(this.number, this.cell);
}

class Junction {
  final int a, b, endA, endB;
  final Point point;
  Junction(this.a, this.b, this.endA, this.endB, this.point);
  int endFor(int segment) => segment == a ? endA : endB;
}

class Polygon {
  final int number;
  final List<int> segments;
  final List<Point> vertices;
  final angles = <int>[],
      lengths = <int>[],
      supports = <int>[],
      vertexCorners = <int>[];
  int sigma = 0;
  String kind = '';
  final explained = <Point>{};
  late Shape shape;
  Polygon(this.number, this.segments, this.vertices);
}

class Shape {
  final String name;
  final Polygon? polygon;
  final Circle? circle;
  final List<Point> representatives;
  int pixels = 0, mean = 0, contrast = 0;
  String enclosing = 'none';
  Shape(this.name, this.representatives, {this.polygon, this.circle});
  bool contains(Point point) {
    final c = circle;
    if (c != null) {
      final dx = point.$1 - c.cell.x, dy = point.$2 - c.cell.y;
      return dx * dx + dy * dy <= c.cell.radius * c.cell.radius;
    }
    final p = polygon!;
    for (var i = 0; i < p.vertices.length; i++) {
      final v = p.vertices[i],
          next = p.vertices[(i + 1) % p.vertices.length],
          value = cross(pointSub(next, v), pointSub(point, v));
      if (p.sigma > 0 && value < 0 || p.sigma < 0 && value > 0) {
        return false;
      }
    }
    return true;
  }
}

Point pointSub(Point a, Point b) => (a.$1 - b.$1, a.$2 - b.$2);
int dot(Point a, Point b) => a.$1 * b.$1 + a.$2 * b.$2;
int chebyshev(Point a, Point b) =>
    max((a.$1 - b.$1).abs(), (a.$2 - b.$2).abs());
int angleDifference(int a, int b) {
  final d = (a - b).abs();
  return min(d, 180 - d);
}

int roundRatio(int n, int d) {
  if (d < 0) {
    n = -n;
    d = -d;
  }
  return floorDiv(2 * n + d, 2 * d);
}

List<Point> bresenham(Point a, Point b) {
  var x = a.$1, y = a.$2;
  final dx = (b.$1 - x).abs(),
      dy = -(b.$2 - y).abs(),
      sx = x < b.$1 ? 1 : -1,
      sy = y < b.$2 ? 1 : -1,
      result = <Point>[];
  var error = dx + dy;
  while (true) {
    result.add((x, y));
    if (x == b.$1 && y == b.$2) {
      return result;
    }
    final twice = 2 * error;
    if (twice >= dy) {
      error += dy;
      x += sx;
    }
    if (twice <= dx) {
      error += dx;
      y += sy;
    }
  }
}

bool edgeAt(Mask edge, Point p) =>
    inside(p, edge.first.length, edge.length) && edge[p.$2][p.$1];
bool nearEdge(Mask edge, Point p) {
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      if (edgeAt(edge, (p.$1 + dx, p.$2 + dy))) {
        return true;
      }
    }
  }
  return false;
}

bool circumference(Circle circle, Point p) {
  final dx = p.$1 - circle.cell.x,
      dy = p.$2 - circle.cell.y,
      d = dx * dx + dy * dy,
      r = circle.cell.radius;
  return (r - 1) * (r - 1) <= d && d <= (r + 1) * (r + 1);
}

List<Circle> chooseCircles(CircleVoting voting, Mask edge, int limit) {
  final result = <Circle>[];
  for (final cell in voting.peaks.take(limit)) {
    final circle = Circle(
          result.length + 1,
          cell,
          voting.offsets[cell.radius - voting.minimum],
        ),
        hits = <bool>[];
    var count = 0;
    for (final offset in circle.offsets) {
      final hit = edgeAt(edge, (cell.x + offset.$1, cell.y + offset.$2));
      hits.add(hit);
      if (hit) {
        count++;
      }
    }
    if (count == hits.length) {
      circle.arcs = 1;
    } else if (count == 0) {
      circle.gap = hits.length;
    } else {
      for (var j = 0; j < hits.length; j++) {
        if (hits[j] && !hits[(j + hits.length - 1) % hits.length]) {
          circle.arcs++;
        }
      }
      var run = 0;
      for (var j = 0; j < 2 * hits.length; j++) {
        if (hits[j % hits.length]) {
          run = 0;
        } else {
          run++;
          circle.gap = max(circle.gap, run);
        }
      }
    }
    result.add(circle);
  }
  return result;
}

(List<Line>, List<Segment>, Mask) extractSegments(
  List<Point> points,
  LineVoting voting,
  List<Point> trig,
  Params p,
  int width,
  int height,
) {
  final used = newMask(width, height), lines = <Line>[], segments = <Segment>[];
  for (final cell in voting.peaks) {
    if (lines.length == p.integer('hough_max_lines')) {
      break;
    }
    final collected = [
      for (final point in points)
        if (!used[point.$2][point.$1] &&
            (rho(point, cell.theta, trig, p.integer('hough_rho_step')) -
                        cell.rho)
                    .abs() <=
                p.integer('segment_tolerance'))
          point,
    ];
    int u(Point point) =>
        point.$2 * trig[cell.theta].$1 - point.$1 * trig[cell.theta].$2;
    collected.sort((a, b) {
      final c = u(a).compareTo(u(b)), x = a.$1.compareTo(b.$1);
      return c != 0
          ? c
          : x != 0
          ? x
          : a.$2.compareTo(b.$2);
    });
    final line = Line(lines.length + 1, cell);
    for (var start = 0; start < collected.length;) {
      var end = start + 1;
      while (end < collected.length &&
          u(collected[end]) - u(collected[end - 1]) <=
              p.integer('segment_max_gap') * 16384) {
        end++;
      }
      final group = collected.sublist(start, end),
          length = chebyshev(group.first, group.last) + 1;
      if (length >= p.integer('segment_min_length')) {
        final segment = Segment(
          segments.length + 1,
          cell.theta,
          group.first,
          group.last,
          length,
          group.length,
        );
        line.segments.add(segment);
        segments.add(segment);
        for (final point in group) {
          used[point.$2][point.$1] = true;
        }
      }
      start = end;
    }
    if (line.segments.isNotEmpty) {
      lines.add(line);
    }
  }
  return (lines, segments, used);
}

(int, int) pairKey(int a, int b) => a < b ? (a, b) : (b, a);
(Map<(int, int), Junction>, List<List<int>>) junctions(
  List<Segment> segments,
  Params p,
) {
  final found = <(int, int), Junction>{},
      adjacent = List.generate(segments.length, (_) => <int>[]);
  for (var i = 0; i < segments.length; i++) {
    final a = segments[i];
    for (var j = i + 1; j < segments.length; j++) {
      final b = segments[j];
      if (angleDifference(a.theta, b.theta) < p.integer('junction_min_angle')) {
        continue;
      }
      final da = pointSub(a.end, a.start),
          db = pointSub(b.end, b.start),
          den = cross(da, db);
      if (den == 0) {
        continue;
      }
      final lambda = cross(pointSub(b.start, a.start), db),
          x = (
            roundRatio(a.start.$1 * den + lambda * da.$1, den),
            roundRatio(a.start.$2 * den + lambda * da.$2, den),
          );
      var endA = 0,
          endB = 0,
          distanceA = chebyshev(a.start, x),
          distanceB = chebyshev(b.start, x);
      final daEnd = chebyshev(a.end, x), dbEnd = chebyshev(b.end, x);
      if (daEnd < distanceA) {
        distanceA = daEnd;
        endA = 1;
      }
      if (dbEnd < distanceB) {
        distanceB = dbEnd;
        endB = 1;
      }
      if (distanceA <= p.integer('junction_distance') &&
          distanceB <= p.integer('junction_distance')) {
        found[pairKey(a.number, b.number)] = Junction(
          a.number,
          b.number,
          endA,
          endB,
          x,
        );
        adjacent[i].add(b.number);
        adjacent[j].add(a.number);
      }
    }
  }
  for (final row in adjacent) {
    row.sort();
  }
  return (found, adjacent);
}

List<Polygon> findPolygons(
  List<Segment> segments,
  Map<(int, int), Junction> joins,
  List<List<int>> adjacent,
) {
  final result = <Polygon>[];
  for (final size in [3, 4]) {
    for (var first = 1; first <= segments.length; first++) {
      void extend(List<int> path) {
        final last = path.last;
        if (path.length == size) {
          final closing = joins[pairKey(last, first)];
          if (closing == null || path[1] >= last) {
            return;
          }
          final previous = joins[pairKey(path[path.length - 2], last)]!,
              opening = joins[pairKey(first, path[1])]!;
          if (previous.endFor(last) == closing.endFor(last) ||
              closing.endFor(first) == opening.endFor(first)) {
            return;
          }
          final vertices = [
            for (var i = 0; i < size; i++)
              joins[pairKey(path[(i + size - 1) % size], path[i])]!.point,
          ];
          var sign = 0;
          for (var i = 0; i < size; i++) {
            final v = vertices[i],
                a = vertices[(i + 1) % size],
                b = vertices[(i + 2) % size],
                z = cross(pointSub(a, v), pointSub(b, a));
            if (z == 0) {
              return;
            }
            final currentSign = z < 0 ? -1 : 1;
            if (sign != 0 && currentSign != sign) {
              return;
            }
            sign = currentSign;
          }
          result.add(Polygon(result.length + 1, List<int>.of(path), vertices));
          return;
        }
        for (final next in adjacent[last - 1]) {
          if (next <= first || path.contains(next)) {
            continue;
          }
          if (path.length > 1) {
            final before = joins[pairKey(path[path.length - 2], last)]!,
                after = joins[pairKey(last, next)]!;
            if (before.endFor(last) == after.endFor(last)) {
              continue;
            }
          }
          extend([...path, next]);
        }
      }

      extend([first]);
    }
  }
  return result;
}

void polygonAttributes(
  Polygon polygon,
  List<Segment> segments,
  Mask edge,
  Params p,
) {
  final size = polygon.vertices.length;
  for (var i = 0; i < size; i++) {
    final v = polygon.vertices[i],
        previous = polygon.vertices[(i + size - 1) % size],
        next = polygon.vertices[(i + 1) % size],
        thetaPrevious =
            segments[polygon.segments[(i + size - 1) % size] - 1].theta,
        theta = segments[polygon.segments[i] - 1].theta;
    var angle = angleDifference(thetaPrevious, theta);
    if (dot(pointSub(previous, v), pointSub(next, v)) < 0) {
      angle = 180 - angle;
    }
    polygon.angles.add(angle);
    final delta = pointSub(next, v);
    polygon.lengths.add(delta.$1 * delta.$1 + delta.$2 * delta.$2);
    polygon.sigma += cross(v, next);
    final points = bresenham(v, next);
    var hits = 0;
    for (final point in points) {
      if (nearEdge(edge, point)) {
        hits++;
      }
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final q = (point.$1 + dx, point.$2 + dy);
          if (inside(q, edge.first.length, edge.length)) {
            polygon.explained.add(q);
          }
        }
      }
    }
    polygon.supports.add(100 * hits ~/ points.length);
  }
  final tolerance = p.integer('angle_tolerance'),
      right = polygon.angles.every((a) => (a - 90).abs() <= tolerance),
      equilateral = polygon.angles.every((a) => (a - 60).abs() <= tolerance),
      someRight = polygon.angles.any((a) => (a - 90).abs() <= tolerance);
  if (size == 3) {
    polygon.kind = equilateral
        ? 'equilateral_triangle'
        : someRight
        ? 'right_triangle'
        : 'triangle';
    return;
  }
  int theta(int i) => segments[polygon.segments[i] - 1].theta;
  final parallelA = angleDifference(theta(0), theta(2)) <= tolerance,
      parallelB = angleDifference(theta(1), theta(3)) <= tolerance;
  if (!parallelA && !parallelB) {
    polygon.kind = 'quadrilateral';
  } else if (parallelA != parallelB) {
    polygon.kind = 'trapezoid';
  } else if (!right) {
    polygon.kind = 'parallelogram';
  } else {
    final smallest = polygon.lengths.reduce(min),
        largest = polygon.lengths.reduce(max);
    polygon.kind =
        100 * (largest - smallest) <= p.integer('square_tolerance') * largest
        ? 'square'
        : 'rectangle';
  }
}

List<Shape> measureShapes(
  List<Polygon> polygons,
  List<Circle> circles,
  Image image,
  int margin,
) {
  final shapes = <Shape>[];
  for (final polygon in polygons) {
    final shape = Shape(
      'polygon ${polygon.number}',
      polygon.vertices,
      polygon: polygon,
    );
    polygon.shape = shape;
    shapes.add(shape);
  }
  for (final circle in circles) {
    final c = circle.cell,
        shape = Shape('circle ${circle.number}', [
          (c.x + c.radius, c.y),
          (c.x, c.y + c.radius),
          (c.x - c.radius, c.y),
          (c.x, c.y - c.radius),
        ], circle: circle);
    circle.shape = shape;
    shapes.add(shape);
  }
  for (final shape in shapes) {
    var x0 = shape.representatives.first.$1,
        x1 = x0,
        y0 = shape.representatives.first.$2,
        y1 = y0;
    for (final q in shape.representatives.skip(1)) {
      x0 = min(x0, q.$1);
      x1 = max(x1, q.$1);
      y0 = min(y0, q.$2);
      y1 = max(y1, q.$2);
    }
    x0 = max(0, x0 - margin);
    x1 = min(image.first.length - 1, x1 + margin);
    y0 = max(0, y0 - margin);
    y1 = min(image.length - 1, y1 + margin);
    var innerSum = 0, outerSum = 0, outerCount = 0;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        if (shape.contains((x, y))) {
          shape.pixels++;
          innerSum += image[y][x];
        } else {
          outerCount++;
          outerSum += image[y][x];
        }
      }
    }
    shape.mean = shape.pixels == 0 ? 0 : floorDiv(innerSum, shape.pixels);
    shape.contrast =
        shape.mean - (outerCount == 0 ? 0 : floorDiv(outerSum, outerCount));
  }
  for (final shape in shapes) {
    Shape? enclosing;
    for (final other in shapes) {
      if (identical(other, shape) ||
          other.pixels <= shape.pixels ||
          enclosing != null && other.pixels >= enclosing.pixels) {
        continue;
      }
      if (shape.representatives.every(other.contains)) {
        enclosing = other;
      }
    }
    if (enclosing != null) {
      shape.enclosing = enclosing.name;
    }
  }
  return shapes;
}

(int, int, int) matchCorners(
  List<Corner> corners,
  List<Polygon> polygons,
  List<Segment> segments,
  int limit,
) {
  var onVertices = 0, onSegments = 0, verticesWithCorner = 0;
  for (final corner in corners) {
    var best = limit + 1;
    for (final polygon in polygons) {
      for (var i = 0; i < polygon.vertices.length; i++) {
        final d = chebyshev(corner.point, polygon.vertices[i]);
        if (d < best) {
          best = d;
          corner.match = 'polygon ${polygon.number} vertex ${i + 1}';
        }
      }
    }
    if (best <= limit) {
      onVertices++;
      continue;
    }
    for (final segment in segments) {
      final ends = [segment.start, segment.end];
      for (var i = 0; i < 2; i++) {
        final d = chebyshev(corner.point, ends[i]);
        if (d < best) {
          best = d;
          corner.match =
              'segment ${segment.number} ${i == 0 ? 'start' : 'end'}';
        }
      }
    }
    if (best <= limit) {
      onSegments++;
    }
  }
  for (final polygon in polygons) {
    for (final vertex in polygon.vertices) {
      var best = limit + 1, number = 0;
      for (final corner in corners) {
        final d = chebyshev(vertex, corner.point);
        if (d < best) {
          best = d;
          number = corner.number;
        }
      }
      polygon.vertexCorners.add(number);
      if (number > 0) {
        verticesWithCorner++;
      }
    }
  }
  return (onVertices, onSegments, verticesWithCorner);
}

List<String> componentLines(
  List<List<Point>> groups,
  Mask edge,
  Image magnitude,
  Image direction,
  List<Shape> shapes,
) {
  final lines = <String>['components ${groups.length}'];
  for (var i = 0; i < groups.length; i++) {
    final group = groups[i], counts = <int, int>{};
    var x0 = group.first.$1,
        x1 = x0,
        y0 = group.first.$2,
        y1 = y0,
        ends = 0,
        total = 0;
    for (final point in group) {
      x0 = min(x0, point.$1);
      x1 = max(x1, point.$1);
      y0 = min(y0, point.$2);
      y1 = max(y1, point.$2);
      final degree = neighbors(
        point,
        edge.first.length,
        edge.length,
      ).where((q) => edge[q.$2][q.$1]).length;
      if (degree == 1) {
        ends++;
      }
      total += magnitude[point.$2][point.$1];
      final d = direction[point.$2][point.$1];
      counts[d] = (counts[d] ?? 0) + 1;
    }
    var mainDirection = 0;
    for (final d in [45, 90, 135]) {
      if ((counts[d] ?? 0) > (counts[mainDirection] ?? 0)) {
        mainDirection = d;
      }
    }
    var match = 'none', explained = 0;
    for (final shape in shapes) {
      var count = 0;
      for (final point in group) {
        if (shape.circle != null
            ? circumference(shape.circle!, point)
            : shape.polygon!.explained.contains(point)) {
          count++;
        }
      }
      if (count > explained) {
        explained = count;
        match = shape.name;
      }
    }
    lines.add(
      'component ${i + 1} pixels ${group.length} box $x0 $y0 $x1 $y1 ends $ends strength ${total ~/ group.length} direction $mainDirection shape $match explained $explained',
    );
  }
  return lines;
}

List<String> lineLines(List<Line> lines) => [
  'lines ${lines.length}',
  for (final line in lines) ...[
    'line ${line.number} theta ${line.cell.theta} rho ${line.cell.rho} votes ${line.cell.votes} segments ${line.segments.length}',
    for (final s in line.segments)
      'segment ${s.number} start ${s.start.$1} ${s.start.$2} end ${s.end.$1} ${s.end.$2} length ${s.length} pixels ${s.pixels}',
  ],
];
List<String> circleLines(List<Circle> circles) => [
  'circles ${circles.length}',
  for (final c in circles)
    'circle ${c.number} center ${c.cell.x} ${c.cell.y} radius ${c.cell.radius} votes ${c.cell.votes} points ${c.cell.points} gap ${c.gap} arcs ${c.arcs} pixels ${c.shape.pixels} mean ${c.shape.mean} contrast ${c.shape.contrast} inside ${c.shape.enclosing}',
];
List<String> polygonLines(List<Polygon> polygons) {
  final lines = <String>['polygons ${polygons.length}'];
  for (final polygon in polygons) {
    final shape = polygon.shape, sigma = polygon.sigma.abs();
    lines.add(
      'polygon ${polygon.number} ${polygon.kind} segments ${polygon.segments.join(' ')} area ${sigma ~/ 2}.${5 * (sigma % 2)} pixels ${shape.pixels} mean ${shape.mean} contrast ${shape.contrast} inside ${shape.enclosing}',
    );
    for (var i = 0; i < polygon.vertices.length; i++) {
      final v = polygon.vertices[i], corner = polygon.vertexCorners[i];
      lines.add(
        'vertex ${i + 1} ${v.$1} ${v.$2} angle ${polygon.angles[i]} corner ${corner == 0 ? 'none' : corner}',
      );
    }
    for (var i = 0; i < polygon.segments.length; i++) {
      lines.add(
        'side ${i + 1} segment ${polygon.segments[i]} length2 ${polygon.lengths[i]} support ${polygon.supports[i]}',
      );
    }
  }
  return lines;
}

List<String> cornerLines(List<Corner> corners) => [
  'corners ${corners.length}',
  for (final c in corners)
    'corner ${c.number} ${c.point.$1} ${c.point.$2} response ${c.response} match ${c.match}',
];
Image overlay(
  Image image,
  List<Segment> segments,
  List<Circle> circles,
  List<Corner> corners,
  int divisor,
) {
  final width = image.first.length,
      height = image.length,
      result = [
        for (final row in image) [for (final v in row) v ~/ divisor],
      ];
  void mark(Point q) {
    if (inside(q, width, height)) {
      result[q.$2][q.$1] = 255;
    }
  }

  for (final segment in segments) {
    for (final q in bresenham(segment.start, segment.end)) {
      mark(q);
    }
  }
  for (final c in circles) {
    for (final o in c.offsets) {
      mark((c.cell.x + o.$1, c.cell.y + o.$2));
    }
  }
  for (final c in corners) {
    for (var e = -2; e <= 2; e++) {
      mark((c.point.$1 + e, c.point.$2));
      mark((c.point.$1, c.point.$2 + e));
    }
  }
  return result;
}

void main() {
  final (image, trig, p) = readInputs();
  final width = image.first.length, height = image.length;
  final (gx, gy, magnitude) = gradient(smooth(image, p));
  final direction = directions(gx, gy), nms = suppress(magnitude, direction);
  final (edge, strong, weak, weakKept) = hysteresis(
    nms,
    p.integer('canny_low'),
    p.integer('canny_high'),
  );
  final groups = components(edge),
      circleVoting = circleVote(edge, p),
      circles = chooseCircles(
        circleVoting,
        edge,
        p.integer('circle_max_count'),
      ),
      linePoints = <Point>[],
      edgeImage = newImage(width, height),
      counts = <String, int>{};
  void increment(String key) {
    counts[key] = (counts[key] ?? 0) + 1;
  }

  var edgePixels = 0, circleEdgePixels = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = magnitude[y][x];
      if (value > 0) {
        increment('gradient_nonzero');
      }
      counts['gradient_max'] = max(counts['gradient_max'] ?? 0, value);
      if (nms[y][x] > 0) {
        increment('nms_kept');
      }
      if (!edge[y][x]) {
        continue;
      }
      edgePixels++;
      edgeImage[y][x] = 255;
      increment('direction_${direction[y][x]}');
      if (circles.any((c) => circumference(c, (x, y)))) {
        circleEdgePixels++;
      } else {
        linePoints.add((x, y));
      }
    }
  }
  final lineVoting = lineVote(
    linePoints,
    width,
    height,
    trig,
    p.integer('hough_rho_step'),
    p.integer('hough_threshold'),
  );
  final (lines, segments, used) = extractSegments(
    linePoints,
    lineVoting,
    trig,
    p,
    width,
    height,
  );
  final (joins, adjacent) = junctions(segments, p);
  final polygons = findPolygons(segments, joins, adjacent);
  for (final polygon in polygons) {
    polygonAttributes(polygon, segments, edge, p);
    increment(polygon.kind);
  }
  final shapes = measureShapes(
    polygons,
    circles,
    image,
    p.integer('contrast_margin'),
  );
  final (corners, cornerCandidates) = harris(gx, gy, p);
  final (onVertices, onSegments, verticesWithCorner) = matchCorners(
    corners,
    polygons,
    segments,
    p.integer('corner_match_distance'),
  );
  final claimed = used.expand((row) => row).where((v) => v).length,
      voteImage = newImage(180, lineVoting.high - lineVoting.low + 1);
  if (lineVoting.maximum > 0) {
    for (var t = 0; t < 180; t++) {
      for (final entry in lineVoting.votes[t].entries) {
        voteImage[entry.key - lineVoting.low][t] =
            255 * entry.value ~/ lineVoting.maximum;
      }
    }
  }
  writePGM('edges.pgm', edgeImage);
  writePGM('hough.pgm', voteImage);
  writePGM(
    'overlay.pgm',
    overlay(image, segments, circles, corners, p.integer('overlay_divisor')),
  );
  writeLines('lines.txt', lineLines(lines));
  writeLines('circles.txt', circleLines(circles));
  writeLines('polygons.txt', polygonLines(polygons));
  writeLines('corners.txt', cornerLines(corners));
  writeLines(
    'components.txt',
    componentLines(groups, edge, magnitude, direction, shapes),
  );
  counts.addAll({
    'strong': strong,
    'weak': weak,
    'edges': edgePixels,
    'weak_kept': weakKept,
    'weak_dropped': weak - weakKept,
    'edge_components': groups.length,
    'circle_candidates': circleVoting.candidates,
    'circle_peaks': circleVoting.peaks.length,
    'circles': circles.length,
    'circle_edge_pixels': circleEdgePixels,
    'line_edge_pixels': linePoints.length,
    'hough_max_votes': lineVoting.maximum,
    'hough_peaks': lineVoting.peaks.length,
    'lines': lines.length,
    'segments': segments.length,
    'claimed_pixels': claimed,
    'junctions': joins.length,
    'polygons': polygons.length,
    'corner_candidates': cornerCandidates,
    'corners': corners.length,
    'corners_on_vertices': onVertices,
    'corners_on_segments': onSegments,
    'corners_unmatched': corners.length - onVertices - onSegments,
    'vertices_with_corner': verticesWithCorner,
  });
  const keys = [
    'gradient_nonzero',
    'gradient_max',
    'nms_kept',
    'strong',
    'weak',
    'edges',
    'weak_kept',
    'weak_dropped',
    'edge_components',
    'direction_0',
    'direction_45',
    'direction_90',
    'direction_135',
    'circle_candidates',
    'circle_peaks',
    'circles',
    'circle_edge_pixels',
    'line_edge_pixels',
    'hough_max_votes',
    'hough_peaks',
    'lines',
    'segments',
    'claimed_pixels',
    'junctions',
    'polygons',
    'equilateral_triangle',
    'right_triangle',
    'triangle',
    'square',
    'rectangle',
    'parallelogram',
    'trapezoid',
    'quadrilateral',
    'corner_candidates',
    'corners',
    'corners_on_vertices',
    'corners_on_segments',
    'corners_unmatched',
    'vertices_with_corner',
  ];
  writeLines('report.txt', [
    'image $width $height',
    for (final key in keys) '$key ${counts[key] ?? 0}',
  ]);
}
