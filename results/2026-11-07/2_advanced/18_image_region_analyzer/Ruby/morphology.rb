# frozen_string_literal: true

module Morphology
  CLOCKWISE = [[0, -1], [1, -1], [1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1]].freeze

  module_function

  def present?(mask, x, y, width, height)
    x >= 0 && x < width && y >= 0 && y < height && mask[y * width + x]
  end

  def erode(mask, offsets, width, height)
    mask.each_index.map do |index|
      x, y = index % width, index.div(width)
      offsets.all? { |dx, dy| present?(mask, x + dx, y + dy, width, height) }
    end
  end

  def dilate(mask, offsets, width, height)
    mask.each_index.map do |index|
      x, y = index % width, index.div(width)
      offsets.any? { |dx, dy| present?(mask, x - dx, y - dy, width, height) }
    end
  end

  def apply(mask, operation, offsets, width, height)
    case operation
    when 'erode' then erode(mask, offsets, width, height)
    when 'dilate' then dilate(mask, offsets, width, height)
    when 'open' then dilate(erode(mask, offsets, width, height), offsets, width, height)
    when 'close' then erode(dilate(mask, offsets, width, height), offsets, width, height)
    end
  end

  def neighbour_bits(mask, index, width, height)
    x, y = index % width, index.div(width)
    CLOCKWISE.map { |dx, dy| present?(mask, x + dx, y + dy, width, height) ? 1 : 0 }
  end

  def transitions(bits)
    bits.each_index.count { |index| bits[index].zero? && bits[(index + 1) % 8] == 1 }
  end

  def thin(pixels, width, height)
    mask = Array.new(width * height, false)
    pixels.each { |index| mask[index] = true }
    loop do
      removed = 0
      2.times do |phase|
        doomed = pixels.select do |index|
          next false unless mask[index]

          bits = neighbour_bits(mask, index, width, height)
          next false unless bits.sum.between?(2, 6) && transitions(bits) == 1

          north, east, south, west = bits.values_at(0, 2, 4, 6)
          if phase.zero?
            (north * east * south).zero? && (east * south * west).zero?
          else
            (north * east * west).zero? && (north * south * west).zero?
          end
        end
        doomed.each { |index| mask[index] = false }
        removed += doomed.length
      end
      break if removed.zero?
    end
    mask
  end
end
