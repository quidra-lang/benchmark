module Entropy
  TABLE_KEYS = [[0, 0], [1, 0], [0, 1], [1, 1]].freeze
  TABLE_NAMES = %w[dc_luma ac_luma dc_chroma ac_chroma].freeze
  module_function

  def category(value)
    value.abs.bit_length
  end

  def extra_bits(value)
    size = category(value)
    [value.negative? ? value + (1 << size) - 1 : value, size]
  end

  def amplitude(bits, size)
    return 0 if size.zero?
    bits >= (1 << (size - 1)) ? bits : bits - (1 << size) + 1
  end

  class HuffmanTable
    attr_reader :counts, :symbols, :codes, :decode

    def initialize(counts, symbols)
      @counts, @symbols = counts.dup, symbols.dup
      @codes, @decode = {}, {}
      code = offset = 0
      counts.each_with_index do |count, i|
        length = i + 1
        symbols[offset, count].each do |symbol|
          @codes[symbol] = [length, code]
          @decode[[length, code]] = symbol
          code += 1
        end
        offset += count
        code *= 2
      end
    end
  end

  def optimized_table(frequencies)
    frequencies = frequencies.dup << 1
    sizes = Array.new(257, 0)
    others = Array.new(257, -1)
    loop do
      available = (0..256).select { |s| frequencies[s].positive? }.sort_by { |s| [frequencies[s], -s] }
      break if available.length < 2
      first, second = available.first(2)
      frequencies[first] += frequencies[second]
      frequencies[second] = 0
      sizes[first] += 1
      while others[first] != -1
        first = others[first]
        sizes[first] += 1
      end
      others[first] = second
      sizes[second] += 1
      while others[second] != -1
        second = others[second]
        sizes[second] += 1
      end
    end
    counts = Array.new(257, 0)
    sizes.each { |size| counts[size] += 1 if size.positive? }
    sizes.max.downto(17) do |length|
      while counts[length].positive?
        shorter = length - 2
        shorter -= 1 while counts[shorter].zero?
        counts[length] -= 2
        counts[length - 1] += 1
        counts[shorter + 1] += 2
        counts[shorter] -= 1
      end
    end
    longest = (1..16).select { |length| counts[length].positive? }.max
    counts[longest] -= 1
    symbols = (0...256).select { |s| sizes[s].positive? }.sort_by { |s| [sizes[s], s] }
    HuffmanTable.new(counts[1, 16], symbols)
  end
end
