# frozen_string_literal: true

require 'set'
require_relative 'clipping'

module Fill
  def self.polygons(sequences, rule, clip)
    rows = Array.new(clip[3] - clip[1] + 1) { Hash.new { |hash, x| hash[x] = [0, 0] } }
    sequences.each do |vertices|
      next if vertices.empty?

      vertices.each_with_index do |first, index|
        last = vertices[(index + 1) % vertices.length]
        next if first[1] == last[1]

        first_y = [first[1], last[1]].min
        last_y = [first[1], last[1]].max - 1
        direction = last[1] > first[1] ? 1 : -1
        [first_y, clip[1]].max.upto([last_y, clip[3]].min) do |y|
          denominator = last[1] - first[1]
          numerator = 2 * first[0] * denominator + (2 * y + 1 - 2 * first[1]) * (last[0] - first[0])
          numerator, denominator = -numerator, -denominator if denominator.negative?
          threshold = (numerator - denominator) / (2 * denominator) + 1
          rows[y - clip[1]][threshold][0] += 1
          rows[y - clip[1]][threshold][1] += direction
        end
      end
    end
    coverage = Set.new
    rows.each_with_index do |events, index|
      ordered = events.sort
      cursor = count = winding = 0
      clip[0].upto(clip[2]) do |x|
        while cursor < ordered.length && ordered[cursor][0] <= x
          count += ordered[cursor][1][0]
          winding += ordered[cursor][1][1]
          cursor += 1
        end
        inside = rule == 'evenodd' ? count.odd? : !winding.zero?
        coverage.add([x, index + clip[1]]) if inside
      end
    end
    coverage
  end

  def self.shape(points, center, clip)
    extents = {}
    points.each { |x, y| extents[y] = [extents.fetch(y, 0), x.abs].max }
    coverage = Set.new
    extents.each do |dy, radius|
      y = center[1] + dy
      next unless y.between?(clip[1], clip[3])

      [center[0] - radius, clip[0]].max.upto([center[0] + radius, clip[2]].min) { |x| coverage.add([x, y]) }
    end
    coverage
  end

  def self.flood(layer, seed, clip, width)
    target = layer.pixels[seed[1] * width + seed[0]]&.color
    coverage = Set.new([seed])
    pending = [seed]
    until pending.empty?
      x, y = pending.pop
      [[x + 1, y], [x - 1, y], [x, y + 1], [x, y - 1]].each do |point|
        next unless Clipping.inside?(point, clip)
        next if coverage.include?(point)
        next unless layer.pixels[point[1] * width + point[0]]&.color == target

        coverage.add(point)
        pending << point
      end
    end
    coverage
  end
end
