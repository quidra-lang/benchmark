require 'set'

module Hough
  module_function

  def rho(point, angle, trig, step)
    x, y = point
    c, s = trig[angle]
    (x * c + y * s) / (16384 * step)
  end

  def circle_points(radius)
    points = Set.new
    a, b, error = radius, 0, 1 - radius
    while a >= b
      points.merge([[a, b], [b, a], [-b, a], [-a, b], [-a, -b], [-b, -a], [b, -a], [a, -b]])
      b += 1
      if error < 0
        error += 2 * b + 1
      else
        a -= 1
        error += 2 * (b - a) + 1
      end
    end
    points.to_a
  end

  def circle_votes(edges, width, height, minimum, maximum)
    outlines, cells = {}, {}
    (minimum..maximum).each do |r|
      outlines[r] = circle_points(r)
      votes = Hash.new(0)
      edges.each do |x, y|
        outlines[r].each do |dx, dy|
          cx, cy = x + dx, y + dy
          votes[[cx, cy]] += 1 if cx >= 0 && cx < width && cy >= 0 && cy < height
        end
      end
      cells[r] = votes
    end
    [cells, outlines]
  end

  def circle_peaks(cells, outlines, width, height, percent)
    candidates, peaks = 0, []
    cells.each do |r, votes|
      n = outlines[r].length
      height.times do |y|
        width.times do |x|
          v = votes[[x, y]]
          next if 100 * v < percent * n
          candidates += 1
          peak = cells.keys.select { |rr| (rr - r).abs <= 2 }.all? do |rr|
            ([0, y - 2].max..[height - 1, y + 2].min).all? do |yy|
              ([0, x - 2].max..[width - 1, x + 2].min).all? do |xx|
                next true if [rr, yy, xx] == [r, y, x]
                left = v * outlines[rr].length
                right = cells[rr][[xx, yy]] * n
                left > right || (left == right && ([rr, yy, xx] <=> [r, y, x]) > 0)
              end
            end
          end
          peaks << [r, x, y, v] if peak
        end
      end
    end
    peaks.sort! do |a, b|
      order = (b[3] * outlines[a[0]].length) <=> (a[3] * outlines[b[0]].length)
      order.zero? ? ([a[0], a[2], a[1]] <=> [b[0], b[2], b[1]]) : order
    end
    [candidates, peaks]
  end

  def line_votes(edges, trig, step)
    votes = Hash.new(0)
    edges.each { |p| 180.times { |t| votes[[t, rho(p, t, trig, step)]] += 1 } }
    votes
  end

  def line_peaks(votes, threshold)
    peaks = []
    votes.each do |(t, r), v|
      next if v < threshold
      peak = ([0, t - 2].max..[179, t + 2].min).all? do |tt|
        (r - 2..r + 2).all? do |rr|
          next true if [tt, rr] == [t, r]
          other = votes[[tt, rr]]
          v > other || (v == other && ([tt, rr] <=> [t, r]) > 0)
        end
      end
      peaks << [t, r, v] if peak
    end
    peaks.sort_by { |t, r, v| [-v, t, r] }
  end
end
