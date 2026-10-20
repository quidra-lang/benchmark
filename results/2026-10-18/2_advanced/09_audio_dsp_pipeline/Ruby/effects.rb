module Effects
  module_function

  def gain(samples, numerator, denominator)
    saturator = Signals::Saturator.new
    result = samples.map { |value| saturator.call(Signals.rdiv(value * numerator, denominator)) }
    [result, { clipped: saturator.clips }]
  end

  def mix(sources, weights, denominator)
    saturator = Signals::Saturator.new
    count = sources.map(&:length).max
    result = Array.new(count) do |index|
      total = 0
      sources.each_with_index do |source, pair|
        total += weights[pair] * (source.samples[index] || 0)
      end
      saturator.call(Signals.rdiv(total, denominator))
    end
    [result, { clipped: saturator.clips }]
  end

  def delay(samples, count)
    Array.new(count, 0) + samples
  end

  def echo(samples, delay, numerator, denominator, tail)
    result = samples + Array.new(tail, 0)
    saturator = Signals::Saturator.new
    delay.upto(result.length - 1) do |index|
      result[index] = saturator.call(result[index] + Signals.rdiv(numerator * result[index - delay], denominator))
    end
    [result, { clipped: saturator.clips }]
  end

  def resample(samples, old_rate, new_rate)
    count = ((samples.length - 1) * new_rate).div(old_rate) + 1
    Array.new(count) do |index|
      position, remainder = (index * old_rate).divmod(new_rate)
      if remainder.zero?
        samples[position]
      else
        samples[position] + Signals.rdiv((samples[position + 1] - samples[position]) * remainder, new_rate)
      end
    end
  end

  def fade(samples, fade_in, fade_out)
    result = samples.dup
    fade_in.times { |index| result[index] = Signals.rdiv(result[index] * index, fade_in) }
    (samples.length - fade_out).upto(samples.length - 1) do |index|
      result[index] = Signals.rdiv(result[index] * (samples.length - 1 - index), fade_out)
    end
    result
  end
end
