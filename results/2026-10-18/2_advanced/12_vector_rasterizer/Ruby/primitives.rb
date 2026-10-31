# frozen_string_literal: true

require 'set'
require_relative 'canvas'

module Primitives
  def self.line(first, last)
    return enum_for(__method__, first, last) unless block_given?

    x, y = first
    dx = (last[0] - x).abs
    dy = -(last[1] - y).abs
    sx = x < last[0] ? 1 : -1
    sy = y < last[1] ? 1 : -1
    error = dx + dy
    loop do
      yield [x, y]
      break if x == last[0] && y == last[1]

      doubled = 2 * error
      if doubled >= dy
        error += dy
        x += sx
      end
      if doubled <= dx
        error += dx
        y += sy
      end
    end
  end

  def self.square(point, width)
    return enum_for(__method__, point, width) unless block_given?

    lower = -((width - 1) / 2)
    lower.upto(lower + width - 1) do |dy|
      lower.upto(lower + width - 1) { |dx| yield [point[0] + dx, point[1] + dy] }
    end
  end

  def self.circle(radius)
    points = Set.new
    a = radius
    b = 0
    error = 1 - radius
    while a >= b
      points.merge([[a, b], [b, a], [-b, a], [-a, b], [-a, -b], [-b, -a], [b, -a], [a, -b]])
      b += 1
      if error.negative?
        error += 2 * b + 1
      else
        a -= 1
        error += 2 * (b - a) + 1
      end
    end
    points
  end

  def self.ellipse(rx, ry)
    x = 0
    y = ry
    rx2 = rx * rx
    ry2 = ry * ry
    points = Set.new([[0, ry], [0, -ry]])
    while ry2 * x < rx2 * y
      decision = 4 * ry2 * (x + 1) * (x + 1) + rx2 * (2 * y - 1) * (2 * y - 1) - 4 * rx2 * ry2
      x += 1
      y -= 1 if decision >= 0
      points.merge([[x, y], [-x, y], [x, -y], [-x, -y]])
    end
    while y.positive?
      decision = ry2 * (2 * x + 1) * (2 * x + 1) + 4 * rx2 * (y - 1) * (y - 1) - 4 * rx2 * ry2
      y -= 1
      x += 1 if decision <= 0
      points.merge([[x, y], [-x, y], [x, -y], [-x, -y]])
    end
    points
  end

  def self.bezier(control, segments)
    degree = control.length - 1
    denominator = degree == 2 ? segments * segments : segments * segments * segments
    0.upto(segments).map do |index|
      remaining = segments - index
      weights = if degree == 2
                  [remaining * remaining, 2 * index * remaining, index * index]
                else
                  [remaining * remaining * remaining, 3 * index * remaining * remaining,
                   3 * index * index * remaining, index * index * index]
                end
      [0, 1].map do |axis|
        numerator = control.each_with_index.sum { |point, i| weights[i] * point[axis] }
        Canvas.round(numerator, denominator)
      end
    end
  end
end
