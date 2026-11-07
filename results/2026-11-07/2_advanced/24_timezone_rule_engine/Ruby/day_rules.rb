# frozen_string_literal: true

module DayRules
  MONTHS = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze
  WEEKDAYS = %w[Sun Mon Tue Wed Thu Fri Sat].freeze
  LENGTHS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31].freeze

  def self.leap?(year)
    (year % 4).zero? && (!(year % 100).zero? || (year % 400).zero?)
  end

  def self.month_length(year, month)
    month == 2 && leap?(year) ? 29 : LENGTHS[month - 1]
  end

  def self.before_year(year)
    previous = year - 1
    365 * previous + previous.div(4) - previous.div(100) + previous.div(400)
  end

  def self.day_number(year, month, day)
    before_year(year) - before_year(1970) + (1...month).sum { |m| month_length(year, m) } + day - 1
  end

  def self.date(number)
    year = 1970 + number.div(365)
    year -= 1 while day_number(year, 1, 1) > number
    year += 1 while day_number(year + 1, 1, 1) <= number
    remaining = number - day_number(year, 1, 1)
    month = 1
    while remaining >= month_length(year, month)
      remaining -= month_length(year, month)
      month += 1
    end
    [year, month, remaining + 1]
  end

  def self.weekday(number)
    (number + 4) % 7
  end

  def self.specification(year, month, token)
    return day_number(year, month, token.to_i) if /\A[0-9]+\z/.match?(token)

    if token.start_with?('last')
      last = day_number(year, month, month_length(year, month))
      target = WEEKDAYS.index(token.delete_prefix('last'))
      return last - (weekday(last) - target) % 7
    end
    target = WEEKDAYS.index(token[0, 3])
    base = day_number(year, month, token[5..].to_i)
    token[3, 2] == '>=' ? base + (target - weekday(base)) % 7 : base - (weekday(base) - target) % 7
  end

  def self.parts(value)
    number, seconds = value.divmod(86_400)
    year, month, day = date(number)
    hour, seconds = seconds.divmod(3600)
    minute, second = seconds.divmod(60)
    [year, month, day, hour, minute, second]
  end
end
