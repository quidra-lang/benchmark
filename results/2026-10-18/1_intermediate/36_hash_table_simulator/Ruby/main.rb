# frozen_string_literal: true

MODES = %w[CHAIN LINEAR QUADRATIC DOUBLE ROBINHOOD CUCKOO].freeze
class CommandError < StandardError; end

Item = Data.define(:key, :value) do
  def to_s = "#{key}=#{value}"
end
Slot = Data.define(:item, :deleted) do
  def empty? = item.nil? && !deleted
  def content = item ? item.key : deleted ? 'D' : '-'
end
EMPTY = Slot.new(nil, false)
TOMB = Slot.new(nil, true)
Removal = Data.define(:shifted, :moves)
Mutation = Data.define(:changed, :lines)
Cost = Data.define(:key, :position, :probes)
Metrics = Data.define(:longest, :average)

class Counters
  attr_accessor :probes, :rehashes, :inserts, :updates, :hits, :misses, :deletes, :absent

  def initialize
    @probes = @rehashes = @inserts = @updates = @hits = @misses = @deletes = @absent = 0
  end
end

class Search
  attr_accessor :item, :position, :chain_index, :available, :probes
  attr_reader :path

  def initialize
    @item = @position = @chain_index = @available = nil
    @probes = 0
    @path = []
  end
end

class Placement
  attr_accessor :position, :pending, :reused, :movements
  attr_reader :moves

  def initialize
    @position = @pending = nil
    @reused = false
    @movements = 0
    @moves = []
  end
end

module Helpers
  def parse_mode(word)
    raise CommandError, "BAD MODE #{word}" unless MODES.include?(word)
    word
  end

  def hash_key(key, base, modulus)
    key.each_byte.reduce(0) { |value, byte| (value * base + byte) % modulus }
  end

  def prime(value)
    candidate = [value, 2].max
    loop do
      divisor = 2
      divisor += 1 while divisor <= candidate / divisor && candidate % divisor != 0
      return candidate if divisor > candidate / divisor
      candidate += 1
    end
  end

  def decimal(numerator, denominator)
    value = denominator.zero? ? 0 : 100 * numerator / denominator
    format('%d.%02d', value / 100, value % 100)
  end

  def gauge(value) = value < 10 ? (48 + value).chr : '+'

  def histogram(values)
    values.tally.sort.map do |value, count|
      "#{value} #{count} #{'#' * [count, 50].min}#{count > 50 ? '+' : ''}"
    end
  end

  def generate(count, length, seed)
    state = seed
    Array.new(count) do
      Array.new(length) do
        state = 48_271 * state % 2_147_483_647
        (97 + state % 26).chr
      end.join.freeze
    end
  end

  def capacity(value)
    raise CommandError, 'BAD CAPACITY' unless (2..10_000).cover?(value)
    value
  end

  def check_generation(count, length, seed)
    return if (1..500).cover?(count) && (1..10).cover?(length) && (1..2_147_483_646).cover?(seed)
    raise CommandError, 'BAD ARGUMENT'
  end
end

