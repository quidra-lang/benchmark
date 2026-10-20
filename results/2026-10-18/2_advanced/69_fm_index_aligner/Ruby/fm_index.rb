require_relative 'suffix_array'

class FMIndex
  attr_reader :size, :bwt, :interval, :c_array, :checkpoints, :samples
  def initialize(text, suffixes, occurrence_interval, sample_interval = nil)
    @size, @interval = text.size, occurrence_interval
    @bwt = suffixes.map { |position| text[position - 1] }.join
    frequencies = Hash.new(0).merge(text.chars.tally)
    offset = 0
    @c_array = SuffixArray::SYMBOLS.chars.to_h do |symbol|
      value = offset
      offset += frequencies[symbol]
      [symbol, value]
    end
    counts = Array.new(6, 0)
    @checkpoints = [counts.dup]
    @bwt.each_char.with_index(1) do |symbol, position|
      counts[SuffixArray::SYMBOL_NUMBER.fetch(symbol)] += 1
      @checkpoints << counts.dup if (position % @interval).zero?
    end
    @samples = if sample_interval
                 suffixes.each_with_index.filter_map { |position, row| [row, position] if (position % sample_interval).zero? }.to_h
               end
  end

  def occurrence(symbol, position)
    checkpoint = position / @interval
    start = checkpoint * @interval
    @checkpoints[checkpoint][SuffixArray::SYMBOL_NUMBER.fetch(symbol)] + @bwt[start...position].count(symbol)
  end
  def lf(row)
    symbol = @bwt[row]
    @c_array.fetch(symbol) + occurrence(symbol, row)
  end
  def extend_interval(lower, upper, base)
    return [0, 0] if base == 'N'
    [@c_array.fetch(base) + occurrence(base, lower), @c_array.fetch(base) + occurrence(base, upper)]
  end
  def locate(row)
    steps = 0
    until @samples.key?(row)
      row = lf(row)
      steps += 1
    end
    [@samples.fetch(row) + steps, steps]
  end
  def inverse
    result = Array.new(@size)
    result[-1] = '$'
    row = 0
    (@size - 2).downto(0) do |position|
      result[position] = @bwt[row]
      row = lf(row)
    end
    result.join
  end
  def backward_search(sequence)
    lower, upper = 0, @size
    sequence.reverse.each_char do |base|
      lower, upper = extend_interval(lower, upper, base)
      break if lower >= upper
    end
    [lower, upper]
  end
end
