require 'set'

WRONG_TYPE = 'WRONGTYPE Operation against a key holding the wrong kind of value'
NOT_INTEGER = 'ERR value is not an integer or out of range'
POSITIVE = 'ERR value is out of range, must be positive'
class CommandError < StandardError; end

TextValue = Data.define(:text) do
  def initialize(text:) = super(text: text.dup.freeze)
  def kind = :string
  def empty? = false
end
ListValue = Data.define(:items) do
  def initialize(items:) = super(items: items.map { |item| item.dup.freeze }.freeze)
  def kind = :list
  def empty? = items.empty?
end
HashValue = Data.define(:fields) do
  def initialize(fields:)
    super(fields: fields.to_h { |field, value| [field.dup.freeze, value.dup.freeze] }.freeze)
  end
  def kind = :hash
  def empty? = fields.empty?
end
SetValue = Data.define(:members) do
  def initialize(members:) = super(members: Set.new(members.map { |member| member.dup.freeze }).freeze)
  def kind = :set
  def empty? = members.empty?
end
SortedSetValue = Data.define(:scores) do
  def initialize(scores:) = super(scores: scores.to_h { |member, score| [member.dup.freeze, score] }.freeze)
  def kind = :zset
  def empty? = scores.empty?
end
Entry = Data.define(:value, :expiry)

