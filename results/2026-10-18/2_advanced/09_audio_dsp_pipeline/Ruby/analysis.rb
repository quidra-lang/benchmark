module Analysis
  module_function

  def energy(samples)
    samples.sum { |value| value * value }
  end

  def rms(samples)
    Integer.sqrt(energy(samples).div(samples.length))
  end

  def zero_crossings(samples)
    samples.each_cons(2).count { |left, right| (left < 0) != (right < 0) }
  end

  def clipped(samples)
    samples.count { |value| value == -32_768 || value == 32_767 }
  end

  def crest(samples)
    denominator = energy(samples)
    return 'none' if denominator.zero?

    peak = Signals.peak(samples)
    numerator = peak * peak * samples.length
    divisor = numerator.gcd(denominator)
    "#{numerator.div(divisor)}/#{denominator.div(divisor)}"
  end

  def autocorrelation(samples, lag)
    total = 0
    index = 0
    while index < samples.length - lag
      total += samples[index] * samples[index + lag]
      index += 1
    end
    total
  end

  def pitch_lag(samples, low, high)
    best = nil
    lag = nil
    low.upto(high) do |candidate|
      correlation = autocorrelation(samples, candidate)
      if best.nil? || correlation > best
        best = correlation
        lag = candidate
      end
    end
    best > 0 ? lag : nil
  end
end
