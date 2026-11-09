class Manager
  KINDS = %w[granted blocked unblocked released finished aborted cancelled].freeze

  def initialize
    @mode, @policy, @trace, @auto = 'AVOID', 'ALLOC', false, false
    @snapshots = {}
    @total, @available, @processes, @queue, @history = [], [], {}, [], []
  end

  def vector(v)
    "(#{v.join(',')})"
  end

  def names(ids)
    ids.map { |id| "P#{id}" }.join(' ')
  end

  def add(a, b)
    a.zip(b).map { |x, y| x + y }
  end

  def sub(a, b)
    a.zip(b).map { |x, y| x - y }
  end

  def fits(a, b)
    a.zip(b).all? { |x, y| x <= y }
  end

  def zero
    Array.new(@total.size, 0)
  end

  def need(id, ps = @processes)
    sub(ps[id][:max], ps[id][:alloc])
  end

  def check(detect = false, trace = false, av = @available, ps = @processes, queue = @queue)
    work = av.dup
    idle = detect ? ps.keys.select { |id| ps[id][:alloc].all?(&:zero?) }.sort : []
    remaining = ps.keys.sort - idle
    sequence = []
    label = detect ? 'detect' : 'safety'
    if trace
      suffix = idle.empty? ? '' : " idle #{names(idle)}"
      puts "[#{label}] start work=#{vector(work)}#{suffix}"
    end
    loop do
      id = remaining.find do |p|
        request = queue.find { |q| q[0] == p }
        required = detect ? (request ? request[1] : zero) : need(p, ps)
        fits(required, work)
      end
      break unless id
      work = add(work, ps[id][:alloc])
      remaining.delete(id)
      sequence << id
      puts "[#{label}] P#{id} can finish, work=#{vector(work)}" if trace
    end
    if trace && !remaining.empty?
      puts "[#{label}] stuck work=#{vector(work)} remaining #{names(remaining)}"
    end
    [remaining.empty?, sequence, remaining]
  end

  def blocked(id)
    @queue.find { |q| q[0] == id }
  end

  def reject(id, v)
    return "process P#{id} is blocked" if blocked(id)
    return 'zero vector' if v.all?(&:zero?)
    return 'request exceeds need' unless fits(v, need(id))
    held = @processes[id][:alloc].each_index.select { |i| @processes[id][:alloc][i] > 0 }
    if @mode == 'ORDER' && !held.empty? && v.each_index.any? { |i| v[i] > 0 && i <= held.max }
      return 'resource order violation'
    end
    nil
  end

  def decision(id, v, trace = @trace)
    return [false, 'insufficient resources', []] unless fits(v, @available)
    if @mode == 'AVOID'
      ps = Marshal.load(Marshal.dump(@processes))
      ps[id][:alloc] = add(ps[id][:alloc], v)
      safe, sequence, = check(false, trace, sub(@available, v), ps)
      return [false, 'unsafe state', []] unless safe
      return [true, '', sequence]
    end
    [true, '', []]
  end

  def record(kind, id, v, wait = nil)
    @history << [@time, kind, id, v.dup, wait]
  end

  def grant(id, v)
    @available = sub(@available, v)
    @processes[id][:alloc] = add(@processes[id][:alloc], v)
  end

  def retry_queue
    old = @queue
    @queue = []
    old.each do |id, v, since|
      if decision(id, v)[0]
        grant(id, v)
        puts "unblocked P#{id} #{vector(v)}"
        record('unblocked', id, v, @time - since)
      else
        @queue << [id, v, since]
      end
    end
  end

  def terminate(id, kind, retry_after = true)
    allocation = @processes[id][:alloc]
    @available = add(@available, allocation)
    @processes.delete(id)
    @queue.reject! { |q| q[0] == id }
    puts "#{kind} P#{id} released #{vector(allocation)}"
    record(kind, id, allocation)
    retry_queue if retry_after
  end

  def fail_if(condition, message)
    raise message if condition
  end

  def run(line, time)
    @time = time
    command, *args = line.split
    id = args[0].to_i
    vector_commands = %w[PROCESS CLAIM REQUEST WHATIF RELEASE]
    v = (vector_commands.include?(command) ? args.drop(1) : args).map(&:to_i)
    if (vector_commands + %w[ADD REMOVE]).include?(command)
      fail_if(v.size != @total.size, 'wrong vector length')
    end
    if %w[CLAIM REQUEST WHATIF RELEASE FINISH ABORT CANCEL MAXGRANT].include?(command)
      fail_if(!@processes.key?(id), "unknown process P#{id}")
    end
    case command
    when 'RESOURCES'
      @total, @available = v.dup, v.dup
      @processes, @queue, @history = {}, [], []
      puts "resources #{vector(v)}"
    when 'MODE', 'POLICY', 'TRACE', 'AUTODETECT'
      case command
      when 'MODE' then @mode = args[0]
      when 'POLICY' then @policy = args[0]
      when 'TRACE' then @trace = args[0] == 'ON'
      when 'AUTODETECT' then @auto = args[0] == 'ON'
      end
      puts "#{command.downcase} #{args[0]}"
    when 'PROCESS'
      fail_if(@processes.key?(id), "duplicate process P#{id}")
      fail_if(!fits(v, @total), 'max exceeds total')
      @processes[id] = {max: v, alloc: zero, born: @time}
      puts "process P#{id} max #{vector(v)}"
    when 'CLAIM'
      fail_if(blocked(id), "process P#{id} is blocked")
      fail_if(!fits(@processes[id][:alloc], v), 'claim below allocation')
      fail_if(!fits(v, @total), 'max exceeds total')
      ps = Marshal.load(Marshal.dump(@processes))
      ps[id][:max] = v
      fail_if(@mode == 'AVOID' && !check(false, @trace, @available, ps)[0], 'claim makes state unsafe')
      @processes[id][:max] = v
      puts "claim P#{id} max #{vector(v)}"
      retry_queue
    when 'ADD', 'REMOVE'
      fail_if(v.all?(&:zero?), 'zero vector')
      if command == 'ADD'
        @total, @available = add(@total, v), add(@available, v)
        puts "added #{vector(v)} total #{vector(@total)}"
        retry_queue
      else
        fail_if(!fits(v, @available), 'remove exceeds available')
        total = sub(@total, v)
        fail_if(total.include?(0), 'total must stay positive')
        fail_if(@processes.keys.any? { |p| !fits(@processes[p][:max], total) }, 'max exceeds total')
        available = sub(@available, v)
        fail_if(@mode == 'AVOID' && !check(false, @trace, available)[0], 'removal makes state unsafe')
        @total, @available = total, available
        puts "removed #{vector(v)} total #{vector(@total)}"
      end
    when 'REQUEST', 'WHATIF'
      reason = reject(id, v)
      if reason
        raise reason if command == 'REQUEST'
        puts "whatif P#{id} #{vector(v)}: rejected (#{reason})"
      else
        granted, reason, sequence = decision(id, v)
        if command == 'WHATIF'
          result = granted ? 'granted' : "blocked (#{reason})"
          result += ", safe sequence #{names(sequence)}" if granted && @mode == 'AVOID'
          puts "whatif P#{id} #{vector(v)}: #{result}"
        elsif granted
          grant(id, v)
          puts "granted P#{id} #{vector(v)}"
          record('granted', id, v)
        else
          @queue << [id, v, @time]
          puts "blocked P#{id} #{vector(v)}: #{reason}"
          record('blocked', id, v)
          if @auto
            dead = check(true, @trace)[2]
            puts "deadlock detected: #{names(dead)}" unless dead.empty?
          end
        end
      end
    when 'RELEASE'
      fail_if(blocked(id), "process P#{id} is blocked")
      fail_if(v.all?(&:zero?), 'zero vector')
      fail_if(!fits(v, @processes[id][:alloc]), 'release exceeds allocation')
      @available = add(@available, v)
      @processes[id][:alloc] = sub(@processes[id][:alloc], v)
      puts "released P#{id} #{vector(v)}"
      record('released', id, v)
      retry_queue
    when 'FINISH', 'ABORT'
      fail_if(command == 'FINISH' && blocked(id), "process P#{id} is blocked")
      terminate(id, command == 'FINISH' ? 'finished' : 'aborted')
    when 'CANCEL'
      request = blocked(id)
      fail_if(!request, "process P#{id} is not blocked")
      @queue.delete(request)
      puts "cancelled P#{id} #{vector(request[1])}"
      record('cancelled', id, request[1])
    when 'MAXGRANT'
      fail_if(blocked(id), "process P#{id} is blocked")
      result = need(id).each_index.map do |i|
        (0..need(id)[i]).to_a.reverse.find do |x|
          w = zero
          w[i] = x
          x == 0 || (!reject(id, w) && decision(id, w, false)[0])
        end
      end
      puts "maxgrant P#{id}: #{vector(result)}"
    when 'SAFE'
      if @processes.empty?
        puts 'safe: no processes'
      else
        safe, sequence, remaining = check(false, @trace)
        puts(safe ? "safe: #{names(sequence)}" : "unsafe: #{names(remaining)} cannot finish")
      end
    when 'SEQUENCES'
      if @processes.empty?
        puts 'safe sequences: no processes'
      else
        count, first = 0, []
        visit = lambda do |work, remaining, path|
          if remaining.empty?
            count += 1
            first << path if first.size < id
          else
            remaining.each do |p|
              visit.call(add(work, @processes[p][:alloc]), remaining - [p], path + [p]) if fits(need(p), work)
            end
          end
        end
        visit.call(@available, @processes.keys.sort, [])
        puts "safe sequences: #{count}"
        first.each { |path| puts names(path) }
      end
    when 'DEFICIT'
      result = @total.each_index.map do |i|
        limit = @processes.keys.sum { |p| need(p)[i] }
        (0..limit).find do |x|
          work = @available.dup
          work[i] += x
          check(false, false, work)[0]
        end || '-'
      end
      puts "deficit: #{vector(result)}"
    when 'STATE'
      widths = @total.map { |n| n.to_s.size }
      table = ->(w) { w.each_with_index.map { |x, i| x.to_s.rjust(widths[i]) }.join(' ') }
      name_row = table.call(@total.each_index.map { |i| (65 + i).chr })
      columns = [10, 3, 4, 7].map { |w| [w, name_row.size].max }
      row = lambda do |heading, content|
        puts((heading.ljust(9) + content.each_with_index.map { |x, i| '  ' + x.ljust(columns[i]) }.join).rstrip)
      end
      row.call('Process', %w[Allocation Max Need Request])
      row.call('', Array.new(4, name_row))
      @processes.keys.sort.each do |p|
        request = blocked(p)
        row.call("P#{p}", [@processes[p][:alloc], @processes[p][:max], need(p), request ? request[1] : zero].map { |w| table.call(w) })
      end
      row.call('Available', [table.call(@available), '', '', ''])
      row.call('Total', [table.call(@total), '', '', ''])
      text = @queue.map { |p, w, s| "P#{p} #{vector(w)} since t=#{s}" }.join(', ')
      puts "blocked queue: #{text.empty? ? 'empty' : text}"
    when 'STATS'
      @total.each_index do |i|
        used = @total[i] - @available[i]
        percent = used * 1000 / @total[i]
        requested = @queue.sum { |q| q[1][i] }
        puts "#{(65 + i).chr}: allocated #{used}/#{@total[i]} (#{percent / 10}.#{percent % 10}%), requested #{requested}"
      end
      puts 'events: ' + KINDS.map { |k| "#{k} #{@history.count { |e| e[1] == k }}" }.join(', ')
      waits = @history.select { |e| e[1] == 'unblocked' }.map { |e| e[4] }
      if waits.empty?
        puts 'waits: none'
      else
        average = waits.sum * 100 / waits.size
        puts "waits: #{waits.size} unblocked, total #{waits.sum}, average #{average / 100}.#{(average % 100).to_s.rjust(2, '0')}"
      end
    when 'DETECT'
      dead = check(true, @trace)[2]
      puts(dead.empty? ? 'no deadlock' : "deadlocked: #{names(dead)}")
    when 'VICTIMS'
      dead = check(true)[2]
      if dead.empty?
        puts 'no deadlock'
      else
        candidates = (1..dead.size).flat_map { |n| dead.combination(n).to_a }
        candidates.sort_by! { |s| [s.size, s.sum { |p| @processes[p][:alloc].sum }, s] }
        victims = candidates.find do |s|
          ps = @processes.reject { |p, _| s.include?(p) }
          work = s.reduce(@available) { |a, p| add(a, @processes[p][:alloc]) }
          check(true, false, work, ps, @queue.reject { |q| s.include?(q[0]) })[0]
        end
        puts "victims: #{names(victims)}"
      end
    when 'RECOVER'
      count = 0
      loop do
        dead = check(true, @trace)[2]
        break if dead.empty?
        if args[0] == 'ALL'
          dead.each { |p| terminate(p, 'aborted', false) }
          count += dead.size
          retry_queue
          break
        end
        p = dead.min_by do |q|
          case @policy
          when 'ALLOC' then [@processes[q][:alloc].sum, -q]
          when 'NEED' then [-need(q).sum, -q]
          else [-@processes[q][:born]]
          end
        end
        terminate(p, 'aborted')
        count += 1
      end
      puts(count == 0 ? 'no deadlock' : "recovered: #{count} aborted")
    when 'WAITGRAPH', 'GRAPH'
      graph(command == 'GRAPH')
    when 'HISTORY'
      events = @history.select { |e| args.empty? || e[1] == args[0] || (args[0].match?(/\A\d+\z/) && e[2] == id) }
      puts 'no events' if events.empty?
      events.each do |s, kind, p, w, wait|
        text = "t=#{s} #{kind} P#{p} #{vector(w)}"
        text += " waited #{wait}" if kind == 'unblocked'
        puts text
      end
    when 'SNAPSHOT'
      @snapshots[args[0]] = Marshal.dump([@total, @available, @processes, @queue, @history])
      puts "saved #{args[0]}"
    when 'RESTORE'
      fail_if(!@snapshots.key?(args[0]), "unknown snapshot #{args[0]}")
      @total, @available, @processes, @queue, @history = Marshal.load(@snapshots[args[0]])
      puts "restored #{args[0]}"
    end
  rescue RuntimeError => e
    puts "error: #{e.message}"
  end

  def graph(single)
    fail_if(single && @total.any? { |x| x != 1 }, 'not single-instance')
    ids = @processes.keys.sort
    edges = ids.to_h { |p| [p, []] }
    if single
      @total.each_index do |i|
        ids.each { |p| puts "assign #{(65 + i).chr} -> P#{p}" if @processes[p][:alloc][i] > 0 }
      end
      ids.each do |p|
        q = blocked(p)
        next unless q
        @total.each_index do |i|
          next if q[1][i] == 0
          puts "request P#{p} -> #{(65 + i).chr}"
          holder = ids.find { |j| @processes[j][:alloc][i] > 0 }
          edges[p] << [i, holder] if holder
        end
      end
      ids.each do |p|
        q = blocked(p)
        @total.each_index do |i|
          puts "claim P#{p} -> #{(65 + i).chr}" if need(p)[i] > 0 && (!q || q[1][i] == 0)
        end
      end
    else
      ids.each do |p|
        q = blocked(p)
        next unless q
        ids.each do |j|
          next if p == j
          labels = @total.each_index.select { |i| q[1][i] > @available[i] && @processes[j][:alloc][i] > 0 }
          next if labels.empty?
          edges[p] << [j, j]
          puts "P#{p} -> P#{j} on #{labels.map { |i| (65 + i).chr }.join(',')}"
        end
      end
      puts 'no wait edges' if edges.values.all?(&:empty?)
    end
    cycles = []
    ids.each do |start|
      visit = lambda do |p, seen, path|
        edges[p].each do |label, next_p|
          extension = single ? [label, next_p] : [next_p]
          if next_p == start
            cycles << path + extension if single || seen.size >= 2
          elsif next_p > start && !seen.include?(next_p)
            visit.call(next_p, seen + [next_p], path + extension)
          end
        end
      end
      visit.call(start, [start], [start])
    end
    cycles.sort.each do |path|
      text = path.each_with_index.map { |x, i| single && i.odd? ? (65 + x).chr : "P#{x}" }.join(' -> ')
      puts "cycle: #{text}"
    end
    puts 'no cycles' if cycles.empty?
  end
end

manager = Manager.new
STDIN.gets.to_i.times { |i| manager.run(STDIN.gets.chomp, i + 1) }