class HashTable
  include Helpers
  attr_reader :mode, :cap, :tomb, :counters, :buckets, :slots
  attr_accessor :size

  def initialize(mode, cap)
    @mode = mode
    @cap = cap
    @size = @tomb = 0
    @counters = Counters.new
    @buckets = mode == 'CHAIN' ? Array.new(cap) { [] } : []
    @slots = Array.new(mode == 'CHAIN' ? 0 : slot_count, EMPTY)
  end

  def slot_count = @cap * (@mode == 'CUCKOO' ? 2 : 1)
  def position(index) = @mode == 'CUCKOO' ? "T#{index / @cap + 1}.#{index % @cap}" : index.to_s
  def distance(item, index) = (index - hash_key(item.key, 31, @cap)) % @cap
  def items = @mode == 'CHAIN' ? @buckets.flatten : @slots.filter_map(&:item)

  def search(key, trace = false)
    result = Search.new
    observe = lambda do |index, content|
      result.probes += 1
      result.path << "#{position(index)}:#{content}" if trace
    end
    home = hash_key(key, 31, @cap)
    if @mode == 'CHAIN'
      @buckets[home].each_with_index do |item, index|
        observe.call(home, item.key)
        next unless item.key == key
        result.item = item
        result.position = home
        result.chain_index = index
        break
      end
      return result
    end
    step = @mode == 'DOUBLE' ? 1 + hash_key(key, 37, @cap - 1) : 1
    (@mode == 'CUCKOO' ? 2 : @cap).times do |i|
      index = if @mode == 'CUCKOO'
                i.zero? ? home : @cap + hash_key(key, 37, @cap)
              else
                (home + (@mode == 'QUADRATIC' ? i * i : i * step)) % @cap
              end
      slot = @slots[index]
      observe.call(index, slot.content)
      if slot.item&.key == key
        result.item = slot.item
        result.position = index
        break
      end
      next if @mode == 'CUCKOO'
      if slot.empty?
        result.available ||= index
        break
      end
      if slot.deleted
        result.available ||= index
        next
      end
      break if @mode == 'ROBINHOOD' && distance(slot.item, index) < i
    end
    result
  end

  def place(item, initial = nil, trace = false)
    result = Placement.new
    home = hash_key(item.key, 31, @cap)
    if @mode == 'CHAIN'
      @buckets[home] << item
      result.position = home
      return result
    end
    if %w[LINEAR QUADRATIC DOUBLE].include?(@mode)
      index = (initial || search(item.key)).available
      unless index
        result.pending = item
        return result
      end
      result.reused = @slots[index].deleted
      @tomb -= 1 if result.reused
      @slots[index] = Slot.new(item, false)
      result.position = index
      return result
    end
    carried = item
    if @mode == 'ROBINHOOD'
      index = home
      traveled = 0
      from = nil
      loop do
        resident = @slots[index].item
        unless resident
          result.moves << "SHIFT #{carried.key} #{from} -> #{index}" if trace && from
          @slots[index] = Slot.new(carried, false)
          result.position ||= index
          return result
        end
        resident_distance = distance(resident, index)
        if resident_distance < traveled
          result.moves << "SHIFT #{carried.key} #{from} -> #{index}" if trace && from
          @slots[index] = Slot.new(carried, false)
          carried = resident
          result.position ||= index
          from = index
          traveled = resident_distance
          result.movements += 1
        end
        index = (index + 1) % @cap
        traveled += 1
      end
    end
    part = 0
    loop do
      index = part * @cap + hash_key(carried.key, part.zero? ? 31 : 37, @cap)
      resident = @slots[index].item
      unless resident
        @slots[index] = Slot.new(carried, false)
        result.position = search(item.key).position
        return result
      end
      if result.movements == @cap
        result.pending = carried
        return result
      end
      result.moves << "KICK #{resident.key} #{position(index)}" if trace
      @slots[index] = Slot.new(carried, false)
      carried = resident
      result.movements += 1
      part = 1 - part
    end
  end

  def remove(found, trace)
    shifted = 0
    moves = []
    if @mode == 'CHAIN'
      @buckets[found.position].delete_at(found.chain_index)
    elsif %w[LINEAR QUADRATIC DOUBLE].include?(@mode)
      @slots[found.position] = TOMB
      @tomb += 1
    else
      @slots[found.position] = EMPTY
      if @mode == 'ROBINHOOD'
        source = (found.position + 1) % @cap
        loop do
          item = @slots[source].item
          break unless item && distance(item, source).positive?
          destination = (source - 1) % @cap
          moves << "SHIFT #{item.key} #{source} -> #{destination}" if trace
          @slots[destination] = @slots[source]
          @slots[source] = EMPTY
          shifted += 1
          source = (source + 1) % @cap
        end
      end
    end
    @size -= 1
    Removal.new(shifted, moves)
  end

  def self.rebuild(mode, cap, items)
    trial = new(mode, cap)
    items.each do |item|
      return nil unless trial.place(item).position
    end
    trial.size = items.length
    trial
  end

  def adopt(replacement)
    @mode = replacement.mode
    @cap = replacement.cap
    @size = replacement.size
    @tomb = replacement.tomb
    @buckets = replacement.buckets
    @slots = replacement.slots
  end

  def automatic(target, reason, pending = nil)
    old = @cap
    listed = items
    listed << pending if pending
    loop do
      trial = HashTable.rebuild(@mode, target, listed)
      if trial
        adopt(trial)
        @counters.rehashes += 1
        return "REHASH #{reason} #{old} -> #{@cap}"
      end
      target = prime(2 * target)
    end
  end

  def load_check(maximum)
    threshold = maximum * slot_count
    return nil if (@size + @tomb) * 100 <= threshold
    grow = @size * 200 > threshold
    automatic(grow ? prime(2 * @cap) : @cap, grow ? 'load' : 'tomb')
  end

  def shrink_check(minimum, maximum)
    target = prime(@cap / 2)
    count = target * (@mode == 'CUCKOO' ? 2 : 1)
    return nil if @size * 100 >= minimum * slot_count || target >= @cap || @size * 100 > maximum * count
    trial = HashTable.rebuild(@mode, target, items)
    return nil unless trial
    old = @cap
    adopt(trial)
    @counters.rehashes += 1
    "REHASH shrink #{old} -> #{@cap}"
  end

  def path_line(found) = "PATH #{found.path.empty? ? 'none' : found.path.join(' ')}"

  def put(item, add, maximum, reporting)
    trace = reporting == :trace
    details = trace || reporting == :full
    found = search(item.key, trace)
    @counters.probes += found.probes
    command = add ? 'ADD' : 'PUT'
    lines = []
    if (old = found.item)
      stored = Item.new(item.key, add ? old.value + item.value : item.value)
      if @mode == 'CHAIN'
        @buckets[found.position][found.chain_index] = stored
      else
        @slots[found.position] = Slot.new(stored, false)
      end
      @counters.updates += 1
      lines << "#{command} #{stored} UPDATED old=#{old.value} at=#{position(found.position)} probes=#{found.probes}" if details
      lines << path_line(found) if trace
      return Mutation.new(false, lines)
    end
    placed = place(item, found, trace)
    @counters.inserts += 1
    if details
      row = "#{command} #{item} NEW"
      if placed.position
        row << " at=#{position(placed.position)} probes=#{found.probes}"
        row << ' reused' if placed.reused
        row << " shifted=#{placed.movements}" if @mode == 'ROBINHOOD'
        row << " kicks=#{placed.movements}" if @mode == 'CUCKOO'
      else
        row << " probes=#{found.probes}"
        row << (@mode == 'QUADRATIC' ? ' full' : " kicks=#{placed.movements} failed")
      end
      lines << row
    end
    if trace
      lines << path_line(found)
      lines.concat(placed.moves)
    end
    if placed.position
      @size += 1
    else
      rehash = automatic(prime(2 * @cap), @mode == 'QUADRATIC' ? 'full' : 'kicks', placed.pending)
      lines << rehash unless reporting == :silent
    end
    rehash = load_check(maximum)
    lines << rehash if rehash && reporting != :silent
    Mutation.new(true, lines)
  end

  def delete(key, minimum, maximum, reporting)
    trace = reporting == :trace
    details = trace || reporting == :full
    found = search(key, trace)
    @counters.probes += found.probes
    lines = []
    unless found.item
      @counters.absent += 1
      lines << "DEL #{key} NOT FOUND probes=#{found.probes}" if details
      lines << path_line(found) if trace
      return Mutation.new(false, lines)
    end
    removed = remove(found, trace)
    @counters.deletes += 1
    if details
      row = "DEL #{key} OK at=#{position(found.position)} probes=#{found.probes}"
      row << " shifted=#{removed.shifted}" if @mode == 'ROBINHOOD'
      lines << row
    end
    if trace
      lines << path_line(found)
      lines.concat(removed.moves)
    end
    rehash = shrink_check(minimum, maximum)
    lines << rehash if rehash && reporting != :silent
    Mutation.new(true, lines)
  end

  def get(key, trace)
    found = search(key, trace)
    @counters.probes += found.probes
    row = if found.item
            @counters.hits += 1
            "GET #{found.item} at=#{position(found.position)} probes=#{found.probes}"
          else
            @counters.misses += 1
            "GET #{key} NOT FOUND probes=#{found.probes}"
          end
    trace ? [row, path_line(found)] : [row]
  end

  def costs
    result = []
    if @mode == 'CHAIN'
      @buckets.each_with_index do |bucket, index|
        bucket.each_with_index { |item, place| result << Cost.new(item.key, index, place + 1) }
      end
    else
      @slots.each_with_index do |slot, index|
        next unless slot.item
        cost = case @mode
               when 'CUCKOO' then index / @cap + 1
               when 'LINEAR', 'ROBINHOOD' then distance(slot.item, index) + 1
               else search(slot.item.key).probes
               end
        result << Cost.new(slot.item.key, index, cost)
      end
    end
    result
  end

  def metrics
    values = costs
    Metrics.new(values.map(&:probes).max || 0, decimal(values.sum(&:probes), @size))
  end

  def dump
    lines = ["DUMP #{@mode} cap=#{@cap} size=#{@size} tomb=#{@tomb}"]
    if @mode == 'CHAIN'
      @buckets.each_with_index { |bucket, index| lines << "#{index} #{bucket.empty? ? '-' : bucket.join(' ')}" }
    else
      @slots.each_with_index do |slot, index|
        prefix = @mode == 'CUCKOO' ? "T#{index / @cap + 1} #{index % @cap}" : index.to_s
        content = slot.item ? slot.item.to_s : slot.content
        content += " d=#{distance(slot.item, index)}" if @mode == 'ROBINHOOD' && slot.item
        lines << "#{prefix} #{content}"
      end
    end
    lines
  end

  def map
    lines = ["MAP #{@mode} cap=#{@cap}"]
    cost_by_slot = Array.new(slot_count, 0)
    costs.each { |cost| cost_by_slot[cost.position] = cost.probes } unless @mode == 'CHAIN'
    (@mode == 'CUCKOO' ? 2 : 1).times do |part|
      (0...@cap).step(40) do |start|
        text = (start...[start + 40, @cap].min).map do |index|
          if @mode == 'CHAIN'
            @buckets[index].empty? ? '.' : gauge(@buckets[index].length)
          else
            position = part * @cap + index
            slot = @slots[position]
            if slot.empty? then '.'
            elsif slot.deleted then 'D'
            elsif @mode == 'CUCKOO' then '#'
            else gauge(cost_by_slot[position] - 1)
            end
          end
        end.join
        prefix = @mode == 'CUCKOO' ? "T#{part + 1} " : ''
        lines << "#{prefix}#{format('%05d', start)} #{text}"
      end
    end
    lines
  end

  def statistics
    values = metrics
    c = @counters
    ["STATS #{@mode} size=#{@size} cap=#{@cap} slots=#{slot_count} tomb=#{@tomb} load=#{decimal(100 * @size, slot_count)}% " \
       "longest=#{values.longest} avg=#{values.average} probes=#{c.probes} rehashes=#{c.rehashes}",
     "OPS inserts=#{c.inserts} updates=#{c.updates} hits=#{c.hits} misses=#{c.misses} deletes=#{c.deletes} absent=#{c.absent}"]
  end

  def scan(cursor, limit)
    keys = []
    while cursor < slot_count && keys.length < limit
      if @mode == 'CHAIN'
        keys.concat(@buckets[cursor].map(&:key))
      elsif (item = @slots[cursor].item)
        keys << item.key
      end
      cursor += 1
    end
    cursor = 0 if cursor == slot_count
    "SCAN next=#{cursor}#{keys.empty? ? '' : ' ' + keys.join(' ')}"
  end

  def clusters
    runs = []
    if @mode == 'CHAIN'
      runs = @buckets.reject(&:empty?).map(&:length)
    else
      (0...slot_count).step(@cap) do |base|
        empty = (0...@cap).find { |i| @slots[base + i].empty? }
        unless empty
          runs << @cap
          next
        end
        length = 0
        (1..@cap).each do |offset|
          if !@slots[base + (empty + offset) % @cap].empty?
            length += 1
          elsif length.positive?
            runs << length
            length = 0
          end
        end
      end
    end
    ["CLUSTERS runs=#{runs.length} longest=#{runs.max || 0}"] + histogram(runs)
  end

  def distribution
    values = costs.map(&:probes)
    ["DIST keys=#{@size} longest=#{values.max || 0}"] + histogram(values)
  end
