POLICIES = %w[COST NEAREST ROUND ETA].freeze
CONFIG_KEYS = %w[FLOORS CARS CAPACITY DOOR START POLICY ZONES PARK PATIENCE BYPASS PERIOD LIMIT COMPARE].freeze
ARG_COUNTS = {'CALL'=>3,'CANCEL'=>1,'OUT'=>1,'IN'=>1,'HOLD'=>2,'FIRE'=>1,'RESET'=>0,'WHERE'=>1,'STATUS'=>0}.freeze
class ConfigError < StandardError
end
def sign(x) = x <=> 0
def joined(items) = items.empty? ? '-' : items.join(',')
def average(total, count)
  return '-' if count.zero?
  n = total * 100 / count
  "#{n / 100}.#{(n % 100).to_s.rjust(2, '0')}"
end
def config_error(bad, message) = (raise ConfigError, message if bad)
def parse_config(lines)
  entries = {}
  lines.each do |key, *vs|
    config_error(!CONFIG_KEYS.include?(key), "unknown key #{key}")
    config_error(entries.key?(key), "duplicate key #{key}")
    entries[key] = vs
  end
  CONFIG_KEYS.take(5).each { |k| config_error(!entries.key?(k), "missing key #{k}") }
  c = {'POLICY'=>'COST','BYPASS'=>100,'LIMIT'=>1000,'COMPARE'=>[]}
  CONFIG_KEYS.each do |k|
    next unless entries.key?(k)
    vs = entries[k]
    e = c['CARS']
    f = c['FLOORS']
    valid_count = case k
    when 'START', 'ZONES'
      vs.length == e
    when 'PARK'
      vs.length == e + 1
    when 'COMPARE'
      (1..4).include?(vs.length)
    else
      vs.length == 1
    end
    config_error(!valid_count, "wrong number of values for #{k}")
    ranges = {'FLOORS'=>2..50,'CARS'=>1..8,'CAPACITY'=>1..20,'DOOR'=>1..9,'PATIENCE'=>1..1000,'BYPASS'=>50..100,'PERIOD'=>1..1000,'LIMIT'=>1..5000}
    if ranges.key?(k)
      n = vs[0].to_i
      config_error(!ranges[k].include?(n), "bad value for #{k}")
      c[k] = n
    elsif k == 'POLICY'
      config_error(!POLICIES.include?(vs[0]), "bad value for #{k}")
      c[k] = vs[0]
    elsif k == 'COMPARE'
      config_error(vs.uniq.length != vs.length || vs.any? { |v| !POLICIES.include?(v) }, "bad value for #{k}")
      c[k] = vs
    elsif k == 'ZONES'
      zs = vs.map { |v| v.split(':').map(&:to_i) }
      config_error(zs.any? { |a, b| !(1 <= a && a < b && b <= f) }, "bad value for #{k}")
      c[k] = zs
    else
      ns = vs.map(&:to_i)
      valid = k == 'PARK' ? (0..100).include?(ns[0]) && ns.drop(1).all? { |n| (1..f).include?(n) } : ns.all? { |n| (1..f).include?(n) }
      config_error(!valid, "bad value for #{k}")
      c[k] = ns
    end
  end
  c['ZONES'] ||= Array.new(c['CARS']) { [1, c['FLOORS']] }
  c['CARS'].times do |i|
    a, b = c['ZONES'][i]
    config_error(!(a..b).include?(c['START'][i]), "car #{i + 1} starts outside its zone")
    config_error(c['PARK'] && !(a..b).include?(c['PARK'][i + 1]), "car #{i + 1} home outside its zone")
  end
  c
