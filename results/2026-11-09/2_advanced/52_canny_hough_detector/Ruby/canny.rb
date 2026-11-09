require 'set'

module Canny
  NEIGHBORS = (-1..1).flat_map { |dy| (-1..1).map { |dx| [dx, dy] } }.reject { |p| p == [0, 0] }.freeze
  OFFSETS = {0 => [[-1, 0], [1, 0]], 45 => [[1, -1], [-1, 1]],
             90 => [[0, -1], [0, 1]], 135 => [[-1, -1], [1, 1]]}.freeze
  module_function

  def directions(gx, gy)
    gx.each_with_index.map do |row, y|
      row.each_with_index.map do |dx, x|
        dy = gy[y][x]
        if 29 * dy.abs <= 12 * dx.abs
          0
        elsif 29 * dy.abs >= 70 * dx.abs
          90
        else
          dx * dy < 0 ? 45 : 135
        end
      end
    end
  end

  def suppress(magnitude, direction)
    result = Array.new(magnitude.length) { Array.new(magnitude.first.length, 0) }
    (1...magnitude.length - 1).each do |y|
      (1...magnitude.first.length - 1).each do |x|
        a, b = OFFSETS[direction[y][x]]
        value = magnitude[y][x]
        result[y][x] = value if value > magnitude[y + a[1]][x + a[0]] && value >= magnitude[y + b[1]][x + b[0]]
      end
    end
    result
  end

  def hysteresis(nonmax, low, high)
    strong, weak = Set.new, Set.new
    nonmax.each_with_index do |row, y|
      row.each_with_index do |v, x|
        strong.add([x, y]) if v >= high
        weak.add([x, y]) if v >= low && v < high
      end
    end
    allowed = strong | weak
    edges = strong.dup
    queue = strong.to_a
    index = 0
    while index < queue.length
      x, y = queue[index]
      index += 1
      NEIGHBORS.each do |dx, dy|
        p = [x + dx, y + dy]
        queue << p if allowed.include?(p) && edges.add?(p)
      end
    end
    [edges, strong, weak]
  end

  def components(edges)
    waiting = edges.dup
    result = []
    edges.sort_by { |x, y| [y, x] }.each do |first|
      next unless waiting.delete?(first)
      queue = [first]
      index = 0
      while index < queue.length
        x, y = queue[index]
        index += 1
        NEIGHBORS.each do |dx, dy|
          p = [x + dx, y + dy]
          queue << p if waiting.delete?(p)
        end
      end
      result << queue
    end
    result
  end
end