end

class Simulator
  include Helpers
  COMMANDS = %w[CREATE MAXLOAD MINLOAD TRACE HASH PUT ADD GET DEL PROBE GEN GENDEL RESIZE CONVERT
                CLEAR DUMP MAP STATS KEYS TOP SCAN CLUSTERS DIST COMPARE BENCH].freeze

  def initialize
    @table = nil
    @maximum = 75
    @minimum = 0
    @trace = false
  end

  def compare(cap)
    items = @table.items.sort_by(&:key)
    lines = ["COMPARE keys=#{items.length} cap=#{cap}"]
    MODES.each do |mode|
      trial = HashTable.new(mode, cap)
      items.each { |item| trial.put(item, false, @maximum, :silent) }
      values = trial.metrics
      lines << "#{mode} cap=#{trial.cap} longest=#{values.longest} avg=#{values.average} probes=#{trial.counters.probes} rehashes=#{trial.counters.rehashes}"
    end
    lines
  end

  def benchmark(cap, count, length, seed)
    keys = generate(2 * count, length, seed)
    lines = ["BENCH cap=#{cap} count=#{count} len=#{length} seed=#{seed}"]
    MODES.each do |mode|
      trial = HashTable.new(mode, cap)
      count.times { |i| trial.put(Item.new(keys[i], i + 1), false, @maximum, :silent) }
      misses = probes = 0
      keys.drop(count).each do |key|
        found = trial.search(key)
        next if found.item
        misses += 1
        probes += found.probes
      end
      lines << "#{mode} cap=#{trial.cap} keys=#{trial.size} hit=#{trial.metrics.average} misses=#{misses} miss=#{decimal(probes, misses)} rehashes=#{trial.counters.rehashes}"
    end
    lines
  end

  def execute(line)
    words = line.split(' ')
    command = words[0]
    number = ->(index) { Integer(words[index], 10) }
    raise CommandError, "UNKNOWN COMMAND #{command}" unless COMMANDS.include?(command)
    case command
    when 'CREATE'
      mode = parse_mode(words[1])
      cap = prime(capacity(number.call(2)))
      @table = HashTable.new(mode, cap)
      return ["CREATE #{mode} cap=#{cap}"]
    when 'MAXLOAD', 'MINLOAD'
      value = number.call(1)
      raise CommandError, 'BAD LOAD' unless (command == 'MAXLOAD' ? 10..95 : 0..40).cover?(value)
      if command == 'MAXLOAD'
        @maximum = value
      else
        @minimum = value
      end
      return ["#{command} #{value}"]
    when 'TRACE'
      raise CommandError, 'BAD ARGUMENT' unless %w[ON OFF].include?(words[1])
      @trace = words[1] == 'ON'
      return ["TRACE #{words[1]}"]
    when 'HASH'
      cap = capacity(number.call(2))
      key = words[1]
      return ["HASH #{key} m=#{cap} h31=#{hash_key(key, 31, cap)} h37=#{hash_key(key, 37, cap)} step=#{1 + hash_key(key, 37, cap - 1)}"]
    when 'BENCH'
      cap = prime(capacity(number.call(1)))
      count, length, seed = (2..4).map(&number)
      check_generation(count, length, seed)
      return benchmark(cap, count, length, seed)
    end
    raise CommandError, 'NO TABLE' unless @table
    reporting = @trace ? :trace : :full
    case command
    when 'PUT', 'ADD'
      @table.put(Item.new(words[1].freeze, number.call(2)), command == 'ADD', @maximum, reporting).lines
    when 'GET' then @table.get(words[1], @trace)
    when 'DEL' then @table.delete(words[1], @minimum, @maximum, reporting).lines
    when 'PROBE'
      found = @table.search(words[1], true)
      path = found.path.empty? ? '' : ' ' + found.path.join(' ')
      ["PROBE #{words[1]}#{path} #{found.item ? 'FOUND' : 'MISS'} probes=#{found.probes}"]
    when 'GEN', 'GENDEL'
      count, length, seed = (1..3).map(&number)
      check_generation(count, length, seed)
      lines = []
      changed = 0
      generate(count, length, seed).each_with_index do |key, index|
        result = if command == 'GEN'
                   @table.put(Item.new(key, index + 1), false, @maximum, :rehashes)
                 else
                   @table.delete(key, @minimum, @maximum, :rehashes)
                 end
        changed += 1 if result.changed
        lines.concat(result.lines)
      end
      lines << if command == 'GEN'
                 "GEN #{count} new=#{changed} updated=#{count - changed}"
               else
                 "GENDEL #{count} deleted=#{changed} missing=#{count - changed}"
               end
      lines
    when 'RESIZE', 'CONVERT'
      cap = command == 'RESIZE' ? prime(capacity(number.call(1))) : @table.cap
      mode = command == 'CONVERT' ? parse_mode(words[1]) : @table.mode
      slots = cap * (mode == 'CUCKOO' ? 2 : 1)
      raise CommandError, 'TOO SMALL' if @table.size * 100 > @maximum * slots
      replacement = HashTable.rebuild(mode, cap, @table.items)
      raise CommandError, 'REBUILD FAILED' unless replacement
      row = command == 'RESIZE' ? "RESIZE #{@table.cap} -> #{cap}" : "CONVERT #{@table.mode} -> #{mode} cap=#{cap}"
      @table.adopt(replacement)
      [row]
    when 'CLEAR'
      size = @table.size
      @table.adopt(HashTable.new(@table.mode, @table.cap))
      ["CLEAR #{size}"]
    when 'DUMP' then @table.dump
    when 'MAP' then @table.map
    when 'STATS' then @table.statistics
    when 'KEYS'
      keys = @table.items.map(&:key).sort
      ["KEYS #{keys.length}#{keys.empty? ? '' : ' ' + keys.join(' ')}"]
    when 'TOP'
      limit = number.call(1)
      raise CommandError, 'BAD ARGUMENT' unless (1..100).cover?(limit)
      selected = @table.costs.sort_by { |cost| [-cost.probes, cost.key] }.take(limit)
      ["TOP #{selected.length}"] + selected.map { |cost| "#{cost.key} cost=#{cost.probes} at=#{@table.position(cost.position)}" }
    when 'SCAN'
      cursor = number.call(1)
      limit = number.call(2)
      raise CommandError, 'BAD ARGUMENT' unless (1..100).cover?(limit)
      raise CommandError, 'BAD CURSOR' if cursor >= @table.slot_count
      [@table.scan(cursor, limit)]
    when 'CLUSTERS' then @table.clusters
    when 'DIST' then @table.distribution
    when 'COMPARE' then compare(prime(capacity(number.call(1))))
    end
  end
end

if (first = $stdin.gets)
  simulator = Simulator.new
  Integer(first, 10).times do
    begin
      simulator.execute($stdin.gets).each { |line| puts line }
    rescue CommandError => error
      puts "ERROR #{error.message}"
    end
  end
end
