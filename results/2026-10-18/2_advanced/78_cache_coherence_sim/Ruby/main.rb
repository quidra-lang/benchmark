require 'set'
require_relative 'config_io'
require_relative 'cache'
require_relative 'protocol'
require_relative 'bus'
require_relative 'stats'

def validate_trace(lines, config)
  events, rejected, latest = [], [], 0
  lines.each_with_index do |line, index|
    fields = line.split(/ /, -1)
    reason = if ![3, 4].include?(fields.length) || fields.include?('')
               'fields'
             elsif !ConfigIO.decimal_integer?(fields[0], 7)
               'cycle'
             elsif !ConfigIO.decimal_integer?(fields[1]) || fields[1].to_i >= config[:cores]
               'core'
             elsif !%w[R W FENCE].include?(fields[2]) || fields.length != (fields[2] == 'FENCE' ? 3 : 4)
               'op'
             elsif fields[2] != 'FENCE' && (!ConfigIO.hex_address?(fields[3]) || fields[3].to_i(16) % 4 != 0 || fields[3].to_i(16) > 0x7fffffff)
               'address'
             elsif fields[0].to_i < latest
               'order'
             end
    if reason
      rejected << [index + 1, reason]
      next
    end
    latest = fields[0].to_i
    event = { number: events.length + 1, cycle: latest, core: fields[1].to_i, op: fields[2] }
    unless event[:op] == 'FENCE'
      address = fields[3].to_i(16)
      event.merge!(address: address, block: address / config[:line], word: address % config[:line] / 4)
    end
    events << event
  end
  [events, rejected]
end

def group_events(events, cores)
  result = Array.new(cores) { [] }
  events.each { |event| result[event[:core]] << event }
  result
end

def reuse_analysis(events, config)
  capacities = [config[:cap] / 4, config[:cap] / 2, config[:cap], 2 * config[:cap], 4 * config[:cap]]
  group_events(events, config[:cores]).each_with_index.map do |ordered, core|
    accesses = ordered.reject { |event| event[:op] == 'FENCE' }
    stack, cold, distances, misses = [], 0, Hash.new(0), Hash.new(0)
    accesses.each do |event|
      position = stack.index(event[:block])
      distance = position && position + 1
      if distance
        bucket = distance == 1 ? 0 : distance <= 4 ? 1 : distance <= 16 ? 2 : distance <= 64 ? 3 : distance <= 256 ? 4 : 5
        distances[Stats::DISTANCE[bucket]] += 1
        stack.delete_at(position)
      else
        cold += 1
      end
      event[:distance] = distance
      capacities.each { |capacity| misses[capacity] += 1 if !distance || distance > capacity }
      stack.unshift(event[:block])
    end
    future = Hash.new { |hash, key| hash[key] = [] }
    accesses.each_with_index { |event, index| future[event[:block]] << index }
    resident, opt = Set.new, 0
    accesses.each do |event|
      block = event[:block]
      future[block].shift
      next if resident.include?(block)
      opt += 1
      if resident.length == config[:cap]
        victim = resident.max_by { |line| [future[line].first || accesses.length, -line] }
        resident.delete(victim)
      end
      resident.add(block)
    end
    ["reuse c#{core} accesses #{accesses.length} lines #{stack.length} distance #{Stats.pairs(Stats::DISTANCE, distances, ':')} cold #{cold}",
     "mrc c#{core} lru #{Stats.pairs(capacities, misses, ':')} opt #{config[:cap]}:#{opt}"]
  end.flatten
end

def static_sharing(events)
  lines = {}
  events.each do |event|
    next if event[:op] == 'FENCE'
    info = (lines[event[:block]] ||= { cores: Set.new, writers: Set.new, reads: 0, writes: 0, words: {} })
    info[:cores].add(event[:core])
    operation = event[:op] == 'W' ? :writes : :reads
    info[operation] += 1
    info[:writers].add(event[:core]) if operation == :writes
    word = (info[:words][event[:word]] ||= { reads: Set.new, writes: Set.new })
    word[operation].add(event[:core])
  end
  lines.each_value do |info|
    info[:shared] = info[:cores].length >= 2 && !info[:writers].empty?
    info[:true] = info[:words].values.any? { |word| !word[:writes].empty? && (word[:reads] | word[:writes]).length >= 2 }
  end
  lines
