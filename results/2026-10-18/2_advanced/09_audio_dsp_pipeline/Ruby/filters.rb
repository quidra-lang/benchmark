module Filters
  module_function

  def fir(samples, divisor, taps)
    saturator = Signals::Saturator.new
    result = Array.new(samples.length) do |index|
      total = 0
      [taps.length, index + 1].min.times { |tap| total += taps[tap] * samples[index - tap] }
      saturator.call(total.div(divisor))
    end
    [result, { clipped: saturator.clips }]
  end

  def biquad(samples, coefficients)
    saturator = Signals::Saturator.new
    result = samples
    coefficients.each_slice(5) do |b0, b1, b2, a1, a2|
      input = result
      result = []
      input.each_index do |index|
        previous_input = index >= 1 ? input[index - 1] : 0
        older_input = index >= 2 ? input[index - 2] : 0
        previous_output = index >= 1 ? result[index - 1] : 0
        older_output = index >= 2 ? result[index - 2] : 0
        total = b0 * input[index] + b1 * previous_input + b2 * older_input
        total -= a1 * previous_output
        total -= a2 * older_output
        result << saturator.call(total.div(16_384))
      end
    end
    [result, { sections: coefficients.length.div(5), clipped: saturator.clips }]
  end

  def moving_average(samples, width)
    total = 0
    samples.each_index.map do |index|
      total += samples[index]
      total -= samples[index - width] if index >= width
      Signals.rdiv(total, width)
    end
  end

  def dc_block(samples, numerator, denominator)
    saturator = Signals::Saturator.new
    previous_input = 0
    previous_output = 0
    result = samples.map do |value|
      output = saturator.call(value - previous_input + Signals.rdiv(numerator * previous_output, denominator))
      previous_input = value
      previous_output = output
      output
    end
    [result, { clipped: saturator.clips }]
  end
end
