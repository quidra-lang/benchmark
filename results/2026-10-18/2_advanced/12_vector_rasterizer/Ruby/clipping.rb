# frozen_string_literal: true

require_relative 'canvas'

module Clipping
  def self.intersection(left, right)
    [[left[0], right[0]].max, [left[1], right[1]].max, [left[2], right[2]].min, [left[3], right[3]].min]
  end

  def self.empty?(rectangle)
    rectangle[0] > rectangle[2] || rectangle[1] > rectangle[3]
  end

  def self.inside?(point, rectangle)
    point[0].between?(rectangle[0], rectangle[2]) && point[1].between?(rectangle[1], rectangle[3])
  end

  def self.code(point, rectangle)
    x, y = point
    code = 0
    code |= 1 if x < rectangle[0]
    code |= 2 if x > rectangle[2]
    code |= 4 if y < rectangle[1]
    code |= 8 if y > rectangle[3]
    code
  end

  def self.segment(first, last, rectangle)
    loop do
      first_code = code(first, rectangle)
      last_code = code(last, rectangle)
      return [first, last] if (first_code | last_code).zero?
      return nil unless (first_code & last_code).zero?

      use_first = !first_code.zero?
      a, b = use_first ? [first, last] : [last, first]
      outside = use_first ? first_code : last_code
      if !(outside & 4).zero? || !(outside & 8).zero?
        y = !(outside & 4).zero? ? rectangle[1] : rectangle[3]
        point = [a[0] + Canvas.round((b[0] - a[0]) * (y - a[1]), b[1] - a[1]), y]
      else
        x = !(outside & 2).zero? ? rectangle[2] : rectangle[0]
        point = [x, a[1] + Canvas.round((b[1] - a[1]) * (x - a[0]), b[0] - a[0])]
      end
      if use_first
        first = point
      else
        last = point
      end
    end
  end

  def self.polygon(vertices, rectangle)
    boundaries = [[0, rectangle[0], :minimum], [0, rectangle[2] + 1, :maximum],
                  [1, rectangle[1], :minimum], [1, rectangle[3] + 1, :maximum]]
    boundaries.each do |axis, boundary, side|
      break if vertices.empty?

      output = []
      previous = vertices.last
      previous_inside = side == :minimum ? previous[axis] >= boundary : previous[axis] <= boundary
      vertices.each do |point|
        current_inside = side == :minimum ? point[axis] >= boundary : point[axis] <= boundary
        if previous_inside != current_inside
          other = 1 - axis
          crossing = [0, 0]
          crossing[axis] = boundary
          crossing[other] = previous[other] + Canvas.round((boundary - previous[axis]) * (point[other] - previous[other]), point[axis] - previous[axis])
          output << crossing
        end
        output << point if current_inside
        previous = point
        previous_inside = current_inside
      end
      vertices = output
    end
    vertices
  end
end
