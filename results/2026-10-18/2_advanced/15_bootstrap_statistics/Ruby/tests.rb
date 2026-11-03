require_relative 'resampling'

module Tests
  module_function

  def position_choices(size, count)
    return enum_for(__method__, size, count) unless block_given?

    choice = (0...count).to_a
    loop do
      yield choice.dup
      index = count - 1
      index -= 1 while index >= 0 && choice[index] == size - count + index
      break if index.negative?

      choice[index] += 1
      ((index + 1)...count).each { |next_index| choice[next_index] = choice[next_index - 1] + 1 }
    end
  end

  def reduced_fraction(numerator, denominator)
    divisor = numerator.gcd(denominator)
    [numerator / divisor, denominator / divisor]
  end

  def contrast(first, second)
    second.length * first.sum - first.length * second.sum
  end

  def equal_counts(values)
    values.tally
  end

  def doubled_ranks(values)
    counts = equal_counts(values)
    ranks = {}
    smaller = 0
    counts.keys.sort.each do |value|
      ranks[value] = 2 * smaller + counts[value] + 1
      smaller += counts[value]
    end
    values.map { |value| ranks.fetch(value) }
  end

  def divide(values, sizes)
    offset = 0
    sizes.map do |size|
      group = values[offset, size]
      offset += size
      group
    end
  end

  def anova(samples)
    sizes = samples.map(&:length)
    count = sizes.sum
    means = samples.map { |sample| Resampling.mean(sample) }
    grand = samples.sum { |sample| sample.sum }.to_f / (100 * count)
    between = within = 0.0
    samples.each_with_index do |sample, index|
      difference = means[index] - grand
      between += sizes[index] * (difference * difference)
      group_squares = 0.0
      sample.each do |value|
        deviation = value / 100.0 - means[index]
        group_squares += deviation * deviation
      end
      within += group_squares
    end
    statistic = between / (samples.length - 1) / (within / (count - samples.length))
    { means: means, grand: grand, ssb: between, ssw: within, f: statistic }
  end

  def kruskal(rank_groups, sizes, correction)
    total = 0.0
    rank_groups.each_with_index do |ranks, index|
      rank_sum = ranks.sum
      total += (rank_sum * rank_sum).to_f / (4 * sizes[index])
    end
    count = sizes.sum
    (12 * total / (count * (count + 1)) - 3 * (count + 1)) / correction
  end
end