end

class Simulation
  attr_reader :config, :scenario, :l1, :l2, :bus, :cores, :total, :accesses, :watch, :handoffs, :shared_misses, :communications, :l2_counts

  def initialize(config, scenario, events)
    @config, @scenario = config, scenario
    @primary = scenario[:name] == config[:primary]
    @l1 = Array.new(config[:cores]) { Cache.new(config[:l1_sets], config[:l1_ways], scenario[:l1]) }
    @l2 = Cache.new(config[:l2_sets], config[:l2_ways], scenario[:l2])
    @bus, @cores = Bus.new(config[:tb]), Array.new(config[:cores]) { Stats.counters }
    @queues = group_events(events, config[:cores])
    @indices, @ready, @writes = Array.new(config[:cores], 0), Array.new(config[:cores], 0), Array.new(config[:cores], 0)
    @seen = Array.new(config[:cores]) { Set.new }
    @invalidations, @word_state, @last_writer = {}, {}, {}
    @l2_counts, @handoffs, @shared_misses = Hash.new(0), Hash.new(0), Hash.new(0)
    @communications = Array.new(config[:cores]) { Array.new(config[:cores], 0) }
    @accesses, @watch = [], []
  end

  def finish
    @total[:finish]
  end

  def tuple(block)
    @l1.map { |cache| cache.state(block) } + [@l2.state(block)]
  end

  def transaction(core, kind, block, request)
    @cores[core][:bus][kind] += 1
    @l2_counts['writebacks'] += 1 if kind == 'WB'
    @bus.assign(core, kind, block, request)
  end

  def snoop(tx, word)
    @l1.each_with_index do |cache, core|
      next if core == tx[:core]
      old = cache.state(tx[:block])
      next if old == 'I'
      updated, supply, flush = Protocol.snoop(@scenario[:protocol], old, tx[:kind])
      tx[:snoop] << "c#{core}:#{old}>#{updated}"
      tx[:snoop_hits] += 1
      if updated == 'I'
        cache.remove(tx[:block])
        tx[:invalidations] += 1
        @cores[tx[:core]][:snoop]['invalidations_sent'] += 1
        @cores[core][:snoop]['invalidations_received'] += 1
        @invalidations[[core, tx[:block]]] = Set[word]
      else
        cache.change(tx[:block], updated)
      end
      if supply
        tx[:supplier] = core
        @cores[core][:snoop]['supplied'] += 1
      end
      tx[:flush] = true if flush
    end
    @l2_counts['flushes'] += 1 if tx[:flush]
  end

  def access_l2(tx)
    block = tx[:block]
    @l2_counts['lookups'] += 1
    if @l2.state(block) != 'I'
      tx[:l2] = 'hit'
      @l2_counts['hits'] += 1
      @l2.touch(block)
    else
      tx[:l2] = 'miss'
      @l2_counts['misses'] += 1
      if (old = @l2.fill(block, 'C'))
        copies, dirty = [], old[:state] == 'D'
        @l1.each_with_index do |cache, core|
          old_state = cache.state(old[:block])
          next if old_state == 'I'
          cache.remove(old[:block])
          copies << "c#{core}:#{old_state}"
          @cores[core][:snoop]['back_invalidations'] += 1
          dirty ||= Protocol::DIRTY.include?(old_state)
        end
        tx[:eviction] = { block: old[:block], copies: copies, dirty: dirty }
        @l2_counts['evictions'] += 1
        @l2_counts['dirty_evictions'] += 1 if dirty
      end
    end
    @l2.change(block, 'D') if tx[:flush] || tx[:kind] == 'BusWr'
  end

  def bus_access(core, kind, block, word, request)
    tx = transaction(core, kind, block, request)
    snoop(tx, word)
    access_l2(tx) unless kind == 'BusUpgr'
    completion = tx[:start] + @config[:tb]
    if kind == 'BusUpgr'
      service = 'upgrade'
    elsif kind == 'BusWr'
      completion += @config[:t2] + (tx[:l2] == 'miss' ? @config[:tm] : 0)
      service = 'through'
    elsif tx[:supplier]
      tx[:source], service = "c#{tx[:supplier]}", 'cache'
    else
      completion += @config[:t2] + (tx[:l2] == 'miss' ? @config[:tm] : 0)
      tx[:source], service = tx[:l2] == 'hit' ? ['L2', 'l2'] : ['mem', 'memory']
    end
    [completion, service]
  end

  def communicate(event)
    block, word, core = event.values_at(:block, :word, :core)
    key = [block, word]
    if event[:op] == 'W'
      @handoffs[block] += 1 if @last_writer.key?(block) && @last_writer[block] != core
      @last_writer[block] = core
      @word_state[key] = [core, Set.new]
    elsif (previous = @word_state[key]) && previous[0] != core && !previous[1].include?(core)
      @communications[previous[0]][core] += 1
      previous[1].add(core)
    end
  end

  def access(event, issue)
    core, block, word, op = event.values_at(:core, :block, :word, :op)
    counters, cache = @cores[core], @l1[core]
    before = @config[:watch].to_h { |line| [line, tuple(line)] } if @primary
    old = cache.state(block)
    hit = old != 'I'
    counters[:simple]['accesses'] += 1
    counters[:simple][op == 'R' ? 'reads' : 'writes'] += 1
    counters[:simple][hit ? 'hits' : 'misses'] += 1
    other = @l1.each_with_index.any? { |other_cache, k| k != core && other_cache.state(block) != 'I' }
    kind, updated = Protocol.requester(@scenario[:protocol], old, op, other)
    miss = nil
    if hit
      cache.touch(block)
    else
      record = @invalidations[[core, block]]
      miss = if !@seen[core].include?(block)
               'compulsory'
             elsif record
               sharing = record.include?(word) ? 'true_sharing' : 'false_sharing'
               counters[:misses][sharing] += 1
               @shared_misses[[block, sharing]] += 1
               'coherence'
             elsif event[:distance] > @config[:cap]
               'capacity'
             else
               'conflict'
             end
      counters[:misses][miss] += 1
    end
    @seen[core].add(block)
    if op == 'W'
      @invalidations.each { |(k, line), words| words.add(word) if k != core && line == block }
    end
    communicate(event) if @primary
    completion, service = kind ? bus_access(core, kind, block, word, issue + @config[:t1]) : [issue + @config[:t1], 'l1']
    if old != 'I'
      cache.change(block, updated)
    elsif updated != 'I'
      evicted = cache.fill(block, updated)
      @invalidations.delete([core, block])
      if evicted && Protocol::DIRTY.include?(evicted[:state])
        transaction(core, 'WB', evicted[:block], @bus.free)
        @l2.touch(evicted[:block])
        @l2.change(evicted[:block], 'D')
      end
    end
    latency = completion - issue
    counters[:service][service] += 1
    counters[:simple]['latency'] += latency
    counters[:simple][op == 'R' ? 'read_latency' : 'write_latency'] += latency
    @ready[core] = op == 'R' ? completion : issue + @config[:t1]
    @writes[core] = [@writes[core], completion].max if op == 'W'
    counters[:finish] = [counters[:finish], completion].max
    @accesses << event.merge(issue: issue, latency: latency, service: service, miss: miss, hit: hit)
    return unless @primary
    @config[:watch].each do |line|
      after = tuple(line)
      next if line != block && before[line] == after
      states = @config[:cores].times.map { |k| "c#{k}:#{after[k]}" }.join(' ')
      @watch << "#{event[:number]} #{issue} c#{core} #{op} #{ConfigIO.hex(event[:address])} line #{ConfigIO.hex(line * @config[:line])} #{states} L2:#{after[-1]}"
    end
  end

  def run
    loop do
      choices = @queues.each_with_index.filter_map do |queue, core|
        event = queue[@indices[core]]
        [[event[:cycle], @ready[core]].max, core, event] if event
      end
      break if choices.empty?
      issue, core, event = choices.min_by { |s, c, _event| [s, c] }
      @indices[core] += 1
      if event[:op] == 'FENCE'
        completion = [issue, @writes[core]].max
        @cores[core][:simple]['fences'] += 1
        @cores[core][:simple]['fence_stall'] += completion - issue
        @cores[core][:finish] = [@cores[core][:finish], completion].max
        @ready[core] = completion
      else
        access(event, issue)
      end
    end
    @total = Stats.total(@cores)
    self
  end
