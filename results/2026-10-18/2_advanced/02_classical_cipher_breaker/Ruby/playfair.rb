# frozen_string_literal: true

module Playfair
  ALPHABET = 'ABCDEFGHIKLMNOPQRSTUVWXYZ'

  module_function

  def square(key)
    (key + ALPHABET).chars.uniq.join
  end

  def prepare(text)
    text = text.tr('J', 'I')
    result = String.new(encoding: Encoding::ASCII_8BIT)
    index = 0
    while index < text.length
      first = text.getbyte(index)
      second = text.getbyte(index + 1)
      result << first
      if !second.nil? && second != first
        result << second
        index += 2
      else
        result << (first == 88 ? 81 : 88)
        index += 1
      end
    end
    result
  end

  def valid_ciphertext?(text)
    return false unless text.length.even?

    text = text.tr('J', 'I')
    (0...text.length).step(2).all? { |index| text.getbyte(index) != text.getbyte(index + 1) }
  end

  def transform(text, key, decrypt: false)
    grid = square(key)
    positions = Array.new(26)
    grid.each_byte.with_index { |byte, index| positions[byte - 65] = index.divmod(5) }
    pairs = decrypt ? text.tr('J', 'I') : prepare(text)
    shift = decrypt ? 4 : 1
    result = String.new(encoding: Encoding::ASCII_8BIT)
    (0...pairs.length).step(2) do |index|
      first_row, first_column = positions[pairs.getbyte(index) - 65]
      second_row, second_column = positions[pairs.getbyte(index + 1) - 65]
      if first_row == second_row
        first_column = (first_column + shift) % 5
        second_column = (second_column + shift) % 5
      elsif first_column == second_column
        first_row = (first_row + shift) % 5
        second_row = (second_row + shift) % 5
      else
        first_column, second_column = second_column, first_column
      end
      result << grid.getbyte(first_row * 5 + first_column)
      result << grid.getbyte(second_row * 5 + second_column)
    end
    result
  end
end
