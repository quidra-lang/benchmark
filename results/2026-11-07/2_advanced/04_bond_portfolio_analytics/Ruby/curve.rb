# frozen_string_literal: true

require_relative 'daycount'
require_relative 'schedule'
require_relative 'pricing'

class ZeroCurve
  attr_reader :days, :rates

  def initialize(days, rates)
    @days = days
    @rates = rates
  end

  def zero(day)
    return @rates.first if day <= @days.first
    return @rates.last if day >= @days.last

    upper = @days.index { |pillar| pillar >= day }
    return @rates[upper] if day == @days[upper]

    weight = (day - @days[upper - 1]).to_f / (@days[upper] - @days[upper - 1]).to_f
    @rates[upper - 1] + (@rates[upper] - @rates[upper - 1]) * weight
  end

  def discount(day, spread = 0.0)
    rate = zero(day) + spread
    years, remainder = day.divmod(365)
    power = 1.0
    years.times { power *= 1.0 + rate }
    1.0 / (power * (1.0 + rate * remainder.to_f / 365.0))
  end

  def present_value(cashflows, spread = 0.0)
    cashflows.reduce(0.0) { |total, (day, amount)| total + amount.to_f * discount(day, spread) }
  end

  def forward(first, last)
    (discount(first) / discount(last) - 1.0) * 365.0 / (last - first).to_f
  end

  def shifted(shifts)
    ZeroCurve.new(@days, @rates.each_with_index.map { |rate, index| rate + shifts[index] })
  end

  def zspread(cashflows, value)
    Bisection.solve(-0.5, 0.5, value.to_f) { |spread| present_value(cashflows, spread) }
  end

  def self.bootstrap(pillars, settlement)
    days = []
    rates = []
    pillars.each do |pillar|
      schedule = CouponSchedule.build(settlement, pillar[:maturity], pillar[:frequency])
      cashflows = schedule.each_cons(2).map do |first, last|
        numerator, denominator = DayCount.fraction(first, last, '30/360')
        amount = pillar[:coupon].to_f * numerator.to_f / (10_000.0 * denominator.to_f)
        amount += 1.0 if last == pillar[:maturity]
        [last - settlement, amount]
      end
      pillar_days = days + [pillar[:maturity] - settlement]
      rate = Bisection.solve(0.0, 1.0, 1.0) do |candidate|
        ZeroCurve.new(pillar_days, rates + [candidate]).present_value(cashflows)
      end
      days = pillar_days
      rates << rate
    end
    ZeroCurve.new(days, rates)
  end
end
