module Dynamics
  module_function

  def envelope(samples, attack, release)
    current = 0
    samples.map do |value|
      amplitude = [value.abs, 32_767].min
      coefficient = amplitude > current ? attack : release
      current += Signals.rdiv((amplitude - current) * coefficient, 32_768)
    end
  end

  def normalize(samples, target)
    peak = Signals.peak(samples)
    result = peak.zero? ? samples.dup : samples.map { |value| Signals.rdiv(value * target, peak) }
    [result, { source_peak: peak }]
  end

  def gate(samples, threshold, hold)
    last_large = nil
    muted = 0
    result = samples.each_with_index.map do |value, index|
      last_large = index if value.abs >= threshold
      if last_large && index - last_large <= hold
        value
      else
        muted += 1
        0
      end
    end
    [result, { muted: muted }]
  end

  def compress(samples, threshold, ratio_num, ratio_den, attack, release)
    env = envelope(samples, attack, release)
    gain = 32_768
    minimum = 32_768
    reduced = 0
    result = samples.each_with_index.map do |value, index|
      level = env[index]
      target = if level > threshold
                 desired = threshold + Signals.rdiv((level - threshold) * ratio_den, ratio_num)
                 Signals.rdiv(desired * 32_768, level)
               else
                 32_768
               end
      gain = target < gain ? target : gain + Signals.rdiv((target - gain) * release, 32_768)
      minimum = [minimum, gain].min
      reduced += 1 if gain < 32_768
      Signals.rdiv(value * gain, 32_768)
    end
    [result, { min_gain: minimum, reduced: reduced }]
  end
end
