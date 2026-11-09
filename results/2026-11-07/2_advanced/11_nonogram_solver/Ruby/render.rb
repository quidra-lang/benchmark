# frozen_string_literal: true

require_relative 'clues'

module Render
  SYMBOLS = ['?', '#', '.'].freeze
  STATES = SYMBOLS.each_with_index.to_h.freeze

  def self.symbol(state)
    SYMBOLS.fetch(state)
  end

  def self.parse(text)
    text.each_char.map { |character| STATES.fetch(character) }
  end

  def self.line(states)
    states.map { |state| symbol(state) }.join
  end

  def self.side_by_side(entries, height)
    rows = Array.new(height) do |row|
      entries.map { |_, grid| line(grid[row]) }.join(' | ')
    end
    ["grid #{entries.map(&:first).join(' ')}"] + rows
  end

  def self.sheet(rows, columns, grid)
    tokens = columns.map { |clue| Clues.text(clue).split(' ') }
    width = tokens.flatten.map(&:length).max + 1
    depth = tokens.map(&:length).max
    labels = rows.map { |clue| Clues.text(clue) }
    margin = labels.map(&:length).max
    lines = Array.new(depth) do |level|
      cells = tokens.map do |column|
        index = level - (depth - column.length)
        index.negative? ? ' ' * width : column[index].rjust(width)
      end
      (' ' * margin + cells.join).rstrip
    end
    grid.each_with_index do |row, index|
      lines << labels[index].rjust(margin) + row.map { |state| ' ' * (width - 1) + symbol(state) }.join
    end
    lines
  end
end
