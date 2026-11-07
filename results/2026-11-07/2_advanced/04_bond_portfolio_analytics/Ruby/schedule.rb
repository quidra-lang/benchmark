# frozen_string_literal: true

require_relative 'dates_calendar'

module CouponSchedule
  FREQUENCIES = [1, 2, 4, 12].freeze

  def self.build(issue, maturity, frequency, eom: false, long: false)
    year, month, day = BondDates.parts(maturity)
    end_of_month = eom && BondDates.month_end?(maturity)
    step = 12 / frequency
    dates = []
    index = 0
    loop do
      period_year, period_month = (year * 12 + month - 1 - step * index).divmod(12)
      period_month += 1
      last_day = BondDates.month_days(period_year, period_month)
      period_day = end_of_month ? last_day : [day, last_day].min
      current = BondDates.number(period_year, period_month, period_day)
      if current <= issue
        dates.pop if long && current != issue && index >= 2
        break
      end
      dates << current
      index += 1
    end
    [issue] + dates.reverse
  end
end