end

def scenario_report(state)
  config, scenario, total, bus = state.config, state.scenario, state.total, state.bus
  rows = ["scenario #{scenario[:name]} #{scenario[:protocol]} #{scenario[:l1]} #{scenario[:l2]}"]
  state.cores.each_with_index { |entry, core| rows.concat(Stats.six_lines("c#{core}", entry)) }
  rows.concat(Stats.six_lines('total', total))
  rows << "l2 #{Stats.pairs(%w[lookups hits misses flushes writebacks evictions dirty_evictions], state.l2_counts)}"
  count = bus.transactions.length
  rows << "bus transactions #{count} busy #{bus.busy} wait #{bus.wait} utilization #{Stats.decimal(100 * bus.busy, state.finish)}"
  kinds = total[:bus]
  data_bytes = config[:line] * (kinds['BusRd'] + kinds['BusRdX'] + kinds['WB']) + 4 * kinds['BusWr']
  rows << "traffic command_bytes #{8 * count} data_bytes #{data_bytes} memory_bytes #{config[:line] * (state.l2_counts['misses'] + state.l2_counts['dirty_evictions'])}"
  snoops = bus.transactions.reject { |tx| tx[:kind] == 'WB' }
  fanout = Hash.new(0)
  snoops.each { |tx| fanout[tx[:invalidations]] += 1 if %w[BusRdX BusUpgr BusWr].include?(tx[:kind]) }
  rows << "snoops probes #{(config[:cores] - 1) * snoops.length} hits #{snoops.sum { |tx| tx[:snoop_hits] }} fanout #{Stats.pairs((0...config[:cores]).to_a, fanout, ':')}"
  histogram = Hash.new(0)
  state.accesses.each do |event|
    latency = event[:latency]
    bucket = latency == 1 ? 0 : latency <= 9 ? 1 : latency <= 29 ? 2 : latency <= 99 ? 3 : latency <= 299 ? 4 : 5
    histogram[Stats::LATENCY[bucket]] += 1
  end
  rows << "latencies reads #{total[:simple]['read_latency']} writes #{total[:simple]['write_latency']} histogram #{Stats.pairs(Stats::LATENCY, histogram, ':')}"
  rows
