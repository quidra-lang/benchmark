require_relative 'rational'

module Intersections
  module_function

  def on_segment?(point, first, second)
    RationalGeometry.cross(first, second, point).zero? &&
      point[0].between?(*[first[0], second[0]].minmax) &&
      point[1].between?(*[first[1], second[1]].minmax)
  end

  def touch?(a, b, c, d)
    proper = RationalGeometry.cross(a, b, c) * RationalGeometry.cross(a, b, d) < 0 &&
             RationalGeometry.cross(c, d, a) * RationalGeometry.cross(c, d, b) < 0
    proper || on_segment?(c, a, b) || on_segment?(d, a, b) || on_segment?(a, c, d) || on_segment?(b, c, d)
  end

  def overlap?(a, b, c, d)
    return false unless RationalGeometry.cross(a, b, c).zero? && RationalGeometry.cross(a, b, d).zero?
    coordinate = a[0] == b[0] ? 1 : 0
    low1, high1 = [a[coordinate], b[coordinate]].minmax
    low2, high2 = [c[coordinate], d[coordinate]].minmax
    [low1, low2].max < [high1, high2].min
  end

  def crossing(a, b, c, d)
    rx, ry = b[0] - a[0], b[1] - a[1]
    sx, sy = d[0] - c[0], d[1] - c[1]
    denominator = rx * sy - ry * sx
    return nil if denominator.zero?
    gx, gy = c[0] - a[0], c[1] - a[1]
    t = Rational(gx * sy - gy * sx) / denominator
    u = Rational(gx * ry - gy * rx) / denominator
    return nil unless t > 0 && t < 1 && u > 0 && u < 1
    [t, u, RationalGeometry.along(a, b, t)]
  end

  def clipping_point(previous, current, a, b)
    RationalGeometry.along(previous, current, Rational(a) / (a - b))
  end
end
