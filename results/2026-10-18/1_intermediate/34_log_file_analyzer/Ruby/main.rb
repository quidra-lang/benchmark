require 'set'

METHODS = %w[GET HEAD POST PUT DELETE PATCH OPTIONS].freeze
REASONS = %w[fields date time ip method path status bytes latency].freeze
MONTH_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31].freeze
STATUS_CLASSES = %w[1xx 2xx 3xx 4xx 5xx].freeze
FILTER_KEYS = %w[METHOD STATUS IP PATH].freeze
TOP_KINDS = %w[PATHS IPS].freeze
NUMBER_RANGES = {
  'limit' => [1, 100], 'minutes' => [1, 1440], 'width' => [1, 100_000],
  'threshold' => [1, 100_000], 'length' => [1, 86_400], 'times' => [1, 1000]
}.freeze
ARGUMENT_ERRORS = {
  'limit' => 'invalid number', 'minutes' => 'invalid number',
  'width' => 'invalid number', 'threshold' => 'invalid number',
  'length' => 'invalid number', 'times' => 'invalid number',
  'kind' => 'invalid kind', 'path' => 'invalid path', 'ip' => 'invalid ip',
  'date' => 'invalid timestamp', 'time' => 'invalid timestamp',
  'key' => 'invalid key', 'subject' => 'invalid key', 'value' => 'invalid value'
}.freeze
QUERY_FORMS = {
  'SUMMARY' => [], 'MALFORMED' => [], 'STATUS' => [], 'METHODS' => [],
  'TOP' => %w[kind limit], 'HOURLY' => [], 'TIMELINE' => %w[minutes],
  'BANDWIDTH' => [], 'VISITORS' => [], 'LATENCY' => %w[path],
  'HISTOGRAM' => %w[width], 'APDEX' => %w[threshold], 'ERRORS' => [],
  'SLOWEST' => %w[limit], 'SESSIONS' => %w[ip minutes],
  'BURST' => %w[length times], 'PEAK' => %w[length], 'GAPS' => %w[length],
  'IP' => %w[ip], 'RANGE' => %w[date time date time],
  'FILTER' => %w[key value], 'UNFILTER' => %w[subject],
  'RESET' => [], 'STATE' => []
}.freeze
OPTIONAL_LAST = %w[LATENCY SESSIONS].freeze
NEEDS_TARGETS = %w[
  STATUS METHODS TOP HOURLY TIMELINE BANDWIDTH VISITORS HISTOGRAM APDEX
  ERRORS SLOWEST BURST PEAK GAPS
].freeze
RATINGS = [[Rational(94, 100), 'excellent'], [Rational(85, 100), 'good'],
           [Rational(70, 100), 'fair'], [Rational(50, 100), 'poor']].freeze
BYTE_UNITS = [[1_073_741_824, 'GB'], [1_048_576, 'MB'], [1024, 'KB']].freeze
DEFAULT_TIMEOUT = 30
BAR_WIDTH = 30
MAX_BUCKETS = 60
PATH_LINES = 3

class QueryError < StandardError; end

def digits?(text)
  /\A[0-9]+\z/.match?(text)
end

def canonical?(text, maximum)
  digits?(text) && text.length <= maximum && (text.length == 1 || text[0] != '0')
end

def leap_year?(year)
  (year % 4).zero? && (!(year % 100).zero? || (year % 400).zero?)
end

def year_days(year)
  leap_year?(year) ? 366 : 365
end

def month_days(year, month)
  month == 2 && leap_year?(year) ? 29 : MONTH_DAYS[month - 1]
end

def valid_date?(text)
  return false unless /\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/.match?(text)
  year, month, day = text.split('-').map(&:to_i)
  year.between?(2000, 2059) && month.between?(1, 12) &&
    day.between?(1, month_days(year, month))
end

def valid_time?(text)
  return false unless /\A[0-9]{2}:[0-9]{2}:[0-9]{2}\z/.match?(text)
  hour, minute, second = text.split(':').map(&:to_i)
  hour <= 23 && minute <= 59 && second <= 59
end

def valid_ip?(text)
  parts = text.split('.', -1)
  parts.length == 4 && parts.all? { |part| canonical?(part, 3) && part.to_i <= 255 }
end