end

def ranking(states)
  ['ranking'] + states.sort_by { |state| [state.finish, state.bus.transactions.length, state.scenario[:order]] }.each_with_index.map do |state, index|
    simple = state.total[:simple]
    "#{index + 1} #{state.scenario[:name]} finish #{state.finish} transactions #{state.bus.transactions.length} amat #{Stats.fraction(simple['latency'], simple['accesses'])} #{Stats.decimal(simple['latency'], simple['accesses'])}"
  end
end

def hot_lines(state)
  counts = Hash.new { |hash, key| hash[key] = Hash.new(0) }
  cores = Hash.new { |hash, key| hash[key] = Set.new }
  state.bus.transactions.each do |tx|
    counts[tx[:block]][tx[:kind]] += 1
    counts[tx[:block]]['invalidations'] += tx[:invalidations]
    cores[tx[:block]].add(tx[:core])
  end
  state.accesses.each do |event|
    next unless event[:miss]
    counts[event[:block]]['misses'] += 1
    counts[event[:block]]['coherence'] += 1 if event[:miss] == 'coherence'
  end
  blocks = counts.keys.select { |block| Stats::TRANSACTIONS.sum { |kind| counts[block][kind] } > 0 }
  blocks.sort_by! { |block| [-Stats::TRANSACTIONS.sum { |kind| counts[block][kind] }, block] }
  ["hot #{state.scenario[:name]}"] + blocks.first(state.config[:top]).each_with_index.map do |block, index|
    count = counts[block]
    "#{index + 1} #{ConfigIO.hex(block * state.config[:line])} transactions #{Stats::TRANSACTIONS.sum { |kind| count[kind] }} #{Stats.pairs(Stats::TRANSACTIONS, count)} misses #{count['misses']} coherence #{count['coherence']} invalidations #{count['invalidations']} cores #{Stats.cores(cores[block])}"
  end
