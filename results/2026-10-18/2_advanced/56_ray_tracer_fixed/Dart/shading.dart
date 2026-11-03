part of 'main.dart';

Vec baseColor(Material m, Vec p) {
  if (m.checker) {
    final q =
        floorDiv(p.x, m.size) + floorDiv(p.y, m.size) + floorDiv(p.z, m.size);
    if (q.isOdd) return m.second;
  }
  return m.color;
}

(int, int) components(Material m, Vec n, Vec l, Vec v, int intensity) {
  final ndl = n.dot(l),
      dif = mul(mul(m.kd, ndl), intensity),
      rv = (n.scaled(2 * ndl) - l).dot(v);
  var spe = 0;
  if (rv > 0) {
    var p = scaleUnit;
    for (var j = 0; j < m.exponent; j++) {
      p = mul(p, rv);
    }
    spe = mul(mul(m.ks, p), intensity);
  }
  return (dif, spe);
}

Vec reflected(Vec d, Vec n) => (d - n.scaled(2 * d.dot(n))).normalized;
(int, int, Vec, bool) refracted(Material m, Vec d, Vec n, bool front) {
  if (m.kt == 0) return (m.kr, m.kt, zero, false);
  final eta = front ? floorDiv(scaleUnit * scaleUnit, m.ior) : m.ior,
      cn = -d.dot(n),
      disc =
          scaleUnit * scaleUnit -
          floorDiv(
            mul(eta, eta) * (scaleUnit * scaleUnit - cn * cn),
            scaleUnit,
          );
  if (disc < 0) return (m.kr + m.kt, 0, zero, true);
  final tdir =
          (d.scaled(eta) + n.scaled(mul(eta, cn) - isqrt(disc))).normalized,
      r0 = floorDiv((m.ior - scaleUnit) * scaleUnit, m.ior + scaleUnit),
      rz = mul(r0, r0),
      x = scaleUnit - min(cn, scaleUnit);
  var p = scaleUnit;
  for (var j = 0; j < 5; j++) {
    p = mul(p, x);
  }
  final fr = mul(m.kt, rz + mul(scaleUnit - rz, p));
  return (m.kr + fr, m.kt - fr, tdir, false);
}

Vec mix(List<Vec> colors, List<int> weights) => Vec.fromList(
  List.generate(3, (a) {
    var v = 0;
    for (var j = 0; j < colors.length; j++) {
      v += floorDiv(colors[j][a] * weights[j], scaleUnit);
    }
    return v;
  }),
);
