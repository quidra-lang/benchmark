module Pathing
  DIRECTIONS = [[0, -1, '^'], [1, 0, '>'], [0, 1, 'v'], [-1, 0, '<']].freeze

  class Field
    def initialize(grid, blocked)
      @grid = grid
      @distances = Array.new(grid.width * grid.height)
      @distances[index(grid.exit)] = 0
      queue = [grid.exit]
      head = 0
      while head < queue.length
        cell = queue[head]
        head += 1
        DIRECTIONS.each do |dx, dy, _arrow|
          neighbor = [cell[0] + dx, cell[1] + dy]
          next unless grid.inside?(neighbor)
          next if grid.rock?(neighbor) || blocked.key?(neighbor)
          next unless @distances[index(neighbor)].nil?

          @distances[index(neighbor)] = distance(cell) + 1
          queue << neighbor
        end
      end
    end

    def index(cell)
      cell[1] * @grid.width + cell[0]
    end

    def distance(cell)
      @distances[index(cell)] if @grid.inside?(cell)
    end

    def next_step(cell)
      best = nil
      best_distance = nil
      DIRECTIONS.each do |dx, dy, arrow|
        neighbor = [cell[0] + dx, cell[1] + dy]
        value = distance(neighbor)
        next if value.nil?
        next unless best_distance.nil? || value < best_distance

        best = [neighbor, arrow]
        best_distance = value
      end
      best
    end

    def next_cell(cell)
      next_step(cell)[0]
    end

    def arrow(cell)
      next_step(cell)[1]
    end

    def path(spawn)
      cells = [spawn]
      cells << next_cell(cells[-1]) until cells[-1] == @grid.exit
      cells
    end
  end
end
