require_relative 'rings'

module Render
  module_function

  def grid(polygons, operands, x0, y0, width, height, columns, rows)
    result_rings = polygons.flatten(1)
    counts = Hash.new(0)
    lines = rows.times.map do |row|
      y = y0 + Rational((2 * (rows - 1 - row) + 1) * height, 2)
      columns.times.map do |column|
        point = [x0 + Rational((2 * column + 1) * width, 2), y]
        character = if Rings.interior?(result_rings, point)
                      '#'
                    elsif operands
                      first, second = operands.map { |sequence| Rings.interior?(sequence, point) }
                      first && second ? '+' : first ? 'a' : second ? 'b' : '.'
                    else
                      '.'
                    end
        counts[character] += 1
        character
      end.join
    end
    [lines, counts]
  end
end
