require 'set'

module LowLevel
  class BudgetExceeded < StandardError; end

  class Budget
    attr_reader :searches, :expansions

    def initialize(limit = nil)
      @limit, @searches, @expansions = limit, 0, 0
    end

    def start_search = @searches += 1

    def expand
      @expansions += 1
      raise BudgetExceeded if @limit && expansions > @limit
    end
  end

  class Prohibitions
    attr_reader :states, :moves, :permanent

    def initialize(states = Set.new, moves = Set.new, permanent = Set.new)
      @states, @moves, @permanent = states.dup, moves.dup, permanent.dup
    end

    def copy = self.class.new(states, moves, permanent)

    def allowed?(source, destination, time)
      !states.include?([destination, time]) &&
        !permanent.any? { |cell, from| cell == destination && from <= time } &&
        (source == destination || !moves.include?([source, destination, time]))
    end

    def arrival_allowed(goal)
      times = states.filter_map { |cell, time| time if cell == goal }
      times.empty? ? 0 : times.max + 1
    end

    def reserve(path, start_time: 0, forever: false)
      path.each_with_index do |cell, step|
        time = start_time + step
        states.add([cell, time])
        moves.add([cell, path[step - 1], time]) if step.positive? && cell != path[step - 1]
      end
      permanent.add([path.last, start_time + path.length - 1]) if forever
    end
  end

  class MinHeap
    def initialize = @entries = []
    def empty? = @entries.empty?
    def length = @entries.length

    def push(key, value)
      entry = [key, value]
      index = @entries.length
      @entries << entry
      while index.positive?
        parent = (index - 1) / 2
        break if (@entries[parent][0] <=> key) <= 0

        @entries[index] = @entries[parent]
        index = parent
      end
      @entries[index] = entry
    end

    def pop
      result = @entries.first[1]
      last = @entries.pop
      unless @entries.empty?
        index = 0
        while (left = index * 2 + 1) < @entries.length
          right = left + 1
          child = right < @entries.length && (@entries[right][0] <=> @entries[left][0]).negative? ? right : left
          break if (last[0] <=> @entries[child][0]) <= 0

          @entries[index] = @entries[child]
          index = child
        end
        @entries[index] = last
      end
      result
    end
  end

  def self.search(grid, agent, distances, start, t0, restrictions, tmax, budget, window: false)
    budget.start_search
    before = budget.expansions
    arrival = restrictions.arrival_allowed(agent.goal)
    beginning = [start, t0]
    parents = { beginning => nil }
    insertion = 0
    open = MinHeap.new
    open.push([distances.fetch(start), 0, 0], beginning)
    until open.empty?
      state = open.pop
      budget.expand
      cell, time = state
      if (cell == agent.goal && time >= arrival) || (window && time == tmax)
        path = []
        while state
          path << state[0]
          state = parents.fetch(state)
        end
        return [path.reverse, budget.expansions - before]
      end
      next if time == tmax

      grid.destinations(cell).each do |destination, _|
        next_time = time + 1
        next_state = [destination, next_time]
        next unless distances.key?(destination) && !parents.key?(next_state) && restrictions.allowed?(cell, destination, next_time)

        insertion += 1
        parents[next_state] = state
        g = next_time - t0
        open.push([g + distances.fetch(destination), -g, insertion], next_state)
      end
    end
    [nil, budget.expansions - before]
  end
end