end

def intervals(state)
  width = state.config[:interval]
  count = state.finish / width + 1
  access = Array.new(count) { Array.new(state.config[:cores], 0) }
  misses, transactions, busy = Array.new(count, 0), Array.new(count, 0), Array.new(count, 0)
  state.accesses.each do |event|
    bucket = event[:issue] / width
    access[bucket][event[:core]] += 1
    misses[bucket] += 1 if event[:miss]
  end
  state.bus.transactions.each do |tx|
    first, last = tx[:start], tx[:start] + state.config[:tb]
    transactions[first / width] += 1 if first / width < count
    (first / width..(last - 1) / width).each do |bucket|
      busy[bucket] += [last, (bucket + 1) * width].min - [first, bucket * width].max if bucket < count
    end
  end
  ["intervals #{state.scenario[:name]} #{width}"] + count.times.map do |bucket|
    "#{bucket} #{bucket * width}-#{(bucket + 1) * width - 1} accesses #{access[bucket].join(' ')} misses #{misses[bucket]} transactions #{transactions[bucket]} busy #{busy[bucket]} utilization #{Stats.decimal(100 * busy[bucket], width)}"
  end
end

def slowest(state)
  ["slowest #{state.scenario[:name]}"] + state.accesses.sort_by { |event| [-event[:latency], event[:number]] }.first(state.config[:top]).each_with_index.map do |event, index|
    "#{index + 1} event #{event[:number]} cycle #{event[:issue]} c#{event[:core]} #{event[:op]} #{ConfigIO.hex(event[:address])} latency #{event[:latency]} service #{event[:service]}"
  end
end

def region_for(address, config)
  region = config[:regions].find { |entry| address.between?(entry[:start], entry[:end]) }
  region ? region[:name] : 'other'
end

def regions(state)
  counts = Hash.new { |hash, key| hash[key] = Hash.new(0) }
  state.accesses.each do |event|
    counter = counts[region_for(event[:address], state.config)]
    counter['accesses'] += 1
    counter[event[:op] == 'R' ? 'reads' : 'writes'] += 1
    counter['latency'] += event[:latency]
    counter[event[:hit] ? 'hits' : event[:miss]] += 1
  end
  state.bus.transactions.each { |tx| counts[region_for(tx[:block] * state.config[:line], state.config)]['transactions'] += 1 }
  ["regions #{state.scenario[:name]}"] + (state.config[:regions].map { |region| region[:name] } + ['other']).map do |name|
    counter = counts[name]
    amat = counter['accesses'].zero? ? '-' : "#{Stats.fraction(counter['latency'], counter['accesses'])} #{Stats.decimal(counter['latency'], counter['accesses'])}"
    "#{name} #{Stats.pairs(%w[accesses reads writes hits] + Stats::MISSES + %w[transactions latency], counter)} amat #{amat}"
  end
end

