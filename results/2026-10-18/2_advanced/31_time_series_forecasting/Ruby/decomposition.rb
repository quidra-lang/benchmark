module Decomposition
  extend self

  # Enumerable#sum can compensate floating-point sums; the specification requires
  # ordinary additions in index order instead.
  def total(values)
    values.reduce(0.0) { |sum, value| sum + value }
  end

  def mean(values)
    total(values) / values.length
  end

  def sample_variance(values)
    average = mean(values)
    total(values.map { |value| (value - average) * (value - average) }) / (values.length - 1)
  end

  def decompose(values, season)
    count = values.length
    half = season / 2
    defined = (half...(count - half)).to_a
    trend = Array.new(count)
    defined.each do |t|
      value = 0.5 * values[t - half]
      ((t - half + 1)...(t + half)).each { |i| value += values[i] }
      value += 0.5 * values[t + half]
      trend[t] = value / season
    end
    additive = []
    multiplicative = []
    season.times do |position|
      times = defined.select { |t| t % season == position }
      additive << mean(times.map { |t| values[t] - trend[t] })
      multiplicative << mean(times.map { |t| values[t] / trend[t] })
    end
    average_add = mean(additive)
    average_mult = mean(multiplicative)
    additive.map! { |value| value - average_add }
    multiplicative.map! { |value| value / average_mult }
    residual_add = Array.new(count)
    residual_mult = Array.new(count)
    defined.each do |t|
      residual_add[t] = values[t] - trend[t] - additive[t % season]
      residual_mult[t] = values[t] / (trend[t] * multiplicative[t % season])
    end
    { trend:, additive:, multiplicative:, residual_add:, residual_mult:, defined: }
  end

  def least_squares_line(values)
    center = (values.length + 1) / 2.0
    average = mean(values)
    numerator = total(values.each_with_index.map { |value, t| (t + 1 - center) * (value - average) })
    denominator = total(values.each_index.map { |t| (t + 1 - center) * (t + 1 - center) })
    slope = numerator / denominator
    [average - slope * center, slope]
  end
end
