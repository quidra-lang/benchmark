part of 'main.dart';

class Bounds {
  final Vec lo, hi;
  Bounds(this.lo, this.hi);
}

class Ray {
  final Vec origin, direction;
  Ray(this.origin, this.direction);
}

class Slab {
  int near = -(1 << 62), far = 1 << 62, nearAxis = 0, farAxis = 0;
}

class Hit {
  final SceneObject object;
  final int distance, axis;
  final bool entering;
  Hit(this.object, this.distance, [this.axis = 0, this.entering = false]);
}

Bounds bounding(SceneObject o, int pad) => Bounds(
  Vec.fromList(
    List.generate(
      3,
      (a) => o.kind == 'sphere' ? o.p[a] - o.radius - pad : o.lo[a] - pad,
    ),
  ),
  Vec.fromList(
    List.generate(
      3,
      (a) => o.kind == 'sphere' ? o.p[a] + o.radius + pad : o.hi[a] + pad,
    ),
  ),
);
Slab? slab(Bounds b, Ray r) {
  final out = Slab();
  for (var a = 0; a < 3; a++) {
    final d = r.direction[a], o = r.origin[a];
    if (d == 0) {
      if (o < b.lo[a] || o > b.hi[a]) return null;
      continue;
    }
    var lo = floorDiv((b.lo[a] - o) * scaleUnit, d),
        hi = floorDiv((b.hi[a] - o) * scaleUnit, d);
    if (lo > hi) {
      final t = lo;
      lo = hi;
      hi = t;
    }
    if (lo > out.near) {
      out.near = lo;
      out.nearAxis = a;
    }
    if (hi < out.far) {
      out.far = hi;
      out.farAxis = a;
    }
  }
  return out.near > out.far ? null : out;
}

Hit? intersect(SceneObject o, Ray r, int eps) {
  switch (o.kind) {
    case 'sphere':
      final oc = r.origin - o.p,
          b = oc.dot(r.direction),
          tc = floorDiv(-b * scaleUnit, r.direction.dot(r.direction)),
          v = oc + r.direction.scaled(tc),
          q = floorDiv(o.radius * o.radius, scaleUnit) - v.dot(v);
      if (q < 0) return null;
      final w = floorDiv(isqrt(q * scaleUnit) * scaleUnit, r.direction.length);
      if (tc - w > eps) return Hit(o, tc - w);
      if (tc + w > eps) return Hit(o, tc + w);
      return null;
    case 'plane':
      final den = r.direction.dot(o.n);
      if (den == 0) return null;
      final t = floorDiv((o.p - r.origin).dot(o.n) * scaleUnit, den);
      return t > eps ? Hit(o, t) : null;
    case 'box':
      final v = slab(Bounds(o.lo, o.hi), r);
      if (v == null) return null;
      if (v.near > eps) return Hit(o, v.near, v.nearAxis, true);
      if (v.far > eps) return Hit(o, v.far, v.farAxis);
      return null;
  }
  return null;
}

Vec outward(Hit h, Vec p, Vec d) {
  final o = h.object;
  if (o.kind == 'sphere') return (p - o.p).normalized;
  if (o.kind == 'plane') return o.n;
  var sign = d[h.axis] < 0 ? -1 : 1;
  if (h.entering) sign = -sign;
  return Vec.fromList(
    List.generate(3, (a) => a == h.axis ? sign * scaleUnit : 0),
  );
}
