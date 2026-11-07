# frozen_string_literal: true

module Bisection
  def self.solve(lower, upper, target)
    80.times do
      middle = (lower + upper) / 2.0
      if yield(middle) > target
        lower = middle
      else
        upper = middle
      end
    end
    (lower + upper) / 2.0
  end
end

class YieldPricing
  def initialize(cashflows, fraction, frequency, outstanding)
    @cashflows = cashflows
    @fraction = fraction
    @frequency = frequency.to_f
    @outstanding = outstanding.to_f
  end

  def values(rate)
    first = 1.0 + @fraction * rate / @frequency
    factor = 1.0 + rate / @frequency
    power = 1.0
    @cashflows.map do |amount|
      value = amount.to_f / (first * power)
      power *= factor
      value
    end
  end

  def dirty(rate)
    values(rate).reduce(0.0, :+) * 100.0 / @outstanding
  end

  def yield_to(target)
    Bisection.solve(0.0, 1.0, target) { |rate| dirty(rate) }
  end

  def analytics(target)
    rate = yield_to(target)
    present_values = values(rate)
    total = present_values.reduce(0.0, :+)
    weighted = 0.0
    convex = 0.0
    present_values.each_with_index do |value, index|
      time = (index.to_f + @fraction) / @frequency
      weighted += time * value
      convex += time * (time + 1.0 / @frequency) * value
    end
    factor = 1.0 + rate / @frequency
    macaulay = weighted / total
    { ytm: rate, macaulay: macaulay, modified: macaulay / factor,
      convexity: convex / (total * factor * factor),
      dv01: (dirty(rate - 0.0001) - dirty(rate + 0.0001)) / 2.0 }
  end
end