end
def validate_events(c, lines)
  accepted = []
  last = groups = 0
  out = []
  fire = false
  lines.each do |line_number, words|
    time = words[0].to_i
    cmd = words[1]
    args = words.drop(2)
    v = args.map(&:to_i)
    error = nil
    if !ARG_COUNTS.key?(cmd)
      error = "unknown command #{cmd}"
    elsif args.length != ARG_COUNTS[cmd]
      error = "wrong number of arguments for #{cmd}"
    elsif time < last
      error = 'time goes backwards'
    else
      case cmd
      when 'CALL'
        a, b, n = v
        error = if !((1..c['FLOORS']).include?(a) && (1..c['FLOORS']).include?(b))
          'bad floor'
        elsif a == b
          'same floor'
        elsif !(1..99).include?(n)
          'bad count'
        elsif !c['ZONES'].any? { |lo, hi| (lo..hi).include?(a) && (lo..hi).include?(b) }
          "no car serves #{a}->#{b}"
        elsif fire
          'fire service active'
        end
      when 'CANCEL', 'WHERE'
        error = 'unknown group' unless (1..groups).include?(v[0])
      when 'OUT', 'IN'
        error = if !(1..c['CARS']).include?(v[0])
          'bad car'
        elsif cmd == 'OUT' && out.include?(v[0])
          "car #{v[0]} already out"
        elsif cmd == 'IN' && !out.include?(v[0])
          "car #{v[0]} already in"
        end
      when 'HOLD'
        error = !(1..c['CARS']).include?(v[0]) ? 'bad car' : !(1..9).include?(v[1]) ? 'bad ticks' : nil
      when 'FIRE'
        error = !(1..c['FLOORS']).include?(v[0]) ? 'bad floor' : fire ? 'fire already active' : nil
      when 'RESET'
        error = 'fire not active' unless fire
      end
    end
    if error
      puts "line #{line_number}: #{error}"
      next
    end
    accepted << [time, cmd, v]
    last = time
    case cmd
    when 'CALL'
      groups += 1
    when 'OUT'
      out << v[0]
    when 'IN'
      out.delete(v[0])
    when 'FIRE'
      fire = true
    when 'RESET'
      fire = false
    end
  end
  accepted
end
Group = Struct.new(:number, :a, :b, :count, :time, :waiting, :car, :boarded, :delivered, :lost, :last_board, :last_alight, :cars, :wait_total, :travel_total) do
  def label = "G#{number}"
  def direction = sign(b - a)
end
Passenger = Struct.new(:group, :count, :board_time)
Car = Struct.new(:number, :floor, :zone, :home, :direction, :door, :passengers, :calls, :service, :idle, :distance, :stops, :boarded, :busy, :energy) do
  def label = "E#{number}"
  def load = passengers.sum(&:count)
  def targets = (passengers.map { |p| p.group.b } + calls.map(&:a)).uniq
  def serves?(g) = (zone[0]..zone[1]).include?(g.a) && (zone[0]..zone[1]).include?(g.b)
