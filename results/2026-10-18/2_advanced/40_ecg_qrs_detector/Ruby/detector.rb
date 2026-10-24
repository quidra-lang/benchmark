module Detector
  Peak = Struct.new(:time, :r, :peak_i, :peak_f, :slope, :thr_i, :thr_f, :kind, keyword_init: true)

  module_function

  def find_peaks(signals)
    integrated, band, derivative = signals.values_at(:integrated, :bandpass, :derivative)
    integrated.each_index.filter_map do |time|
      value = integrated[time]
      next if value <= 0
      next if ([0, time - 20].max...time).any? { |j| integrated[j] >= value }
      next if (time + 1..[integrated.length - 1, time + 20].min).any? { |j| integrated[j] > value }

      r = ([0, time - 30].max..time).max_by { |j| [band[j].abs, -j] }
      slope = derivative[[0, time - 29].max..time].map(&:abs).max
      Peak.new(time: time, r: r, peak_i: value, peak_f: band[r].abs, slope: slope)
    end
  end

  def initial_levels(signals)
    integrated = signals[:integrated].first(400)
    band = signals[:bandpass].first(400).map(&:abs)
    { spki: integrated.max / 3, npki: integrated.reduce(0, :+) / 800,
      spkf: band.max / 3, npkf: band.reduce(0, :+) / 800 }
  end

  def width_ms(band, r)
    peak = band[r].abs
    positions = ([0, r - 25].max..[band.length - 1, r + 25].min).select do |j|
      4 * band[j].abs >= peak
    end
    5 * (positions.last - positions.first + 1)
  end
end
