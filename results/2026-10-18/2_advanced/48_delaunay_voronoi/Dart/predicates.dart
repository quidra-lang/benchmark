part of 'main.dart';

class Point {
  final int x, y;
  const Point(this.x, this.y);
  @override
  bool operator ==(Object other) =>
      other is Point && x == other.x && y == other.y;
  @override
  int get hashCode => Object.hash(x, y);
}

class Center {
  final int x, y, d;
  Center(this.x, this.y, this.d);
}

typedef Edge = (int, int);
typedef Triangle = (int, int, int);
int orient(Point p, Point q, Point r) =>
    (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x);
int d2(Point p, Point q) {
  final x = p.x - q.x, y = p.y - q.y;
  return x * x + y * y;
}

int dot(Point o, Point p, Point q) =>
    (p.x - o.x) * (q.x - o.x) + (p.y - o.y) * (q.y - o.y);
int incircle(Point a, Point b, Point c, Point d) {
  final ax = a.x - d.x,
      ay = a.y - d.y,
      bx = b.x - d.x,
      by = b.y - d.y,
      cx = c.x - d.x,
      cy = c.y - d.y;
  final aa = ax * ax + ay * ay, bb = bx * bx + by * by, cc = cx * cx + cy * cy;
  return ax * (by * cc - bb * cy) -
      ay * (bx * cc - bb * cx) +
      aa * (bx * cy - by * cx);
}

Center circumcenter(Point a, Point b, Point c) {
  final bx = b.x - a.x, by = b.y - a.y, cx = c.x - a.x, cy = c.y - a.y;
  final bb = bx * bx + by * by,
      cc = cx * cx + cy * cy,
      d = 2 * (bx * cy - by * cx);
  return Center(a.x * d + cy * bb - by * cc, a.y * d + bx * cc - cx * bb, d);
}

int gcd(int a, int b) {
  a = a.abs();
  b = b.abs();
  while (b != 0) {
    final t = b;
    b = a % b;
    a = t;
  }
  return a;
}

String fraction(int n, int d) {
  final g = gcd(n, d);
  n ~/= g;
  d ~/= g;
  return d == 1 ? '$n' : '$n/$d';
}

Point direction(int dx, int dy) {
  final g = gcd(dx, dy);
  return Point(dx ~/ g, dy ~/ g);
}

Edge orderedEdge(int a, int b) => a < b ? (a, b) : (b, a);
int compareEdges(Edge a, Edge b) {
  final c = a.$1.compareTo(b.$1);
  return c != 0 ? c : a.$2.compareTo(b.$2);
}

List<int> triangleSites(Triangle t) => [t.$1, t.$2, t.$3];
List<Edge> triangleEdges(Triangle t) => [
  (t.$1, t.$2),
  (t.$2, t.$3),
  (t.$3, t.$1),
];
