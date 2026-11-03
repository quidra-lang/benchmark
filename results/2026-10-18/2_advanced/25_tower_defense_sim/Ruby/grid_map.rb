class GridMap
  attr_reader :width, :height, :rows, :spawns, :exit

  def initialize(path)
    lines = File.readlines(path, chomp: true)
    @width, @height = lines.shift.split.map(&:to_i)
    @rows = lines
    @spawns = {}
    @rows.each_with_index do |row, y|
      row.each_char.with_index do |character, x|
        @spawns[character.to_i] = [x, y] if character >= '1' && character <= '9'
        @exit = [x, y] if character == 'E'
      end
    end
    @spawns = @spawns.sort.to_h
  end

  def inside?(cell)
    x, y = cell
    x >= 0 && x < @width && y >= 0 && y < @height
  end

  def terrain(cell)
    @rows[cell[1]][cell[0]]
  end

  def rock?(cell)
    terrain(cell) == '#'
  end

  def water?(cell)
    terrain(cell) == '~'
  end

  def buildable?(cell)
    terrain(cell) == '.'
  end

  def center(cell)
    [100 * cell[0], 100 * cell[1]]
  end
end
