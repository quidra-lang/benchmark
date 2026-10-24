ALGORITHMS = %w[FCFS SJF SRTF RR PRIORITY HRRN EDF LOTTERY MLFQ].freeze
KEYS = %w[cs q k s seed].freeze
RANGES = {'cs'=>0..5,'q'=>1..20,'k'=>1..50,'s'=>0..500,'seed'=>1..2147483646}.freeze
DEFAULTS = {'cs'=>0,'q'=>4,'k'=>5,'s'=>0,'seed'=>1}.freeze
METRICS = %w[turnaround waiting response].freeze
EVENTS = %w[PREEMPT EXPIRE DEMOTE BOOST AGE].freeze
SYMBOLS = {'FUTURE'=>'-','DONE'=>'-','RUN'=>'#','SWITCH'=>'s','READY'=>'.','IO'=>'i'}.freeze
class CommandError < StandardError
end
def allowed(a) = ['cs'] + ({'RR'=>['q'],'LOTTERY'=>%w[q seed],'PRIORITY'=>['k'],'MLFQ'=>['s']}[a] || [])
def notation(p, a = nil) = (a ? allowed(a) : KEYS).map { |k| "#{k}=#{p[k]}" }.join(' ')
def truncated(u, v)
  n = u * 100 / v
  "#{n / 100}.#{(n % 100).to_s.rjust(2, '0')}"
end
def fail_if(bad, reason) = (raise CommandError, reason if bad)
def params(words, a = nil, preset = [])
  p = DEFAULTS.dup
  seen = preset.dup
  words.each do |word|
    k, text = word.split('=')
    v = text.to_i
    fail_if(!RANGES.key?(k), "unknown key #{k}")
    fail_if(a && !allowed(a).include?(k), "key #{k} not allowed for #{a}")
    fail_if(seen.include?(k), "duplicate key #{k}")
    fail_if(!RANGES[k].include?(v), "invalid #{k}")
    seen << k
    p[k] = v
  end
  p
end
ProcessDef = Struct.new(:id, :arrival, :priority, :bursts, :deadline) do
  def describe = "#{id} arrival=#{arrival} priority=#{priority} deadline=#{deadline || 'none'} bursts=#{bursts.each_with_index.map { |n, i| "#{i.even? ? 'C' : 'I'}#{n}" }.join(',')}"
end
Burst = Struct.new(:length, :ready, :start, :finish, :slices)
Job = Struct.new(:process, :state, :burst, :left, :effective, :wait, :level, :used, :enqueued, :start, :finish, :records, :timeline) do
  def id = process.id
  def deadline = process.deadline && process.arrival + process.deadline
  def metrics
    turn = finish - process.arrival
    [turn, turn - process.bursts.sum, start - process.arrival]
  end
  def slices = records.sum(&:slices)
  def missed? = deadline && finish > deadline