def valid_status?(text)
  text.length == 3 && digits?(text) && text.to_i.between?(100, 599)
end

def valid_filter_value?(key, value)
  case key
  when 'METHOD' then METHODS.include?(value)
  when 'STATUS' then STATUS_CLASSES.include?(value) || valid_status?(value)
  when 'IP' then valid_ip?(value)
  else value.start_with?('/')
  end
end

def valid_argument?(kind, value, args)
  if NUMBER_RANGES.key?(kind)
    low, high = NUMBER_RANGES.fetch(kind)
    return canonical?(value, 6) && value.to_i.between?(low, high)
  end
  case kind
  when 'kind' then TOP_KINDS.include?(value)
  when 'path' then value.start_with?('/')
  when 'ip' then valid_ip?(value)
  when 'date' then valid_date?(value)
  when 'time' then valid_time?(value)
  when 'key' then FILTER_KEYS.include?(value)
  when 'subject' then FILTER_KEYS.include?(value) || value == 'RANGE'
  else valid_filter_value?(args[0], value)
  end
end

def malformed_reason(fields)
  return 'fields' unless fields.length == 8
  date, clock, ip, method, path, status, bytes, latency = fields
  return 'date' unless valid_date?(date)
  return 'time' unless valid_time?(clock)
  return 'ip' unless valid_ip?(ip)
  return 'method' unless METHODS.include?(method)
  return 'path' unless path.start_with?('/')
  return 'status' unless valid_status?(status)
  return 'bytes' unless canonical?(bytes, 8)
  return 'latency' unless canonical?(latency, 6)
  nil
end

def day_number(year, month, day)
  days = day - 1
  (2000...year).each { |y| days += year_days(y) }
  (1...month).each { |m| days += month_days(year, m) }
  days
end

def seconds_of(date, clock)
  year, month, day = date.split('-').map(&:to_i)
  hour, minute, second = clock.split(':').map(&:to_i)
  day_number(year, month, day) * 86_400 + hour * 3600 + minute * 60 + second
end

def interval_label(seconds)
  days, rest = seconds.divmod(86_400)
  year = 2000
  while days >= year_days(year)
    days -= year_days(year)
    year += 1
  end
  month = 1
  while days >= month_days(year, month)
    days -= month_days(year, month)
    month += 1
  end
  format('%d-%02d-%02d %02d:%02d', year, month, days + 1, rest / 3600, rest % 3600 / 60)
end

def normalize_path(text)
  parts = []
  text.split('?', 2)[0].split('/').each do |part|
    case part
    when '..' then parts.pop
    when '', '.' then next
    else parts << part
    end
  end
  '/' + parts.map do |part|
    if digits?(part)
      '{id}'
    elsif part.length >= 8 && /\A[0-9a-f]+\z/.match?(part) && /[0-9]/.match?(part)
      '{hex}'
    else
      part
    end
  end.join('/')
end

def ip_order(ip)
  ip.split('.').map(&:to_i)
end

def status_matches?(value, status)
  STATUS_CLASSES.include?(value) ? status / 100 == value[0].to_i : status == value.to_i
end

def decimal(numerator, denominator, places)
  scale = 10**places
  whole, fraction = ((numerator * scale) / denominator).divmod(scale)
  "#{whole}.#{fraction.to_s.rjust(places, '0')}"
end

def percentage(part, whole)
  decimal(part * 100, whole, 2) + '%'
end

def bar(count, maximum)
  '#' * ((count * BAR_WIDTH + maximum - 1) / maximum)
end

def byte_notation(size)
  BYTE_UNITS.each do |unit, suffix|
    return decimal(size, unit, 1) + suffix if size >= unit
  end
  "#{size}B"
end

def group_by(records)
  records.group_by { |record| yield record }
end

def by_count(counts)
  counts.keys.sort_by { |key| [-counts[key], block_given? ? yield(key) : key] }
end

def class_counts(records)
  counts = Array.new(5, 0)
  records.each { |record| counts[record.status / 100 - 1] += 1 }
  counts
end

def bucket_counts(numbers)
  first, last = numbers.minmax
  raise QueryError, 'too many buckets' if last - first + 1 > MAX_BUCKETS
  counts = Array.new(last - first + 1, 0)
  numbers.each { |number| counts[number - first] += 1 }
  [first, counts]
