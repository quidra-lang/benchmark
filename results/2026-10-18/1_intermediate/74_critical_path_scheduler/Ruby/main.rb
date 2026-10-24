require 'date'
require 'set'

Task = Struct.new(:base, :resource, :units, :day, :crash_limit, :cost, :used, :estimate) do
  def duration
    base - used
  end
end

class ScheduleError < StandardError; end

class Scheduler
  ANALYSIS = %w[CPM CRITICAL SLACK DRAG STATS CALENDAR GANTT LEVEL LOAD PERTSUM CRASH WHATIF BASELINE VARIANCE].freeze

  def initialize
    @tasks = {}
    @deps = {}
    @capacities = {}
    @start = nil
    @deadline = nil
    @holidays = Set.new
    @baseline = nil
  end

  def require_task(name)
    raise ScheduleError, "unknown task #{name}" unless @tasks.key?(name)
  end

  def predecessors(name)
    @deps.keys.select { |a, b| b == name }.map(&:first).sort
  end

  def successors(name)
    @deps.keys.select { |a, b| a == name }.map(&:last).sort
  end

  def topology
    remaining = @tasks.keys.sort
    order = []
    loop do
      name = remaining.find { |t| (predecessors(t) & remaining).empty? }
      break unless name
      remaining.delete(name)
      order << name
    end
    return [order, nil] if remaining.empty?
    walk = [remaining.first]
    loop do
      following = (predecessors(walk.last) & remaining).min
      if (i = walk.index(following))
        cycle = [walk[i]] + walk[(i + 1)..].reverse
        cycle = cycle.rotate(cycle.index(cycle.min))
        return [order, (cycle + [cycle.first]).join(' -> ')]
      end
      walk << following
    end
  end

  def compute(overrides = {})
    order, = topology
    result = {}
    order.each do |name|
      task = @tasks[name]
      duration = overrides.fetch(name, task.duration)
      start = predecessors(name).map do |a|
        kind, lag = @deps[[a, name]]
        case kind
        when 'FS' then result[a][:EF] + lag
        when 'SS' then result[a][:ES] + lag
        else result[a][:EF] + lag - duration
        end
      end.push(task.day).max
      result[name] = { DUR: duration, ES: start, EF: start + duration }
    end
    total = result.values.map { |v| v[:EF] }.max
    order.reverse_each do |name|
      value = result[name]
      finish = successors(name).map do |b|
        kind, lag = @deps[[name, b]]
        case kind
        when 'FS' then result[b][:LS] - lag
        when 'SS' then result[b][:LS] - lag + value[:DUR]
        else result[b][:LF] - lag
        end
      end.push(total).min
      value[:LF] = finish
      value[:LS] = finish - value[:DUR]
      value[:TF] = value[:LS] - value[:ES]
    end
    @tasks.each_key do |name|
      value = result[name]
      value[:FF] = successors(name).map { |b| margin(name, b, result) }.push(total - value[:EF]).min
    end
    [result, total]
  end

  def margin(a, b, schedule)
    kind, lag = @deps[[a, b]]
    case kind
    when 'FS' then schedule[b][:ES] - schedule[a][:EF] - lag
    when 'SS' then schedule[b][:ES] - schedule[a][:ES] - lag
    else schedule[b][:EF] - schedule[a][:EF] - lag
    end
  end

  def critical(schedule)
    @tasks.keys.sort.select { |name| schedule[name][:TF].zero? }
  end

  def critical_paths(schedule)
    selected = critical(schedule)
    edges = @deps.keys.select { |a, b| selected.include?(a) && selected.include?(b) && margin(a, b, schedule).zero? }
    roots = selected.reject { |name| edges.any? { |_, b| b == name } }
    paths = []
    visit = lambda do |path|
      next_tasks = edges.select { |a, _| a == path.last }.map(&:last).sort
      if next_tasks.empty?
        paths << path
      else
        next_tasks.each { |name| visit.call(path + [name]) }
      end
    end
    roots.each { |name| visit.call([name]) }
    paths
  end

  def signed(value)
    format('%+d', value)
  end

  def decimal(numerator, denominator)
    hundredths = numerator * 100 / denominator
    format('%d.%02d', hundredths / 100, hundredths % 100)
  end

  def date_value(text)
    year, month, day = text.split('-').map(&:to_i)
    raise ScheduleError, "invalid date #{text}" unless Date.valid_date?(year, month, day)
    Date.new(year, month, day)
  end

  def date_text(date)
    date.strftime('%Y-%m-%d') + ' ' + %w[Sun Mon Tue Wed Thu Fri Sat][date.wday]
  end

  def working?(date)
    !date.saturday? && !date.sunday? && !@holidays.include?(date)
  end

  def calendar(schedule, total)
    dates = []
    current = @start
    while dates.length < total
      dates << current if working?(current)
      current += 1
    end
    @tasks.keys.sort_by { |name| [schedule[name][:ES], name] }.each do |name|
      puts "#{name} #{date_text(dates[schedule[name][:ES]])} - #{date_text(dates[schedule[name][:EF] - 1])}"
    end
    first = dates.first
    finish = dates.last
    puts "project #{date_text(first)} - #{date_text(finish)}, #{total} working days, #{(finish - first).to_i + 1} calendar days"
    if @deadline
      days = 0
      lower, upper = [finish, @deadline].minmax
      current = lower + 1
      while current <= upper
        days += 1 if working?(current)
        current += 1
      end
      description = finish <= @deadline ? "met, #{days} working days to spare" : "missed by #{days} working days"
      puts "deadline #{date_text(@deadline)} #{description}"
    end
    holidays = @holidays.to_a.sort.select { |date| date >= first && date <= finish && !date.saturday? && !date.sunday? }
    puts "holidays in span: #{holidays.empty? ? 'none' : holidays.map { |date| date_text(date) }.join(', ')}"
  end

  def usage(schedule, resource, start_key = :ES, finish_key = :EF)
    daily = Hash.new(0)
    @tasks.each do |name, task|
      next unless task.resource == resource
      (schedule[name][start_key]...schedule[name][finish_key]).each { |day| daily[day] += task.units }
    end
    daily
  end

  def level(limit, schedule, total)
    capacity = ->(r) { @capacities.fetch(r, limit) }
    @tasks.keys.sort.each do |name|
      task = @tasks[name]
      raise ScheduleError, "capacity #{capacity.call(task.resource)} too small for #{name}" if task.units > capacity.call(task.resource)
    end
    decided = {}
    order = []
    daily = Hash.new { |hash, key| hash[key] = Hash.new(0) }
    until decided.length == @tasks.length
      name = (@tasks.keys - decided.keys).select { |t| predecessors(t).all? { |a| decided.key?(a) } }.min_by { |t| [schedule[t][:LS], t] }
      task = @tasks[name]
      start = predecessors(name).map do |a|
        kind, lag = @deps[[a, name]]
        case kind
        when 'FS' then decided[a][:F] + lag
        when 'SS' then decided[a][:S] + lag
        else decided[a][:F] + lag - task.duration
        end
      end.push(task.day).max
      while (start...(start + task.duration)).any? { |day| daily[task.resource][day] + task.units > capacity.call(task.resource) }
        start += 1
      end
      decided[name] = { S: start, F: start + task.duration }
      (start...(start + task.duration)).each { |day| daily[task.resource][day] += task.units }
      order << name
    end
    puts "level capacity #{limit}: duration #{total} -> #{decided.values.map { |v| v[:F] }.max}"
    order.each { |name| puts "#{name} start #{decided[name][:S]} finish #{decided[name][:F]} shift #{decided[name][:S] - schedule[name][:ES]}" }
    @tasks.values.map(&:resource).uniq.sort.each do |r|
      peak = usage(schedule, r).values.max || 0
      leveled = daily[r].values.max || 0
      puts "resource #{r} capacity #{capacity.call(r)} peak #{peak} -> #{leveled}"
    end
  end

  def crash(budget, initial)
    remaining = budget
    steps = 0
    final = initial
    reason = nil
    loop do
      schedule, total = compute
      candidates = critical(schedule).select do |name|
        task = @tasks[name]
        task.crash_limit && task.used < task.crash_limit && compute(name => task.duration - 1)[1] < total
      end
      if candidates.empty?
        reason = 'no candidate'
        break
      end
      name = candidates.min_by { |t| [@tasks[t].cost, t] }
      task = @tasks[name]
      if task.cost > remaining
        reason = 'insufficient budget'
        break
      end
      before = task.duration
      task.used += 1
      remaining -= task.cost
      steps += 1
      final = compute[1]
      puts "step #{steps}: #{name} #{before} -> #{task.duration}, cost #{task.cost}, project #{final}"
    end
    puts "crash done: #{steps} days, cost #{budget - remaining}, project #{initial} -> #{final}, budget left #{remaining}, #{reason}"
  end

  def analyze(command, args)
    raise ScheduleError, 'no tasks' if @tasks.empty?
    _, cycle = topology
    raise ScheduleError, "cycle #{cycle}" if cycle
    case command
    when 'CALENDAR'
      raise ScheduleError, 'no start date' unless @start
    when 'LOAD'
      raise ScheduleError, "unknown resource #{args[0]}" unless @tasks.values.any? { |t| t.resource == args[0] }
    when 'WHATIF'
      require_task(args[0])
    when 'VARIANCE'
      raise ScheduleError, 'no baseline' unless @baseline
    end
    schedule, total = compute
    names = @tasks.keys.sort
    case command
    when 'CPM'
      width = [4, names.map(&:length).max].max
      puts 'TASK'.ljust(width) + %w[DUR ES EF LS LF TF FF].map { |s| s.rjust(5) }.join
      names.each { |name| puts name.ljust(width) + %i[DUR ES EF LS LF TF FF].map { |key| schedule[name][key].to_s.rjust(5) }.join + (schedule[name][:TF].zero? ? ' *' : '') }
      puts "project duration #{total}"
    when 'CRITICAL', 'PERTSUM'
      paths = critical_paths(schedule)
      puts "critical paths: #{paths.length}" if command == 'CRITICAL'
      paths.each do |path|
        notation = path.join(' -> ')
        if command == 'CRITICAL'
          puts notation
        else
          estimates = path.map { |name| @tasks[name].estimate || Array.new(3, @tasks[name].duration) }
          expected = estimates.sum { |o, m, p| o + 4 * m + p }
          variance = estimates.sum { |o, _, p| (p - o)**2 }
          puts "#{notation}: expected #{decimal(expected, 6)} variance #{decimal(variance, 36)}"
        end
      end
    when 'SLACK'
      names.group_by { |name| schedule[name][:TF] }.sort.each { |float, tasks| puts "float #{float}: #{tasks.join(' ')}" }
    when 'DRAG'
      critical(schedule).each { |name| puts "#{name} drag #{total - compute(name => 0)[1]}" }
    when 'STATS'
      count = critical(schedule).length
      kinds = %w[FS SS FF].map { |kind| @deps.values.count { |k, _| k == kind } }
      puts "tasks #{names.length}, critical #{count}, dependencies #{@deps.length} (FS #{kinds[0]}, SS #{kinds[1]}, FF #{kinds[2]})"
      work = @tasks.values.group_by(&:resource).sort.map { |r, tasks| "#{r} #{tasks.sum { |t| t.duration * t.units }}" }
      puts 'work ' + work.join(', ')
      sum = schedule.values.sum { |value| value[:TF] }
      puts "float total #{sum}, average #{decimal(sum, names.length)}"
      puts "duration #{total}, critical share #{decimal(100 * count, names.length)}%"
    when 'CALENDAR'
      calendar(schedule, total)
    when 'GANTT'
      raise ScheduleError, "chart too wide (#{total} days)" if total > 60
      width = names.map(&:length).max
      puts ' ' * width + ' |' + (0...total).map { |d| d % 10 }.join + '|'
      names.sort_by { |name| [schedule[name][:ES], name] }.each do |name|
        value = schedule[name]
        bar = (0...total).map do |day|
          if day >= value[:ES] && day < value[:EF]
            value[:TF].zero? ? '=' : '-'
          elsif day >= value[:EF] && day < value[:LF]
            '.'
          else
            ' '
          end
        end.join
        puts name.ljust(width) + ' |' + bar + '|'
      end
    when 'LEVEL'
      level(args[0].to_i, schedule, total)
    when 'LOAD'
      resource = args[0]
      daily = usage(schedule, resource)
      values = (0...total).map { |day| daily[day] }
      puts "load #{resource}: #{values.join(' ')}"
      puts "peak #{values.max} on day #{values.index(values.max)}"
      puts "capacity #{@capacities[resource]} exceeded on #{values.count { |u| u > @capacities[resource] }} days" if @capacities.key?(resource)
    when 'CRASH'
      crash(args[0].to_i, total)
    when 'WHATIF'
      name, duration = args
      after, new_total = compute(name => duration.to_i)
      puts "whatif #{name} #{@tasks[name].duration} -> #{duration}: project #{total} -> #{new_total}"
      names.each do |t|
        differences = %i[ES EF TF].select { |key| schedule[t][key] != after[t][key] }
        puts t + differences.map { |key| " #{key} #{schedule[t][key]}->#{after[t][key]}" }.join unless differences.empty?
      end
      puts "critical #{critical(schedule).join(' ')} -> #{critical(after).join(' ')}" if critical(schedule) != critical(after)
    when 'BASELINE'
      @baseline = [total, names.to_h { |name| [name, [schedule[name][:ES], schedule[name][:EF]]] }]
      puts "baseline saved: #{names.length} tasks, duration #{total}"
    when 'VARIANCE'
      old_total, old = @baseline
      puts "variance: duration #{old_total} -> #{total} (#{signed(total - old_total)})"
      lines = []
      (names | old.keys).sort.each do |name|
        if !@tasks.key?(name)
          lines << "#{name} removed"
        elsif !old.key?(name)
          lines << "#{name} new"
        elsif [schedule[name][:ES], schedule[name][:EF]] != old[name]
          lines << "#{name} start #{signed(schedule[name][:ES] - old[name][0])} finish #{signed(schedule[name][:EF] - old[name][1])}"
        end
      end
      puts(lines.empty? ? ['no task changes'] : lines)
    end
  end

  def execute(line)
    command, *args = line.split(' ')
    if ANALYSIS.include?(command)
      analyze(command, args)
      return
    end
    name = args[0]
    case command
    when 'TASK'
      raise ScheduleError, "task #{name} already exists" if @tasks.key?(name)
      @tasks[name] = Task.new(args[1].to_i, args[2], args[3].to_i, 0, nil, nil, 0, nil)
      puts "task #{name} added"
    when 'DEP', 'UNDEP'
      a, b = args
      require_task(a)
      require_task(b)
      if command == 'DEP'
        raise ScheduleError, "self dependency #{a}" if a == b
        raise ScheduleError, "dependency #{a} -> #{b} already exists" if @deps.key?([a, b])
        @deps[[a, b]] = [args[2], args[3].to_i]
        puts "dependency #{a} -> #{b} #{args[2]}#{signed(args[3].to_i)} added"
      else
        raise ScheduleError, "no dependency #{a} -> #{b}" unless @deps.key?([a, b])
        @deps.delete([a, b])
        puts "dependency #{a} -> #{b} removed"
      end
    when 'CAPACITY'
      @capacities[name] = args[1].to_i
      puts "capacity #{name} #{args[1]}"
    when 'START', 'HOLIDAY', 'DEADLINE'
      date = date_value(name)
      if command == 'START'
        @start = date
      elsif command == 'DEADLINE'
        @deadline = date
      else
        raise ScheduleError, "duplicate holiday #{name}" if @holidays.include?(date)
        @holidays << date
      end
      puts "#{command.downcase} #{date_text(date)}"
    when 'LIST'
      puts "tasks #{@tasks.length}, dependencies #{@deps.length}, holidays #{@holidays.length}"
      @tasks.keys.sort.each do |t|
        task = @tasks[t]
        preds = predecessors(t)
        puts "#{t} duration #{task.duration} resource #{task.resource} units #{task.units} preds #{preds.empty? ? 'none' : preds.join(' ')}"
      end
    else
      require_task(name)
      task = @tasks[name]
      case command
      when 'REMOVE'
        removed = @deps.keys.select { |pair| pair.include?(name) }
        removed.each { |key| @deps.delete(key) }
        @tasks.delete(name)
        puts "task #{name} removed with #{removed.length} dependencies"
      when 'NOTBEFORE'
        task.day = args[1].to_i
        puts "notbefore #{name} #{args[1]}"
      when 'CRASHCOST'
        maximum, cost = args.drop(1).map(&:to_i)
        raise ScheduleError, "crash limit too large for #{name}" if maximum >= task.base
        raise ScheduleError, "crash limit below used days for #{name}" if maximum < task.used
        task.crash_limit = maximum
        task.cost = cost
        puts "crash #{name} max #{maximum} cost #{cost}"
      when 'UNCRASH'
        puts "uncrash #{name} restored #{task.used} days"
        task.used = 0
      when 'PERT'
        o, m, p = args.drop(1).map(&:to_i)
        raise ScheduleError, 'invalid estimate' unless o <= m && m <= p
        task.estimate = [o, m, p]
        puts "pert #{name} expected #{decimal(o + 4 * m + p, 6)} variance #{decimal((p - o)**2, 36)}"
      when 'SHOW'
        puts "task #{name} duration #{task.duration} resource #{task.resource} units #{task.units}#{task.day.zero? ? '' : " notbefore #{task.day}"}"
        preds = predecessors(name).map do |a|
          kind, lag = @deps[[a, name]]
          "#{a} #{kind}#{signed(lag)}"
        end
        succs = successors(name).map do |b|
          kind, lag = @deps[[name, b]]
          "#{b} #{kind}#{signed(lag)}"
        end
        puts "preds: #{preds.empty? ? 'none' : preds.join(', ')}"
        puts "succs: #{succs.empty? ? 'none' : succs.join(', ')}"
        puts(task.crash_limit ? "crash: max #{task.crash_limit} used #{task.used} cost #{task.cost}" : 'crash: none')
        puts(task.estimate ? "pert: #{task.estimate.join(' ')}" : 'pert: none')
        _, cycle = topology
        if cycle
          puts 'schedule: unavailable'
        else
          schedule, = compute
          puts 'schedule: ' + %i[ES EF LS LF TF FF].map { |key| "#{key} #{schedule[name][key]}" }.join(' ') + (schedule[name][:TF].zero? ? ' critical' : '')
        end
      when 'IMPACT'
        seen = [name]
        seen.each { |a| successors(a).each { |b| seen << b unless seen.include?(b) } }
        affected = (seen - [name]).sort
        puts "impact #{name}: #{affected.empty? ? 'none' : affected.join(' ')}"
      end
    end
  rescue ScheduleError => error
    puts "error: #{error.message}"
  end
end

scheduler = Scheduler.new
count = STDIN.gets.to_i
count.times { scheduler.execute(STDIN.gets.chomp) }
