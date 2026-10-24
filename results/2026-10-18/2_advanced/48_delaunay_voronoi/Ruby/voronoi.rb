require_relative 'predicates'

module Voronoi
  extend self
  include Predicates

  def squared_radius(a, b, c)
    l1, l2, l3 = [d2(a, b), d2(b, c), d2(c, a)].map(&:to_f)
    area2 = orient(a, b, c).to_f
    ((l1 * l2) * l3) / ((4.0 * area2) * area2)
  end

  def position(center, points, hull)
    x, y, denominator = center
    on = false
    hull.each_with_index do |u, index|
      v = hull[(index + 1) % hull.size]
      ux, uy = points[u]
      vx, vy = points[v]
      sigma = (vx - ux) * (y - uy * denominator) - (vy - uy) * (x - ux * denominator)
      return 'outside' if sigma.negative?

      on = true if sigma.zero?
    end
    on ? 'on' : 'inside'
  end

  def neighbor_order(site, neighbors, directed, hull_next)
    first = hull_next.fetch(site) { neighbors.min }
    order = [first]
    order << directed.fetch([site, order.last]) while order.size < neighbors.size
    order
  end

  def outward(points, u, v)
    dx = points[v][0] - points[u][0]
    dy = points[v][1] - points[u][1]
    reduce_direction(dy, -dx)
  end

  def bounded_area(site, centers)
    x, y = site
    relative = centers.map { |vx, vy, denominator| [vx.fdiv(denominator) - x, vy.fdiv(denominator) - y] }
    total = 0.0
    relative.each_with_index do |(u, w), index|
      next_u, next_w = relative[(index + 1) % relative.size]
      total += u * next_w - next_u * w
    end
    total / 2.0
  end

  def clipped_area(points, site, neighbors)
    polygon = [[0.0, 0.0], [1000.0, 0.0], [1000.0, 1000.0], [0.0, 1000.0]]
    xs, ys = points[site]
    neighbors.each do |other|
      xt, yt = points[other]
      c1 = 2 * (xt - xs)
      c2 = 2 * (yt - ys)
      c3 = xt * xt + yt * yt - xs * xs - ys * ys
      clipped = []
      polygon.each_with_index do |p, index|
        q = polygon[(index + 1) % polygon.size]
        fp = c1 * p[0] + c2 * p[1] - c3
        fq = c1 * q[0] + c2 * q[1] - c3
        clipped << p if fp <= 0.0
        next unless (fp < 0.0 && fq > 0.0) || (fq < 0.0 && fp > 0.0)

        ratio = fp / (fp - fq)
        clipped << [p[0] + (q[0] - p[0]) * ratio, p[1] + (q[1] - p[1]) * ratio]
      end
      polygon = clipped
    end
    total = 0.0
    polygon.each_with_index do |p, index|
      q = polygon[(index + 1) % polygon.size]
      total += p[0] * q[1] - q[0] * p[1]
    end
    total / 2.0
  end
end
