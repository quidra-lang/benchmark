part of 'main.dart';

bool between(Rational value, Rational a, Rational b) {
  if (a.compare(b) > 0) {
    final t = a;
    a = b;
    b = t;
  }
  return a.compare(value) <= 0 && value.compare(b) <= 0;
}

bool onSegment(Point p, Point a, Point b) =>
    cross(a, b, p).sign == 0 &&
    between(p.x, a.x, b.x) &&
    between(p.y, a.y, b.y);
bool touching(Point a, Point b, Point c, Point d) {
  final abC = cross(a, b, c).sign,
      abD = cross(a, b, d).sign,
      cdA = cross(c, d, a).sign,
      cdB = cross(c, d, b).sign;
  return abC * abD < 0 && cdA * cdB < 0 ||
      onSegment(c, a, b) ||
      onSegment(d, a, b) ||
      onSegment(a, c, d) ||
      onSegment(b, c, d);
}

bool overlapping(Point a, Point b, Point c, Point d) {
  if (cross(a, b, c).sign != 0 || cross(a, b, d).sign != 0) return false;
  var aa = a.x, bb = b.x, cc = c.x, dd = d.x;
  if (a.x == b.x) {
    aa = a.y;
    bb = b.y;
    cc = c.y;
    dd = d.y;
  }
  if (aa.compare(bb) > 0) {
    final t = aa;
    aa = bb;
    bb = t;
  }
  if (cc.compare(dd) > 0) {
    final t = cc;
    cc = dd;
    dd = t;
  }
  if (cc.compare(aa) > 0) aa = cc;
  if (dd.compare(bb) < 0) bb = dd;
  return aa.compare(bb) < 0;
}

(Rational, Rational, Point)? crossing(Point a, Point b, Point c, Point d) {
  final rx = b.x.sub(a.x),
      ry = b.y.sub(a.y),
      sx = d.x.sub(c.x),
      sy = d.y.sub(c.y),
      den = rx.mul(sy).sub(ry.mul(sx));
  if (den.sign == 0) return null;
  final gx = c.x.sub(a.x),
      gy = c.y.sub(a.y),
      t = gx.mul(sy).sub(gy.mul(sx)).div(den),
      u = gx.mul(ry).sub(gy.mul(rx)).div(den);
  if (t.sign <= 0 ||
      t.compare(rational(1)) >= 0 ||
      u.sign <= 0 ||
      u.compare(rational(1)) >= 0)
    return null;
  return (t, u, along(a, b, t));
}

Point lineIntersection(Point a, Point b, Point c, Point d) {
  final first = cross(c, d, a), second = cross(c, d, b);
  return along(a, b, first.div(first.sub(second)));
}
