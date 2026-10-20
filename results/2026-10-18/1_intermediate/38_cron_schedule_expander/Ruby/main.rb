# frozen_string_literal: true

require 'set'

FIELD_NAMES = %w[minute hour day-of-month month day-of-week].freeze
MINIMUM = [0, 0, 1, 1, 0].freeze
MAXIMUM = [59, 23, 31, 12, 7].freeze
MONTH_NAMES = %w[January February March April May June July August September October November December].freeze
WEEKDAY_NAMES = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
MONTH_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31].freeze
MONTH_CODES = %w[JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC].freeze
WEEKDAY_CODES = %w[SUN MON TUE WED THU FRI SAT].freeze

class CommandError < StandardError; end

def fail_command(reason) = raise(CommandError, reason)
def digits?(text, minimum, maximum) = text.length.between?(minimum, maximum) && text.each_byte.all? { |c| c.between?(48, 57) }
def leap?(year) = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
def month_length(year, month) = month == 2 && leap?(year) ? 29 : MONTH_DAYS[month - 1]

CivilDate = Data.define(:year, :month, :day) do
  def number
    result = day - 1
    (2000...year).each { |y| result += leap?(y) ? 366 : 365 }
    (1...month).each { |m| result += month_length(year, m) }
    result
  end

  def weekday = (number + 6) % 7
  def to_s = format('%04d-%02d-%02d %s', year, month, day, WEEKDAY_NAMES[weekday][0, 3])

  def self.from_number(number)
    year = 2000
    month = 1
    while number >= (leap?(year) ? 366 : 365)
      number -= leap?(year) ? 366 : 365
      year += 1
    end
    while number >= month_length(year, month)
      number -= month_length(year, month)
      month += 1
    end
    new(year, month, number + 1)
  end
end

def read_date(text, reason = 'invalid date')
  fail_command(reason) unless text.match?(/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/)
  date = CivilDate.new(text[0, 4].to_i, text[5, 2].to_i, text[8, 2].to_i)
  unless date.year.between?(2001, 2098) && date.month.between?(1, 12) && date.day.between?(1, month_length(date.year, date.month))
    fail_command(reason)
  end
  date
end

def read_datetime(words, at)
  date = read_date(words[at], 'invalid datetime')
  time = words[at + 1]
  fail_command('invalid datetime') unless time.match?(/\A[0-9]{2}:[0-9]{2}\z/)
  hour = time[0, 2].to_i
  minute = time[3, 2].to_i
  fail_command('invalid datetime') if hour > 23 || minute > 59
  date.number * 1440 + hour * 60 + minute
end

def read_month(text)
  fail_command('invalid month') unless text.match?(/\A[0-9]{4}-[0-9]{2}\z/)
  date = CivilDate.new(text[0, 4].to_i, text[5, 2].to_i, 1)
  fail_command('invalid month') unless date.year.between?(2001, 2098) && date.month.between?(1, 12)
  date
end

def datetime_text(time)
  date = CivilDate.from_number(time / 1440)
  format('%04d-%02d-%02d %02d:%02d %s', date.year, date.month, date.day, time % 1440 / 60, time % 60, WEEKDAY_NAMES[date.weekday][0, 3])
end

def span(minutes) = format('%dd%02dh%02dm', minutes / 1440, minutes % 1440 / 60, minutes % 60)

def positive(text, width, maximum, reason)
  fail_command(reason) unless digits?(text, 1, width) && text[0] != '0' && text.to_i <= maximum
  text.to_i
end

Window = Data.define(:low, :high)

def read_window(words, at)
  low = read_datetime(words, at)
  high = read_datetime(words, at + 2)
  fail_command('invalid window') if low > high
  fail_command('window too long') if high - low > 44_640
  Window.new(low, high)
end

