module Resampling
  module_function

  def float_sum(values)
    values.reduce(0.0) { |total, value| total + value }
  end

  def mean(sample)
    sample.sum.to_f / (100 * sample.length)
  end

  def median_twice(sample)
    sorted = sample.sort
    sorted[(sorted.length - 1) / 2] + sorted[sorted.length / 2]
  end

  def median(sample)
    median_twice(sample) / 200.0
  end

  def trimmed_mean(sample)
    trim = sample.length / 10
    sample.sort[trim, sample.length - 2 * trim].sum.to_f /
      (100 * (sample.length - 2 * trim))
  end

  def sd(sample)
    center = mean(sample)
    squares = 0.0
    sample.each do |value|
      deviation = value / 100.0 - center
      squares += deviation * deviation
    end
    Math.sqrt(squares / (sample.length - 1))
  end

  def moments(sample)
    center = mean(sample)
    second = third = fourth = 0.0
    sample.each do |value|
      deviation = value / 100.0 - center
      second += deviation * deviation
      third += deviation * deviation * deviation
      fourth += deviation * deviation * deviation * deviation
    end
    [second / sample.length, third / sample.length, fourth / sample.length]
  end

  def mad(sample)
    center = median_twice(sample)
    median_twice(sample.map { |value| (2 * value - center).abs }) / 400.0
  end

  def quantile_numerator(sample, percentile)
    sorted = sample.sort
    index, fraction = ((sample.length - 1) * percentile).divmod(100)
    result = 100 * sorted[index]
    result += fraction * (sorted[index + 1] - sorted[index]) unless fraction.zero?
    result
  end

  def winsorized(sample)
    sorted = sample.sort
    trim = sample.length / 10
    low = sorted[trim]
    high = sorted[sample.length - trim - 1]
    sample.map { |value| value.clamp(low, high) }
  end

  def mean_difference(first, second)
    numerator = second.length * first.sum - first.length * second.sum
    numerator.to_f / (100 * first.length * second.length)
  end

  def median_ratio(first, second)
    median_twice(first).to_f / median_twice(second)
  end

  def hodges_lehmann(first, second)
    differences = first.flat_map { |value| second.map { |other| value - other } }
    median_twice(differences) / 200.0
  end

  def pooled_sd(first, second)
    sx = sd(first)
    sy = sd(second)
    Math.sqrt(((first.length - 1) * sx * sx + (second.length - 1) * sy * sy) /
              (first.length + second.length - 2))
  end

  def cohen_d(first, second)
    mean_difference(first, second) / pooled_sd(first, second)
  end

  def correlation(first, second)
    mx = mean(first)
    my = mean(second)
    cross = squares_x = squares_y = 0.0
    first.each_index do |index|
      x = first[index] / 100.0 - mx
      y = second[index] / 100.0 - my
      cross += x * y
      squares_x += x * x
      squares_y += y * y
    end
    cross / Math.sqrt(squares_x * squares_y)
  end

  def statistics(sample)
    [mean(sample), median(sample), trimmed_mean(sample), sd(sample)]
  end

  def pair_statistics(first, second)
    [mean_difference(first, second), median_ratio(first, second),
     hodges_lehmann(first, second), cohen_d(first, second)]
  end

  def ordinary_indices(size, generator)
    Array.new(size) { generator.below(size) }
  end

  def balanced_indices(size, replicates, generator)
    generator.shuffle((0...size).to_a * replicates).each_slice(size).to_a
  end

  def without(sample, index)
    result = sample.dup
    result.delete_at(index)
    result
  end

  def average_and_se(values)
    average = float_sum(values) / values.length
    squares = 0.0
    values.each do |value|
      deviation = value - average
      squares += deviation * deviation
    end
    [average, Math.sqrt(squares / (values.length - 1))]
  end

  def phi(value)
    return 1 - phi(-value) if value.negative?

    eta = 1 / (1 + 0.2316419 * value)
    psi = eta * (0.319381530 + eta * (-0.356563782 + eta *
      (1.781477937 + eta * (-1.821255978 + eta * 1.330274429))))
    1 - 0.3989422804014327 * Math.exp(-(value * value) / 2) * psi
  end

  def phi_inverse(probability)
    return -phi_inverse(1 - probability) if probability > 0.5

    eta = Math.sqrt(-2 * Math.log(probability))
    -(eta - (2.515517 + eta * (0.802853 + eta * 0.010328)) /
      (1 + eta * (1.432788 + eta * (0.189269 + eta * 0.001308))))
  end
end