end
class Simulation
  attr_reader :jobs, :events, :counts, :labels, :states, :lengths, :snapshot, :time, :switches
  def initialize(processes, algo, p, snapshot_time = nil)
    @a, @p, @snapshot_time = algo, p, snapshot_time
    @jobs = processes.sort_by(&:id).map { |d| Job.new(d, 'FUTURE', 0, d.bursts[0], d.priority, 0, 0, 0, 0, nil, nil, [], '') }
    @queues = [[], [], []]
    @cpu = 'IDLE'
    @current = @previous = nil
    @switch_left = @run = @switches = 0
    @random = p['seed']
    @events = []
    @counts = Hash.new(0)
    @labels, @states, @lengths = [], [], []
    @time = 0
    simulate
  end
  def record(kind, *details)
    @events << [@time, kind, *details].join(' ')
    @counts[kind] += 1
  end
  def enqueue(j)
    j.state = 'READY'
    j.enqueued = @time
    @queues[j.level] << j
  end
  def advance(j) = (j.burst += 1; j.left = j.process.bursts[j.burst])
  def release = (@cpu = 'IDLE'; @current = nil)
  def start(j)
    @cpu, @current, @run, j.state = 'RUN', j, 0, 'RUN'
    j.start ||= @time
    j.records.last.start ||= @time
  end
  def preempts?(j)
    case @a
    when 'SRTF'
      @queues[0].any? { |x| x.left < j.left }
    when 'PRIORITY'
      @queues[0].any? { |x| x.effective < j.effective }
    when 'EDF'
      @queues[0].any? { |x| x.deadline && (!j.deadline || x.deadline < j.deadline) }
    when 'MLFQ'
      @queues.take(j.level).any? { |q| !q.empty? }
    else
      false
    end
  end
  def choose(q)
    case @a
    when 'SJF', 'SRTF'
      q.min_by(&:left)
    when 'PRIORITY'
      q.min_by(&:effective)
    when 'EDF'
      q.select(&:deadline).min_by(&:deadline) || q.first
    when 'HRRN'
      q.reduce { |b, j| (@time - j.enqueued + j.left) * b.left > (@time - b.enqueued + b.left) * j.left ? j : b }
    when 'LOTTERY'
      @random = 48271 * @random % 2147483647
      target = @random % q.sum { |j| 10 - j.process.priority }
      q.find { |j| target -= 10 - j.process.priority
        target < 0 }
    else
      q.first
    end
  end
  def simulate
    loop do
      if @a == 'PRIORITY'
        @queues[0].each do |j|
          j.wait += 1
          if j.wait == @p['k']
            j.wait = 0
            if j.effective > 0
              j.effective -= 1
              record('AGE', j.id, j.effective)
            end
          end
        end
      end
      @jobs.each do |j|
        if j.state == 'IO' && j.left.zero?
          advance(j)
          j.records << Burst.new(j.left, @time, nil, nil, 0)
          enqueue(j)
          record('IODONE', j.id)
        end
      end
      @jobs.each do |j|
        if j.state == 'FUTURE' && j.process.arrival == @time
          j.records << Burst.new(j.left, @time, nil, nil, 0)
          enqueue(j)
          record('ARRIVE', j.id)
        end
      end
      j = @current
      if @cpu == 'SWITCH' && @switch_left.zero?
        start(j)
        record('START', j.id)
      elsif @cpu == 'RUN'
        if j.left.zero? && j.burst == j.process.bursts.length - 1
          j.state, j.finish = 'DONE', @time
          record('DONE', j.id)
          release
        else
          demoted = @a == 'MLFQ' && j.level < 2 && j.used == [4, 8][j.level]
          if demoted
            j.level += 1
            j.used = 0
            record('DEMOTE', j.id, j.level)
          end
          if j.left.zero?
            advance(j)
            j.state = 'IO'
            record('IO', j.id, j.left)
            release
          elsif demoted
            enqueue(j)
            release
          elsif %w[RR LOTTERY].include?(@a) && @run == @p['q']
            enqueue(j)
            record('EXPIRE', j.id)
            release
          elsif preempts?(j)
            enqueue(j)
            record('PREEMPT', j.id)
            release
          end
        end
      end
      break if @jobs.all? { |x| x.state == 'DONE' }
      if @a == 'MLFQ' && @p['s'] > 0 && @time > 0 && @time % @p['s'] == 0
        @queues = [@queues.flatten, [], []]
        @jobs.each { |x| x.level = x.used = 0 }
        record('BOOST')
      end
      if @cpu == 'IDLE' && @queues.any? { |q| !q.empty? }
        q = @queues.find { |queue| !queue.empty? }
        j = choose(q)
        q.delete(j)
        j.effective, j.wait = j.process.priority, 0
        j.records.last.slices += 1
        switched = j != @previous
        @switches += 1 if switched
        if switched && @p['cs'] > 0
          @cpu, @current, @switch_left, j.state = 'SWITCH', j, @p['cs'], 'SWITCH'
          record('SWITCH', j.id)
        else
          start(j)
          record('DISPATCH', j.id)
        end
      end
      capture if @time == @snapshot_time
      @jobs.each { |x| x.timeline << SYMBOLS[x.state] }
      @lengths << @queues.sum(&:length)
      @states << @cpu
      if @cpu == 'RUN'
        j = @current
        j.left -= 1
        j.used += 1
        @run += 1
        @previous = j
        @labels << j.id
        j.records.last.finish = @time + 1 if j.left.zero?
      elsif @cpu == 'SWITCH'
        @switch_left -= 1
        @labels << 'CS'
      else
        @labels << 'IDLE'
      end
      @jobs.each { |x| x.left -= 1 if x.state == 'IO' }
      @time += 1
    end
    capture unless @snapshot
  end
  def capture
    @snapshot = [@cpu == 'IDLE' ? 'CPU IDLE' : "CPU #{@cpu} #{@current.id}"]
    (@a == 'MLFQ' ? (0..2) : [0]).each do |i|
      @snapshot << "QUEUE#{@a == 'MLFQ' ? i : ''} #{@queues[i].empty? ? 'none' : @queues[i].map(&:id).join(' ')}"
    end
    @jobs.each do |j|
      text = if j.state == 'FUTURE'
        "#{j.id} FUTURE at=#{j.process.arrival}"
      elsif j.state == 'DONE'
        "#{j.id} DONE at=#{j.finish}"
      else
        s = "#{j.id} #{j.state} burst=#{j.burst + 1} left=#{j.left}"
        s += " prio=#{j.effective}" if @a == 'PRIORITY'
        s += " level=#{j.level} used=#{j.used}" if @a == 'MLFQ'
        s
      end
      @snapshot << text
    end
  end
  def totals = (0..2).map { |i| @jobs.sum { |j| j.metrics[i] } }
  def averages = totals.map { |n| truncated(n, @jobs.length) }
  def utilization = truncated(@states.count('RUN') * 100, @time)
  def missed = @jobs.count(&:missed?)
  def met = @jobs.count { |j| j.deadline && !j.missed? }
  def ticks(a, b) = %w[RUN SWITCH IDLE].map { |s| @states[a...b].count(s) }
  def segments
    result = []
    start = 0
    (1..@time).each do |t|
      if t == @time || @labels[t] != @labels[start]
        result << "[#{start}-#{t} #{@labels[start]}]"
        start = t
      end
    end
    result
  end