end
class Simulation
  attr_reader :groups, :cars, :time, :status, :delivered, :wait_total, :travel_total, :policy
  def initialize(c, events, policy, logging)
    @c, @events, @policy, @logging = c, events, policy, logging
    @cars = c['CARS'].times.map { |i| Car.new(i + 1, c['START'][i], c['ZONES'][i], c['PARK']&.[](i + 1), 0, 0, [], [], true, 0, 0, 0, 0, 0, 0) }
    @groups, @pending = [], []
    @fire = nil
    @round = @time = @delivered = @wait_total = @travel_total = @max_wait = @abandoned = @evacuated = 0
    run
  end
  def emit(*parts)
    puts([@time, *parts].join(' ')) if @logging
  end
  def bypass?(car) = car.load * 100 >= @c['CAPACITY'] * @c['BYPASS']
  def cost(car, g)
    f, d, x = car.floor, car.direction, g.a
    return (f - x).abs if @policy == 'NEAREST' || d.zero?
    ts = car.targets
    if g.direction == d && (x - f) * d >= 0
      distance = (x - f).abs
      via = ts.count { |y| (y - f) * d > 0 && (x - y) * d > 0 }
    else
      m = d > 0 ? (ts + [f]).max : (ts + [f]).min
      distance = (f - m).abs + (m - x).abs
      via = ts.count { |y| (y - f) * d > 0 }
    end
    distance + (@policy == 'ETA' ? @c['DOOR'] * via + car.door : 0)
  end
  def assign(g, excluded = nil)
    candidates = @cars.select { |car| car.service && car != excluded && car.serves?(g) }
    return false if candidates.empty?
    if @policy == 'ROUND'
      chosen = candidates.find { |car| car.number > @round } || candidates.first
      @round = chosen.number
      emit(chosen.label, 'ASSIGN', g.label)
    else
      chosen = candidates.min_by { |car| [cost(car, g), car.number] }
      emit(chosen.label, 'ASSIGN', g.label, "cost=#{cost(chosen, g)}")
    end
    g.car.calls.delete(g) if g.car
    chosen.calls << g
    g.car = chosen
    true
  end
  def dispatch(g)
    return if assign(g)
    @pending << g
    emit('PENDING', g.label)
  end
  def walk(g, word)
    g.car ? g.car.calls.delete(g) : @pending.delete(g)
    g.car = nil
    emit(word, g.label, "x#{g.waiting}")
    g.lost += g.waiting
    @abandoned += g.waiting
    g.waiting = 0
  end
  def event(cmd, v)
    case cmd
    when 'CALL'
      a, b, n = v
      g = Group.new(@groups.length + 1, a, b, n, @time, n, nil, 0, 0, 0, 0, 0, [], 0, 0)
      @groups << g
      emit(cmd, g.label, "#{a}->#{b}", "x#{n}")
      dispatch(g)
    when 'CANCEL'
      g = @groups[v[0] - 1]
      g.waiting > 0 ? walk(g, cmd) : emit(cmd, g.label, 'ignored')
    when 'OUT'
      car = @cars[v[0] - 1]
      car.service = false
      emit(car.label, cmd)
      calls = car.calls
      car.calls = []
      calls.each { |g| g.car = nil
        dispatch(g) }
    when 'IN'
      car = @cars[v[0] - 1]
      car.service = true
      car.idle = @time
      emit(car.label, cmd)
      pending = @pending
      @pending = []
      pending.each { |g| @pending << g unless assign(g) }
    when 'HOLD'
      car = @cars[v[0] - 1]
      car.door += v[1] if car.door > 0
      emit(car.label, cmd, car.door > 0 ? car.door : 'ignored')
    when 'FIRE'
      @fire = v[0]
      emit(cmd, @fire)
      @groups.each { |g| walk(g, 'ABANDON') if g.waiting > 0 }
    when 'RESET'
      @fire = nil
      emit(cmd)
      @cars.each { |car| car.idle = @time }
    when 'WHERE'
      g = @groups[v[0] - 1]
      place = g.waiting.zero? ? '-' : g.car ? g.car.label : 'pending'
      riding = @cars.filter_map { |car| n = car.passengers.sum { |p| p.group == g ? p.count : 0 }
        "#{car.label}x#{n}" if n > 0 }
      emit(cmd, g.label, "waiting=#{g.waiting}", "car=#{place}", "riding=#{joined(riding)}", "delivered=#{g.delivered}", "lost=#{g.lost}")
    when 'STATUS'
      @cars.each do |car|
        emit(cmd, car.label, "floor=#{car.floor}", "dir=#{ {1=>'up', -1=>'down', 0=>'idle'}[car.direction] }", "door=#{car.door}", "load=#{car.load}", "stops=#{joined(car.passengers.map { |p| p.group.b }.uniq.sort)}", "calls=#{joined(car.calls.map(&:label))}", "service=#{car.service ? 'in' : 'out'}")
      end
      emit(cmd, "pending=#{joined(@pending.map(&:label))}")
    end
  end
  def heading(car)
    f, d = car.floor, car.direction
    here = bypass?(car) ? [] : car.calls.select { |g| g.a == f }
    ts = car.targets
    return d if d != 0 && (ts.any? { |y| (y - f) * d > 0 } || here.any? { |g| g.direction == d })
    return here.first.direction unless here.empty?
    return -d if d != 0 && ts.any? { |y| (y - f) * d < 0 }
    return sign(car.calls.first.a - f) if d.zero? && !car.calls.empty?
    0
  end
  def move(car, n)
    car.energy += n > 0 ? 3 + car.load : 1
    car.floor += n
    car.distance += 1
  end
  def deliver(p)
    g = p.group
    w, r = p.board_time - g.time, @time - g.time
    g.delivered += p.count
    g.last_alight = @time
    g.wait_total += w * p.count
    g.travel_total += r * p.count
    @delivered += p.count
    @wait_total += w * p.count
    @travel_total += r * p.count
    @max_wait = [@max_wait, w].max
  end
  def open(car)
    emit(car.label, 'OPEN', car.floor)
    car.door = @c['DOOR']
    car.stops += 1
    car.energy += 2
    riding = []
    car.passengers.each do |p|
      if p.group.b == car.floor
        emit(car.label, 'ALIGHT', p.group.label, "x#{p.count}")
        deliver(p)
      elsif @fire
        emit(car.label, 'EVACUATE', p.group.label, "x#{p.count}")
        p.group.lost += p.count
        @evacuated += p.count
      else
        riding << p
      end
    end
    car.passengers = riding
    return if @fire
    n = heading(car)
    car.direction = n unless n.zero?
    car.calls.select { |g| g.a == car.floor && g.direction == n }.each do |g|
      k = [@c['CAPACITY'] - car.load, g.waiting].min
      if k > 0
        car.passengers << Passenger.new(g, k, @time)
        car.boarded += k
        g.waiting -= k
        g.boarded += k
        g.last_board = @time
        g.cars |= [car.number]
        emit(car.label, 'BOARD', g.label, "x#{k}")
      end
      if g.waiting.zero?
        car.calls.delete(g)
        g.car = nil
      else
        emit(car.label, 'LEFT', g.label, "x#{g.waiting}")
        assign(g, car)
      end
    end
  end
  def advance(car)
    old = car.floor
    car.door -= 1 if car.door > 0
    if car.door.zero?
      n = @fire ? sign(@fire - car.floor) : heading(car)
      stop = @fire ? n.zero? && !car.passengers.empty? : car.passengers.any? { |p| p.group.b == car.floor } || (!bypass?(car) && car.calls.any? { |g| g.a == car.floor && g.direction == n })
      if stop
        open(car)
      elsif n != 0
        car.direction = n
        move(car, n)
      else
        if car.direction != 0
          emit(car.label, 'IDLE', car.floor)
          car.direction = 0
          car.idle = @time
        end
        if !@fire && car.service && car.home && car.floor != car.home && @time - car.idle >= @c['PARK'][0]
          move(car, sign(car.home - car.floor))
          emit(car.label, 'PARK', car.home) if car.floor == car.home
        end
      end
    end
    car.busy += 1 if car.door > 0 || old != car.floor
  end
  def settled?(car)
    car.door.zero? && car.passengers.empty? && car.calls.empty? && (@fire ? car.floor == @fire : !car.service || !car.home || car.floor == car.home)
  end
  def run
    index = 0
    loop do
      @groups.each { |g| walk(g, 'ABANDON') if g.waiting > 0 && @c['PATIENCE'] && @time == g.time + @c['PATIENCE'] }
      while index < @events.length && @events[index][0] == @time
        _, cmd, v = @events[index]
        event(cmd, v)
        index += 1
      end
      @cars.each { |car| advance(car) }
      if index == @events.length && @cars.all? { |car| settled?(car) }
        @status = 'end'
        emit('END')
        break
      end
      if @time == @c['LIMIT']
        @status = 'abort'
        emit('ABORT')
        break
      end
      @time += 1
    end
  end
  def averages = "avg_wait=#{average(@wait_total, @delivered)} avg_travel=#{average(@travel_total, @delivered)} max_wait=#{@delivered.zero? ? '-' : @max_wait}"
  def breakdown(label, gs)
    "#{label}: groups=#{gs.length} passengers=#{gs.sum(&:count)} delivered=#{gs.sum(&:delivered)} avg_wait=#{average(gs.sum(&:wait_total), gs.sum(&:delivered))}"
  end
  def report
    @groups.each do |g|
      puts "#{g.label} t=#{g.time} #{g.a}->#{g.b} n=#{g.count} delivered=#{g.delivered} lost=#{g.lost} wait=#{g.boarded == g.count ? g.last_board - g.time : '-'} travel=#{g.delivered == g.count ? g.last_alight - g.time : '-'} cars=#{joined(g.cars.sort)}"
    end
    @cars.each do |car|
      n = car.busy * 1000 / (@time + 1)
      puts "#{car.label} distance=#{car.distance} stops=#{car.stops} boarded=#{car.boarded} busy=#{car.busy} util=#{n / 10}.#{n % 10}% energy=#{car.energy}"
    end
    @groups.group_by(&:a).sort.each { |f, gs| puts breakdown("F#{f}", gs) }
    if (w = @c['PERIOD'])
      @groups.group_by { |g| g.time / w }.sort.each { |k, gs| puts breakdown("P#{k} #{k * w}-#{k * w + w - 1}", gs) }
    end
    puts "summary: groups=#{@groups.length} passengers=#{@groups.sum(&:count)} delivered=#{@delivered} abandoned=#{@abandoned} evacuated=#{@evacuated} #{averages} end=#{@time}"
  end