Special = Data.define(:kind, :value, :occurrence) do
  def to_s
    case kind
    when :last then 'L'
    when :last_workday then 'LW'
    when :before_last then "L-#{value}"
    when :nearest then "#{value}W"
    when :nth_weekday then "#{value}##{occurrence}"
    when :last_weekday then "#{value}L"
    end
  end

  def phrase
    case kind
    when :last then 'the last day'
    when :last_workday then 'the last weekday'
    when :before_last then "#{value} #{value == 1 ? 'day' : 'days'} before the last day"
    when :nearest then "the weekday nearest day #{value}"
    when :nth_weekday then "the #{%w[1st 2nd 3rd 4th 5th][occurrence - 1]} #{WEEKDAY_NAMES[value]}"
    when :last_weekday then "the last #{WEEKDAY_NAMES[value]}"
    end
  end
end

def read_value(text, index)
  names = index == 3 ? MONTH_CODES : index == 4 ? WEEKDAY_CODES : []
  named = names.index(text)
  return named + (index == 3 ? 1 : 0) if named
  fail_command('invalid value') unless digits?(text, 1, 2)
  value = text.to_i
  fail_command('out of range') unless value.between?(MINIMUM[index], MAXIMUM[index])
  value
end

def special_number(text, maximum, width = 2)
  fail_command('invalid value') unless digits?(text, 1, width)
  value = text.to_i
  fail_command('out of range') unless value.between?(1, maximum)
  value
end

def word_list(parts, either = false)
  return parts.join if parts.length < 2
  parts[0...-1].join(', ') + (either ? ' or ' : ' and ') + parts[-1]
end

CronField = Data.define(:index, :values, :specials, :restricted) do
  def include?(value) = values.include?(value)

  def stepped
    return 0 if values.length < 2 || values[0] != 0 || values[1] < 2
    step = values[1]
    return 0 unless values.length == MAXIMUM[index] / step + 1 && values.each_with_index.all? { |value, i| value == i * step }
    step
  end

  def value_name(value)
    case index
    when 3 then MONTH_NAMES[value - 1]
    when 4 then WEEKDAY_NAMES[value]
    else value.to_s
    end
  end

  def value_list(either = false)
    parts = []
    first = 0
    while first < values.length
      last = first
      last += 1 while last + 1 < values.length && values[last + 1] == values[last] + 1
      if last - first >= 2
        parts << "#{value_name(values[first])} through #{value_name(values[last])}"
      else
        (first..last).each { |i| parts << value_name(values[i]) }
      end
      first = last + 1
    end
    word_list(parts, either)
  end

  def day_phrase(either = false)
    parts = []
    unless values.empty?
      parts << (index == 4 ? value_list(either) : "#{values.length == 1 ? 'day' : 'days'} #{value_list}")
    end
    parts.concat(specials.map(&:phrase))
    word_list(parts, either) + (index == 2 || !specials.empty? ? ' of the month' : '')
  end

  def self.parse(text, index)
    values = Set.new
    specials = []
    text.split(',', -1).each do |item|
      fail_command('empty item') if item.empty?
      special = if index == 2 && (item.start_with?('L') || item.end_with?('W'))
                  if item == 'L'
                    Special.new(:last, 0, 0)
                  elsif item == 'LW'
                    Special.new(:last_workday, 0, 0)
                  elsif item.start_with?('L-')
                    Special.new(:before_last, special_number(item[2..], 30), 0)
                  elsif item.end_with?('W')
                    Special.new(:nearest, special_number(item[0...-1], 31), 0)
                  else
                    fail_command('invalid value')
                  end
                elsif index == 4 && item.include?('#')
                  at = item.index('#')
                  weekday = read_value(item[0...at], index)
                  occurrence = special_number(item[(at + 1)..], 5, 1)
                  Special.new(:nth_weekday, weekday % 7, occurrence)
                elsif index == 4 && item.length >= 2 && item.end_with?('L')
                  Special.new(:last_weekday, read_value(item[0...-1], index) % 7, 0)
                end
      if special
        specials << special unless specials.include?(special)
        next
      end
      slash = item.index('/')
      base = slash ? item[0...slash] : item
      if base == '*'
        first = MINIMUM[index]
        last = MAXIMUM[index]
      elsif (dash = base.index('-'))
        first = read_value(base[0...dash], index)
        last = read_value(base[(dash + 1)..], index)
        fail_command('invalid range') if first > last
      else
        first = read_value(base, index)
        last = slash ? MAXIMUM[index] : first
      end
      step = 1
      if slash
        part = item[(slash + 1)..]
        fail_command('invalid step') unless digits?(part, 1, 2) && part.to_i >= 1
        step = part.to_i
      end
      first.step(last, step) { |value| values.add(index == 4 ? value % 7 : value) }
    end
    new(index, values.to_a.sort.freeze, specials.freeze, !text.start_with?('*'))
  rescue CommandError => error
    fail_command("#{FIELD_NAMES[index]} #{error.message}")
  end