end

def percentile(values, rank)
  values[(rank * values.length + 99) / 100 - 1]
end

class Record
  attr_reader :line_number, :date, :hour, :timestamp, :seconds, :ip, :method, :path,
              :status, :size, :latency

  def initialize(line_number, fields)
    date, clock, @ip, @method, path, status, size, latency = fields
    @line_number = line_number
    @date = date
    @hour = clock[0, 2].to_i
    @timestamp = "#{date} #{clock}"
    @seconds = seconds_of(date, clock)
    @path = normalize_path(path)
    @status, @size, @latency = status.to_i, size.to_i, latency.to_i
  end

  def order
    [@seconds, @line_number]
  end

  def error?
    @status >= 400
  end
end

class TimeRange
  attr_reader :start, :end, :start_seconds, :end_seconds

  def initialize(start_date, start_time, end_date, end_time)
    @start = "#{start_date} #{start_time}"
    @end = "#{end_date} #{end_time}"
    @start_seconds = seconds_of(start_date, start_time)
    @end_seconds = seconds_of(end_date, end_time)
  end

  def contains?(seconds)
    seconds.between?(@start_seconds, @end_seconds)
  end
end

class Filters
  attr_accessor :range
  attr_reader :conditions

  def initialize
    @range = nil
    @conditions = FILTER_KEYS.to_h { |key| [key, nil] }
  end

  def accepts?(record)
    return false if @range && !@range.contains?(record.seconds)
    return false if @conditions['METHOD'] && record.method != @conditions['METHOD']
    return false if @conditions['STATUS'] && !status_matches?(@conditions['STATUS'], record.status)
    return false if @conditions['IP'] && record.ip != @conditions['IP']
    @conditions['PATH'].nil? || record.path == @conditions['PATH']
  end
end

class Window
  attr_reader :size, :start, :end

  def initialize(records, length)
    @size, @start, @end = 0, nil, nil
    first = 0
    records.each_with_index do |record, last|
      first += 1 while record.seconds - records[first].seconds >= length
      next unless last - first + 1 > @size
      @size = last - first + 1
      @start, @end = records[first], record
    end
  end
end

class ApdexScore
  attr_reader :count, :satisfied, :tolerating, :frustrated, :score

  def initialize(records, threshold)
    @count = records.length
    @satisfied = records.count { |r| r.status < 500 && r.latency <= threshold }
    @tolerating = records.count { |r| r.status < 500 && r.latency > threshold && r.latency <= 4 * threshold }
    @frustrated = @count - @satisfied - @tolerating
    @points = 2 * @satisfied + @tolerating
    @score = Rational(@points, 2 * @count)
  end

  def notation
    decimal(@points, 2 * @count, 3)
  end

  def rating
    RATINGS.each { |minimum, name| return name if @score >= minimum }
    'unacceptable'
  end
end

class PathErrors
  attr_reader :path, :count, :client, :server, :failed

  def initialize(path, records)
    @path = path
    @count = records.length
    @client = records.count { |r| r.status / 100 == 4 }
    @server = records.count { |r| r.status / 100 == 5 }
    @failed = @client + @server
  end

  def order
    [-Rational(@failed, @count), -@failed, @path]
  end
end

class Endpoint
  attr_reader :method, :path, :count, :total, :maximum

  def initialize(method, path, records)
    @method, @path = method, path
    @count = records.length
    @total = records.sum(&:latency)
    @maximum = records.map(&:latency).max
  end

  def order
    [-Rational(@total, @count), -@maximum, @path, @method]
  end
end

