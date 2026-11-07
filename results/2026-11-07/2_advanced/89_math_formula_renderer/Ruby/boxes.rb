require_relative 'lexer'

class Box
  attr_reader :width, :height, :baseline, :description, :children, :strings

  def initialize(width, height, baseline, description)
    @width, @height, @baseline, @description = width, height, baseline, description
    @children, @strings = [], []
  end

  def descent
    @height - 1 - @baseline
  end

  def add(child, x, y, role = '')
    @children << [child, x, y, role]
  end

  def draw(text, x = 0, y = 0)
    @strings << [text, x, y]
  end
end

module Boxes
  DISPLAY = Lexer::SYMBOL_COMMANDS.transform_values(&:first).freeze
  COMMAND_TYPES = Lexer::SYMBOL_COMMANDS.transform_values(&:last).freeze
  SYMBOL_TYPES = { '+' => 'binary', '-' => 'binary', '*' => 'binary',
                   '=' => 'relation', '<' => 'relation', '>' => 'relation', ':' => 'relation',
                   '(' => 'open', '[' => 'open', ')' => 'close', ']' => 'close', '!' => 'close',
                   ',' => 'punctuation', ';' => 'punctuation' }.freeze
  LARGE_GLYPHS = { '\\sum' => ['\\--', ' > ', '/--'], '\\prod' => ['___', '| |', '| |'],
                   '\\int' => [' /', ' |', '/ '] }.freeze

  def self.delimiter_glyph(delimiter, height)
    return [] if delimiter == '.'
    return [delimiter[-1]] if height == 1
    return Array.new(height, delimiter) if ['[', ']', '|'].include?(delimiter)
    left = ['(', '\\{'].include?(delimiter)
    result = [left ? '/' : '\\'] + Array.new(height - 2, '|') + [left ? '\\' : '/']
    result[(height - 1) / 2] = left ? '<' : '>' if ['\\{', '\\}'].include?(delimiter) && height >= 3
    result
  end
end
