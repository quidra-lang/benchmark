module Aggregation
  DIRECTIONS = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [-1, 1], [1, -1]].freeze
  module_function

  def path_costs(base, left, width, height, direction, p1, p2, gamma)
    rx, ry = direction
    rows = (0...height).to_a
    columns = (0...width).to_a
    rows.reverse! if ry.negative?
    columns.reverse! if rx.negative?
    result = Array.new(base.length)
    rows.each do |y|
      columns.each do |x|
        p = y * width + x
        qx, qy = x - rx, y - ry
        unless qx.between?(0, width - 1) && qy.between?(0, height - 1)
          result[p] = base[p].dup
          next
        end
        q = qy * width + qx
        previous = result[q]
        minimum = previous.min
        penalty = [p1, p2 * gamma / (gamma + (left[p] - left[q]).abs)].max
        result[p] = base[p].each_with_index.map do |cost, d|
          best = [previous[d], minimum + penalty].min
          best = [best, previous[d - 1] + p1].min if d.positive?
          best = [best, previous[d + 1] + p1].min if d + 1 < previous.length
          cost + best - minimum
        end
      end
    end
    result
  end

  def cumulative_costs(base, left, width, height, paths, p1, p2, gamma)
    total = Array.new(base.length) { Array.new(base.first.length, 0) }
    DIRECTIONS.first(paths).each_with_index do |direction, i|
      path_costs(base, left, width, height, direction, p1, p2, gamma).each_with_index do |row, p|
        row.each_with_index { |value, d| total[p][d] += value }
      end
      yield total, i + 1
    end
    total
  end
end
