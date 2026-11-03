# frozen_string_literal: true

require_relative 'line_solver'

module Propagation
  def self.known(grid)
    grid.sum { |row| row.count { |state| state != LineSolver::UNKNOWN } }
  end

  def self.label(index, height)
    index < height ? "R#{index + 1}" : "C#{index - height + 1}"
  end

  def self.line(grid, index)
    index < grid.length ? grid[index].dup : grid.map { |row| row[index - grid.length] }
  end

  def self.run(grid, rows, columns, kind, marks = nil)
    height = rows.length
    width = columns.length
    pending = marks ? marks.dup : Array.new(height + width, true)
    record = []
    while (index = pending.index(true))
      pending[index] = false
      current = line(grid, index)
      clue = index < height ? rows[index] : columns[index - height]
      solved = LineSolver.solve(current, clue, kind)
      if solved.nil?
        record << { line: index, gain: nil }
        return { grid: grid, status: 'contradiction', conflict: index, record: record, known: known(grid) }
      end
      gain = 0
      current.each_index do |position|
        next unless current[position] == LineSolver::UNKNOWN && solved[position] != LineSolver::UNKNOWN

        row, column = index < height ? [index, position] : [position, index - height]
        grid[row][column] = solved[position]
        pending[index < height ? height + column : row] = true
        gain += 1
      end
      record << { line: index, gain: gain }
    end
    determined = known(grid)
    { grid: grid, status: determined == height * width ? 'solved' : 'stuck', record: record, known: determined }
  end
end
