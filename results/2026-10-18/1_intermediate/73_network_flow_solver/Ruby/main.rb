Edge = Struct.new(:u, :v, :capacity, :cost, :lower, :flow)

class FlowNetwork
  attr_reader :n, :edges

  def initialize(n, edges = [])
    @n = n
    @edges = edges.map(&:dup)
  end

  def arcs(vertex = nil)
    forward = @edges.each_index.select { |i| vertex.nil? || @edges[i].u == vertex }.map { |i| i + 1 }
    backward = @edges.each_index.select { |i| vertex.nil? || @edges[i].v == vertex }.map { |i| -i - 1 }
    forward + backward
  end

  def edge(arc)
    @edges[arc.abs - 1]
  end

  def from(arc)
    arc.positive? ? edge(arc).u : edge(arc).v
  end

  def to(arc)
    arc.positive? ? edge(arc).v : edge(arc).u
  end

  def residual(arc)
    arc.positive? ? edge(arc).capacity - edge(arc).flow : edge(arc).flow
  end

  def arc_cost(arc)
    arc.positive? ? edge(arc).cost : -edge(arc).cost
  end

  def push(path, amount)
    path.each { |arc| edge(arc).flow += arc.positive? ? amount : -amount }
  end

  def bottleneck(path)
    path.map { |arc| residual(arc) }.min
  end

  def bfs(source, threshold = 1)
    levels = Array.new(@n)
    parents = Array.new(@n)
    levels[source] = 0
    queue = [source]
    queue.each do |u|
      arcs(u).each do |arc|
        v = to(arc)
        next unless residual(arc) >= threshold && levels[v].nil?
        levels[v] = levels[u] + 1
        parents[v] = arc
        queue << v
      end
    end
    [levels, parents]
  end

  def path_to(source, target, parents)
    path = []
    until target == source
      arc = parents[target]
      path << arc
      target = from(arc)
    end
    path.reverse
  end

  def augment(source, target, threshold = 1)
    levels, parents = bfs(source, threshold)
    return nil if levels[target].nil?
    path = path_to(source, target, parents)
    amount = bottleneck(path)
    push(path, amount)
    { path: path, amount: amount, delta: threshold }
  end

  def maxflow(source, target, method = 'MAXFLOW')
    records = []
    phases = 0
    if method == 'DINIC'
      loop do
        levels, = bfs(source)
        break if levels[target].nil?
        phases += 1
        lists = (0...@n).map { |v| arcs(v) }
        pointers = Array.new(@n, 0)
        path = []
        u = source
        loop do
          if u == target
            amount = bottleneck(path)
            push(path, amount)
            records << { path: path.dup, amount: amount, phase: phases }
            path = []
            u = source
          elsif pointers[u] >= lists[u].length
            break if u == source
            u = from(path.pop)
            pointers[u] += 1
          else
            arc = lists[u][pointers[u]]
            v = to(arc)
            if residual(arc).positive? && levels[v] && levels[v] == levels[u] + 1
              path << arc
              u = v
            else
              pointers[u] += 1
            end
          end
        end
      end
    else
      threshold = 1
      maximum = @edges.map(&:capacity).max || 0
      threshold *= 2 while method == 'SCALING' && threshold * 2 <= maximum
      while threshold >= 1
        loop do
          record = augment(source, target, threshold)
          break unless record
          records << record
        end
        threshold = method == 'SCALING' ? threshold / 2 : 0
      end
    end
    [records, phases]
  end

  def negative_cycle?
    distance = Array.new(@n, 0)
    @n.times do
      changed = false
      @edges.each do |e|
        next unless e.capacity.positive? && distance[e.u] + e.cost < distance[e.v]
        distance[e.v] = distance[e.u] + e.cost
        changed = true
      end
      return false unless changed
    end
    @n.positive?
  end

  def mincost(source, target, limit = nil)
    amount = 0
    cost = 0
    records = []
    while limit.nil? || amount < limit
      usable = arcs.select { |arc| residual(arc).positive? }
      distance = Array.new(@n)
      parents = Array.new(@n)
      distance[source] = 0
      loop do
        changed = false
        usable.each do |arc|
          u = from(arc)
          v = to(arc)
          next if distance[u].nil?
          value = distance[u] + arc_cost(arc)
          next unless distance[v].nil? || value < distance[v]
          distance[v] = value
          parents[v] = arc
          changed = true
        end
        break unless changed
      end
      break if distance[target].nil?
      path = path_to(source, target, parents)
      delta = bottleneck(path)
      delta = [delta, limit - amount].min if limit
      push(path, delta)
      amount += delta
      cost += delta * distance[target]
      records << { path: path, amount: delta, cost: distance[target] }
    end
    [amount, cost, records]
  end

  def balance
    values = Array.new(@n, 0)
    @edges.each do |e|
      values[e.u] += e.flow
      values[e.v] -= e.flow
    end
    values
  end

  def total_cost
    @edges.sum { |e| e.flow * e.cost }
  end

  def decompose
    remaining = @edges.map(&:flow)
    balances = balance
    result = []
    while (first = remaining.index(&:positive?))
      start = balances.index(&:positive?) || @edges[first].u
      vertices = [start]
      path = []
      loop do
        u = vertices.last
        i = @edges.each_index.find { |j| @edges[j].u == u && remaining[j].positive? }
        v = @edges[i].v
        path << i + 1
        if (q = vertices.index(v))
          cycle = path[q..]
          delta = cycle.map { |arc| remaining[arc - 1] }.min
          cycle.each { |arc| remaining[arc - 1] -= delta }
          result << { kind: 'CYCLE', start: v, path: cycle, amount: delta }
          break
        end
        vertices << v
        next unless balances[v].negative?
        delta = [path.map { |arc| remaining[arc - 1] }.min, balances[start], -balances[v]].min
        path.each { |arc| remaining[arc - 1] -= delta }
        balances[start] -= delta
        balances[v] += delta
        result << { kind: 'PATH', start: start, path: path, amount: delta }
        break
      end
    end
    result
  end
