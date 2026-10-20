# frozen_string_literal: true

require_relative 'line_solver'

module Clues
  def self.parse(text)
    return [] if text == '0'
    return nil unless /\A[1-9][0-9]?(?: [1-9][0-9]?)*\z/.match?(text)

    text.split(' ').map(&:to_i)
  end

  def self.fits?(clue, length)
    clue.empty? || clue.sum + clue.length - 1 <= length
  end

  def self.text(clue, separator = ' ')
    clue.empty? ? '0' : clue.join(separator)
  end

  def self.runs(line)
    blocks = []
    length = 0
    line.each do |state|
      if state == LineSolver::FILLED
        length += 1
      elsif length.positive?
        blocks << length
        length = 0
      end
    end
    blocks << length if length.positive?
    blocks
  end
end
