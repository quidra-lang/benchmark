class Grid
  State = Struct.new(:cells, :assigned) do
    def copy
      self.class.new(cells.dup, assigned.dup)
    end

    def pattern(slot)
      slot.cells.map { |cell| cells[cell] }.join
    end
  end

  attr_reader :width, :height, :cells, :white_cells

  def initialize(rows)
    @height = rows.length
    @width = rows.first.length
    @cells = rows.join.chars
    @white_cells = @cells.each_index.select { |cell| white?(cell) }
  end

  def white?(cell)
    @cells[cell] != '#'
  end

  def position(cell)
    [cell / @width + 1, cell % @width + 1]
  end

  def initial_state(slot_count)
    State.new(@cells.dup, Array.new(slot_count))
  end

  def symmetry_failure(kind)
    return nil if kind == 'none'

    @cells.each_index do |cell|
      row, column = cell.divmod(@width)
      partner = if kind == 'rot180'
                  (@height - 1 - row) * @width + @width - 1 - column
                else
                  row * @width + @width - 1 - column
                end
      return [row + 1, column + 1] if white?(cell) != white?(partner)
    end
    nil
  end

  def components
    seen = Array.new(@cells.length, false)
    count = 0
    @white_cells.each do |start|
      next if seen[start]

      count += 1
      seen[start] = true
      pending = [start]
      until pending.empty?
        cell = pending.pop
        row, column = cell.divmod(@width)
        neighbors = []
        neighbors << cell - @width if row.positive?
        neighbors << cell + @width if row + 1 < @height
        neighbors << cell - 1 if column.positive?
        neighbors << cell + 1 if column + 1 < @width
        neighbors.each do |neighbor|
          next if seen[neighbor] || !white?(neighbor)

          seen[neighbor] = true
          pending << neighbor
        end
      end
    end
    count
  end
end
