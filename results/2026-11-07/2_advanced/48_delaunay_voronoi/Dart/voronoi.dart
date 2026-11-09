part of 'main.dart';

double squaredRadius(Point a, Point b, Point c) {
  final l1 = d2(a, b).toDouble(),
      l2 = d2(b, c).toDouble(),
      l3 = d2(c, a).toDouble(),
      area = orient(a, b, c).toDouble();
  return ((l1 * l2) * l3) / ((4 * area) * area);
}

String position(Center center, List<Point> points, List<int> hull) {
  var on = false;
  for (var i = 0; i < hull.length; i++) {
    final a = points[hull[i]], b = points[hull[(i + 1) % hull.length]];
    final sigma =
        (b.x - a.x) * (center.y - a.y * center.d) -
        (b.y - a.y) * (center.x - a.x * center.d);
    if (sigma < 0) {
      return 'outside';
    }
    if (sigma == 0) {
      on = true;
    }
  }
  return on ? 'on' : 'inside';
}

List<int> neighborOrder(
  int s,
  List<int> neighbors,
  Map<Edge, int> directed,
  Map<int, int> hullNext,
) {
  final first = hullNext[s] ?? neighbors.reduce(min), result = <int>[];
  result.add(first);
  while (result.length < neighbors.length) {
    result.add(directed[(s, result.last)]!);
  }
  return result;
}

Point outward(List<Point> points, int u, int v) =>
    direction(points[v].y - points[u].y, points[u].x - points[v].x);
typedef RealPoint = (double, double);
double boundedArea(Point site, List<Center> centers) {
  final relative = [
    for (final c in centers) (c.x / c.d - site.x, c.y / c.d - site.y),
  ];
  var total = 0.0;
  for (var i = 0; i < relative.length; i++) {
    final p = relative[i], q = relative[(i + 1) % relative.length];
    total += p.$1 * q.$2 - q.$1 * p.$2;
  }
  return total / 2;
}

double clippedArea(List<Point> points, int s, List<int> neighbors) {
  var polygon = <RealPoint>[(0, 0), (1000, 0), (1000, 1000), (0, 1000)];
  final site = points[s];
  for (final t in neighbors) {
    final other = points[t],
        c1 = 2 * (other.x - site.x),
        c2 = 2 * (other.y - site.y),
        c3 =
            other.x * other.x +
            other.y * other.y -
            site.x * site.x -
            site.y * site.y;
    final clipped = <RealPoint>[];
    for (var i = 0; i < polygon.length; i++) {
      final p = polygon[i], q = polygon[(i + 1) % polygon.length];
      final fp = c1 * p.$1 + c2 * p.$2 - c3, fq = c1 * q.$1 + c2 * q.$2 - c3;
      if (fp <= 0) {
        clipped.add(p);
      }
      if (fp < 0 && fq > 0 || fq < 0 && fp > 0) {
        final lambda = fp / (fp - fq);
        clipped.add((
          p.$1 + (q.$1 - p.$1) * lambda,
          p.$2 + (q.$2 - p.$2) * lambda,
        ));
      }
    }
    polygon = clipped;
  }
  var total = 0.0;
  for (var i = 0; i < polygon.length; i++) {
    final p = polygon[i], q = polygon[(i + 1) % polygon.length];
    total += p.$1 * q.$2 - q.$1 * p.$2;
  }
  return total / 2;
}
