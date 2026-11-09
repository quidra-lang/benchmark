NAMES = %w[RETAILER WHOLESALER DISTRIBUTOR FACTORY].freeze
PARAMETERS = {'FIXED' => 1, 'PASS' => 0, 'BASESTOCK' => 1, 'MINMAX' => 2,
              'MOVAVG' => 2, 'SMOOTH' => 2, 'STERMAN' => 4}.freeze
MODES = {'ORDERS' => :order, 'INV' => :inventory, 'BACK' => :backlog}.freeze
class CommandError < StandardError; end

def money(value)
  format('%d.%02d', value / 100, value % 100)
end

def decimal(numerator, denominator, places)
  scale = 10**places
  value = numerator * scale / denominator
  format("%d.%0#{places}d", value / scale, value % scale)
end

def variation(values)
  values.length * values.sum { |v| v * v } - values.sum**2
end

def parse_policy(tokens)
  name = tokens[0]
  raise CommandError, "unknown policy #{name}" unless PARAMETERS.key?(name)
  count = PARAMETERS[name]
  raise CommandError, "#{name} needs #{count} parameters" if tokens.length - 1 != count
  values = tokens.drop(1).each_with_index.map { |t, i| name == 'STERMAN' && i < 3 ? t.delete('.').to_i : t.to_i }
  valid = case name
          when 'FIXED' then (0..1000).cover?(values[0])
          when 'PASS' then true
          when 'BASESTOCK' then (0..10000).cover?(values[0])
          when 'MINMAX' then 0 <= values[0] && values[0] < values[1] && values[1] <= 10000
          when 'MOVAVG' then (1..52).cover?(values[0]) && (0..10000).cover?(values[1])
          when 'SMOOTH' then (1..10).cover?(values[0]) && (0..10000).cover?(values[1])
          else values.first(3).all? { |v| (0..100).cover?(v) } && (0..10000).cover?(values[3])
          end
  raise CommandError, "invalid parameter for #{name}" unless valid
  {name: name, args: values, text: tokens.join(' ')}
end

class Simulation
  attr_accessor :week, :demands, :stages, :plant_backlog, :plant_capacity, :plant_records, :visibility

  def initialize(initials, demands)
    @initials = initials
    @week = 0
    @demands = demands.dup
    @stages = initials.map do |i|
      {
        inventory: i[:inventory], backlog: 0,
        shipping: Array.new(i[:shipping], i[:quantity]), orders: Array.new(i[:orders], i[:quantity]),
        policy: i[:policy], expected: 100 * i[:quantity], holding: i[:holding],
        backlog_rate: i[:backlog], lot: 1, capacity: nil, records: []
      }
    end
    @plant_backlog = 0
    @plant_capacity = nil
    @plant_records = []
    @visibility = 'OFF'
  end

  def signal(index, week, current = nil)
    return @demands[week - 1] if @visibility == 'ON'
    return current[index] if current && week == @week + 1
    @stages[index][:records][week - 1][:incoming]
  end

  def set_policy(index, policy)
    stage = @stages[index]
    stage[:policy] = policy
    if policy[:name] == 'STERMAN'
      stage[:expected] = 100 * (@week.positive? ? signal(index, @week) : @initials[index][:quantity])
    end
  end

  def positions
    supply = @stages.each_with_index.map do |s, i|
      s[:orders].sum + (i < 3 ? @stages[i + 1][:backlog] : @plant_backlog) + s[:shipping].sum
    end
    [supply, @stages.each_with_index.map { |s, i| s[:inventory] + supply[i] - s[:backlog] }]
  end

  def policy_order(index, incoming, line, position)
    s = @stages[index]
    name = s[:policy][:name]
    a = s[:policy][:args]
    week = @week + 1
    signal = signal(index, week, incoming)
    case name
    when 'FIXED' then a[0]
    when 'PASS' then incoming[index]
    when 'BASESTOCK' then [0, a[0] - position].max
    when 'MINMAX' then position <= a[0] ? a[1] - position : 0
    when 'MOVAVG'
      count = [a[0], week].min
      forecast = ((week - count + 1)..week).sum { |u| signal(index, u, incoming) } / count
      delay = @initials[index][:shipping] + @initials[index][:orders]
      [0, a[1] + forecast * delay - position].max
    when 'SMOOTH'
      [0, signal + (a[1] - position).div(a[0])].max
    else
      theta, alpha, beta, target = a
      s[:expected] = (100 * theta * signal + (100 - theta) * s[:expected]) / 100
      net = s[:inventory] - s[:backlog]
      [0, (100 * s[:expected] + alpha * (100 * (target - net) - beta * line)).div(10000)].max
    end
  end

  def step
    received = @stages.map do |s|
      quantity = s[:shipping].shift
      s[:inventory] += quantity
      quantity
    end
    incoming = [@demands[@week], *@stages.first(3).map { |s| s[:orders].shift }]
    plant_incoming = @stages[3][:orders].shift
    records = []
    @stages.each_with_index do |s, i|
      before = s[:backlog]
      requested = before + incoming[i]
      shipped = [s[:inventory], requested, s[:capacity] || requested].min
      s[:inventory] -= shipped
      s[:backlog] = requested - shipped
      @stages[i - 1][:shipping] << shipped if i.positive?
      records << {
        received: received[i], incoming: incoming[i], shipped: shipped, before: before,
        ontime: [[0, shipped - before].max, incoming[i]].min,
        inventory: s[:inventory], backlog: s[:backlog]
      }
    end
    requested = @plant_backlog + plant_incoming
    produced = [requested, @plant_capacity || requested].min
    @plant_backlog = requested - produced
    @stages[3][:shipping] << produced
    supply, positions = positions()
    orders = @stages.each_index.map { |i| policy_order(i, incoming, supply[i], positions[i]) }
    @stages.each_with_index do |s, i|
      quantity = (orders[i] + s[:lot] - 1) / s[:lot] * s[:lot]
      s[:orders] << quantity
      r = records[i]
      r[:order] = quantity
      r[:holding] = s[:holding] * s[:inventory]
      r[:backlog_cost] = s[:backlog_rate] * s[:backlog]
      r[:cost] = r[:holding] + r[:backlog_cost]
      s[:records] << r
    end
    @plant_records << {incoming: plant_incoming, produced: produced, backlog: @plant_backlog}
    @week += 1
    records
  end

  def costs
    @stages.map { |s| s[:records].sum { |r| r[:cost] } }
  end
