# frozen_string_literal: true

require_relative 'propagation'

module Search
  def self.choose(grid)
    rows = grid.map { |row| row.count(LineSolver::UNKNOWN) }
    columns = grid.first.each_index.map { |column| grid.count { |row| row[column] == LineSolver::UNKNOWN } }
    chosen = nil
    smallest = nil
    grid.each_with_index do |line, row|
      line.each_with_index do |state, column|
        next unless state == LineSolver::UNKNOWN

        score = rows[row] + columns[column]
        if smallest.nil? || score < smallest
          smallest = score
          chosen = [row, column]
        end
      end
    end
    chosen
  end

  class Explorer
    def initialize(rows, columns)
      @rows = rows
      @columns = columns
      @records = []
      @solutions = []
      @maximum_depth = 0
      @backtracks = 0
      @line_solves = 0
    end

    def visit(grid, depth)
      row, column = Search.choose(grid)
      [LineSolver::FILLED, LineSolver::EMPTY].each do |value|
        number = @records.length + 1
        @maximum_depth = [@maximum_depth, depth].max
        child = grid.map(&:dup)
        child[row][column] = value
        marks = Array.new(@rows.length + @columns.length, false)
        marks[row] = marks[@rows.length + column] = true
        outcome = Propagation.run(child, @rows, @columns, :precise, marks)
        @line_solves += outcome[:record].length
        result = if outcome[:status] == 'contradiction'
                   @backtracks += 1
                   "contradiction at=#{Propagation.label(outcome[:conflict], @rows.length)}"
                 elsif outcome[:status] == 'solved'
                   @solutions << child
                   "solution#{@solutions.length}"
                 else
                   'open'
                 end
        @records << { number: number, depth: depth, row: row, column: column, value: value,
                      solves: outcome[:record].length, known: outcome[:known], result: result }
        return if @solutions.length == 2

        visit(child, depth + 1) if result == 'open'
        return if @solutions.length == 2
      end
    end

    def run(grid)
      visit(grid, 1)
      { guesses: @records.length, max_depth: @maximum_depth, backtracks: @backtracks,
        solutions: @solutions, line_solves: @line_solves, records: @records }
    end
  end

  def self.run(grid, rows, columns)
    Explorer.new(rows, columns).run(grid)
  end
end