end

class FlowError < StandardError; end

class FlowSolver
  def initialize
    clear
  end

  def clear
    @names = []
    @demands = []
    @network = FlowNetwork.new(0)
    @owner = nil
  end

  def vertex(name)
    index = @names.index(name)
    raise FlowError, "UNKNOWN NODE #{name}" unless index
    index
  end

  def endpoints(s, t)
    source = vertex(s)
    target = vertex(t)
    raise FlowError, 'SAME NODE' if source == target
    [source, target]
  end

  def checked_edge(text)
    number = text.to_i
    raise FlowError, "UNKNOWN EDGE #{text}" unless number.between?(1, @network.edges.length)
    @network.edges[number - 1]
  end

  def start_flow(source, target)
    @network.edges.each { |e| e.flow = 0 } unless @owner == [:flow, source, target]
    @owner = [:flow, source, target]
    @network.balance[source]
  end

  def notation(network, start, path, original_only = nil)
    words = [@names[start]]
    path.each do |arc|
      next if original_only && arc.abs > original_only
      words << "#{arc.positive? ? '+' : '-'}#{arc.abs}"
      words << (original_only ? @names[@network.edges[arc.abs - 1].v] : @names[network.to(arc)])
    end
    words.join(' ')
  end

  def flow_list
    @network.edges.each_with_index { |e, i| puts "FLOW #{i + 1} #{@names[e.u]} #{@names[e.v]} #{e.flow}/#{e.capacity}" }
  end

  def fresh
    network = FlowNetwork.new(@names.length, @network.edges)
    network.edges.each { |e| e.flow = 0 }
    network
  end

  def circulation(mode)
    work = fresh
    work.edges.each { |e| e.capacity -= e.lower }
    raise FlowError, 'NEGATIVE CYCLE' if mode == 'MINCOST' && work.negative_cycle?
    total = @demands.sum
    unless total.zero?
      puts "CIRCULATION infeasible unbalanced=#{total}"
      return
    end
    residual = @demands.dup
    @network.edges.each do |e|
      residual[e.v] -= e.lower
      residual[e.u] += e.lower
    end
    source = @names.length
    target = source + 1
    edges = work.edges.map(&:dup)
    residual.each_with_index { |r, v| edges << Edge.new(source, v, -r, 0, 0, 0) if r.negative? }
    sinks = []
    residual.each_with_index do |r, v|
      next unless r.positive?
      sinks << edges.length
      edges << Edge.new(v, target, r, 0, 0, 0)
    end
    work = FlowNetwork.new(target + 1, edges)
    mode == 'ANY' ? work.maxflow(source, target) : work.mincost(source, target)
    required = residual.select(&:positive?).sum
    achieved = sinks.sum { |i| work.edges[i].flow }
    if achieved < required
      puts "CIRCULATION infeasible required=#{required} achieved=#{achieved}"
      reachable, = work.bfs(source)
      puts 'CUT ' + @names.each_index.select { |v| reachable[v] }.map { |v| @names[v] }.join(' ')
    else
      @network.edges.each_with_index { |e, i| e.flow = e.lower + work.edges[i].flow }
      @owner = [:circulation]
      puts "CIRCULATION feasible required=#{required} cost=#{@network.total_cost}"
      flow_list
    end
  end

  def matching(left_text, right_text, pair_text)
    left = left_text.split(',')
    right = right_text.split(',')
    seen = []
    (left + right).each do |name|
      raise FlowError, "DUPLICATE VERTEX #{name}" if seen.include?(name)
      seen << name
    end
    pairs = pair_text == '-' ? [] : pair_text.split(',').map { |word| word.split('-') }
    seen_pairs = []
    pairs.each do |a, b|
      raise FlowError, "UNKNOWN VERTEX #{a}" unless left.include?(a)
      raise FlowError, "UNKNOWN VERTEX #{b}" unless right.include?(b)
      raise FlowError, "DUPLICATE PAIR #{a}-#{b}" if seen_pairs.include?([a, b])
      seen_pairs << [a, b]
    end
    lp = {}
    rp = {}
    examined = []
    attempt = lambda do |a|
      pairs.each do |x, b|
        next unless x == a && !examined.include?(b)
        examined << b
        if !rp.key?(b) || attempt.call(rp[b])
          rp[b] = a
          lp[a] = b
          return true
        end
      end
      false
    end
    left.each do |a|
      examined = []
      attempt.call(a)
    end
    free_left = left.reject { |a| lp.key?(a) }
    free_right = right.reject { |b| rp.key?(b) }
    zl = free_left.dup
    zr = []
    zl.each do |a|
      pairs.each do |x, b|
        next unless x == a && lp[a] != b && !zr.include?(b)
        zr << b
        zl << rp[b] if rp.key?(b) && !zl.include?(rp[b])
      end
    end
    cover = left.reject { |a| zl.include?(a) } + right.select { |b| zr.include?(b) }
    puts "MATCH size=#{lp.length} left=#{left.length} right=#{right.length}"
    left.each { |a| puts "PAIR #{a} #{lp[a]}" if lp.key?(a) }
    puts "FREE #{free_left.empty? ? '-' : free_left.join(',')} #{free_right.empty? ? '-' : free_right.join(',')}"
    puts "COVER size=#{cover.length}#{cover.empty? ? '' : ' ' + cover.join(' ')}"
    puts "HALL #{left.select { |a| zl.include?(a) }.join(',')} #{zr.empty? ? '-' : right.select { |b| zr.include?(b) }.join(',')}" unless free_left.empty?
  end

  def assignment(mode, n, values)
    raise FlowError, 'BAD SIZE' unless n.between?(1, 8)
    raise FlowError, 'BAD LENGTH' unless values.length == n * n
    best = nil
    count = 0
    chosen = nil
    (0...n).to_a.permutation do |permutation|
      cells = permutation.each_with_index.map { |column, row| values[row * n + column] }
      next if cells.include?('x')
      total = cells.sum(&:to_i)
      if best.nil? || (mode == 'MIN' ? total < best : total > best)
        best = total
        count = 1
        chosen = permutation.dup
      elsif total == best
        count += 1
        chosen = permutation.dup if (permutation <=> chosen).negative?
      end
    end
    if best.nil?
      puts "ASSIGN #{mode} n=#{n} infeasible"
    else
      puts "ASSIGN #{mode} n=#{n} total=#{best} optimal=#{count}"
      chosen.each_with_index { |column, row| puts "MATE #{row + 1} #{column + 1} #{values[row * n + column]}" }
    end
  end

  def execute(line)
    command, *args = line.split(' ')
    case command
    when 'NODE'
      seen = @names.dup
      args.each do |name|
        raise FlowError, "DUPLICATE NODE #{name}" if seen.include?(name)
        seen << name
      end
      raise FlowError, 'TOO MANY NODES' if seen.length > 20
      @names = seen
      @demands.concat(Array.new(args.length, 0))
      @network = FlowNetwork.new(@names.length, @network.edges)
      puts "NODE added=#{args.length} total=#{@names.length}"
    when 'EDGE'
      u = vertex(args[0])
      v = vertex(args[1])
      raise FlowError, 'SELF LOOP' if u == v
      raise FlowError, 'TOO MANY EDGES' if @network.edges.length == 60
      e = Edge.new(u, v, args[2].to_i, (args[3] || '0').to_i, 0, 0)
      @network.edges << e
      puts "EDGE #{@network.edges.length} #{args[0]} #{args[1]} cap=#{e.capacity} cost=#{e.cost}"
    when 'LOWER', 'CAP', 'COST'
      e = checked_edge(args[0])
      value = args[1].to_i
      if command == 'LOWER'
        raise FlowError, 'BAD BOUND' if value > e.capacity
        e.lower = value
        puts "LOWER #{args[0]} low=#{value} cap=#{e.capacity}"
      elsif command == 'CAP'
        raise FlowError, 'BAD BOUND' if value < e.lower
        raise FlowError, 'BELOW FLOW' if value < e.flow
        e.capacity = value
        puts "CAP #{args[0]} low=#{e.lower} cap=#{value}"
      else
        e.cost = value
        puts "COST #{args[0]} cost=#{value}"
      end
    when 'DEMAND'
      v = vertex(args[0])
      @demands[v] = args[1].to_i
      puts "DEMAND #{args[0]} #{args[1]} total=#{@demands.sum}"
    when 'RESET'
      puts "RESET edges=#{@network.edges.count { |e| !e.flow.zero? }}"
      @network.edges.each { |e| e.flow = 0 }
      @owner = nil
    when 'CLEAR'
      puts "CLEAR nodes=#{@names.length} edges=#{@network.edges.length}"
      clear
    when 'SHOW'
      balances = @network.balance
      puts "NETWORK nodes=#{@names.length} edges=#{@network.edges.length}"
      if @owner.nil?
        puts 'STATE none'
      elsif @owner[0] == :circulation
        puts "STATE circulation cost=#{@network.total_cost}"
      else
        puts "STATE flow #{@names[@owner[1]]} #{@names[@owner[2]]} value=#{balances[@owner[1]]} cost=#{@network.total_cost}"
      end
      @names.each_with_index do |name, v|
        out = @network.edges.select { |e| e.u == v }.sum(&:flow)
        incoming = out - balances[v]
        puts "NODE #{name} demand=#{@demands[v]} out=#{out} in=#{incoming}"
      end
      @network.edges.each_with_index { |e, i| puts "EDGE #{i + 1} #{@names[e.u]} #{@names[e.v]} cap=#{e.capacity} cost=#{e.cost} low=#{e.lower} flow=#{e.flow}" }
    when 'AUGMENT', 'MAXFLOW', 'DINIC', 'SCALING', 'MINCUT', 'SENSITIVITY', 'MINCOST', 'DISJOINT'
      s, t = endpoints(args[0], args[1])
      flow_command(command, args, s, t)
    when 'DECOMPOSE'
      records = @network.decompose
      puts "DECOMPOSE paths=#{records.count { |r| r[:kind] == 'PATH' }} cycles=#{records.count { |r| r[:kind] == 'CYCLE' }}"
      counters = Hash.new(0)
      records.each do |r|
        counters[r[:kind]] += 1
        puts "#{r[:kind]} #{counters[r[:kind]]} amount=#{r[:amount]} #{notation(@network, r[:start], r[:path])}"
      end
    when 'VERIFY'
      violations = []
      @network.edges.each_with_index { |e, i| violations << "LOW #{i + 1} flow=#{e.flow} low=#{e.lower}" if e.flow < e.lower }
      balance = @network.balance
      @names.each_with_index do |name, v|
        next if @owner && @owner[0] == :flow && @owner.drop(1).include?(v)
        required = @owner && @owner[0] == :flow ? 0 : @demands[v]
        violations << "BALANCE #{name} net=#{-balance[v]} need=#{required}" if -balance[v] != required
      end
      puts(violations.empty? ? 'VERIFY ok' : ["VERIFY violations=#{violations.length}", *violations])
    when 'CIRCULATION'
      circulation(args[0])
    when 'MATCH'
      matching(*args)
    when 'ASSIGN'
      assignment(args[0], args[1].to_i, args.drop(2))
    end
  rescue FlowError => error
    puts "ERROR #{error.message}"
  end

  def flow_command(command, args, source, target)
    prefix = "#{command} #{args[0]} #{args[1]}"
    if command == 'SENSITIVITY'
      maximum = lambda do |index, delta|
        work = fresh
        work.edges[index].capacity += delta if index
        work.maxflow(source, target)
        work.balance[source]
      end
      value = maximum.call(nil, 0)
      critical = @network.edges.each_index.map do |i|
        [i, maximum.call(i, 1) > value, @network.edges[i].capacity.positive? && maximum.call(i, -1) < value]
      end
      puts "#{prefix} value=#{value} up=#{critical.count { |r| r[1] }} down=#{critical.count { |r| r[2] }}"
      critical.each { |i, up, down| puts "CRITICAL #{i + 1} #{@names[@network.edges[i].u]} #{@names[@network.edges[i].v]} up=#{up ? 'yes' : 'no'} down=#{down ? 'yes' : 'no'}" if up || down }
    elsif command == 'MINCOST'
      work = fresh
      raise FlowError, 'NEGATIVE CYCLE' if work.negative_cycle?
      limit = args[2] == 'MAX' ? nil : args[2].to_i
      amount, cost, records = work.mincost(source, target, limit)
      if limit && amount < limit
        puts "#{prefix} k=#{args[2]} infeasible max=#{amount}"
        return
      end
      @network.edges.each_with_index { |e, i| e.flow = work.edges[i].flow }
      @owner = [:flow, source, target]
      puts "#{prefix} k=#{args[2]} flow=#{amount} cost=#{cost}"
      records.each_with_index { |r, i| puts "AUG #{i + 1} amount=#{r[:amount]} cost=#{r[:cost]} #{notation(work, source, r[:path])}" }
      flow_list
    elsif command == 'DISJOINT'
      edges = @network.edges.map { |e| Edge.new(e.u, e.v, e.capacity.positive? ? 1 : 0, 0, 0, 0) }
      n = @names.length
      if args[2] == 'VERTEX'
        exits = (0...n).to_a
        @names.each_index do |v|
          next if v == source || v == target
          exits[v] = n
          n += 1
        end
        edges.each { |e| e.u = exits[e.u] }
        @names.each_index { |v| edges << Edge.new(v, exits[v], 1, 0, 0, 0) unless v == source || v == target }
      end
      work = FlowNetwork.new(n, edges)
      work.maxflow(source, target)
      records = work.decompose.select { |r| r[:kind] == 'PATH' }
      puts "#{prefix} #{args[2]} count=#{records.length}"
      records.each_with_index { |r, i| puts "PATH #{i + 1} #{notation(work, source, r[:path], @network.edges.length)}" }
    else
      start = start_flow(source, target)
      if command == 'AUGMENT'
        record = @network.augment(source, target)
        ending = record ? "amount=#{record[:amount]} #{notation(@network, source, record[:path])}" : 'none'
        puts "#{prefix} value=#{@network.balance[source]} #{ending}"
        return
      end
      records, phases = @network.maxflow(source, target, command)
      value = @network.balance[source]
      if command == 'MINCUT'
        reachable, = @network.bfs(source)
        cut = @network.edges.each_index.select { |i| reachable[@network.edges[i].u] && reachable[@network.edges[i].v].nil? }
        puts "#{prefix} value=#{value} edges=#{cut.length}"
        puts 'SOURCE ' + @names.each_index.select { |v| reachable[v] }.map { |v| @names[v] }.join(' ')
        puts 'SINK ' + @names.each_index.select { |v| reachable[v].nil? }.map { |v| @names[v] }.join(' ')
        cut.each do |i|
          e = @network.edges[i]
          puts "CUT #{i + 1} #{@names[e.u]} #{@names[e.v]} #{e.capacity}"
        end
      else
        puts "#{prefix} value=#{value} start=#{start}#{command == 'DINIC' ? " phases=#{phases}" : ''} paths=#{records.length}"
        records.each_with_index do |r, i|
          extra = command == 'DINIC' ? "phase=#{r[:phase]} " : command == 'SCALING' ? "delta=#{r[:delta]} " : ''
          puts "AUG #{i + 1} #{extra}amount=#{r[:amount]} #{notation(@network, source, r[:path])}"
        end
        flow_list
      end
    end
  end
end

solver = FlowSolver.new
count = STDIN.gets.to_i
count.times { solver.execute(STDIN.gets.chomp) }
