# frozen_string_literal: true

module Transposition
  module_function

  def rail_number(position, rails)
    cycle = 2 * rails - 2
    offset = position % cycle
    [offset, cycle - offset].min
  end

  def rail_order(length, rails)
    positions = Array.new(rails) { [] }
    length.times { |index| positions[rail_number(index, rails)] << index }
    positions.flatten
  end

  def railfence(text, rails, decrypt: false)
    order = rail_order(text.length, rails)
    return order.map { |index| text.getbyte(index) }.pack('C*') unless decrypt

    result = Array.new(text.length)
    order.each_with_index { |position, index| result[position] = text.getbyte(index) }
    result.pack('C*')
  end

  def column_order(key)
    (0...key.length).sort_by { |column| [key.getbyte(column), column] }
  end

  def rank_string(key)
    ranks = Array.new(key.length)
    column_order(key).each_with_index { |column, rank| ranks[column] = rank + 1 }
    ranks.join
  end

  def columnar(text, key, decrypt: false)
    width = key.length
    result = String.new(encoding: Encoding::ASCII_8BIT)
    order = column_order(key)
    unless decrypt
      order.each do |column|
        index = column
        while index < text.length
          result << text.getbyte(index)
          index += width
        end
      end
      return result
    end

    columns = Array.new(width)
    offset = 0
    order.each do |column|
      length = (text.length + width - 1 - column) / width
      columns[column] = text.byteslice(offset, length)
      offset += length
    end
    text.length.times do |index|
      result << columns[index % width].getbyte(index / width)
    end
    result
  end
end
