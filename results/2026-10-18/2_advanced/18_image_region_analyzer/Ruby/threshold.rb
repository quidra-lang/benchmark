# frozen_string_literal: true

module Threshold
  Candidate = Struct.new(:threshold, :below, :above, :sum_below, :sum_above,
                         :quotient, :remainder, :denominator, keyword_init: true)
  Statistics = Struct.new(:histogram, :count, :sum, :minimum, :maximum, :median,
                          :mode, :levels, :bin_width, :bins, :candidates,
                          :otsu, :upper, :isodata, :iterations, keyword_init: true)

  module_function

  def isodata(counts, sums, total_count, total_sum)
    threshold = total_sum.div(total_count)
    iterations = 0
    loop do
      below = counts[threshold]
      above = total_count - below
      break if below.zero? || above.zero?

      sum_below = sums[threshold]
      sum_above = total_sum - sum_below
      updated = (sum_below * above + sum_above * below).div(2 * below * above)
      iterations += 1
      break if updated == threshold

      threshold = updated
      break if iterations == 100
    end
    [threshold, iterations]
  end

  def analyze(image)
    histogram = Array.new(image.maximum + 1, 0)
    image.pixels.each { |value| histogram[value] += 1 }
    count = image.pixels.length
    sum = histogram.each_index.sum { |value| value * histogram[value] }
    counts = []
    sums = []
    accumulated_count = 0
    accumulated_sum = 0
    histogram.each_with_index do |frequency, value|
      accumulated_count += frequency
      accumulated_sum += value * frequency
      counts << accumulated_count
      sums << accumulated_sum
    end
    candidates = []
    image.maximum.times do |threshold|
      below = counts[threshold]
      above = count - below
      next if histogram[threshold].zero? || above.zero?

      sum_below = sums[threshold]
      sum_above = sum - sum_below
      numerator = sum_below * sum_below * above + sum_above * sum_above * below
      denominator = below * above
      quotient, remainder = numerator.divmod(denominator)
      candidates << Candidate.new(threshold: threshold, below: below, above: above,
                                  sum_below: sum_below, sum_above: sum_above,
                                  quotient: quotient, remainder: remainder, denominator: denominator)
    end
    candidates.sort! do |first, second|
      comparison = second.quotient <=> first.quotient
      if comparison.zero?
        comparison = second.remainder * first.denominator <=> first.remainder * second.denominator
      end
      comparison.zero? ? first.threshold <=> second.threshold : comparison
    end
    minimum = histogram.index { |frequency| frequency > 0 }
    maximum = histogram.rindex { |frequency| frequency > 0 }
    otsu = candidates.empty? ? minimum : candidates.first.threshold
    upper = candidates.empty? ? minimum : ((otsu + 1)..image.maximum).find { |value| histogram[value] > 0 } - 1
    threshold, iterations = isodata(counts, sums, count, sum)
    bin_width = (image.maximum + 8).div(8)
    bins = (0..image.maximum).step(bin_width).map { |first| histogram[first, bin_width].sum }
    Statistics.new(histogram: histogram, count: count, sum: sum, minimum: minimum,
                   maximum: maximum, median: counts.index { |value| 2 * value >= count },
                   mode: histogram.index(histogram.max), levels: histogram.count(&:positive?),
                   bin_width: bin_width, bins: bins, candidates: candidates,
                   otsu: otsu, upper: upper, isodata: threshold, iterations: iterations)
  end
end
