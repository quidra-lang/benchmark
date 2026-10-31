module Filters
  module_function

  def at(values, index) = index.negative? ? 0 : values[index]

  def filter_ecg(samples)
    size = samples.length
    c, low, band, derivative, squared, integrated = Array.new(6) { Array.new(size, 0) }
    high_sum = window_sum = 0
    size.times do |n|
      c[n] = 2 * at(c, n - 1) - at(c, n - 2) + samples[n] -
             2 * at(samples, n - 6) + at(samples, n - 12)
      low[n] = c[n] / 32
      high_sum += low[n] - at(low, n - 32)
      band[n] = at(low, n - 16) - high_sum / 32
      derivative[n] = (2 * band[n] + at(band, n - 1) - at(band, n - 3) - 2 * at(band, n - 4)) / 8
      squared[n] = derivative[n] * derivative[n]
      window_sum += squared[n] - at(squared, n - 30)
      integrated[n] = window_sum / 30
    end
    { ecg: samples, lowpass: low, bandpass: band, derivative: derivative,
      squared: squared, integrated: integrated }
  end
end
