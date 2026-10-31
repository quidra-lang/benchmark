import 'canvas.dart';

typedef Point = (int, int);
List<Point> bresenham(Point start, Point end) {
  var (x, y) = start; final (ex, ey) = end; final dx = (ex - x).abs(), dy = -(ey - y).abs(), sx = x < ex ? 1 : -1, sy = y < ey ? 1 : -1; var error = dx + dy; final points = <Point>[];
  while (true) { points.add((x, y)); if (x == ex && y == ey) return points; final doubled = 2 * error; if (doubled >= dy) { error += dy; x += sx; } if (doubled <= dx) { error += dx; y += sy; } }
}
List<Point> expandSquare(int x, int y, int width) { final low = -((width - 1) ~/ 2); return [for (var j = low; j < low + width; j++) for (var i = low; i < low + width; i++) (x + i, y + j)]; }
Set<Point> circlePoints(int radius) {
  var a = radius, b = 0, error = 1 - radius; final points = <Point>{};
  while (a >= b) { points.addAll([(a, b), (b, a), (-b, a), (-a, b), (-a, -b), (-b, -a), (b, -a), (a, -b)]); b++; if (error < 0) { error += 2 * b + 1; } else { a--; error += 2 * (b - a) + 1; } } return points;
}
void addQuadrants(Set<Point> points, int x, int y) => points.addAll([(x, y), (-x, y), (x, -y), (-x, -y)]);
Set<Point> ellipsePoints(int rx, int ry) {
  final rx2 = rx * rx, ry2 = ry * ry; var x = 0, y = ry; final points = <Point>{(0, ry), (0, -ry)};
  while (ry2 * x < rx2 * y) { final d = 4 * ry2 * (x + 1) * (x + 1) + rx2 * (2 * y - 1) * (2 * y - 1) - 4 * rx2 * ry2; x++; if (d >= 0) y--; addQuadrants(points, x, y); }
  while (y > 0) { final d = ry2 * (2 * x + 1) * (2 * x + 1) + 4 * rx2 * (y - 1) * (y - 1) - 4 * rx2 * ry2; y--; if (d <= 0) x++; addQuadrants(points, x, y); } return points;
}
List<Point> bezierPoints(List<Point> controls, int segments) {
  final degree = controls.length - 1, scale = controls.length == 3 ? segments * segments : segments * segments * segments; final points = <Point>[];
  for (var i = 0; i <= segments; i++) { final r = segments - i, weights = degree == 2 ? [r * r, 2 * i * r, i * i] : [r * r * r, 3 * i * r * r, 3 * i * i * r, i * i * i]; var x = 0, y = 0; for (var j = 0; j < controls.length; j++) { x += weights[j] * controls[j].$1; y += weights[j] * controls[j].$2; } points.add((roundRatio(x, scale), roundRatio(y, scale))); } return points;
}
