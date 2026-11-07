module Units
  SINE = [0, 174, 342, 500, 643, 766, 866, 940, 985, 1000].freeze

  module_function

  def sin(angle)
    angle %= 360
    if angle <= 90
      SINE[angle / 10]
    elsif angle <= 180
      SINE[(180 - angle) / 10]
    elsif angle <= 270
      -SINE[(angle - 180) / 10]
    else
      -SINE[(360 - angle) / 10]
    end
  end

  def cos(angle) = sin(angle + 90)
  def knots(value) = (value * 1944 + 500).div(1000)
  def inhg(value) = (value * 2953 + 500).div(1000)
  def hpa(value) = (value * 33864 + 50_000).div(100_000)

  def miles(visibility)
    if visibility[:kind] == :miles
      Rational(visibility[:whole] * visibility[:denominator] + visibility[:numerator], visibility[:denominator])
    else
      Rational(1000 * visibility[:value], 1_609_344)
    end
  end

  def meters(visibility)
    return visibility[:value] unless visibility[:kind] == :miles
    value = miles(visibility)
    (1_609_344 * value.numerator).div(1000 * value.denominator)
  end

  def fraction(numerator, denominator)
    return 'undefined' if denominator.zero?
    divisor = numerator.gcd(denominator)
    "#{numerator / divisor}/#{denominator / divisor}"
  end

  def days(year, month)
    return 30 if [4, 6, 9, 11].include?(month)
    return 31 unless month == 2
    year % 400 == 0 || (year % 4 == 0 && year % 100 != 0) ? 29 : 28
  end

  class Calendar
    attr_reader :days

    def initialize(year, month)
      @year = year
      @month = month
      @days = Units.days(year, month)
      @next_year, @next_month = month == 12 ? [year + 1, 1] : [year, month + 1]
      @next_days = Units.days(@next_year, @next_month)
    end

    def report_time(text)
      match = /\A(\d{2})(\d{2})(\d{2})Z\z/.match(text)
      return nil unless match
      day, hour, minute = match.captures.map(&:to_i)
      return nil unless day.between?(1, @days) && hour <= 23 && minute <= 59
      ((day - 1) * 24 + hour) * 60 + minute
    end

    def day_time(day, hour, minute, issue_day)
      following = day < issue_day
      return nil unless day.between?(1, following ? @next_days : @days)
      (following ? @days * 1440 : 0) + ((day - 1) * 24 + hour) * 60 + minute
    end

    def period(text, issue_day, maximum = nil)
      match = /\A(\d{2})(\d{2})\/(\d{2})(\d{2})\z/.match(text)
      return nil unless match
      first_day, first_hour, last_day, last_hour = match.captures.map(&:to_i)
      return nil unless first_hour <= 23 && last_hour.between?(1, 24)
      first = day_time(first_day, first_hour, 0, issue_day)
      last = day_time(last_day, last_hour, 0, issue_day)
      return nil unless first && last && first < last && (!maximum || last <= first + maximum)
      [first, last]
    end

    def stamp(time)
      year, month = @year, @month
      if time >= @days * 1440
        time -= @days * 1440
        year, month = @next_year, @next_month
      end
      format('%04d-%02d-%02dT%02d:%02dZ', year, month, time.div(1440) + 1, time % 1440 / 60, time % 60)
    end
  end
end