end
lines = STDIN.read.lines.map(&:chomp)
index = 1
scenarios = []
lines[0].to_i.times do |ordinal|
  name = lines[index].split[1]
  index += 1
  settings, events = [], []
  until lines[index] == 'END'
    words = lines[index].split
    words[0].match?(/\A\d/) ? events << [index + 1, words] : settings << words
    index += 1
  end
  index += 1
  puts "== #{name} =="
  begin
    c = parse_config(settings)
    puts "config: floors=#{c['FLOORS']} cars=#{c['CARS']} capacity=#{c['CAPACITY']} door=#{c['DOOR']} policy=#{c['POLICY']} park=#{c['PARK'] ? c['PARK'][0] : 'off'} patience=#{c['PATIENCE'] || 'off'} bypass=#{c['BYPASS']} period=#{c['PERIOD'] || 'off'} limit=#{c['LIMIT']} compare=#{joined(c['COMPARE'])}"
    c['CARS'].times { |i| puts "E#{i + 1}: start=#{c['START'][i]} zone=#{c['ZONES'][i].join('-')} home=#{c['PARK'] ? c['PARK'][i + 1] : '-'}" }
    accepted = validate_events(c, events)
    sim = Simulation.new(c, accepted, c['POLICY'], true)
    sim.report
    scenarios << [name, c, sim, ordinal]
    c['COMPARE'].each do |policy|
      other = Simulation.new(c, accepted, policy, false)
      puts "compare #{policy}: delivered=#{other.delivered} #{other.averages} end=#{other.time} status=#{other.status}"
    end
  rescue ConfigError => e
    puts "error: #{e.message}"
    scenarios << [name, nil, nil, ordinal]
  end
end
puts '== ranking =='
ranked = scenarios.select { |_, _, s, _| s && s.status == 'end' && s.delivered > 0 }.sort do |x, y|
  a, b = x[2], y[2]
  (a.wait_total * b.delivered <=> b.wait_total * a.delivered).nonzero? || (a.travel_total * b.delivered <=> b.travel_total * a.delivered).nonzero? || x[3] <=> y[3]
end
ranked.each_with_index { |(name, c, s, _), i| puts "#{i + 1}. #{name} policy=#{c['POLICY']} #{s.averages}" }
scenarios.each do |name, _, s, _|
  next if s && s.status == 'end' && s.delivered > 0
  puts "- #{name} #{!s ? 'invalid' : s.status == 'abort' ? 'aborted' : 'empty'}"
end
puts '== policies =='
POLICIES.each do |p|
  ss = ranked.select { |_, c, _, _| c['POLICY'] == p }.map { |v| v[2] }
  next if ss.empty?
  puts "#{p}: runs=#{ss.length} avg_wait=#{average(ss.sum(&:wait_total), ss.sum(&:delivered))} avg_travel=#{average(ss.sum(&:travel_total), ss.sum(&:delivered))}"
end
