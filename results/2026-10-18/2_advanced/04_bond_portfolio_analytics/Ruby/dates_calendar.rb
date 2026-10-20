# frozen_string_literal: true

require 'date'
require 'set'

module BondDates
  EPOCH = Date.new(2000, 1, 1)

  def self.leap?(year)
    (year % 4).zero? && (!(year % 100).zero? || (year % 400).zero?)
  end

  def self.month_days(year, month)
    [31, leap?(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
  end

  def self.number(year, month, day)
    (Date.new(year, month, day) - EPOCH).to_i
  end

  def self.parse(text)
    match = /\A([0-9]{4})-([0-9]{2})-([0-9]{2})\z/.match(text)
    return nil unless match

    year, month, day = match.captures.map(&:to_i)
    return nil unless year.between?(2001, 2099) && month.between?(1, 12)
    return nil unless day.between?(1, month_days(year, month))

    number(year, month, day)
  end

  def self.parts(day)
    date = EPOCH + day
    [date.year, date.month, date.day]
  end

  def self.text(day)
    format('%04d-%02d-%02d', *parts(day))
  end

  def self.month_end?(day)
    year, month, date = parts(day)
    date == month_days(year, month)
  end

  class Calendar
    def initialize(holidays)
      @holidays = holidays.to_set
    end

    def business?(day)
      ((day + 6) % 7).between?(1, 5) && !@holidays.include?(day)
    end

    def shift(day, count)
      step = count.negative? ? -1 : 1
      remaining = count.abs
      while remaining.positive?
        day += step
        remaining -= 1 if business?(day)
      end
      day
    end

    def adjust(day, convention)
      return day if convention == 'UNADJUSTED'

      direction = convention == 'PRECEDING' ? -1 : 1
      adjusted = day
      adjusted += direction until business?(adjusted)
      if convention == 'MODIFIED_FOLLOWING' && BondDates.parts(adjusted)[1] != BondDates.parts(day)[1]
        adjusted = day
        adjusted -= 1 until business?(adjusted)
      end
      adjusted
    end
  end
end
