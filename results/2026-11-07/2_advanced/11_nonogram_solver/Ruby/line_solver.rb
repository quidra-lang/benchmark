# frozen_string_literal: true

module LineSolver
  UNKNOWN = 0
  FILLED = 1
  EMPTY = 2

  class Placements
    def initialize(line, clue)
      @line = line
      @clue = clue
      @length = line.length
      @filled = [0]
      @empty = [0]
      line.each do |state|
        @filled << @filled.last + (state == FILLED ? 1 : 0)
        @empty << @empty.last + (state == EMPTY ? 1 : 0)
      end
      @required = Array.new(clue.length)
      remaining = 0
      (clue.length - 1).downto(0) do |index|
        remaining += clue[index] + (index == clue.length - 1 ? 0 : 1)
        @required[index] = remaining
      end
      @suffix = Array.new(clue.length + 1) { Array.new(@length + 1, false) }
      0.upto(@length) { |position| @suffix[clue.length][position] = @filled[position] == @filled[@length] }
      (clue.length - 1).downto(0) do |index|
        0.upto(@length) do |position|
          transitions(index, position) do |_start, _ending, following|
            if @suffix[index + 1][following]
              @suffix[index][position] = true
              break
            end
          end
        end
      end
    end

    def feasible?
      @suffix[0][0]
    end

    def transitions(index, position)
      position.upto(@length - @required[index]) do |start|
        break if @filled[start] != @filled[position]

        ending = start + @clue[index]
        next unless @empty[start] == @empty[ending]

        following = ending
        if index < @clue.length - 1
          next if @line[ending] == FILLED

          following += 1
        end
        yield start, ending, following
      end
    end

    def support
      reachable = Array.new(@clue.length + 1) { Array.new(@length + 1, false) }
      reachable[0][0] = true
      filled = Array.new(@length, false)
      empty = Array.new(@length, false)
      left = Array.new(@clue.length)
      right = Array.new(@clue.length)
      @clue.each_index do |index|
        0.upto(@length) do |position|
          next unless reachable[index][position]

          transitions(index, position) do |start, ending, following|
            next unless @suffix[index + 1][following]

            reachable[index + 1][following] = true
            left[index] = start if left[index].nil? || start < left[index]
            right[index] = start if right[index].nil? || start > right[index]
            (position...start).each { |cell| empty[cell] = true }
            (start...ending).each { |cell| filled[cell] = true }
            empty[ending] = true if following > ending
          end
        end
      end
      0.upto(@length) do |position|
        (position...@length).each { |cell| empty[cell] = true } if reachable[@clue.length][position]
      end
      [filled, empty, left, right]
    end
  end

  def self.consistent?(line, clue)
    Placements.new(line, clue).feasible?
  end

  def self.solve(line, clue, kind)
    placements = Placements.new(line, clue)
    return nil unless placements.feasible?

    possible_filled, possible_empty, left, right = placements.support
    result = line.dup
    if kind == :precise
      line.each_index do |index|
        next unless line[index] == UNKNOWN

        result[index] = FILLED unless possible_empty[index]
        result[index] = EMPTY unless possible_filled[index]
      end
    else
      covered = Array.new(line.length, false)
      clue.each_with_index do |length, index|
        (left[index]...(right[index] + length)).each { |cell| covered[cell] = true }
        (right[index]...(left[index] + length)).each { |cell| result[cell] = FILLED if line[cell] == UNKNOWN }
      end
      line.each_index { |index| result[index] = EMPTY if line[index] == UNKNOWN && !covered[index] }
    end
    result
  end
end
