require_relative 'filters'
require_relative 'canny'

module Corners
  module_function

  def detect(gx, gy, window, threshold, limit)
    height, width = gx.length, gx.first.length
    half = window / 2
    response = Array.new(height) do |y|
      Array.new(width) do |x|
        xx = yy = xy = 0
        (-half..half).each do |j|
          (-half..half).each do |i|
            dx, dy = Filters.at(gx, x + i, y + j), Filters.at(gy, x + i, y + j)
            xx += dx * dx
            yy += dy * dy
            xy += dx * dy
          end
        end
        xx * yy - xy * xy - (xx + yy)**2 / 25
      end
    end
    candidates = []
    height.times do |y|
      width.times do |x|
        value = response[y][x]
        next if value < threshold
        peak = Canny::NEIGHBORS.all? do |dx, dy|
          xx, yy = x + dx, y + dy
          next true if xx < 0 || xx >= width || yy < 0 || yy >= height
          value > response[yy][xx] || (value == response[yy][xx] && ([yy, xx] <=> [y, x]) > 0)
        end
        candidates << {point: [x, y], response: value} if peak
      end
    end
    corners = candidates.sort_by { |c| [-c[:response], c[:point][1], c[:point][0]] }.first(limit)
    corners.each_with_index { |c, i| c[:number] = i + 1 }
    [candidates.length, corners]
  end
end
