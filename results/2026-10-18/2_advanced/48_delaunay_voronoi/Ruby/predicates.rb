module Predicates
  extend self

  def orient(p, q, r)
    (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
  end

  def d2(p, q)
    (p[0] - q[0])**2 + (p[1] - q[1])**2
  end

  def dot(o, p, q)
    (p[0] - o[0]) * (q[0] - o[0]) + (p[1] - o[1]) * (q[1] - o[1])
  end

  def incircle(a, b, c, d)
    ax, ay = a[0] - d[0], a[1] - d[1]
    bx, by = b[0] - d[0], b[1] - d[1]
    cx, cy = c[0] - d[0], c[1] - d[1]
    aa, bb, cc = ax * ax + ay * ay, bx * bx + by * by, cx * cx + cy * cy
    ax * (by * cc - bb * cy) - ay * (bx * cc - bb * cx) + aa * (bx * cy - by * cx)
  end

  def circumcenter(a, b, c)
    bx, by = b[0] - a[0], b[1] - a[1]
    cx, cy = c[0] - a[0], c[1] - a[1]
    bb, cc = bx * bx + by * by, cx * cx + cy * cy
    denominator = 2 * (bx * cy - by * cx)
    x = a[0] * denominator + cy * bb - by * cc
    y = a[1] * denominator + bx * cc - cx * bb
    [x, y, denominator]
  end

  def fraction(numerator, denominator)
    common = numerator.gcd(denominator)
    numerator /= common
    denominator /= common
    denominator == 1 ? numerator.to_s : "#{numerator}/#{denominator}"
  end

  def reduce_direction(dx, dy)
    common = dx.gcd(dy)
    [dx / common, dy / common]
  end
end
