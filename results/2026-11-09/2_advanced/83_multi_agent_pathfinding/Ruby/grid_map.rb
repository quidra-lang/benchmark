require 'set'

module GridMap
  ACTIONS = [[0, 0, '.'], [0, -1, 'N'], [1, 0, 'E'], [0, 1, 'S'], [-1, 0, 'W']].freeze
  Agent = Data.define(:id, :start, :goal) do
    def name = (65 + id).chr
  end

  class Grid
    attr_reader :width, :height, :rows, :free

    def initialize(width, height, rows)
      @width, @height, @rows = width, height, rows
      @free = Set.new
      rows.each_with_index do |row, y|
        row.each_char.with_index { |char, x| free.add([x, y].freeze) if char == '.' }
      end
      @destinations = free.to_h do |cell|
        choices = ACTIONS.filter_map do |dx, dy, action|
          destination = [cell[0] + dx, cell[1] + dy].freeze
          [destination, action] if free.include?(destination)
        end
        [cell, choices]
      end
    end

    def destinations(cell) = @destinations.fetch(cell, [])
    def neighbors(cell) = destinations(cell).drop(1).map(&:first)
    def degree(cell) = destinations(cell).length - 1

    def distances(goal)
      result, queue, head = { goal => 0 }, [goal], 0
      while head < queue.length
        cell = queue[head]
        head += 1
        neighbors(cell).each do |neighbor|
          next if result.key?(neighbor)

          result[neighbor] = result.fetch(cell) + 1
          queue << neighbor
        end
      end
      result
    end
  end

  def self.read_grid
    lines = File.readlines('input/map.txt', chomp: true)
    width, height = lines.shift.split.map(&:to_i)
    Grid.new(width, height, lines)
  end

  def self.read_agents
    File.readlines('input/agents.csv', chomp: true).drop(1).map do |line|
      id, sx, sy, gx, gy = line.split(',').map(&:to_i)
      Agent.new(id, [sx, sy].freeze, [gx, gy].freeze)
    end
  end
end
