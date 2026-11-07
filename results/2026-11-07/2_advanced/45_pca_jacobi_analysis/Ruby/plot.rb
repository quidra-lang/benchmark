module Plot
  module_function

  def grid(rows, columns)
    Array.new(rows) { Array.new(columns, ' ') }
  end

  def framed(grid)
    border = '+' + '-' * grid[0].length + '+'
    [border] + grid.map { |row| '|' + row.join + '|' } + [border]
  end

  def grid_index(fraction, size)
    [(fraction * size).floor, size - 1].min
  end

  def rounded_position(fraction, size)
    (fraction * size + 0.5).floor
  end

  def biplot_cell(x, y, x_limit, y_limit, width, height)
    [grid_index((y_limit - y) / (2 * y_limit), height),
     grid_index((x + x_limit) / (2 * x_limit), width)]
  end

  def circle_cell(first, second, radius)
    [radius / 2 + 1 - rounded_position(second, radius / 2.0),
     radius + 1 + rounded_position(first, radius)]
  end

  def diagnostic_cell(t2, spe, t2_max, spe_max, width, height)
    [height - 1 - grid_index(spe / spe_max, height), grid_index(t2 / t2_max, width)]
  end

  def shaft_cells(origin, tip)
    dr = tip[0] - origin[0]
    dc = tip[1] - origin[1]
    steps = [dc.abs, dr.abs].max
    (1...steps).map do |s|
      row = origin[0] + (dr <=> 0) * ((2 * s * dr.abs + steps) / (2 * steps))
      col = origin[1] + (dc <=> 0) * ((2 * s * dc.abs + steps) / (2 * steps))
      [row, col]
    end
  end

  def shaft_character(origin, tip)
    dr = tip[0] - origin[0]
    dc = tip[1] - origin[1]
    return '-' if 2 * dr.abs <= dc.abs
    return '|' if 2 * dc.abs <= dr.abs

    dc * dr < 0 ? '/' : '\\'
  end

  def scree_line(length, kaiser, broken, width)
    characters = (1..width).map do |position|
      if position == broken
        'o'
      elsif position == kaiser
        ':'
      elsif position <= length
        '#'
      else
        ' '
      end
    end
    '|' + characters.join + '|'
  end
end
