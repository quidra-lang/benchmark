# frozen_string_literal: true

module Analysis
  module_function

  def counts(text)
    result = Array.new(26, 0)
    text.each_byte { |byte| result[byte - 65] += 1 }
    result
  end

  def coincidence(text)
    return 0 if text.length < 2

    numerator = counts(text).sum { |count| count * (count - 1) }
    100_000 * numerator / (text.length * (text.length - 1))
  end

  def columns(text, period)
    result = Array.new(period) { String.new(encoding: Encoding::ASCII_8BIT) }
    text.each_byte.with_index { |byte, index| result[index % period] << byte }
    result
  end

  def kasiski(text)
    positions = Hash.new { |table, trigram| table[trigram] = [] }
    (0...(text.length - 2)).each { |index| positions[text.byteslice(index, 3)] << index + 1 }
    repeats = []
    gaps = []
    positions.keys.sort.each do |trigram|
      occurrences = positions[trigram]
      next if occurrences.length < 2

      spacings = occurrences.each_cons(2).map { |first, second| second - first }
      repeats << {trigram: trigram, positions: occurrences, gaps: spacings, gcd: spacings.reduce(0, :gcd)}
      gaps.concat(spacings)
    end
    {repeats: repeats, gaps: gaps}
  end

  def periods(text, maximum, examination)
    (1..maximum).map do |period|
      indices = columns(text, period).map { |column| coincidence(column) }
      {length: period, columns: indices, ioc: indices.sum / period,
       kasiski: examination[:gaps].count { |gap| gap % period == 0 }}
    end
  end

  def percentage(count, length)
    rounded = (2000 * count + length) / (2 * length)
    "#{rounded / 10}.#{rounded % 10}"
  end

  def pair_counts(text, step: 1)
    result = Hash.new(0)
    index = 0
    while index + 1 < text.length
      result[text.byteslice(index, 2)] += 1
      index += step
    end
    result
  end

  def top_pairs(counts)
    counts.sort_by { |pair, count| [-count, pair] }.first(10).map { |pair, count| "#{pair}:#{count}" }.join(' ')
  end
end
