# frozen_string_literal: true

require_relative 'headers'

module Dates
  MONTHS = %w[jan feb mar apr may jun jul aug sep oct nov dec].freeze
  WEEKDAYS = %w[mon tue wed thu fri sat sun].freeze
  ZONES = { 'ut' => 0, 'gmt' => 0, 'z' => 0, 'est' => -300, 'edt' => -240,
            'cst' => -360, 'cdt' => -300, 'mst' => -420, 'mdt' => -360,
            'pst' => -480, 'pdt' => -420 }.freeze

  def self.leap?(year)
    ((year % 4).zero? && !(year % 100).zero?) || (year % 400).zero?
  end

  def self.month_length(year, month)
    return leap?(year) ? 29 : 28 if month == 2

    [4, 6, 9, 11].include?(month) ? 30 : 31
  end

  def self.parse(text)
    stripped = Headers.remove_comments(text)
    return [nil, 'bad Date syntax'] unless stripped

    tokens = stripped.gsub(',', ' , ').scan(/[^ \t]+/)
    weekday = nil
    if tokens.length >= 3 && WEEKDAYS.include?(tokens[0].downcase) && tokens[1] == ','
      weekday = WEEKDAYS.index(tokens.shift.downcase)
      tokens.shift
    end
    return [nil, 'bad Date syntax'] unless tokens.length == 5

    day_text, month_text, year_text, time_text, zone_text = tokens
    month_index = MONTHS.index(month_text.downcase)
    clock = time_text.split(':', -1)
    numeric_zone = zone_text.match?(/\A[+-][0-9]{4}\z/)
    syntax_valid = day_text.match?(/\A[0-9]{1,2}\z/) && month_index &&
                   year_text.match?(/\A(?:[0-9]{2}|[0-9]{4})\z/) &&
                   [2, 3].include?(clock.length) && clock.all? { |part| part.match?(/\A[0-9]{2}\z/) } &&
                   (numeric_zone || ZONES.key?(zone_text.downcase))
    return [nil, 'bad Date syntax'] unless syntax_valid

    day = day_text.to_i
    month = month_index + 1
    year = year_text.to_i
    year += year < 50 ? 2000 : 1900 if year_text.length == 2
    hour, minute, second = clock.map(&:to_i)
    second ||= 0
    if numeric_zone
      zone_hour = zone_text[1, 2].to_i
      zone_minute = zone_text[3, 2].to_i
      return [nil, 'Date out of range'] if zone_hour > 23 || zone_minute > 59

      offset = zone_hour * 60 + zone_minute
      offset = -offset if zone_text.start_with?('-')
    else
      offset = ZONES.fetch(zone_text.downcase)
    end
    return [nil, 'Date out of range'] unless year.between?(1970, 2099) &&
                                            day.between?(1, month_length(year, month)) &&
                                            hour <= 23 && minute <= 59 && second <= 59

    days = day - 1
    (1970...year).each { |prior| days += leap?(prior) ? 366 : 365 }
    (1...month).each { |prior| days += month_length(year, prior) }
    seconds = days * 86_400 + hour * 3600 + minute * 60 + second - offset * 60
    return [nil, 'Date out of range'] if seconds.negative?
    return [nil, 'Date weekday mismatch'] if weekday && (days + 3) % 7 != weekday

    [seconds, nil]
  end

  def self.notation(seconds)
    days, remainder = seconds.divmod(86_400)
    year = 1970
    while days >= (leap?(year) ? 366 : 365)
      days -= leap?(year) ? 366 : 365
      year += 1
    end
    month = 1
    while days >= month_length(year, month)
      days -= month_length(year, month)
      month += 1
    end
    format('%04d-%02d-%02d %02d:%02d:%02d', year, month, days + 1,
           remainder / 3600, (remainder % 3600) / 60, remainder % 60)
  end
end
