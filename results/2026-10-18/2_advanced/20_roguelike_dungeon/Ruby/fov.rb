# frozen_string_literal: true

require 'set'

module Fov
  NAMES = %w[N NE E SE S SW W NW].freeze
  DIRECTIONS = [[0, -1], [1, -1], [1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1]].freeze
  PASSABLE = ['.', '#', '+', '<', '>'].freeze

  def self.passable?(level, position)
    x, y = position
    y.between?(0, level.terrain.length - 1) && x.between?(0, level.terrain.first.length - 1) && PASSABLE.include?(level.terrain[y][x])
  end

  def self.move?(level, position, direction)
    x, y = position
    dx, dy = direction
    target = [x + dx, y + dy]
    return false unless passable?(level, target)
    return false if !dx.zero? && !dy.zero? && (level.terrain[y][x] == '+' || level.terrain[target[1]][target[0]] == '+')

    true
  end

  def self.line(first, last)
    x, y = first
    dx = (last[0] - x).abs
    dy = (last[1] - y).abs
    sx = last[0] > x ? 1 : -1
    sy = last[1] > y ? 1 : -1
    error = dx - dy
    cells = []
    until [x, y] == last
      doubled = 2 * error
      if doubled > -dy
        error -= dy
        x += sx
      end
      if doubled < dx
        error += dx
        y += sy
      end
      cells << [x, y]
    end
    cells
  end

  def self.visible(level, position, radius)
    visible = Set.new([position.dup])
    level.terrain.each_with_index do |row, y|
      row.each_index do |x|
        dx = x - position[0]
        dy = y - position[1]
        next if dx * dx + dy * dy > radius * radius

        cells = line(position, [x, y])
        visible.add([x, y]) if cells.take([cells.length - 1, 0].max).all? { |cell| passable?(level, cell) }
      end
    end
    visible
  end

  def self.distances(level, position)
    distances = Array.new(level.terrain.length) { Array.new(level.terrain.first.length) }
    distances[position[1]][position[0]] = 0
    queue = [position.dup]
    cursor = 0
    while cursor < queue.length
      x, y = queue[cursor]
      cursor += 1
      DIRECTIONS.each do |direction|
        next unless move?(level, [x, y], direction)

        target = [x + direction[0], y + direction[1]]
        next unless distances[target[1]][target[0]].nil?

        distances[target[1]][target[0]] = distances[y][x] + 1
        queue << target
      end
    end
    distances
  end
end
