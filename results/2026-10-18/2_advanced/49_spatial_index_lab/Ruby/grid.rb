class Grid
  class Cell
    attr_reader :column, :row, :box, :points

    def initialize(column, row, size)
      @column, @row = column, row
      x, y = column * size, row * size
      @box = [x, y, x + size - 1, y + size - 1]
      @points = []
    end
  end

  attr_reader :world, :cell_size, :side, :cells

  def initialize(world, cell_size, points)
    @world, @cell_size = world, cell_size
    @side = world / cell_size
    @cells = Array.new(@side * @side) do |index|
      Cell.new(index % @side, index / @side, cell_size)
    end
    points.each { |point| insert(point) }
  end

  def position(point)
    [point[1] / @cell_size, point[2] / @cell_size]
  end

  def cell(point)
    column, row = position(point)
    @cells[row * @side + column]
  end

  def insert(point)
    points = cell(point).points
    index = points.bsearch_index { |other| other[0] > point[0] } || points.length
    points.insert(index, point)
  end

  def delete(point)
    cell(point).points.delete(point)
  end
end