end
class Scheduler
  def initialize = (@registry = {})
  def emit(*parts) = puts(parts.join(' '))
  def algorithm(a) = fail_if(!ALGORITHMS.include?(a), "unknown algorithm #{a}")
  def process(id) = @registry.fetch(id) { raise CommandError, "unknown process #{id}" }
  def prepare(words, a = nil, preset = [])
    p = params(words, a, preset)
    fail_if(@registry.empty?, 'no processes')
    p
  end
  def simulate(a, p, t = nil) = Simulation.new(@registry.values, a, p, t)
  def table(cells) = cells[0].ljust(8) + cells.drop(1).map { |v| ' ' + v.to_s.rjust(8) }.join
  def execute(line)
    c, *a = line.split
    case c
    when 'PROC'
      id, arrival, priority, *words = a
      at, pr = arrival.to_i, priority.to_i
      fail_if(@registry.key?(id), "duplicate process #{id}")
      fail_if(@registry.length >= 10, 'too many processes')
      fail_if(at > 200, "invalid arrival #{id}")
      fail_if(pr > 9, "invalid priority #{id}")
      fail_if(words.length.even? || words.each_with_index.any? { |w, i| w[0] != (i.even? ? 'C' : 'I') || !(1..30).include?(w[1..].to_i) }, "invalid bursts #{id}")
      bs = words.map { |w| w[1..].to_i }
      @registry[id] = ProcessDef.new(id, at, pr, bs, nil)
      emit(c, id, "cpu=#{bs.each_with_index.sum { |v, i| i.even? ? v : 0 }}", "io=#{bs.each_with_index.sum { |v, i| i.odd? ? v : 0 }}")
    when 'GEN'
      prefix, count, seed = a
      ids = (1..count.to_i).map { |i| prefix + i.to_s }
      ids.each { |id| fail_if(@registry.key?(id), "duplicate process #{id}") }
      fail_if(@registry.length + ids.length > 10, 'too many processes')
      emit(c, "count=#{ids.length}")
      x = seed.to_i
      draw = ->(m) { x = 48271 * x % 2147483647
        x % m }
      ids.each do |id|
        at, pr, m = draw.call(21), draw.call(10), 1 + draw.call(3)
        bs = []
        m.times { |i| bs << 1 + draw.call(8) if i > 0
          bs << 1 + draw.call(9) }
        @registry[id] = ProcessDef.new(id, at, pr, bs, nil)
        emit(@registry[id].describe)
      end
    when 'SETPRIO', 'DEADLINE'
      d = process(a[0])
      n = a[1].to_i
      fail_if(n > (c == 'SETPRIO' ? 9 : 1000), "invalid #{c == 'SETPRIO' ? 'priority' : 'deadline'} #{d.id}")
      if c == 'SETPRIO'
        d.priority = n
        emit(c, d.id, "priority=#{n}")
      else
        d.deadline = n.zero? ? nil : n
        emit(c, d.id, d.deadline || 'none')
      end
    when 'DROP'
      process(a[0])
      @registry.delete(a[0])
      emit(c, a[0])
    when 'CLEAR'
      emit(c, "count=#{@registry.length}")
      @registry.clear
    when 'LIST'
      emit(c, "count=#{@registry.length}")
      @registry.keys.sort.each { |id| emit(@registry[id].describe) }
    when 'COMPARE', 'DIFF', 'RANK'
      first = second = metric = nil
      if c == 'DIFF'
        first, second = a.shift(2)
        algorithm(first)
        algorithm(second)
      elsif c == 'RANK'
        metric = a.shift
        fail_if(!(METRICS + %w[end switches missed]).include?(metric), "unknown metric #{metric}")
      end
      p = prepare(a)
      emit(c, *[first, second, metric].compact, notation(p))
      algos = c == 'DIFF' ? [first, second] : ALGORITHMS
      sims = algos.map { |algo| simulate(algo, p) }
      if c == 'COMPARE'
        emit(table(%w[ALGO TURN WAIT RESP UTIL END SWITCH MISS]))
        sims.each_with_index { |s, i| emit(table([algos[i], *s.averages, s.utilization, s.time, s.switches, s.missed])) }
        emit('BEST', *METRICS.each_with_index.map { |m, i| "#{m}=#{algos.each_index.min_by { |j| sims[j].totals[i] }.then { |j| algos[j] }}" })
      elsif c == 'DIFF'
        wins = [0, 0, 0]
        sims[0].jobs.zip(sims[1].jobs).each do |j, k|
          x, y = j.metrics, k.metrics
          emit(j.id, *METRICS.each_with_index.map { |m, i| "#{m}=#{x[i]}/#{y[i]}" })
          wins[x[0] < y[0] ? 0 : x[0] > y[0] ? 1 : 2] += 1
        end
        emit('WINS', "#{first}=#{wins[0]}", "#{second}=#{wins[1]}", "ties=#{wins[2]}")
      else
        idx = METRICS.index(metric)
        values = sims.map { |s| idx ? s.totals[idx] : metric == 'end' ? s.time : metric == 'switches' ? s.switches : s.missed }
        algos.each_index.sort_by { |i| [values[i], i] }.each { |i| emit(1 + values.count { |v| v < values[i] }, algos[i], idx ? truncated(values[i], @registry.length) : values[i]) }
      end
    else
      algo = a.shift
      algorithm(algo)
      extra = nil
      preset = []
      if c == 'WINDOW'
        extra = a.shift.to_i
        fail_if(!(1..1000).include?(extra), 'invalid window')
      elsif c == 'SNAPSHOT'
        extra = a.shift.to_i
      elsif c == 'SWEEP'
        key, lo, hi = a.shift(3)
        lo, hi = lo.to_i, hi.to_i
        fail_if(!RANGES.key?(key), "unknown key #{key}")
        fail_if(!allowed(algo).include?(key), "key #{key} not allowed for #{algo}")
        fail_if(lo > hi || !RANGES[key].include?(lo) || !RANGES[key].include?(hi) || hi - lo > 20, 'invalid range')
        preset = [key]
      end
      p = prepare(a, algo, preset)
      if c == 'SWEEP'
        emit(c, algo, key, lo, hi)
        best = nil
        best_value = lo
        (lo..hi).each do |v|
          p[key] = v
          s = simulate(algo, p)
          av = s.averages
          emit(notation(p, algo), *METRICS.each_with_index.map { |m, i| "#{m}=#{av[i]}" }, "util=#{s.utilization}", "end=#{s.time}", "switches=#{s.switches}")
          if best.nil? || s.totals[1] < best
            best, best_value = s.totals[1], v
          end
        end
        emit('BEST', "#{key}=#{best_value}")
        return
      end
      s = simulate(algo, p, c == 'SNAPSHOT' ? extra : nil)
      fail_if(c == 'TIMELINE' && s.time > 100, "too long #{s.time}")
      suffix = c == 'TIMELINE' ? ["end=#{s.time}"] : c == 'SNAPSHOT' ? ["t=#{extra}"] : c == 'WINDOW' ? ["width=#{extra}"] : []
      emit(c, algo, notation(p, algo), *suffix)
      case c
      when 'TRACE'
        s.events.each { |v| emit(v) }
        emit('END', s.time)
      when 'SNAPSHOT'
        s.snapshot.each { |v| emit(v) }
      when 'TIMELINE'
        s.jobs.each { |j| emit(j.id.ljust(8), j.timeline) }
      when 'BURSTS'
        s.jobs.each { |j| j.records.each_with_index { |r, i| emit(j.id, "##{i + 1}", "len=#{r.length}", "ready=#{r.ready}", "start=#{r.start}", "end=#{r.finish}", "wait=#{r.finish - r.ready - r.length}", "slices=#{r.slices}") } }
      when 'WINDOW'
        (0...s.time).step(extra) do |start|
          stop = [start + extra, s.time].min
          b, cs, idle = s.ticks(start, stop)
          counts = Hash.new(0)
          (start...stop).each { |t| counts[s.labels[t]] += 1 if s.states[t] == 'RUN' }
          top = counts.keys.min_by { |id| [-counts[id], id] } || 'none'
          emit("#{start}-#{stop}", "busy=#{b}", "switch=#{cs}", "idle=#{idle}", "util=#{truncated(b * 100, stop - start)}", "top=#{top}")
        end
      when 'STATS'
        METRICS.each_with_index do |m, i|
          vs = s.jobs.map { |j| j.metrics[i] }
          sorted = vs.sort
          n = vs.length
          doubled = sorted[(n - 1) / 2] + sorted[n / 2]
          emit(m, "min=#{vs.min}", "(#{s.jobs[vs.index(vs.min)].id})", "max=#{vs.max}", "(#{s.jobs[vs.index(vs.max)].id})", "median=#{doubled / 2}.#{doubled.odd? ? 5 : 0}", "total=#{vs.sum}")
        end
      when 'RUN'
        s.segments.each_slice(8) { |g| emit('GANTT', g.join) }
        s.jobs.each do |j|
          t, w, r = j.metrics
          text = "#{j.id} arrival=#{j.process.arrival} done=#{j.finish} turnaround=#{t} waiting=#{w} response=#{r} slices=#{j.slices}"
          text += " deadline=#{j.deadline} late=#{[0, j.finish - j.deadline].max}" if j.deadline
          emit(text)
        end
        emit('AVERAGE', *METRICS.zip(s.averages).map { |m, v| "#{m}=#{v}" })
        b, cs, idle = s.ticks(0, s.time)
        emit('CPU', "end=#{s.time}", "busy=#{b}", "switch=#{cs}", "idle=#{idle}", "switches=#{s.switches}", "util=#{s.utilization}")
        emit('QUEUE', "max=#{s.lengths.max}", "avg=#{truncated(s.lengths.sum, s.time)}")
        emit('EVENTS', *EVENTS.map { |k| "#{k.downcase}=#{s.counts[k]}" })
        emit('DEADLINE', "met=#{s.met}", "missed=#{s.missed}")
      end
    end
  rescue CommandError => e
    emit('ERROR', e.message)
  end
end
scheduler = Scheduler.new
STDIN.gets.to_i.times { scheduler.execute(STDIN.gets) }
