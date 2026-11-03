import 'canvas.dart';
import 'primitives.dart';

typedef Rect = (int, int, int, int);
int regionCode(Point p, Rect c) => (p.$1 < c.$1 ? 1 : 0) | (p.$1 > c.$3 ? 2 : 0) | (p.$2 < c.$2 ? 4 : 0) | (p.$2 > c.$4 ? 8 : 0);
(Point, Point)? clipSegment(Point start, Point end, Rect clip) {
  final (x0, y0, x1, y1) = clip;
  while (true) { final sc = regionCode(start, clip), ec = regionCode(end, clip); if ((sc | ec) == 0) return (start, end); if ((sc & ec) != 0) return null; final code = sc != 0 ? sc : ec; final (ax, ay) = sc != 0 ? start : end; final (bx, by) = sc != 0 ? end : start; late Point p;
    if ((code & 4) != 0) { p = (ax + roundRatio((bx - ax) * (y0 - ay), by - ay), y0); }
    else if ((code & 8) != 0) { p = (ax + roundRatio((bx - ax) * (y1 - ay), by - ay), y1); }
    else if ((code & 2) != 0) { p = (x1, ay + roundRatio((by - ay) * (x1 - ax), bx - ax)); }
    else { p = (x0, ay + roundRatio((by - ay) * (x0 - ax), bx - ax)); }
    if (sc != 0) { start = p; } else { end = p; }
  }
}
bool boundaryInside(Point p, int axis, int limit, bool minimum) { final value = axis == 0 ? p.$1 : p.$2; return minimum ? value >= limit : value <= limit; }
Point boundaryIntersection(Point s, Point e, int axis, int limit) => axis == 0 ? (limit, s.$2 + roundRatio((limit - s.$1) * (e.$2 - s.$2), e.$1 - s.$1)) : (s.$1 + roundRatio((limit - s.$2) * (e.$1 - s.$1), e.$2 - s.$2), limit);
List<Point> clipPolygon(List<Point> vertices, Rect clip) {
  for (final (axis, limit, minimum) in [(0, clip.$1, true), (0, clip.$3 + 1, false), (1, clip.$2, true), (1, clip.$4 + 1, false)]) {
    final output = <Point>[]; for (var i = 0; i < vertices.length; i++) { final s = vertices[(i + vertices.length - 1) % vertices.length], e = vertices[i], si = boundaryInside(s, axis, limit, minimum), ei = boundaryInside(e, axis, limit, minimum); if (ei) { if (!si) output.add(boundaryIntersection(s, e, axis, limit)); output.add(e); } else if (si) { output.add(boundaryIntersection(s, e, axis, limit)); } } vertices = output;
  } return vertices;
}