class LogAnalyzer
  attr_reader :output

  def initialize(log_lines)
    @line_count = log_lines.length
    @records = []
    @malformed = []
    log_lines.each_with_index do |line, index|
      fields = line.split
      reason = malformed_reason(fields)
      if reason.nil?
        @records << Record.new(index + 1, fields)
      else
        @malformed << [index + 1, reason]
      end
    end
    @records.sort_by!(&:order)
    @filters = Filters.new
    @output = []
    @handlers = {
      'SUMMARY' => :summary, 'MALFORMED' => :malformed_lines, 'STATUS' => :status_breakdown,
      'METHODS' => :method_breakdown, 'TOP' => :top, 'HOURLY' => :hourly,
      'TIMELINE' => :timeline, 'BANDWIDTH' => :bandwidth, 'VISITORS' => :visitors,
      'LATENCY' => :latency, 'HISTOGRAM' => :histogram, 'APDEX' => :apdex,
      'ERRORS' => :errors, 'SLOWEST' => :slowest, 'SESSIONS' => :sessions,
      'BURST' => :burst, 'PEAK' => :peak, 'GAPS' => :gaps, 'IP' => :ip_details,
      'RANGE' => :set_range, 'FILTER' => :add_filter, 'UNFILTER' => :remove_filter,
      'RESET' => :reset, 'STATE' => :state
    }
  end

  def emit(*parts)
    @output << parts.join(' ')
  end

  def bar_line(label, count, maximum)
    if count.zero?
      emit(label, count)
    else
      emit(label, count, bar(count, maximum))
    end
  end

  def targets
    @records.select { |record| @filters.accepts?(record) }
  end

  def summary(_arguments, records)
    emit('SUMMARY', 'lines', @line_count, 'valid', @records.length,
         'malformed', @malformed.length)
    emit('requests', records.length, 'bytes', records.sum(&:size),
         'ips', records.map(&:ip).uniq.length, 'paths', records.map(&:path).uniq.length)
    if records.empty?
      emit('span', 'none')
    else
      first, last = records.first, records.last
      emit('span', first.timestamp, last.timestamp, last.seconds - first.seconds)
    end
  end

  def malformed_lines(_arguments, _records)
    emit('MALFORMED', @malformed.length)
    REASONS.each do |reason|
      numbers = @malformed.filter_map { |number, cause| number if cause == reason }
      emit(reason, numbers.length, *numbers) unless numbers.empty?
    end
  end

  def status_breakdown(_arguments, records)
    total = records.length
    emit('STATUS', total)
    STATUS_CLASSES.zip(class_counts(records)).each do |label, amount|
      emit(label, amount, percentage(amount, total))
    end
    counts = records.map(&:status).tally
    counts.keys.sort.each do |status|
      emit(status, counts[status], percentage(counts[status], total))
    end
  end

  def method_breakdown(_arguments, records)
    counts = records.map(&:method).tally
    emit('METHODS', records.length)
    by_count(counts).each do |method|
      emit(method, counts[method], percentage(counts[method], records.length))
    end
  end

  def top(arguments, records)
    kind, limit = arguments[0], arguments[1].to_i
    counts = records.map { |r| kind == 'PATHS' ? r.path : r.ip }.tally
    keys = kind == 'PATHS' ? by_count(counts) : by_count(counts) { |ip| ip_order(ip) }
    shown = [limit, keys.length].min
    emit('TOP', kind, shown, 'of', keys.length)
    rank = 0
    keys.take(shown).each_with_index do |key, index|
      rank = index + 1 if index.zero? || counts[key] != counts[keys[index - 1]]
      emit(rank, key, counts[key], percentage(counts[key], records.length))
    end
  end

  def hourly(_arguments, records)
    counts = Array.new(24, 0)
    records.each { |r| counts[r.hour] += 1 }
    maximum = counts.max
    peak_hour = counts.index(maximum)
    emit('HOURLY', records.length, 'peak', format('%02d', peak_hour), maximum)
    counts.each_with_index do |amount, hour|
      bar_line(format('%02d', hour), amount, maximum)
    end
  end

  def timeline(arguments, records)
    minutes = arguments[0].to_i
    width = minutes * 60
    first, counts = bucket_counts(records.map { |r| r.seconds / width })
    emit('TIMELINE', minutes, counts.length)
    maximum = counts.max
    counts.each_with_index do |amount, offset|
      bar_line(interval_label((first + offset) * width), amount, maximum)
    end
  end

  def bandwidth(_arguments, records)
    days = records.group_by(&:date)
    size = records.sum(&:size)
    emit('BANDWIDTH', days.length, size, byte_notation(size))
    days.keys.sort.each do |date|
      volume = days[date].sum(&:size)
      emit(date, days[date].length, volume, byte_notation(volume))
    end
  end

  def visitors(_arguments, records)
    first_days = {}
    records.each do |r|
      first_days[r.ip] = r.date if !first_days.key?(r.ip) || r.date < first_days[r.ip]
    end
    days = records.group_by(&:date)
    emit('VISITORS', days.length, first_days.length)
    days.keys.sort.each do |date|
      ips = days[date].map(&:ip).uniq
      first = ips.count { |ip| first_days[ip] == date }
      emit(date, 'unique', ips.length, 'new', first, 'returning', ips.length - first)
    end
  end

  def latency(arguments, records)
    if arguments.empty?
      name = 'all'
      selected = records
    else
      name = normalize_path(arguments[0])
      selected = records.select { |r| r.path == name }
    end
    if selected.empty?
      emit('LATENCY', 'no records')
      return
    end
    values = selected.map(&:latency).sort
    count = values.length
    trim = count / 10
    trimmed = values[trim, count - 2 * trim]
    emit('LATENCY', name, 'count', count, 'min', values.first,
         'p50', percentile(values, 50), 'p90', percentile(values, 90),
         'p99', percentile(values, 99), 'max', values.last,
         'mean', decimal(values.sum, count, 2),
         'trimmed', decimal(trimmed.sum, trimmed.length, 2))
  end

  def histogram(arguments, records)
    width = arguments[0].to_i
    first, counts = bucket_counts(records.map { |r| r.latency / width })
    emit('HISTOGRAM', width, counts.length)
    maximum = counts.max
    counts.each_with_index do |amount, index|
      low = (first + index) * width
      bar_line("#{low}-#{low + width - 1}", amount, maximum)
    end
  end

  def apdex(arguments, records)
    threshold = arguments[0].to_i
    overall = ApdexScore.new(records, threshold)
    emit('APDEX', threshold, overall.notation, overall.rating,
         'satisfied', overall.satisfied, 'tolerating', overall.tolerating,
         'frustrated', overall.frustrated)
    scores = records.group_by(&:path).map { |path, items| [path, ApdexScore.new(items, threshold)] }
    scores.sort_by! { |path, score| [score.score, -score.count, path] }
    scores.each do |path, score|
      emit(path, score.notation, score.rating, score.count)
    end
  end

  def errors(_arguments, records)
    failed = records.count(&:error?)
    emit('ERRORS', failed, 'of', records.length, percentage(failed, records.length))
    rows = records.group_by(&:path).map { |path, items| PathErrors.new(path, items) }
    rows.select! { |r| r.failed > 0 }
    rows.sort_by!(&:order)
    rows.each { |r| emit(r.path, r.count, r.client, r.server, percentage(r.failed, r.count)) }
  end

  def slowest(arguments, records)
    limit = arguments[0].to_i
    groups = records.group_by { |r| [r.method, r.path] }
    endpoints = groups.map { |(method, path), items| Endpoint.new(method, path, items) }
    endpoints.sort_by!(&:order)
    shown = [limit, endpoints.length].min
    emit('SLOWEST', shown, 'of', endpoints.length)
    endpoints.take(shown).each_with_index do |endpoint, index|
      emit(index + 1, endpoint.method, endpoint.path,
           'count', endpoint.count, 'avg', decimal(endpoint.total, endpoint.count, 2),
           'max', endpoint.maximum)
    end
  end

  def sessions(arguments, records)
    ip = arguments[0]
    minutes = arguments.length == 2 ? arguments[1].to_i : DEFAULT_TIMEOUT
    selected = records.select { |r| r.ip == ip }
    if selected.empty?
      emit('SESSIONS', 'no records')
      return
    end
    sessions = [[selected[0]]]
    selected.each_cons(2) do |previous, current|
      if current.seconds - previous.seconds <= minutes * 60
        sessions[-1] << current
      else
        sessions << [current]
      end
    end
    durations = sessions.sum { |s| s.last.seconds - s.first.seconds }
    emit('SESSIONS', ip, 'timeout', minutes, 'count', sessions.length,
         'requests', selected.length, 'avg_duration', decimal(durations, sessions.length, 1),
         'avg_requests', decimal(selected.length, sessions.length, 1))
    sessions.each_with_index do |session, index|
      first, last = session.first, session.last
      emit(index + 1, first.timestamp, last.timestamp, last.seconds - first.seconds,
           session.length, session.map(&:path).uniq.length)
    end
  end

  def burst(arguments, records)
    length, times = arguments.map(&:to_i)
    failures = records.select(&:error?)
    matches = failures.group_by(&:ip).filter_map do |ip, group|
      window = Window.new(group, length)
      [ip, window] if window.size >= times
    end
    matches.sort_by! { |ip, window| [-window.size, ip_order(ip)] }
    emit('BURST', length, times, matches.length)
    matches.each do |ip, window|
      emit(ip, window.size, window.start.timestamp, window.end.timestamp)
    end
  end

  def peak(arguments, records)
    length = arguments[0].to_i
    window = Window.new(records, length)
    emit('PEAK', length, window.size, window.start.timestamp, window.end.timestamp)
  end

  def gaps(arguments, records)
    length = arguments[0].to_i
    gaps = records.each_cons(2).select { |a, b| b.seconds - a.seconds >= length }
    emit('GAPS', length, gaps.length)
    gaps.each { |a, b| emit(a.timestamp, b.timestamp, b.seconds - a.seconds) }
  end

  def ip_details(arguments, records)
    ip = arguments[0]
    selected = records.select { |r| r.ip == ip }
    if selected.empty?
      emit('IP', 'no records')
      return
    end
    paths = selected.map(&:path).tally
    emit('IP', ip, 'requests', selected.length, 'bytes', selected.sum(&:size),
         'errors', selected.count(&:error?), 'paths', paths.length)
    emit('first', selected.first.timestamp, 'last', selected.last.timestamp)
    methods = selected.map(&:method).tally
    parts = ['methods']
    by_count(methods).each { |method| parts.concat([method, methods[method]]) }
    emit(*parts)
    parts = ['classes']
    STATUS_CLASSES.zip(class_counts(selected)).each { |label, amount| parts.concat([label, amount]) }
    emit(*parts)
    by_count(paths).take(PATH_LINES).each { |path| emit('path', path, paths[path]) }
  end

  def set_range(arguments, _records)
    range = TimeRange.new(*arguments)
    raise QueryError, 'invalid range' if range.start_seconds > range.end_seconds
    @filters.range = range
    emit('RANGE', range.start, range.end, 'active', targets.length)
  end

  def add_filter(arguments, _records)
    key, value = arguments
    value = normalize_path(value) if key == 'PATH'
    @filters.conditions[key] = value
    emit('FILTER', key, value, 'active', targets.length)
  end

  def remove_filter(arguments, _records)
    key = arguments[0]
    if key == 'RANGE'
      raise QueryError, 'not filtered' if @filters.range.nil?
      @filters.range = nil
    else
      raise QueryError, 'not filtered' if @filters.conditions[key].nil?
      @filters.conditions[key] = nil
    end
    emit('UNFILTER', key, 'active', targets.length)
  end

  def reset(_arguments, _records)
    @filters = Filters.new
    emit('RESET', 'active', targets.length)
  end

  def state(_arguments, records)
    range = @filters.range
    range_text = range.nil? ? '-' : "#{range.start} #{range.end}"
    parts = ['STATE', 'active', records.length, 'range', range_text]
    FILTER_KEYS.each do |key|
      value = @filters.conditions[key]
      parts.concat([key.downcase, value.nil? ? '-' : value])
    end
    emit(*parts)
  end

  def execute(line)
    name, *args = line.split
    begin
      form = QUERY_FORMS[name]
      raise QueryError, 'unknown query' if form.nil?
      optional = OPTIONAL_LAST.include?(name) && args.length == form.length - 1
      raise QueryError, 'wrong arguments' if args.length != form.length && !optional
      form.zip(args).each do |kind, value|
        next if value.nil?
        raise QueryError, ARGUMENT_ERRORS[kind] unless valid_argument?(kind, value, args)
      end
      records = targets
      if NEEDS_TARGETS.include?(name) && records.empty?
        emit(name, 'no records')
      else
        send(@handlers.fetch(name), args, records)
      end
    rescue QueryError => e
      emit('ERROR', e.message)
    end
  end
end

lines = STDIN.each_line.map(&:chomp)
separator = lines.index('---')
finish = separator + 1 + lines[(separator + 1)..].index('END')
analyzer = LogAnalyzer.new(lines[0...separator])
lines[(separator + 1)...finish].each { |line| analyzer.execute(line) }
puts analyzer.output