end

DayMatch = Data.define(:dom, :dow, :condition)
Cron = Data.define(:fields, :daily, :text, :expanded) do
  def or_rule? = fields[2].restricted && fields[4].restricted

  def match_day(date)
    last = month_length(date.year, date.month)
    weekday = date.weekday
    nearest = lambda do |day|
      case (date.number - date.day + day + 6) % 7
      when 6 then day == 1 ? 3 : day - 1
      when 0 then day == last ? day - 2 : day + 1
      else day
      end
    end
    dom = fields[2].include?(date.day) || fields[2].specials.any? { |special|
      case special.kind
      when :last then date.day == last
      when :last_workday then date.day == nearest.call(last)
      when :before_last then date.day == last - special.value
      when :nearest then special.value <= last && date.day == nearest.call(special.value)
      end
    }
    dow = fields[4].include?(weekday) || fields[4].specials.any? { |special|
      weekday == special.value && (special.kind == :nth_weekday ? (date.day - 1) / 7 + 1 == special.occurrence : date.day + 7 > last)
    }
    DayMatch.new(dom, dow, or_rule? ? dom || dow : dom && dow)
  end

  def scheduled?(date) = fields[3].include?(date.month) && match_day(date).condition

  def fires(low, high, holidays, reverse: false)
    return enum_for(__method__, low, high, holidays, reverse: reverse) unless block_given?
    first = low / 1440
    last = high / 1440
    days = reverse ? last.downto(first) : first.upto(last)
    times = reverse ? daily.reverse : daily
    days.each do |day|
      next if holidays.include?(day) || !scheduled?(CivilDate.from_number(day))
      times.each do |offset|
        time = day * 1440 + offset
        yield time if time.between?(low, high)
      end
    end
  end

  def description
    minute, hour, dom, month, dow = fields
    text = if daily.length <= 4
             'At ' + word_list(daily.map { |time| format('%02d:%02d', time / 60, time % 60) })
           else
             ms = minute.stepped
             hs = hour.stepped
             time = if minute.values.length == 60
                      'Every minute'
                    elsif ms > 0
                      "Every #{ms} minutes"
                    elsif minute.values.length == 1
                      "At minute #{minute.values[0]}"
                    else
                      "At minutes #{minute.value_list}"
                    end
             if hour.values.length == 24
               time += ' of every hour' if time.start_with?('At minute')
             elsif hs > 0
               time += ", every #{hs} hours"
             elsif hour.values[-1] - hour.values[0] + 1 == hour.values.length
               time += format(', between %02d:00 and %02d:59', hour.values[0], hour.values[-1])
             else
               time += ", during hours #{hour.value_list}"
             end
             time
           end
    d_full = dom.values.length == 31
    w_full = dow.values.length == 7
    if or_rule?
      text += ", on #{dom.day_phrase} or on #{dow.day_phrase}" unless d_full || w_full
    elsif !d_full && !w_full
      text += ", on #{dom.day_phrase} if it is #{dow.day_phrase(true)}"
    elsif !d_full
      text += ", on #{dom.day_phrase}"
    elsif !w_full
      text += ", on #{dow.day_phrase}"
    end
    text += ", in #{month.value_list}" unless month.values.length == 12
    text
  end

  def self.parse(input)
    text = input.join(' ')
    words = input
    if input.length == 1 && input[0].start_with?('@')
      expanded = case input[0]
                 when '@yearly', '@annually' then '0 0 1 1 *'
                 when '@monthly' then '0 0 1 * *'
                 when '@weekly' then '0 0 * * 0'
                 when '@daily', '@midnight' then '0 0 * * *'
                 when '@hourly' then '0 * * * *'
                 else fail_command('unknown macro')
                 end
      words = expanded.split(' ')
    end
    fail_command('field count') unless words.length == 5
    fields = words.each_with_index.map { |word, index| CronField.parse(word, index) }
    daily = fields[1].values.flat_map { |hour| fields[0].values.map { |minute| hour * 60 + minute } }
    new(fields.freeze, daily.freeze, text.freeze, words.join(' ').freeze)
  end
