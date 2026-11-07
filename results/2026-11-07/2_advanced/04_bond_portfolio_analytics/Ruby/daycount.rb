# frozen_string_literal: true

require_relative 'dates_calendar'

module DayCount
  CONVENTIONS = %w[30/360 30E/360 ACT/360 ACT/365F ACT/ACT].freeze

  def self.fraction(first, last, convention)
    return [last - first, 360] if convention == 'ACT/360'
    return [last - first, 365] if convention == 'ACT/365F'

    if convention == 'ACT/ACT'
      numerator = 0
      cursor = first
      while cursor < last
        year = BondDates.parts(cursor)[0]
        ending = [last, BondDates.number(year + 1, 1, 1)].min
        numerator += (ending - cursor) * (BondDates.leap?(year) ? 365 : 366)
        cursor = ending
      end
      return [numerator, 133_590]
    end

    year1, month1, day1 = BondDates.parts(first)
    year2, month2, day2 = BondDates.parts(last)
    if convention == '30/360'
      february1 = month1 == 2 && BondDates.month_end?(first)
      february2 = month2 == 2 && BondDates.month_end?(last)
      day2 = 30 if february1 && february2
      day1 = 30 if february1
      day2 = 30 if day2 == 31 && day1 >= 30
      day1 = 30 if day1 == 31
    else
      day1 = 30 if day1 == 31
      day2 = 30 if day2 == 31
    end
    [360 * (year2 - year1) + 30 * (month2 - month1) + day2 - day1, 360]
  end
end
