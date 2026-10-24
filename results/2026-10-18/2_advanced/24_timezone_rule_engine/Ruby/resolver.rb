# frozen_string_literal: true

module Resolver
  def self.period_index(periods, time)
    left = 0
    right = periods.length
    while left < right
      middle = (left + right) / 2
      if middle.zero? || periods[middle][:start] <= time
        left = middle + 1
      else
        right = middle
      end
    end
    left - 1
  end

  def self.period(periods, time)
    periods[period_index(periods, time)]
  end

  def self.range(periods, index)
    [periods[index][:start], periods[index + 1]&.fetch(:start)]
  end

  def self.candidates(periods, local)
    result = []
    periods.each_with_index do |period, index|
      time = local - period[:state][0]
      first, last = range(periods, index)
      next if (!first.nil? && time < first) || (!last.nil? && time >= last)

      result << [time, period]
    end
    result.sort_by(&:first)
  end

  def self.skipping(periods, local)
    periods.each_cons(2).find do |before, after|
      time = after[:start]
      time + before[:state][0] <= local && local < time + after[:state][0]
    end
  end
end
