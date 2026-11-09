class Canvas
  def initialize(width, height)
    @width = width
    @height = height
    @rows = Array.new(height) { Array.new(width, ' ') }
  end

  def position(x, y, denominator = 1)
    column = (2 * x * (@width - 1) + 1000 * denominator) / (2000 * denominator)
    row = @height - 1 - (2 * y * (@height - 1) + 1000 * denominator) / (2000 * denominator)
    [column, row]
  end

  def mark(point, character)
    column, row = position(*point)
    @rows[row][column] = character
  end

  def line(first, second, character)
    x, y = position(*first)
    end_x, end_y = position(*second)
    dx = (end_x - x).abs
    dy = -(end_y - y).abs
    step_x = x < end_x ? 1 : -1
    step_y = y < end_y ? 1 : -1
    error = dx + dy
    loop do
      @rows[y][x] = character
      break if x == end_x && y == end_y

      twice_error = 2 * error
      if twice_error >= dy
        error += dy
        x += step_x
      end
      if twice_error <= dx
        error += dx
        y += step_y
      end
    end
  end

  def draw_voronoi(points)
    horizontal = @width - 1
    vertical = @height - 1
    owners = Array.new(@height) do |row|
      Array.new(@width) do |column|
        (1...points.size).min_by do |site|
          x, y = points[site]
          dx = (column * 1000 - x * horizontal) * vertical
          dy = ((vertical - row) * 1000 - y * vertical) * horizontal
          [dx * dx + dy * dy, site]
        end
      end
    end
    @height.times do |row|
      @width.times do |column|
        owner = owners[row][column]
        right_differs = column < horizontal && owner != owners[row][column + 1]
        below_differs = row < vertical && owner != owners[row + 1][column]
        @rows[row][column] = '#' if right_differs || below_differs
      end
    end
    points.drop(1).each { |point| mark(point, 'o') }
  end

  def framed
    border = '+' + '-' * @width + '+'
    [border, *@rows.map { |row| '|' + row.join + '|' }, border]
  end
end
