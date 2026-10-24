require_relative "report"

module HRV
  module_function

  def root(numerator, denominator)
    (Integer.sqrt(40_000 * numerator / denominator) + 1) / 2
  end

  def mean(values)
    Report.rdiv(100 * values.reduce(0, :+), values.length) unless values.empty?
  end

  def mean_heart_rate(values)
    Report.rdiv(6_000_000 * values.length, values.reduce(0, :+)) unless values.empty?
  end

  def variance_numerator(values)
    values.length * values.reduce(0) { |total, value| total + value * value } - values.reduce(0, :+)**2
  end

  def statistics(rr, nn, pairs)
    differences = pairs.map { |a, b| b - a }
    sums = pairs.map { |a, b| a + b }
    e, k = nn.length, pairs.length
    nn50 = differences.count { |value| value.abs > 50 }
    {
      mean_rr: mean(rr), mean_hr: mean_heart_rate(rr), mean_nn: mean(nn),
      sdnn: e >= 2 ? root(variance_numerator(nn), e * (e - 1)) : nil,
      rmssd: k.positive? ? root(differences.reduce(0) { |total, value| total + value * value }, k) : nil,
      sdsd: k >= 2 ? root(variance_numerator(differences), k * (k - 1)) : nil,
      nn50: nn50, pnn50: k.positive? ? Report.rdiv(10_000 * nn50, k) : nil,
      sd1: k >= 2 ? root(variance_numerator(differences), 2 * k * (k - 1)) : nil,
      sd2: k >= 2 ? root(variance_numerator(sums), 2 * k * (k - 1)) : nil
    }
  end

  def histogram(values)
    values.map { |value| 16 * value / 125 }.tally.sort
  end

  def ranges(items)
    result = []
    start = nil
    items.each_with_index do |item, index|
      if yield(item)
        start ||= index
      elsif !start.nil?
        result << [start, index - 1]
        start = nil
      end
    end
    result << [start, items.length - 1] unless start.nil?
    result
  end
end
