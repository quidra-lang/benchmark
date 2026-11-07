require 'set'

class Filler
  Attempt = Struct.new(:minimum, :budget, :outcome, :nodes, :backtracks, :prunes,
                       :dead_ends, :max_depth, :failures, :trace, :sequence, :state,
                       keyword_init: true)

  def initialize(index, slots, initial, minimum, budget)
    @index = index
    @slots = slots
    @state = initial.copy
    @minimum = minimum
    @budget = budget
    @used = Set.new(@state.assigned.compact)
    @nodes = @backtracks = @prunes = @dead_ends = @max_depth = 0
    @sequence = []
    @best = @state.copy
    @failures = Array.new(slots.length, 0)
    @trace = []
  end

  def run
    result = search
    outcome = { complete: 'filled', fail: 'unfillable', abort: 'budget' }.fetch(result)
    final_state = result == :complete ? @state.copy : @best
    Attempt.new(minimum: @minimum, budget: @budget, outcome: outcome, nodes: @nodes,
                backtracks: @backtracks, prunes: @prunes, dead_ends: @dead_ends,
                max_depth: @max_depth, failures: @failures, trace: @trace,
                sequence: @sequence.dup, state: final_state)
  end

  private

  def candidates(slot)
    @index.candidates(@state.pattern(slot), @minimum, @used)
  end

  def search
    chosen = nil
    choices = nil
    @slots.each do |slot|
      next if @state.assigned[slot.id]

      available = candidates(slot)
      if chosen.nil? || available.length < choices.length
        chosen = slot
        choices = available
      end
    end
    return :complete if chosen.nil?

    if choices.empty?
      @dead_ends += 1
      @failures[chosen.id] += 1
      return :fail
    end
    choices.each do |word|
      return :abort if @nodes == @budget

      @nodes += 1
      @state.assigned[chosen.id] = word
      @used.add(word)
      changed = []
      chosen.cells.each_with_index do |cell, position|
        next unless @state.cells[cell] == '.'

        changed << cell
        @state.cells[cell] = word[position]
      end
      @sequence << chosen.id
      wiped = chosen.crossings.find do |id|
        @state.assigned[id].nil? && candidates(@slots[id]).empty?
      end
      @trace << "#{chosen.label}=#{word}#{wiped.nil? ? '' : '!'}" if @nodes <= 10
      if wiped
        @prunes += 1
        @failures[wiped] += 1
        result = :fail
      else
        if @sequence.length > @max_depth
          @max_depth = @sequence.length
          @best = @state.copy
        end
        result = search
      end
      return result if result == :complete || result == :abort

      @state.assigned[chosen.id] = nil
      @used.delete(word)
      changed.each { |cell| @state.cells[cell] = '.' }
      @sequence.pop
      @backtracks += 1
    end
    :fail
  end
end