def quoted(text)
  text.nil? ? '(nil)' : '"' + text.gsub(/["\\]/) { |c| '\\' + c } + '"'
end
def integer_reply(value) = "(integer) #{value}"
def array_reply(values)
  return '(empty array)' if values.empty?
  width = values.length.to_s.length
  values.each_with_index.map { |value, i| "#{(i + 1).to_s.rjust(width)}) #{quoted(value)}" }.join("\n")
end

def split_line(line)
  words = []
  position = 0
  while position < line.length
    if line[position] == ' '
      position += 1
      next
    end
    if line[position] != '"'
      start = position
      position += 1 while position < line.length && line[position] != ' '
      words << line[start...position].freeze
      next
    end
    position += 1
    word = +''
    while position < line.length && line[position] != '"'
      character = line[position]
      position += 1
      if character == '\\'
        return nil if position == line.length
        character = line[position]
        position += 1
        return nil unless character == '\\' || character == '"'
      end
      word << character
    end
    return nil if position == line.length
    position += 1
    return nil if position < line.length && line[position] != ' '
    words << word.freeze
  end
  words
end

def parse_integer(text)
  text.match?(/\A(?:0|-?[1-9][0-9]{0,8})\z/) ? text.to_i(10) : nil
end
def number(text, message = NOT_INTEGER)
  parse_integer(text) || raise(CommandError, message)
end
def increment(old, delta)
  value = old + delta
  raise CommandError, 'ERR increment or decrement would overflow' unless (-999_999_999..999_999_999).cover?(value)
  value
end
def normalized_range(length, start, stop)
  start += length if start.negative?
  stop += length if stop.negative?
  start = [0, start].max
  stop = [length - 1, stop].min
  start <= stop ? (start..stop) : (0...0)
end

ScoreBound = Data.define(:value, :exclusive) do
  def accepts?(score, lower)
    return lower if value == :negative_infinity
    return !lower if value == :positive_infinity
    (lower ? score > value : score < value) || (!exclusive && score == value)
  end
end
def score_bound(text)
  return ScoreBound.new(:negative_infinity, false) if text == '-inf'
  return ScoreBound.new(:positive_infinity, false) if text == '+inf'
  exclusive = text.start_with?('(')
  value = number(exclusive ? text[1..] : text, 'ERR min or max is not a float')
  ScoreBound.new(value, exclusive)
end

PatternPart = Data.define(:kind, :value, :negated) do
  def accepts?(character)
    case kind
    when :any then true
    when :literal then value == character
    else value.include?(character.ord) != negated
    end
  end
end
def parse_pattern(text)
  parts = []
  i = 0
  while i < text.length
    case (character = text[i])
    when '\\'
      i += 1
      raise CommandError, 'ERR invalid pattern' if i == text.length
      parts << PatternPart.new(:literal, text[i], false)
    when '['
      finish = text.index(']', i + 1)
      raise CommandError, 'ERR invalid pattern' unless finish
      i += 1
      negated = i < finish && text[i] == '^'
      i += 1 if negated
      raise CommandError, 'ERR invalid pattern' if i == finish
      characters = Set.new
      while i < finish
        first = text[i].ord
        if i + 2 < finish && text[i + 1] == '-'
          last = text[i + 2].ord
          ([first, last].min..[first, last].max).each { |code| characters.add(code) }
          i += 3
        else
          characters.add(first)
          i += 1
        end
      end
      parts << PatternPart.new(:class, characters, negated)
    when '*' then parts << PatternPart.new(:star, nil, false)
    when '?' then parts << PatternPart.new(:any, nil, false)
    else parts << PatternPart.new(:literal, character, false)
    end
    i += 1
  end
  parts
end
def matches_pattern?(parts, text)
  previous = Array.new(text.length + 1, false)
  previous[0] = true
  parts.each do |part|
    current = Array.new(previous.length, false)
    if part.kind == :star
      current[0] = previous[0]
      (1...current.length).each { |i| current[i] = previous[i] || current[i - 1] }
    else
      text.each_char.with_index { |character, i| current[i + 1] = previous[i] && part.accepts?(character) }
    end
    previous = current
  end
  previous[text.length]
end

CommandSpec = Data.define(:group, :minimum, :maximum, :parity) do
  def accepts?(count)
    count >= minimum && (maximum.nil? || count <= maximum) && (parity.nil? || count % 2 == parity)
  end
end
COMMANDS = {}.tap do |commands|
  register = lambda do |group, names, minimum, maximum = minimum, parity = nil|
    names.split.each { |name| commands[name] = CommandSpec.new(group, minimum, maximum, parity) }
  end
  register.call(:text_command, 'SET', 2, nil)
  register.call(:text_command, 'GET INCR DECR STRLEN', 1)
  register.call(:text_command, 'MSET', 2, nil, 0)
  register.call(:text_command, 'MGET', 1, nil)
  register.call(:text_command, 'INCRBY DECRBY APPEND', 2)
  register.call(:text_command, 'GETRANGE', 3)
  register.call(:list_command, 'LPUSH RPUSH', 2, nil)
  register.call(:list_command, 'LPOP RPOP', 1, 2)
  register.call(:list_command, 'LRANGE LSET LREM LTRIM', 3)
  register.call(:list_command, 'LLEN', 1)
  register.call(:list_command, 'LINDEX', 2)
  register.call(:list_command, 'LINSERT', 4)
  register.call(:hash_command, 'HSET', 3, nil, 1)
  register.call(:hash_command, 'HGET HEXISTS', 2)
  register.call(:hash_command, 'HDEL', 2, nil)
  register.call(:hash_command, 'HGETALL HLEN HKEYS HVALS', 1)
  register.call(:hash_command, 'HINCRBY', 3)
  register.call(:set_command, 'SADD SREM SINTERSTORE SUNIONSTORE SDIFFSTORE', 2, nil)
  register.call(:set_command, 'SISMEMBER', 2)
  register.call(:set_command, 'SMEMBERS SCARD', 1)
  register.call(:set_command, 'SINTER SUNION SDIFF', 1, nil)
  register.call(:sorted_set_command, 'ZADD', 3, nil, 1)
  register.call(:sorted_set_command, 'ZSCORE ZRANK', 2)
  register.call(:sorted_set_command, 'ZINCRBY', 3)
  register.call(:sorted_set_command, 'ZREM', 2, nil)
  register.call(:sorted_set_command, 'ZCARD', 1)
  register.call(:sorted_set_command, 'ZRANGE ZRANGEBYSCORE', 3, 4)
  register.call(:key_command, 'DEL EXISTS', 1, nil)
  register.call(:key_command, 'TYPE KEYS TTL PERSIST TICK', 1)
  register.call(:key_command, 'RENAME RENAMENX', 2)
  register.call(:key_command, 'EXPIRE', 2, 3)
  register.call(:key_command, 'TIME DBSIZE FLUSH INFO', 0)
  register.call(:control_command, 'BEGIN COMMIT ROLLBACK', 0)
  register.call(:control_command, 'SNAPSHOT RESTORE', 1)
end.freeze

class Store
  def initialize
    @database = {}
    @stack = []
    @snapshots = {}
    @time = 0
  end

  def execute(words)
    command = words.first.upcase
    spec = COMMANDS[command]
    raise CommandError, "ERR unknown command '#{words.first}'" unless spec
    args = words.drop(1)
    raise CommandError, "ERR wrong number of arguments for '#{command.downcase}' command" unless spec.accepts?(args.length)
    send(spec.group, command, args)
  end

  private

  def read(key, type, empty)
    entry = @database[key]
    return empty unless entry
    raise CommandError, WRONG_TYPE unless entry.value.is_a?(type)
    entry.value
  end
  def text(key) = read(key, TextValue, TextValue.new('')).text
  def list(key) = read(key, ListValue, ListValue.new([])).items.dup
  def hash(key) = read(key, HashValue, HashValue.new({})).fields.dup
  def members(key) = read(key, SetValue, SetValue.new(Set.new)).members.dup
  def sorted_set(key) = read(key, SortedSetValue, SortedSetValue.new({})).scores.dup
  def replace(key, value, expiry = nil)
    if value.empty? then @database.delete(key)
    else @database[key] = Entry.new(value, expiry)
    end
  end
  def update(key, value) = replace(key, value, @database[key]&.expiry)
  def purge
    before = @database.length
    @database.delete_if { |_, entry| !entry.expiry.nil? && entry.expiry <= @time }
    before - @database.length
  end

  def text_command(command, a)
    key = a.first
    case command
    when 'SET'
      options = Set.new
      seconds_text = nil
      i = 2
      while i < a.length
        option = a[i].upcase
        i += 1
        raise CommandError, 'ERR syntax error' unless %w[NX XX EX KEEPTTL GET].include?(option) && options.add?(option)
        if option == 'EX'
          raise CommandError, 'ERR syntax error' if i == a.length
          seconds_text = a[i]
          i += 1
        end
      end
      if (options.include?('NX') && options.include?('XX')) || (options.include?('EX') && options.include?('KEEPTTL'))
        raise CommandError, 'ERR syntax error'
      end
      expiry = nil
      unless seconds_text.nil?
        seconds = number(seconds_text)
        raise CommandError, "ERR invalid expire time in 'set' command" unless seconds.positive?
        expiry = @time + seconds
      end
      old = @database[key]
      old_text = nil
      if options.include?('GET')
        value = text(key)
        old_text = value if old
      end
      blocked = (options.include?('NX') && old) || (options.include?('XX') && !old)
      unless blocked
        expiry = old.expiry if options.include?('KEEPTTL') && old
        replace(key, TextValue.new(a[1]), expiry)
      end
      options.include?('GET') ? quoted(old_text) : blocked ? '(nil)' : 'OK'
    when 'MSET'
      a.each_slice(2) { |name, value| replace(name, TextValue.new(value)) }
      'OK'
    when 'MGET'
      array_reply(a.map { |name| (entry = @database[name]) && entry.value.is_a?(TextValue) ? entry.value.text : nil })
    when 'INCR', 'DECR', 'INCRBY', 'DECRBY'
      delta = a.length == 2 ? number(a[1]) : 1
      delta = -delta if command.start_with?('DECR')
      old = text(key)
      value = increment(@database.key?(key) ? number(old) : 0, delta)
      update(key, TextValue.new(value.to_s))
      integer_reply(value)
    when 'APPEND'
      value = text(key) + a[1]
      update(key, TextValue.new(value))
      integer_reply(value.length)
    when 'GETRANGE'
      start = number(a[1])
      stop = number(a[2])
      value = text(key)
      quoted(value[normalized_range(value.length, start, stop)])
    when 'STRLEN' then integer_reply(text(key).length)
    else
      value = text(key)
      quoted(@database.key?(key) ? value : nil)
    end
  end

  def list_command(command, a)
    key = a.first
    case command
    when 'LPUSH', 'RPUSH'
      values = list(key)
      a.drop(1).each { |value| command == 'LPUSH' ? values.unshift(value) : values.push(value) }
      update(key, ListValue.new(values))
      integer_reply(values.length)
    when 'LPOP', 'RPOP'
      count = a.length == 2 ? number(a[1], POSITIVE) : nil
      raise CommandError, POSITIVE if count && count.negative?
      values = list(key)
      return '(nil)' unless @database.key?(key)
      removed = Array.new([count || 1, values.length].min) { command == 'LPOP' ? values.shift : values.pop }
      update(key, ListValue.new(values))
      count.nil? ? quoted(removed.first) : array_reply(removed)
    when 'LRANGE', 'LTRIM'
      start = number(a[1])
      stop = number(a[2])
      values = list(key)
      kept = values[normalized_range(values.length, start, stop)]
      return array_reply(kept) if command == 'LRANGE'
      update(key, ListValue.new(kept))
      'OK'
    when 'LLEN' then integer_reply(list(key).length)
    when 'LINDEX', 'LSET'
      index = number(a[1])
      values = list(key)
      index += values.length if index.negative?
      valid = index >= 0 && index < values.length
      return quoted(valid ? values[index] : nil) if command == 'LINDEX'
      raise CommandError, 'ERR no such key' unless @database.key?(key)
      raise CommandError, 'ERR index out of range' unless valid
      values[index] = a[2]
      update(key, ListValue.new(values))
      'OK'
    when 'LREM'
      count = number(a[1])
      values = list(key)
      values.reverse! if count.negative?
      removed = 0
      kept = values.reject do |value|
        if value == a[2] && (count.zero? || removed < count.abs) then removed += 1; true
        else false
        end
      end
      kept.reverse! if count.negative?
      update(key, ListValue.new(kept))
      integer_reply(removed)
    else
      where = a[1].upcase
      raise CommandError, 'ERR syntax error' unless %w[BEFORE AFTER].include?(where)
      values = list(key)
      return integer_reply(0) unless @database.key?(key)
      index = values.index(a[2])
      return integer_reply(-1) unless index
      values.insert(index + (where == 'AFTER' ? 1 : 0), a[3])
      update(key, ListValue.new(values))
      integer_reply(values.length)
    end
  end

  def hash_command(command, a)
    key = a.first
    if command == 'HINCRBY'
      delta = number(a[2])
      fields = hash(key)
      old = fields.key?(a[1]) ? number(fields[a[1]], 'ERR hash value is not an integer') : 0
      value = increment(old, delta)
      fields[a[1]] = value.to_s
      update(key, HashValue.new(fields))
      return integer_reply(value)
    end
    fields = hash(key)
    case command
    when 'HSET'
      added = 0
      a.drop(1).each_slice(2) do |field, value|
        added += 1 unless fields.key?(field)
        fields[field] = value
      end
      update(key, HashValue.new(fields))
      integer_reply(added)
    when 'HDEL'
      removed = a.drop(1).count { |field| fields.delete(field) }
      update(key, HashValue.new(fields))
      integer_reply(removed)
    when 'HGET' then quoted(fields[a[1]])
    when 'HEXISTS' then integer_reply(fields.key?(a[1]) ? 1 : 0)
    when 'HLEN' then integer_reply(fields.length)
    when 'HKEYS' then array_reply(fields.keys.sort)
    when 'HVALS' then array_reply(fields.keys.sort.map { |field| fields[field] })
    else array_reply(fields.keys.sort.flat_map { |field| [field, fields[field]] })
    end
  end

  def set_command(command, a)
    key = a.first
    storing = command.end_with?('STORE')
    if command.start_with?('SINTER', 'SUNION', 'SDIFF')
      sources = a.drop(storing ? 1 : 0).map { |source| members(source) }
      result = sources.first.dup
      sources.drop(1).each do |source|
        result = if command.start_with?('SINTER') then result & source
                 elsif command.start_with?('SUNION') then result | source
                 else result - source
                 end
      end
      return array_reply(result.to_a.sort) unless storing
      replace(key, SetValue.new(result))
      return integer_reply(result.length)
    end
    values = members(key)
    case command
    when 'SADD', 'SREM'
      changed = a.drop(1).count { |member| command == 'SADD' ? values.add?(member) : values.delete?(member) }
      update(key, SetValue.new(values))
      integer_reply(changed)
    when 'SCARD' then integer_reply(values.length)
    when 'SISMEMBER' then integer_reply(values.include?(a[1]) ? 1 : 0)
    else array_reply(values.to_a.sort)
    end
  end

  def sorted_set_command(command, a)
    key = a.first
    if command == 'ZADD'
      numbers = a.drop(1).each_slice(2).map { |score, _| number(score) }
      scores = sorted_set(key)
      added = 0
      numbers.each_with_index do |score, i|
        member = a[2 * i + 2]
        added += 1 unless scores.key?(member)
        scores[member] = score
      end
      update(key, SortedSetValue.new(scores))
      return integer_reply(added)
    end
    if command == 'ZINCRBY'
      delta = number(a[1])
      scores = sorted_set(key)
      value = increment(scores.fetch(a[2], 0), delta)
      scores[a[2]] = value
      update(key, SortedSetValue.new(scores))
      return quoted(value.to_s)
    end
    with_scores = false
    start = stop = 0
    minimum = maximum = nil
    if command == 'ZRANGE' || command == 'ZRANGEBYSCORE'
      with_scores = a.length == 4
      raise CommandError, 'ERR syntax error' if with_scores && a[3].upcase != 'WITHSCORES'
      if command == 'ZRANGE'
        start = number(a[1])
        stop = number(a[2])
      else
        minimum = score_bound(a[1])
        maximum = score_bound(a[2])
      end
    end
    scores = sorted_set(key)
    case command
    when 'ZREM'
      removed = a.drop(1).count { |member| scores.delete(member) }
      update(key, SortedSetValue.new(scores))
      return integer_reply(removed)
    when 'ZCARD' then return integer_reply(scores.length)
    when 'ZSCORE' then return quoted(scores[a[1]]&.to_s)
    end
    ordered = scores.sort_by { |member, score| [score, member] }
    if command == 'ZRANK'
      index = ordered.index { |member, _| member == a[1] }
      return index.nil? ? '(nil)' : integer_reply(index)
    end
    selected = if command == 'ZRANGE'
                 ordered[normalized_range(ordered.length, start, stop)]
               else
                 ordered.select { |_, score| minimum.accepts?(score, true) && maximum.accepts?(score, false) }
               end
    array_reply(with_scores ? selected.flat_map { |member, score| [member, score.to_s] } : selected.map(&:first))
  end

  def key_command(command, a)
    case command
    when 'TIME' then return integer_reply(@time)
    when 'DBSIZE' then return integer_reply(@database.length)
    when 'FLUSH' then @database.clear; return 'OK'
    when 'INFO'
      counts = Hash.new(0)
      @database.each_value { |entry| counts[entry.value.kind] += 1 }
      expires = @database.count { |_, entry| !entry.expiry.nil? }
      return "keys=#{@database.length},expires=#{expires},string=#{counts[:string]},list=#{counts[:list]},hash=#{counts[:hash]}," \
             "set=#{counts[:set]},zset=#{counts[:zset]},time=#{@time},depth=#{@stack.length},snapshots=#{@snapshots.length}"
    when 'DEL' then return integer_reply(a.count { |key| @database.delete(key) })
    when 'EXISTS' then return integer_reply(a.count { |key| @database.key?(key) })
    when 'KEYS'
      parts = parse_pattern(a.first)
      return array_reply(@database.keys.sort.select { |key| matches_pattern?(parts, key) })
    when 'TICK'
      ticks = number(a.first)
      raise CommandError, POSITIVE unless ticks.positive?
      @time += ticks
      return integer_reply(purge)
    end
    key = a.first
    if command == 'EXPIRE'
      condition = a.length == 3 ? a[2].upcase : nil
      if condition && !%w[NX XX GT LT].include?(condition)
        raise CommandError, "ERR Unsupported option #{a[2]}"
      end
      seconds = number(a[1])
      entry = @database[key]
      return integer_reply(0) unless entry
      expiry = @time + seconds
      rejected = case condition
                 when 'NX' then !entry.expiry.nil?
                 when 'XX' then entry.expiry.nil?
                 when 'GT' then entry.expiry.nil? || expiry <= entry.expiry
                 when 'LT' then !entry.expiry.nil? && expiry >= entry.expiry
                 else false
                 end
      return integer_reply(0) if rejected
      if seconds <= 0 then @database.delete(key)
      else @database[key] = Entry.new(entry.value, expiry)
      end
      return integer_reply(1)
    end
    entry = @database[key]
    case command
    when 'TYPE' then entry ? entry.value.kind.to_s : 'none'
    when 'TTL' then integer_reply(entry.nil? ? -2 : entry.expiry.nil? ? -1 : entry.expiry - @time)
    when 'PERSIST'
      return integer_reply(0) if entry.nil? || entry.expiry.nil?
      @database[key] = Entry.new(entry.value, nil)
      integer_reply(1)
    else
      raise CommandError, 'ERR no such key' unless entry
      destination = a[1]
      return integer_reply(0) if command == 'RENAMENX' && @database.key?(destination)
      if key != destination
        @database.delete(key)
        @database[destination] = entry
      end
      command == 'RENAME' ? 'OK' : integer_reply(1)
    end
  end

  def control_command(command, a)
    case command
    when 'BEGIN' then @stack << @database.dup
    when 'COMMIT', 'ROLLBACK'
      raise CommandError, 'ERR no transaction' if @stack.empty?
      saved = @stack.pop
      if command == 'ROLLBACK'
        @database = saved
        purge
      end
    when 'SNAPSHOT' then @snapshots[a.first] = @database.dup
    when 'RESTORE'
      saved = @snapshots[a.first]
      raise CommandError, 'ERR no such snapshot' unless saved
      @database = saved.dup
      purge
    end
    'OK'
  end
end

store = Store.new
STDIN.gets.to_i(10).times do
  words = split_line(STDIN.gets.chomp)
  begin
    result = words.nil? ? 'Invalid argument(s)' : store.execute(words)
  rescue CommandError => error
    result = "(error) #{error.message}"
  end
  STDOUT.puts(result)
end