def sharing_report(static, state)
  totals = Hash.new(0)
  shared = static.keys.sort.select { |block| static[block][:shared] }
  rows = shared.map do |block|
    info = static[block]
    true_misses, false_misses = state.shared_misses[[block, 'true_sharing']], state.shared_misses[[block, 'false_sharing']]
    totals['true'] += true_misses
    totals['false'] += false_misses
    totals[info[:true] ? 'true_lines' : 'false_lines'] += 1
    words = info[:words].sort.map { |word, item| "w#{word}=#{Stats.cores(item[:reads])}/#{Stats.cores(item[:writes])}" }.join(' ')
    "#{ConfigIO.hex(block * state.config[:line])} #{info[:true] ? 'true' : 'false'} cores #{Stats.cores(info[:cores])} writers #{Stats.cores(info[:writers])} reads #{info[:reads]} writes #{info[:writes]} handoffs #{state.handoffs[block]} coherence #{true_misses + false_misses} true #{true_misses} false #{false_misses} words #{words}"
  end
  rows << "lines #{shared.length} true_lines #{totals['true_lines']} false_lines #{totals['false_lines']} coherence #{totals['true'] + totals['false']} true #{totals['true']} false #{totals['false']}"
  rows << 'communication'
  state.communications.each_with_index { |vector, core| rows << "c#{core} #{vector.join(' ')}" }
  rows
end

def final_state(state)
  rows = []
  (state.l1 + [state.l2]).each_with_index do |cache, index|
    label = index == state.config[:cores] ? 'L2' : "c#{index}"
    cache.entries.each_with_index do |ways, set|
      values = ways.map { |entry| entry ? "#{ConfigIO.hex(entry[:block] * state.config[:line])}:#{entry[:state]}" : '-' }.join(' ')
      rows << "#{label} #{set} #{values} #{cache.replacement.downcase} #{cache.order(set)} fills #{cache.fills[set]} evictions #{cache.evictions[set]}"
    end
    counts = Hash.new(0)
    cache.lines.each { |entry| counts[entry[:state]] += 1 }
    if label == 'L2'
      in_l1 = state.l1.flat_map(&:lines).map { |entry| entry[:block] }.uniq.length
      rows << "L2 lines #{cache.lines.length} dirty #{counts['D']} clean #{counts['C']} in_l1 #{in_l1}"
    else
      rows << "#{label} lines #{cache.lines.length} #{Stats.pairs(%w[M O E S V], counts)}"
    end
  end
  rows
end

def main
  config, trace = ConfigIO.read_config, ConfigIO.read_trace
  events, rejected = validate_trace(trace, config)
  reuse = reuse_analysis(events, config)
  static = static_sharing(events)
  states = config[:scenarios].map { |scenario| Simulation.new(config, scenario, events).run }
  primary = states.find { |state| state.scenario[:name] == config[:primary] }
  header = ["trace lines #{trace.length} accepted #{events.length} rejected #{rejected.length}"]
  header.concat(rejected.map { |line, reason| "reject line #{line} #{reason}" })
  header << "geometry cores #{config[:cores]} line #{config[:line]} l1 #{config[:l1_size]} #{config[:l1_ways]} sets #{config[:l1_sets]} l2 #{config[:l2_size]} #{config[:l2_ways]} sets #{config[:l2_sets]}"
  header << "latency l1 #{config[:t1]} l2 #{config[:t2]} memory #{config[:tm]} bus #{config[:tb]}"
  sections = [header, reuse] + states.map { |state| scenario_report(state) } + [ranking(states), hot_lines(primary), intervals(primary), slowest(primary), regions(primary)]
  ConfigIO.write_lines('stats.txt', sections.map { |section| section.join("\n") }.join("\n\n").split("\n", -1))
  ConfigIO.write_lines('bus_log.txt', primary.bus.transactions.map { |tx| primary.bus.log_line(tx, config[:line]) })
  ConfigIO.write_lines('watch.txt', primary.watch)
  ConfigIO.write_lines('sharing.txt', sharing_report(static, primary))
  ConfigIO.write_lines('final_state.txt', final_state(primary))
end

main if $PROGRAM_NAME == __FILE__