end

Job = Struct.new(:cron, :enabled, :duration, :policy)

def bit_count(value)
  count = 0
  until value == 0
    value &= value - 1
    count += 1
  end
  count
end

class Scheduler
  def initialize
    @jobs = {}
    @holidays = Set.new
  end

  def job(id) = @jobs.fetch(id) { fail_command('unknown job') }

  def new_id(id)
    fail_command('invalid id') unless id.match?(/\A[a-z][a-z0-9_]{0,15}\z/)
    fail_command('duplicate job') if @jobs.key?(id)
  end

  def enabled = @jobs.sort.select { |_, job| job.enabled }

  def timeline(window, conflicts)
    enabled = self.enabled
    masks = Array.new(window.high - window.low + 1, 0)
    enabled.each_with_index do |(_, job), i|
      job.cron.fires(window.low, window.high, @holidays).each { |time| masks[time - window.low] |= 1 << i }
    end
    counts = masks.map { |mask| bit_count(mask) }
    total = conflicts ? counts.count { |count| count >= 2 } : counts.sum
    peak = counts.max >= 2 ? counts.max : 0
    rows = [conflicts ? "CONFLICTS #{total} peak #{peak}" : "TIMELINE #{total}"]
    masks.each_with_index do |mask, i|
      break if rows.length == 101
      if conflicts
        next if counts[i] < 2
        ids = enabled.each_with_index.filter_map { |(id, _), index| id if mask & (1 << index) != 0 }
        rows << "#{datetime_text(window.low + i)} #{ids.length} #{ids.join(' ')}"
      else
        enabled.each_with_index do |(id, _), index|
          break if rows.length == 101
          rows << "#{datetime_text(window.low + i)} #{id}" if mask & (1 << index) != 0
        end
      end
    end
    rows << "... #{total - 100} more" if total > 100
    rows
  end

  def simulate(window)
    enabled = self.enabled
    events = Array.new(window.high - window.low + 1441, 0)
    rows = enabled.map do |id, job|
      started = skipped = replaced = busy = 0
      last_end = nil
      job.cron.fires(window.low, window.high, @holidays).each do |time|
        if last_end && last_end > time && job.policy == :FORBID
          skipped += 1
          next
        end
        if last_end && last_end > time && job.policy == :REPLACE
          events[last_end - window.low] += 1
          events[time - window.low] -= 1
          busy -= last_end - time
          replaced += 1
        end
        last_end = time + job.duration
        events[time - window.low] += 1
        events[last_end - window.low] -= 1
        started += 1
        busy += job.duration
      end
      "#{id} #{job.policy} started #{started} skipped #{skipped} replaced #{replaced} busy #{busy}"
    end
    running = peak = at = 0
    events.each_with_index do |change, i|
      running += change
      if running > peak
        peak = running
        at = window.low + i
      end
    end
    rows.unshift("SIMULATE #{enabled.length} peak #{peak}" + (peak == 0 ? '' : " at #{datetime_text(at)}"))
  end

  def execute(words)
    command = words[0]
    expected = case command
               when 'JOB' then -3
               when 'VALIDATE' then -2
               when 'LIST', 'HOLIDAYS' then 1
               when 'REMOVE', 'ENABLE', 'DISABLE', 'DESCRIBE', 'WEEK', 'EXCLUDE', 'INCLUDE' then 2
               when 'RENAME', 'EXPAND', 'CALENDAR' then 3
               when 'RUNTIME', 'MATCH', 'GAP' then 4
               when 'NEXT', 'PREV', 'TIMELINE', 'CONFLICTS', 'SIMULATE' then 5
               when 'COUNT' then 6
               when 'OVERLAP' then 7
               else fail_command('unknown command')
               end
    wrong_count = expected < 0 ? words.length < -expected : words.length != expected
    fail_command('wrong arguments') if wrong_count
    case command
    when 'JOB'
      new_id(words[1])
      cron = Cron.parse(words[2..])
      @jobs[words[1]] = Job.new(cron, true, 1, :ALLOW)
      ["JOB #{words[1]} added"]
    when 'VALIDATE'
      cron = Cron.parse(words[1..])
      ["VALID #{cron.expanded} #{cron.or_rule? ? 'OR' : 'AND'} #{cron.daily.length}"]
    when 'REMOVE'
      job(words[1])
      @jobs.delete(words[1])
      ["REMOVE #{words[1]}"]
    when 'RENAME'
      old = job(words[1])
      new_id(words[2])
      @jobs.delete(words[1])
      @jobs[words[2]] = old
      ["RENAME #{words[1]} #{words[2]}"]
    when 'ENABLE', 'DISABLE'
      current = job(words[1])
      desired = command == 'ENABLE'
      fail_command(desired ? 'already enabled' : 'already disabled') if current.enabled == desired
      current.enabled = desired
      ["#{command} #{words[1]}"]
    when 'RUNTIME'
      current = job(words[1])
      duration = positive(words[2], 4, 1440, 'invalid duration')
      fail_command('invalid policy') unless %w[ALLOW FORBID REPLACE].include?(words[3])
      current.duration = duration
      current.policy = words[3].to_sym
      ["RUNTIME #{words[1]} #{duration} #{current.policy}"]
    when 'LIST'
      ["LIST #{@jobs.length}"] + @jobs.sort.map { |id, current| "#{id} #{current.enabled ? 'on' : 'off'} #{current.duration} #{current.policy} #{current.cron.text}" }
    when 'EXPAND'
      current = job(words[1])
      index = FIELD_NAMES.index(words[2])
      fail_command('invalid field') unless index
      field = current.cron.fields[index]
      [["EXPAND #{words[1]} #{words[2]} #{field.values.length}", *field.values, *field.specials].join(' ')]
    when 'DESCRIBE'
      current = job(words[1])
      ["DESCRIBE #{words[1]} #{current.cron.description}"]
    when 'MATCH'
      current = job(words[1])
      time = read_datetime(words, 2)
      date = CivilDate.from_number(time / 1440)
      match = current.cron.match_day(date)
      reasons = []
      reasons << 'minute' unless current.cron.fields[0].include?(time % 60)
      reasons << 'hour' unless current.cron.fields[1].include?(time % 1440 / 60)
      reasons << 'day-of-month' if !match.condition && !match.dom
      reasons << 'month' unless current.cron.fields[3].include?(date.month)
      reasons << 'day-of-week' if !match.condition && !match.dow
      reasons << 'excluded' if @holidays.include?(time / 1440)
      ["MATCH #{words[1]} #{datetime_text(time)} " + (reasons.empty? ? 'yes' : "no #{reasons.join(' ')}")]
    when 'NEXT', 'PREV'
      current = job(words[1])
      base = read_datetime(words, 2)
      limit = positive(words[4], 2, 50, 'invalid count')
      reverse = command == 'PREV'
      times = current.cron.fires(reverse ? base - 527_040 : base + 1, reverse ? base - 1 : base + 527_040, @holidays, reverse: reverse).take(limit)
      rows = ["#{command} #{words[1]} #{times.length}"] + times.map { |time| "#{datetime_text(time)} #{reverse ? '-' : '+'}#{span((time - base).abs)}" }
      rows << 'NONE' if times.length < limit
      rows
    when 'COUNT'
      current = job(words[1])
      window = read_window(words, 2)
      times = current.cron.fires(window.low, window.high, @holidays).to_a
      ["COUNT #{words[1]} runs #{times.length} days #{times.map { |time| time / 1440 }.uniq.length}"]
    when 'GAP'
      current = job(words[1])
      base = read_datetime(words, 2)
      times = current.cron.fires(base, base + 44_640, @holidays).to_a
      return ["GAP #{words[1]} runs #{times.length} none"] if times.length < 2
      histogram = Hash.new(0)
      longest = first = 0
      times.each_cons(2).with_index do |(a, b), i|
        gap = b - a
        histogram[gap] += 1
        if gap > longest
          longest = gap
          first = i
        end
      end
      ["GAP #{words[1]} runs #{times.length} shortest #{span(histogram.keys.min)} longest #{span(longest)} from #{datetime_text(times[first])} to #{datetime_text(times[first + 1])}"] + histogram.sort.map { |gap, count| "#{span(gap)} #{count}" }
    when 'OVERLAP'
      a = job(words[1])
      b = job(words[2])
      window = read_window(words, 3)
      other = b.cron.fires(window.low, window.high, @holidays).to_set
      times = a.cron.fires(window.low, window.high, @holidays).select { |time| other.include?(time) }
      ["OVERLAP #{words[1]} #{words[2]} #{times.length}" + (times.empty? ? '' : " first #{datetime_text(times[0])} last #{datetime_text(times[-1])}")]
    when 'TIMELINE', 'CONFLICTS', 'SIMULATE'
      window = read_window(words, 1)
      command == 'SIMULATE' ? simulate(window) : timeline(window, command == 'CONFLICTS')
    when 'WEEK'
      first = read_date(words[1]).number
      counts = Array.new(7) { Array.new(24, 0) }
      enabled.each do |_, current|
        current.cron.fires(first * 1440, (first + 7) * 1440 - 1, @holidays).each { |time| counts[time / 1440 - first][time % 1440 / 60] += 1 }
      end
      rows = counts.each_with_index.map do |hours, day|
        heat = hours.map { |count| count == 0 ? '.' : count >= 10 ? '+' : count.to_s }.join
        "#{CivilDate.from_number(first + day)} #{heat} #{hours.sum}"
      end
      ["WEEK #{words[1]} #{counts.sum(&:sum)}"] + rows
    when 'CALENDAR'
      current = job(words[1])
      first = read_month(words[2])
      cells = Array.new(first.weekday, '...')
      days = 0
      1.upto(month_length(first.year, first.month)) do |day|
        date = first.with(day: day)
        mark = !current.cron.scheduled?(date) ? '-' : @holidays.include?(date.number) ? 'x' : '*'
        days += 1 if mark == '*'
        cells << format('%02d%s', day, mark)
      end
      cells << '...' until cells.length % 7 == 0
      ["CALENDAR #{words[1]} #{words[2]} days #{days} runs #{days * current.cron.daily.length}", 'Sun Mon Tue Wed Thu Fri Sat'] + cells.each_slice(7).map { |week| week.join(' ') }
    when 'EXCLUDE', 'INCLUDE'
      date = read_date(words[1])
      if command == 'EXCLUDE'
        fail_command('already excluded') unless @holidays.add?(date.number)
      else
        fail_command('not excluded') unless @holidays.delete?(date.number)
      end
      ["#{command} #{date} holidays #{@holidays.length}"]
    when 'HOLIDAYS'
      ["HOLIDAYS #{@holidays.length}"] + @holidays.sort.map { |day| CivilDate.from_number(day).to_s }
    end
  end
end

first = $stdin.gets
exit unless first
scheduler = Scheduler.new
first.to_i.times do
  words = $stdin.gets.chomp.split(' ')
  begin
    $stdout.write(scheduler.execute(words).join("\n") + "\n")
  rescue CommandError => error
    $stdout.write("ERROR #{error.message}\n")
  end
end
