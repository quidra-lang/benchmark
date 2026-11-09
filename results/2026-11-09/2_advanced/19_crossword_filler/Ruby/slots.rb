module Slots
  Run = Struct.new(:start, :direction, :cells) do
    def length
      cells.length
    end
  end

  Slot = Struct.new(:id, :number, :direction, :cells, :crossings) do
    def length
      cells.length
    end

    def label
      "#{number}#{direction == 'across' ? 'A' : 'D'}"
    end
  end

  Layout = Struct.new(:slots, :numbers, :cell_slots)

  def self.runs(grid)
    result = []
    grid.white_cells.each do |start|
      row, column = start.divmod(grid.width)
      if column.zero? || !grid.white?(start - 1)
        cells = []
        current = start
        while current < (row + 1) * grid.width && grid.white?(current)
          cells << current
          current += 1
        end
        result << Run.new(start, 'across', cells)
      end
      if row.zero? || !grid.white?(start - grid.width)
        cells = []
        current = start
        while current < grid.cells.length && grid.white?(current)
          cells << current
          current += grid.width
        end
        result << Run.new(start, 'down', cells)
      end
    end
    result
  end

  def self.short_run(runs)
    runs.find { |run| run.length == 2 }
  end

  def self.extract(grid, runs)
    numbers = Array.new(grid.cells.length)
    cell_slots = Array.new(grid.cells.length) { [] }
    slots = []
    next_number = 0
    runs.each do |run|
      next if run.length < 3

      unless numbers[run.start]
        next_number += 1
        numbers[run.start] = next_number
      end
      slot = Slot.new(slots.length, numbers[run.start], run.direction, run.cells, [])
      slots << slot
      slot.cells.each { |cell| cell_slots[cell] << slot.id }
    end
    slots.each do |slot|
      slot.crossings = slot.cells.flat_map { |cell| cell_slots[cell] }
                           .reject { |id| id == slot.id }.uniq.sort
    end
    Layout.new(slots, numbers, cell_slots)
  end
end
