module Spectrum
  COEFFICIENTS = {
    'rectangular' => [1.0], 'hann' => [0.5, 0.5], 'hamming' => [0.54, 0.46],
    'blackman' => [0.42, 0.5, 0.08],
    'flattop' => [0.21557895, 0.41663158, 0.277263158, 0.083578947, 0.006947368]
  }.freeze

  def ordered_sum(values)
    total = 0.0
    values.each { |v| total += v }
    total
  end

  def window(name, length)
    Array.new(length) do |n|
      total = 0.0
      COEFFICIENTS.fetch(name).each_with_index do |weight, j|
        total += (-1)**j * weight * Math.cos(2 * PI * j * n / length)
      end
      total
    end
  end

  def figures(values, fs)
    n = values.length
    s1, s2 = ordered_sum(values), ordered_sum(values.map { |v| v * v })
    magnitude = ordered_sum(values.each_with_index.map { |v, j| v * rot(PI * j / n) }).abs
    enbw = n * s2 / (s1 * s1)
    {s1: s1, s2: s2, coherent_gain: s1 / n, enbw_bins: enbw,
     enbw_hz: enbw * fs / n, scalloping_db: -20 * Math.log10(magnitude / s1)}
  end
end