end

class Game
  attr_reader :output

  def initialize(settings)
    @initials = settings.map do |a|
      {
        inventory: a[1].to_i, quantity: a[2].to_i, shipping: a[3].to_i, orders: a[4].to_i,
        holding: a[5].to_i, backlog: a[6].to_i, policy: parse_policy(a.drop(7))
      }
    end
    @base = []
    @sim = Simulation.new(@initials, [])
    @snapshots = {}
    @output = []
  end

  def emit(*parts)
    @output << parts.join(' ')
  end

  def stage_index(text)
    index = NAMES.index(text)
    raise CommandError, "unknown stage #{text}" unless index
    index
  end

  def target(text)
    text == 'ALL' ? [0, 1, 2, 3] : [stage_index(text)]
  end

  def require_weeks
    raise CommandError, 'no weeks simulated' if @sim.week.zero?
  end

  def range_check(args, limit)
    return [1, limit] if args.empty?
    first, last = args.map(&:to_i)
    raise CommandError, "bad range #{args[0]} #{args[1]}" unless 1 <= first && first <= last && last <= limit
    [first, last]
  end

  def mode_check(mode)
    raise CommandError, "unknown mode #{mode}" unless %w[ORDERS INV BACK NET].include?(mode)
  end

  def values(index, mode)
    @sim.stages[index][:records].map { |r| mode == 'NET' ? r[:inventory] - r[:backlog] : r[MODES[mode]] }
  end

  def initialize_sim(demands = nil)
    @base = demands.dup unless demands.nil?
    @sim = Simulation.new(@initials, @base)
  end

  def trial(policies)
    current = @sim
    trial = Simulation.new(@initials, current.demands)
    trial.visibility = current.visibility
    trial.plant_capacity = current.plant_capacity
    trial.stages.each_with_index do |s, i|
      old = current.stages[i]
      s[:lot] = old[:lot]
      s[:capacity] = old[:capacity]
      s[:holding] = old[:holding]
      s[:backlog_rate] = old[:backlog_rate]
      trial.set_policy(i, policies[i])
    end
    trial.step while trial.week < trial.demands.length
    trial
  end

  def demand(values)
    initialize_sim(values)
    emit('DEMAND', 'weeks', values.length, 'total', values.sum, 'min', values.min, 'max', values.max)
  end

  def generate(a)
    weeks, base, spread, seed = a.first(4).map(&:to_i)
    changes = a.drop(4).each_slice(3).map { |kind, week, amount| [kind, week.to_i, amount.to_i] }
    changes.each do |_, week, _|
      raise CommandError, "week #{week} outside horizon" unless (1..weeks).cover?(week)
    end
    levels = (1..weeks).map do |week|
      level = base
      changes.each do |kind, start, amount|
        if (kind == 'STEP' && week >= start) || (kind == 'PULSE' && week == start)
          level += amount
        elsif kind == 'RAMP' && week >= start
          level += amount * (week - start + 1)
        end
      end
      raise CommandError, "negative level at week #{week}" if level.negative?
      level
    end
    demands = levels.map do |level|
      seed = 48271 * seed % 2147483647
      level + seed % spread
    end
    demand(demands)
  end

  def status
    s = @sim
    emit('STATUS', 'week', s.week, 'of', s.demands.length)
    supply, positions = s.positions
    s.stages.each_with_index do |stage, i|
      parts = [NAMES[i], 'inv', stage[:inventory], 'back', stage[:backlog],
               'transit', stage[:shipping].join(','), 'pending', stage[:orders].join(','),
               'supply', supply[i], 'position', positions[i], 'policy', stage[:policy][:text]]
      parts.push('expect', money(stage[:expected])) if stage[:policy][:name] == 'STERMAN'
      emit(*parts)
    end
    emit('PLANT', 'back', s.plant_backlog)
  end

  def fill(records)
    ordered = records.sum { |r| r[:incoming] }
    ontime = records.sum { |r| r[:ontime] }
    [ordered, ontime, ordered.zero? ? 'n/a' : decimal(ontime * 100, ordered, 2) + '%']
  end

  def peaks
    s = @sim
    emit('PEAKS', 'weeks', "1-#{s.week}")
    s.stages.each_with_index do |stage, i|
      inventories = stage[:records].map { |r| r[:inventory] }
      backlogs = stage[:records].map { |r| r[:backlog] }
      mi = inventories.max
      mb = backlogs.max
      run = 0
      longest = 0
      start = 0
      best_start = 0
      best_end = 0
      backlogs.each_with_index do |backlog, j|
        if backlog.positive?
          start = j + 1 if run.zero?
          run += 1
          if run > longest
            longest = run
            best_start = start
            best_end = j + 1
          end
        else
          run = 0
        end
      end
      emit(NAMES[i], 'max_inv', mi, 'week', mi.positive? ? inventories.index(mi) + 1 : '-',
           'max_back', mb, 'week', mb.positive? ? backlogs.index(mb) + 1 : '-',
           'longest_stockout', longest.positive? ? "#{longest} weeks #{best_start}-#{best_end}" : 0)
    end
  end

  def leadtime(index)
    records = @sim.stages[index][:records]
    initial = @initials[index]
    nominal = initial[:shipping] + initial[:orders]
    received = 0
    cumulative = records.map do |r|
      received += r[:received]
      received - nominal * initial[:quantity]
    end
    ordered = 0
    count = 0
    leads = []
    records.each_with_index do |r, t|
      ordered += r[:order]
      next if r[:order].zero?
      count += 1
      ((t + 1)...records.length).each do |u|
        if cumulative[u] >= ordered
          leads << u - t
          break
        end
      end
    end
    emit('LEADTIME', NAMES[index], 'nominal', nominal, 'orders', count, 'completed', leads.length,
         'open', count - leads.length, 'min', leads.empty? ? '-' : leads.min,
         'avg', leads.empty? ? '-' : decimal(leads.sum, leads.length, 2), 'max', leads.empty? ? '-' : leads.max)
  end

  def plot(index, mode, first, last)
    values = values(index, mode)[(first - 1)...last]
    maximum = values.max
    if mode == 'NET'
      emit('PLOT', NAMES[index], mode, "#{first}-#{last}", 'min', values.min, 'max', maximum)
      scale = values.map(&:abs).max
      values.each_with_index do |value, i|
        length = scale.zero? ? 0 : value.abs * 25 / scale
        left = value.negative? ? ' ' * (25 - length) + '-' * length : ' ' * 25
        right = value.positive? ? '+' * length : ''
        emit(format('%3d', first + i) + " #{left}|#{right} #{value}")
      end
    else
      emit('PLOT', NAMES[index], mode, "#{first}-#{last}", 'max', maximum)
      values.each_with_index do |value, i|
        length = maximum.zero? ? 0 : value * 50 / maximum
        emit(format('%3d', first + i) + ' |' + '#' * length + " #{value}")
      end
    end
  end

  def command(cmd, a)
    s = @sim
    case cmd
    when 'DEMAND'
      demand(a.map(&:to_i))
    when 'GENERATE'
      generate(a)
    when 'RUN'
      raise CommandError, "horizon reached at week #{s.demands.length}" if s.week == s.demands.length
      first = s.week + 1
      count = [a[0].to_i, s.demands.length - s.week].min
      cost = 0
      count.times do
        s.step.each_with_index do |r, i|
          cost += r[:cost]
          if r[:before].zero? && r[:backlog].positive?
            emit('STOCKOUT', NAMES[i], 'week', s.week, 'backlog', r[:backlog])
          elsif r[:before].positive? && r[:backlog].zero?
            emit('RECOVER', NAMES[i], 'week', s.week)
          end
        end
      end
      emit('RUN', "#{first}-#{s.week}", 'demand', s.demands[(first - 1)...s.week].sum, 'cost', money(cost))
      emit('HORIZON', s.week) if s.week == s.demands.length
    when 'RESET'
      initialize_sim
      emit('RESET', 'week', 0)
    when 'SAVE'
      @snapshots[a[0]] = Marshal.dump(s)
      emit('SAVE', a[0], 'week', s.week)
    when 'LOAD'
      raise CommandError, "no snapshot #{a[0]}" unless @snapshots.key?(a[0])
      @sim = Marshal.load(@snapshots[a[0]])
      emit('LOAD', a[0], 'week', @sim.week)
    when 'SET'
      indices = target(a[0])
      policy = parse_policy(a.drop(1))
      indices.each { |i| s.set_policy(i, policy) }
      emit('SET', a[0], policy[:text])
    when 'BATCH'
      i = stage_index(a[0])
      lot = a[1].to_i
      raise CommandError, "invalid batch size #{a[1]}" unless (1..100).cover?(lot)
      s.stages[i][:lot] = lot
      emit('BATCH', a[0], lot)
    when 'CAPACITY'
      i = a[0] == 'PLANT' ? nil : stage_index(a[0])
      capacity = a[1] == 'OFF' ? nil : a[1].to_i
      raise CommandError, "invalid capacity #{a[1]}" if capacity && capacity > 10000
      if i.nil?
        s.plant_capacity = capacity
      else
        s.stages[i][:capacity] = capacity
      end
      emit('CAPACITY', a[0], a[1])
    when 'COST'
      i = stage_index(a[0])
      holding, backlog = a.drop(1).map(&:to_i)
      raise CommandError, 'invalid cost' if holding > 1000 || backlog > 1000
      s.stages[i][:holding] = holding
      s.stages[i][:backlog_rate] = backlog
      emit('COST', a[0], 'holding', holding, 'backlog', backlog)
    when 'VISIBILITY'
      raise CommandError, "unknown visibility #{a[0]}" unless %w[ON OFF].include?(a[0])
      s.visibility = a[0]
      emit('VISIBILITY', a[0])
    when 'SHOCK'
      week, demand = a.map(&:to_i)
      raise CommandError, "week #{a[0]} outside horizon" unless (1..s.demands.length).cover?(week)
      raise CommandError, "week #{a[0]} already simulated" if week <= s.week
      old = s.demands[week - 1]
      s.demands[week - 1] = demand
      emit('SHOCK', 'week', week, old, '->', demand)
    when 'STATUS'
      status
    when 'SETTINGS'
      emit('SETTINGS')
      s.stages.each_with_index do |stage, i|
        emit(NAMES[i], 'holding', stage[:holding], 'backlog', stage[:backlog_rate], 'batch', stage[:lot],
             'capacity', stage[:capacity].nil? ? 'OFF' : stage[:capacity],
             'delays', @initials[i][:shipping], @initials[i][:orders])
      end
      emit('PLANT', 'capacity', s.plant_capacity.nil? ? 'OFF' : s.plant_capacity)
      emit('VISIBILITY', s.visibility)
    when 'WEEK'
      require_weeks
      week = a[0].to_i
      raise CommandError, "bad week #{a[0]}" unless (1..s.week).cover?(week)
      emit('WEEK', week, 'demand', s.demands[week - 1])
      s.stages.each_with_index do |stage, i|
        r = stage[:records][week - 1]
        emit(NAMES[i], 'recv', r[:received], 'in', r[:incoming], 'ship', r[:shipped],
             'inv', r[:inventory], 'back', r[:backlog], 'order', r[:order], 'cost', money(r[:cost]))
      end
      p = s.plant_records[week - 1]
      emit('PLANT', 'in', p[:incoming], 'made', p[:produced], 'back', p[:backlog])
    when 'TABLE'
      i = stage_index(a[0])
      require_weeks
      first, last = range_check(a.drop(1), s.week)
      emit('TABLE', a[0], "#{first}-#{last}")
      widths = [4, 6, 6, 6, 6, 6, 6, 9]
      emit(%w[week in ship recv inv back order cost].zip(widths).map { |v, width| v.rjust(width) }.join(' '))
      (first..last).each do |week|
        r = s.stages[i][:records][week - 1]
        values = [week, r[:incoming], r[:shipped], r[:received], r[:inventory], r[:backlog], r[:order], money(r[:cost])]
        emit(values.zip(widths).map { |v, width| v.to_s.rjust(width) }.join(' '))
      end
    when 'CHAIN'
      require_weeks
      first, last = range_check(a, s.week)
      emit('CHAIN', "#{first}-#{last}")
      emit('week'.rjust(4) + ' ' + 'demand'.rjust(6) + ' ' + NAMES.map { |n| n.rjust(11) }.join(' '))
      (first..last).each do |week|
        orders = s.stages.map { |stage| stage[:records][week - 1][:order].to_s.rjust(11) }.join(' ')
        emit(week.to_s.rjust(4) + ' ' + s.demands[week - 1].to_s.rjust(6) + ' ' + orders)
      end
    when 'DEMANDS'
      first, last = range_check(a, s.demands.length)
      values = s.demands[(first - 1)...last]
      emit('DEMANDS', "#{first}-#{last}", 'total', values.sum, 'min', values.min, 'max', values.max)
      emit(*values)
    when 'COSTS'
      emit('COSTS', 'week', s.week)
      total_holding = 0
      total_backlog = 0
      s.stages.each_with_index do |stage, i|
        holding = stage[:records].sum { |r| r[:holding] }
        backlog = stage[:records].sum { |r| r[:backlog_cost] }
        total_holding += holding
        total_backlog += backlog
        emit(NAMES[i], 'holding', money(holding), 'backlog', money(backlog), 'total', money(holding + backlog))
      end
      emit('TOTAL', 'holding', money(total_holding), 'backlog', money(total_backlog), 'total', money(total_holding + total_backlog))
    when 'SUMMARY'
      require_weeks
      emit('SUMMARY', 'weeks', "1-#{s.week}")
      s.stages.each_with_index do |stage, i|
        orders = stage[:records].map { |r| r[:order] }
        emit(NAMES[i], 'avg_inv', decimal(stage[:records].sum { |r| r[:inventory] }, s.week, 2),
             'avg_back', decimal(stage[:records].sum { |r| r[:backlog] }, s.week, 2),
             'orders', orders.sum, 'min', orders.min, 'max', orders.max, 'zero_weeks', orders.count(0))
      end
    when 'BALANCE'
      emit('BALANCE', 'week', s.week)
      s.stages.each_with_index do |stage, i|
        emit(NAMES[i], 'start', @initials[i][:inventory], 'received', stage[:records].sum { |r| r[:received] },
             'shipped', stage[:records].sum { |r| r[:shipped] }, 'end', stage[:inventory], 'owed', stage[:backlog])
      end
      initial = @initials.sum { |i| i[:inventory] + i[:quantity] * i[:shipping] }
      emit('SYSTEM', 'initial', initial, 'produced', s.plant_records.sum { |r| r[:produced] },
           'delivered', s.stages[0][:records].sum { |r| r[:shipped] }, 'stock', s.stages.sum { |stage| stage[:inventory] },
           'transit', s.stages.sum { |stage| stage[:shipping].sum })
    when 'FILLRATE'
      require_weeks
      emit('FILLRATE', 'weeks', "1-#{s.week}")
      s.stages.each_with_index do |stage, i|
        ordered, ontime, text = fill(stage[:records])
        stockouts = stage[:records].count { |r| r[:backlog].positive? }
        emit(NAMES[i], 'fill', text, 'ontime', ontime, 'ordered', ordered, 'stockout_weeks', stockouts,
             'service', decimal((s.week - stockouts) * 100, s.week, 2) + '%')
      end
    when 'BULLWHIP'
      require_weeks
      n = s.week
      demands = s.demands.first(n)
      dv = variation(demands)
      emit('BULLWHIP', 'weeks', "1-#{n}", 'demand', 'mean', decimal(demands.sum, n, 4), 'var', decimal(dv, n * n, 4))
      previous = dv
      s.stages.each_with_index do |stage, i|
        values = stage[:records].map { |r| r[:order] }
        v = variation(values)
        emit(NAMES[i], 'mean', decimal(values.sum, n, 4), 'var', decimal(v, n * n, 4),
             'ratio', dv.zero? ? 'n/a' : decimal(v, dv, 4), 'step', previous.zero? ? 'n/a' : decimal(v, previous, 4))
        previous = v
      end
    when 'PEAKS'
      require_weeks
      peaks
    when 'LEADTIME'
      i = stage_index(a[0])
      require_weeks
      leadtime(i)
    when 'PLOT', 'HISTOGRAM'
      i = stage_index(a[0])
      mode_check(a[1])
      width = cmd == 'HISTOGRAM' ? a[2].to_i : 1
      raise CommandError, "invalid width #{a[2]}" if cmd == 'HISTOGRAM' && !(1..100).cover?(width)
      require_weeks
      if cmd == 'PLOT'
        plot(i, a[1], *range_check(a.drop(2), s.week))
      else
        bins = values(i, a[1]).map { |value| value.div(width) }.tally
        emit('HISTOGRAM', a[0], a[1], 'width', width, 'weeks', "1-#{s.week}")
        (bins.keys.min..bins.keys.max).each do |bucket|
          count = bins.fetch(bucket, 0)
          emit("#{bucket * width}..#{bucket * width + width - 1}", count, *(count.positive? ? ['*' * count] : []))
        end
      end
    when 'COMPARE'
      policies = []
      start = 0
      (0..a.length).each do |finish|
        next unless finish == a.length || a[finish] == '/'
        policies << parse_policy(a[start...finish])
        start = finish + 1
      end
      rows = policies.each_with_index.map do |policy, index|
        trial = trial([policy] * 4)
        cost = trial.costs.sum
        text = fill(trial.stages[0][:records])[2]
        dv = variation(trial.demands)
        fv = variation(trial.stages[3][:records].map { |r| r[:order] })
        [cost, index, policy[:text], text, dv.zero? ? 'n/a' : decimal(fv, dv, 4)]
      end
      emit('COMPARE', policies.length, 'weeks', s.demands.length)
      rows.sort_by { |cost, index, _, _, _| [cost, index] }.each_with_index do |(cost, _, policy, text, ratio), i|
        emit(i + 1, policy, 'total', money(cost), 'fill', text, 'bullwhip', ratio)
      end
    when 'OPTIMIZE'
      indices = target(a[0])
      low, high = a.drop(1).map(&:to_i)
      raise CommandError, "bad range #{a[1]} #{a[2]}" if low > high
      raise CommandError, 'range too large' if high - low > 200
      best = nil
      (low..high).each do |target|
        policies = s.stages.map { |stage| stage[:policy] }
        indices.each { |i| policies[i] = {name: 'BASESTOCK', args: [target], text: "BASESTOCK #{target}"} }
        costs = trial(policies).costs
        objective = indices.sum { |i| costs[i] }
        best = [objective, target, costs.sum] if best.nil? || objective < best[0]
      end
      emit('OPTIMIZE', a[0], 'BASESTOCK', best[1], 'cost', money(best[0]), 'total', money(best[2]))
    else
      raise CommandError, "unknown command #{cmd}"
    end
  end

  def execute(line)
    cmd, *args = line.split
    begin
      command(cmd, args)
    rescue CommandError => error
      emit('ERROR', error.message)
    end
  end
end

settings = Array.new(4) { STDIN.gets.split }
game = Game.new(settings)
STDIN.each_line do |line|
  line = line.chomp
  break if line == 'END'
  game.execute(line)
end
STDOUT.write(game.output.join("\n") + "\n") unless game.output.empty?
