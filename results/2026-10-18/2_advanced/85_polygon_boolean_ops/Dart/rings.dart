part of 'main.dart';

typedef Ring = List<Point>;
bool insideRing(Point p, Ring ring) {
  var inside = false;
  for (var i = 0; i < ring.length; i++) {
    final u = ring[i], w = ring[(i + 1) % ring.length];
    if ((u.y.compare(p.y) > 0) == (w.y.compare(p.y) > 0)) continue;
    final lo = u.y.compare(w.y) < 0 ? u : w, hi = u.y.compare(w.y) < 0 ? w : u;
    if (cross(lo, hi, p).sign > 0) inside = !inside;
  }
  return inside;
}

bool interior(Point p, List<Ring> rings) {
  var inside = false;
  for (final ring in rings) {
    if (insideRing(p, ring)) inside = !inside;
  }
  return inside;
}

bool boundary(Point p, Ring ring) {
  for (var i = 0; i < ring.length; i++) {
    if (onSegment(p, ring[i], ring[(i + 1) % ring.length])) return true;
  }
  return false;
}

Ring rotate(Ring ring) {
  var first = 0;
  for (var i = 0; i < ring.length; i++) {
    if (pointCompare(ring[i], ring[first]) < 0) first = i;
  }
  return [...ring.skip(first), ...ring.take(first)];
}

bool ccw(Ring ring) => cross(ring.last, ring.first, ring[1]).sign > 0;
Ring reverse(Ring ring) => [ring.first, ...ring.skip(1).toList().reversed];
Ring normalize(Ring ring, bool outer) {
  var out = rotate(ring);
  if (ccw(out) != outer) out = reverse(out);
  return out;
}

Polygon canonical(List<Ring> input) {
  final outer = normalize(input.first, true),
      holes = [for (final ring in input.skip(1)) normalize(ring, false)]
        ..sort((a, b) => pointCompare(a.first, b.first));
  return Polygon(
    [for (final ring in input) List<Point>.of(ring)],
    [outer, ...holes],
  );
}

List<Polygon> assemble(List<Ring> input) {
  final rings = [for (final r in input) rotate(r)],
      depth = List.filled(input.length, 0);
  for (var i = 0; i < rings.length; i++) {
    for (var j = 0; j < rings.length; j++) {
      if (i != j && insideRing(rings[i].first, rings[j])) depth[i]++;
    }
    if (ccw(rings[i]) != (depth[i] % 2 == 0)) rings[i] = reverse(rings[i]);
  }
  final outer = [
    for (var i = 0; i < rings.length; i++)
      if (depth[i] % 2 == 0) i,
  ]..sort((i, j) => pointCompare(rings[i].first, rings[j].first));
  final out = <Polygon>[];
  for (final i in outer) {
    final holes = [
      for (var j = 0; j < rings.length; j++)
        if (depth[j] == depth[i] + 1 && insideRing(rings[j].first, rings[i]))
          rings[j],
    ]..sort((a, b) => pointCompare(a.first, b.first));
    out.add(Polygon([], [rings[i], ...holes]));
  }
  return out;
}

double ringArea(Ring ring) {
  var sum = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final p = ring[i], q = ring[(i + 1) % ring.length];
    sum += p.x.real * q.y.real - q.x.real * p.y.real;
  }
  return sum / 2;
}

double ringPerimeter(Ring ring) {
  var sum = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final p = ring[i],
        q = ring[(i + 1) % ring.length],
        dx = q.x.real - p.x.real,
        dy = q.y.real - p.y.real;
    sum += sqrt(dx * dx + dy * dy);
  }
  return sum;
}

List<Ring> flatten(List<Polygon> polygons) => [
  for (final p in polygons) ...p.rings,
];
double totalArea(List<Polygon> polygons) {
  var sum = 0.0;
  for (final ring in flatten(polygons)) {
    sum += ringArea(ring);
  }
  return sum;
}
