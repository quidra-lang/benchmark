# frozen_string_literal: true

require_relative 'day_rules'

module TzParser
  def self.extract(line)
    content = line.partition('#')[0].sub(/ +\z/, '')
    return nil if content.empty?

    { continued: content.start_with?(' '), fields: content.split(' ') }
  end

  def self.hms(token)
    match = /\A([0-9]{1,2})(?::([0-9]{2})(?::([0-9]{2}))?)?\z/.match(token)
    return nil unless match

    hour = match[1].to_i
    minute = match[2].to_i
    second = match[3].to_i
    return nil if minute > 59 || second > 59

    hour * 3600 + minute * 60 + second
  end

  def self.year(token)
    return nil unless /\A[0-9]{4}\z/.match?(token)

    value = token.to_i
    value if value.between?(1800, 2099)
  end

  def self.to_year(token, first)
    return first if token == 'only'
    return 2099 if token == 'max'

    value = year(token)
    value if value && value >= first
  end

  def self.month(token)
    index = DayRules::MONTHS.index(token)
    index && index + 1
  end

  def self.day(token, month)
    if /\A[1-9][0-9]?\z/.match?(token)
      return token if token.to_i <= DayRules::LENGTHS[month - 1]
    elsif /\Alast(Sun|Mon|Tue|Wed|Thu|Fri|Sat)\z/.match?(token)
      return token
    else
      match = /\A(Sun|Mon|Tue|Wed|Thu|Fri|Sat)(>=|<=)([1-9][0-9]?)\z/.match(token)
      return token if match && match[3].to_i <= DayRules::LENGTHS[month - 1]
    end
    nil
  end

  def self.time(token)
    suffix = %w[w s u].include?(token[-1])
    value = hms(suffix ? token[0...-1] : token)
    return nil if value.nil? || value > 86_400

    [value, suffix ? token[-1] : 'w']
  end

  def self.save(token)
    return nil unless /\A[0-9]{1,2}(?::[0-9]{2})?\z/.match?(token)

    value = hms(token)
    value if value && value <= 7200
  end

  def self.letter(token)
    return '' if token == '-'

    token if /\A[A-Z]{1,5}\z/.match?(token)
  end

  def self.offset(token)
    negative = token.start_with?('-')
    value = hms(negative ? token[1..] : token)
    return nil if value.nil? || value >= 57_600

    negative ? -value : value
  end

  def self.format?(token, named_rules)
    return false unless /\A[A-Za-z0-9+\/%\-]+\z/.match?(token)
    return false if token.scan('%s').length > 1 || token.gsub('%s', '').include?('%')
    return false if token.count('/') > 1 || (token.include?('/') && token.include?('%s'))
    return false if token.include?('/') && token.split('/', -1).any?(&:empty?)
    return false if !named_rules && token.include?('%s')

    true
  end

  def self.until_fields(fields)
    return [nil, nil] if fields.empty?

    year = year(fields[0])
    return [nil, 'bad year'] if year.nil?

    month = month(fields[1] || 'Jan')
    return [nil, 'bad month'] if month.nil?

    day = day(fields[2] || '1', month)
    return [nil, 'bad day spec'] if day.nil?

    time = time(fields[3] || '0:00')
    return [nil, 'bad time'] if time.nil?

    value = DayRules.specification(year, month, day) * 86_400 + time[0]
    [{ value: value, time: time, raw: [fields[0], fields[1] || 'Jan', fields[2] || '1'] }, nil]
  end

  def self.date(token)
    match = /\A([0-9]{4})-([0-9]{2})-([0-9]{2})\z/.match(token)
    return nil unless match

    year = year(match[1])
    month = match[2].to_i
    day = match[3].to_i
    return nil if year.nil? || !month.between?(1, 12)
    return nil unless day.between?(1, DayRules.month_length(year, month))

    DayRules.day_number(year, month, day)
  end

  def self.timestamp(token, utc = false)
    text = utc ? token.delete_suffix('Z') : token
    match = /\A([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})\z/.match(text)
    return nil unless match

    day = date(match[1])
    hour, minute, second = match.captures.drop(1).map(&:to_i)
    return nil if day.nil? || hour > 23 || minute > 59 || second > 59

    day * 86_400 + hour * 3600 + minute * 60 + second
  end
end
