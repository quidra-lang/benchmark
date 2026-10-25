def yn(value) = value ? 'yes' : 'no'
def mark(values) = '(' + values.map { |v| v.negative? ? 'w' : v.to_s }.join(',') + ')'
def listing(values) = values.empty? ? 'none' : values.join(' ')
def number(word, low, high)
  return nil unless /\A(?:0|[1-9][0-9]{0,9})\z/.match?(word)
  value = word.to_i
  (low..high).cover?(value) ? value : nil
end
def reachable(adj, start)
  seen = Array.new(adj.size, false); queue = [start]; seen[start] = true
  queue.each { |u| adj[u].each { |v| unless seen[v]; seen[v] = true; queue << v; end } }
  seen
end
def semiflows(matrix)
  n = matrix.size; m = matrix[0].size
  rows = matrix.each_with_index.map { |r, i| r + Array.new(n) { |j| i == j ? 1 : 0 } }
  m.times do |j|
    next_rows = rows.select { |r| r[j].zero? }
    rows.select { |r| r[j].positive? }.each do |r|
      rows.select { |s| s[j].negative? }.each do |s|
        v = r.zip(s).map { |a, b| -s[j] * a + r[j] * b }; d = v.reduce(0) { |g, x| g.gcd(x) }
        next_rows << v.map { |x| x / d }
      end
    end
    unique = next_rows.uniq
    supports = unique.map { |r| r.drop(m).each_index.reduce(0) { |s, i| r[m + i].positive? ? s | (1 << i) : s } }
    rows = unique.each_with_index.filter_map { |r, i| r unless supports.any? { |s| s != supports[i] && s & supports[i] == s } }
  end
  rows.map { |r| r.drop(m) }.sort.reverse
end
class Net
  attr_reader :places, :transitions, :initial, :arcs, :inhibitors
  def initialize(name)
    @name = name; @places = []; @transitions = []; @initial = []; @capacity = []; @priority = []
    @pre, @post, @inhibit = Array.new(3) { Array.new(16) { Array.new(16, 0) } }
    @arcs = @inhibitors = 0; @current = []; @history = []
  end
  def define(words)
    cmd, a, b, c = words; n = words.size - 1
    raise "unknown definition #{cmd}" unless %w[place transition arc inhibit].include?(cmd)
    valid = case cmd; when 'place' then [2, 3].include?(n); when 'transition' then [1, 2].include?(n); else n == 3; end
    raise 'wrong number of arguments' unless valid
    if %w[place transition].include?(cmd)
      raise "duplicate name #{a}" if (@places + @transitions).include?(a)
      if cmd == 'place'
        raise "tokens exceed capacity of #{a}" if n == 3 && b.to_i > c.to_i
        @places << a; @initial << b.to_i; @capacity << (n == 3 ? c.to_i : 0)
      else
        @transitions << a; @priority << (n == 2 ? b.to_i : 0)
      end
    elsif cmd == 'arc'
      [a, b].each { |x| raise "unknown node #{x}" unless (@places + @transitions).include?(x) }
      pa = @places.index(a); pb = @places.index(b)
      raise 'arc must connect a place and a transition' if pa.nil? == pb.nil?
      p = pa || pb; t = @transitions.index(pa ? b : a); matrix = pa ? @pre : @post
      raise "duplicate arc #{a} #{b}" unless matrix[p][t].zero?
      matrix[p][t] = c.to_i; @arcs += 1
    else
      p = @places.index(a); t = @transitions.index(b)
      raise "unknown place #{a}" unless p
      raise "unknown transition #{b}" unless t
      raise "duplicate inhibitor #{a} #{b}" unless @inhibit[p][t].zero?
      @inhibit[p][t] = c.to_i; @inhibitors += 1
    end
  end
  def summary
    @current = @initial.dup
    puts "net #{@name}: places=#{@places.size} transitions=#{@transitions.size} arcs=#{@arcs} inhibitors=#{@inhibitors}"
  end
  def reason(m, t)
    @places.each_index { |p| return "insufficient tokens in #{@places[p]}" if m[p] >= 0 && m[p] < @pre[p][t] }
    @places.each_index { |p| return "inhibited by #{@places[p]}" if @inhibit[p][t] > 0 && (m[p] < 0 || m[p] >= @inhibit[p][t]) }
    @places.each_index { |p| return "capacity of #{@places[p]} exceeded" if @capacity[p] > 0 && (m[p] < 0 || m[p] - @pre[p][t] + @post[p][t] > @capacity[p]) }
    nil
  end
  def enabled(m) = @transitions.each_index.select { |t| !reason(m, t) }
  def fire(m, t) = m.each_index.map { |p| m[p] < 0 ? -1 : m[p] - @pre[p][t] + @post[p][t] }
  def names(indices) = indices.map { |i| @transitions[i] }
  def commit(t)
    @history << @current; @current = fire(@current, t)
  end
  def graph(start, limit, target = nil)
    g = { states: [start.dup], parent: [-1], via: [-1], edges: [[]], found: nil, aborted: false }
    matches = ->(m) { target && m.each_index.all? { |p| m[p] >= target[p][0] && (target[p][1] < 0 || m[p] == target[p][1]) } }
    if matches.call(start); g[:found] = 0; return g; end
    index = { start => 0 }; q = 0
    while q < g[:states].size
      enabled(g[:states][q]).each do |t|
        m = fire(g[:states][q], t); k = index[m]
        unless k
          if g[:states].size == limit; g[:aborted] = true; return g; end
          k = g[:states].size; index[m] = k; g[:states] << m; g[:parent] << q; g[:via] << t; g[:edges] << []
          if matches.call(m); g[:found] = k; return g; end
        end
        g[:edges][q] << [t, k]
      end
      q += 1
    end
    g
  end
  def path(g, k)
    result = []
    while g[:parent][k] >= 0; result << g[:via][k]; k = g[:parent][k]; end
    result.reverse
  end
  def reach(limit, display)
    g = graph(@current, limit); states = g[:states]; edges = g[:edges]
    if g[:aborted]; puts "reachability graph limit #{limit} exceeded"; return; end
    if display
      states.each_with_index { |m, i| puts "M#{i} #{mark(m)}: " + (edges[i].empty? ? 'dead' : edges[i].map { |t, k| "#{@transitions[t]}->M#{k}" }.join(' ')) }; return
    end
    adj = edges.map { |e| e.map(&:last) }; closure = states.each_index.map { |i| reachable(adj, i) }; comp = Array.new(states.size, -1); count = 0
    states.each_index do |i|
      next if comp[i] >= 0
      states.each_index { |j| comp[j] = count if closure[i][j] && closure[j][i] }; count += 1
    end
    terminal = Array.new(count, true); edges.each_with_index { |e, i| e.each { |_, j| terminal[comp[i]] = false if comp[i] != comp[j] } }
    dead = states.each_index.select { |i| edges[i].empty? }; maximum = @places.each_index.map { |p| states.map { |m| m[p] }.max }; bound = maximum.max
    home = states.each_index.map { |j| closure.all? { |r| r[j] } }
    persistent = states.each_index.all? { |i| edges[i].all? { |t, k| edges[i].all? { |u, _| t == u || !reason(states[k], u) } } }
    levels = @transitions.each_index.map do |t|
      present = Array.new(count, false); used = cycle = false
      edges.each_with_index { |e, i| e.each { |u, k| if t == u; used = true; present[comp[i]] = true; cycle = true if comp[i] == comp[k]; end } }
      level = terminal.each_index.all? { |c| !terminal[c] || present[c] } ? 'L4' : cycle ? 'L3' : used ? 'L1' : 'L0'
      "#{@transitions[t]}=#{level}"
    end
    puts "reachable markings: #{states.size}", "edges: #{edges.sum(&:size)}", "components: #{count} (terminal #{terminal.count(true)})", "dead markings: #{dead.size}"
    dead.each { |i| p = names(path(g, i)); puts "  M#{i} #{mark(states[i])} path #{p.empty? ? 'empty' : p.join(' ')}" }
    puts "max tokens: #{mark(maximum)}", "bound: #{bound}", "safe: #{yn(bound <= 1)}", "home markings: #{home.count(true)}", "reversible: #{yn(home[0])}", "persistent: #{yn(persistent)}", "liveness: #{levels.join(' ')}"
  end
  def cover(limit)
    states = [@current.dup]; parents = [-1]; via = [-1]; old = [false]; dead = [false]; rank = ->(v) { v < 0 ? Float::INFINITY : v }; q = 0
    while q < states.size
      unless old[q]
        es = enabled(states[q]); dead[q] = es.empty?; ancestors = []; a = q
        while a >= 0; ancestors << a; a = parents[a]; end
        es.each do |t|
          m = fire(states[q], t)
          ancestors.reverse_each do |ancestor|
            pairs = m.zip(states[ancestor])
            if pairs.all? { |x, y| rank.call(x) >= rank.call(y) } && pairs.any? { |x, y| rank.call(x) > rank.call(y) }
              m.each_index { |p| m[p] = -1 if @capacity[p].zero? && rank.call(m[p]) > rank.call(states[ancestor][p]) }
            end
          end
          if states.size == limit; puts "coverability tree limit #{limit} exceeded"; return; end
          old << states.include?(m); states << m; parents << q; via << t; dead << false
        end
      end
      q += 1
    end
    puts "coverability tree nodes: #{states.size}"
    states.each_with_index { |m, i| puts "  #{i} #{mark(m)} " + (i.zero? ? 'root' : "<- #{parents[i]} #{@transitions[via[i]]}") + (old[i] ? ' old' : '') + (dead[i] ? ' dead' : '') }
    maximum = @places.each_index.map { |p| states.any? { |m| m[p] < 0 } ? -1 : states.map { |m| m[p] }.max }
    puts "bounds: #{mark(maximum)}", "unbounded: #{listing(@places.each_index.filter_map { |p| @places[p] if maximum[p] < 0 })}"
  end
  def sets(trap)
    found = (1...(1 << @places.size)).select do |mask|
      @transitions.each_index.all? do |t|
        input = output = false
        @places.each_index { |p| if mask & (1 << p) != 0; input ||= @post[p][t] > 0; output ||= @pre[p][t] > 0; end }
        trap ? !output || input : !input || output
      end
    end
    found.reject { |m| found.any? { |s| s != m && s & m == s } }.sort_by { |m| p = @places.each_index.select { |i| m & (1 << i) != 0 }; [p.size, p] }
  end
  def set_text(mask) = '{' + @places.each_index.filter_map { |p| @places[p] if mask & (1 << p) != 0 }.join(',') + '}'
  def realize(counts)
    used = Array.new(counts.size, 0); stack = [@current]; choices = [0]; result = []; seen = {}; total = counts.sum
    until stack.empty?
      depth = result.size; return result if depth == total
      chosen = nil
      (choices[depth]...counts.size).each do |t|
        choices[depth] = t + 1
        next if used[t] >= counts[t] || reason(stack[depth], t)
        key = used.dup; key[t] += 1; next if seen[key]
        seen[key] = true; chosen = t; break
      end
      if chosen
        used[chosen] += 1; result << chosen; stack << fire(stack[depth], chosen); choices << 0
      else
        stack.pop; choices.pop; used[result.pop] -= 1 unless result.empty?
      end
    end
    nil
  end
  def invariants(transpose)
    matrix = @places.each_index.map { |p| @transitions.each_index.map { |t| @post[p][t] - @pre[p][t] } }; matrix = matrix.transpose if transpose
    flows = semiflows(matrix); names = transpose ? @transitions : @places; covered = Array.new(names.size, false); bounds = Array.new(names.size)
    puts "#{transpose ? 'T' : 'P'}-semiflows: #{flows.size}"
    flows.each do |coeff|
      terms = coeff.each_index.filter_map { |i| (coeff[i] == 1 ? '' : "#{coeff[i]}*") + names[i] if coeff[i] > 0 }.join(' + ')
      coeff.each_index { |i| covered[i] = true if coeff[i] > 0 }
      if transpose
        sequence = realize(coeff); puts "  #{terms}: " + (sequence ? 'realizable ' + self.names(sequence).join(' ') : 'not realizable')
      else
        value = coeff.zip(@current).sum { |a, b| a * b }; puts "  #{terms} = #{value}"
        coeff.each_index { |p| bounds[p] = [bounds[p] || value / coeff[p], value / coeff[p]].min if coeff[p] > 0 }
      end
    end
    puts 'bounds: (' + bounds.map { |b| b ? b.to_s : '-' }.join(',') + ')' unless transpose
    puts (transpose ? 'consistent: ' : 'conservative: ') + yn(covered.all?)
  end
  def classify
    inputs = @transitions.each_index.map { |t| @places.each_index.select { |p| @pre[p][t] > 0 } }
    outputs = @places.each_index.map { |p| @transitions.each_index.select { |t| @pre[p][t] > 0 } }
    ordinary = @places.each_index.all? { |p| @transitions.each_index.all? { |t| @pre[p][t] <= 1 && @post[p][t] <= 1 } }
    pure = @places.each_index.all? { |p| @transitions.each_index.all? { |t| @pre[p][t].zero? || @post[p][t].zero? } }
    sm = ordinary && inputs.each_index.all? { |t| inputs[t].size == 1 && @places.each_index.count { |p| @post[p][t] > 0 } == 1 }
    mg = ordinary && outputs.each_index.all? { |p| outputs[p].size == 1 && @transitions.each_index.count { |t| @post[p][t] > 0 } == 1 }
    fc = ordinary && outputs.all? { |a| a.all? { |t| a.size == 1 || inputs[t].size == 1 } }
    efc = ordinary && outputs.all? { |a| outputs.all? { |b| (a & b).empty? || a == b } }
    [['ordinary',ordinary],['pure',pure],['state machine',sm],['marked graph',mg],['free choice',fc],['extended free choice',efc]].each { |name, v| puts "#{name}: #{yn(v)}" }
    verdict = !fc ? 'not applicable' : @places.size > 12 ? 'too many places' : 'holds'
    if fc && @places.size <= 12
      traps = sets(true)
      sets(false).each do |s|
        unless traps.any? { |q| q & s == q && @current.each_index.any? { |p| @current[p] > 0 && q & (1 << p) != 0 } }
          verdict = 'fails at ' + set_text(s); break
        end
      end
    end
    puts 'commoner: ' + verdict
  end
  def workflow(limit)
    source = @places.each_index.select { |p| @transitions.each_index.all? { |t| @post[p][t].zero? } }
    sink = @places.each_index.select { |p| @transitions.each_index.all? { |t| @pre[p][t].zero? } }
    if source.size != 1; puts "workflow: no (#{source.size} source places)"; return; end
    if sink.size != 1; puts "workflow: no (#{sink.size} sink places)"; return; end
    i = source[0]; o = sink[0]; n = @places.size; names = @places + @transitions; adj = Array.new(names.size) { [] }; rev = Array.new(names.size) { [] }
    @places.each_index { |p| @transitions.each_index { |t| if @pre[p][t] > 0; adj[p] << n+t; rev[n+t] << p; end; if @post[p][t] > 0; adj[n+t] << p; rev[p] << n+t; end } }
    f = reachable(adj,i); b = reachable(rev,o)
    names.each_index { |v| unless f[v] && b[v]; puts "workflow: no (#{names[v]} is not on a path from #{@places[i]} to #{@places[o]})"; return; end }
    puts "workflow: source #{@places[i]} sink #{@places[o]}"
    start = Array.new(n,0); start[i] = 1; goal = Array.new(n,0); goal[o] = 1; g = graph(start,limit)
    if g[:aborted]; puts "reachability graph limit #{limit} exceeded"; return; end
    goal_index = g[:states].index(goal); rev = Array.new(g[:states].size) { [] }; g[:edges].each_with_index { |e,u| e.each { |_,v| rev[v] << u } }
    option = goal_index && reachable(rev,goal_index).all?; proper = g[:states].all? { |m| m[o] < 1 || m == goal }; live = @transitions.each_index.all? { |t| g[:edges].any? { |e| e.any? { |u,_| t == u } } }
    puts "option to complete: #{yn(option)}", "proper completion: #{yn(proper)}", "no dead transitions: #{yn(live)}", "sound: #{yn(option && proper && live)}"
  end
  ARITY = {'MARKING'=>0,'RESET'=>0,'SET'=>2,'ENABLED'=>0,'FIRE'=>-1,'UNDO'=>1,'SIMULATE'=>3,'CONFLICTS'=>0,'REACH'=>1,'GRAPH'=>1,'COVER'=>1,'PATH'=>2,'INCIDENCE'=>0,'PINV'=>0,'TINV'=>0,'SIPHONS'=>0,'TRAPS'=>0,'CLASSIFY'=>0,'WORKFLOW'=>1,'SHOW'=>0}.freeze
  def execute(words)
    cmd, *args = words
    raise "unknown command #{cmd}" unless ARITY.key?(cmd)
    raise 'wrong number of arguments' unless ARITY[cmd] < 0 ? !args.empty? : args.size == ARITY[cmd]
    if %w[REACH GRAPH COVER PATH WORKFLOW].include?(cmd); limit = number(args[0],1,2000); raise "invalid limit #{args[0]}" unless limit; end
    case cmd
    when 'MARKING' then puts "marking #{mark(@current)}"
    when 'RESET' then @current = @initial.dup; @history = []; puts "marking #{mark(@current)}"
    when 'SET'
      p = @places.index(args[0]); raise "unknown place #{args[0]}" unless p
      v = number(args[1],0,999); raise "invalid tokens #{args[1]}" unless v
      raise "tokens exceed capacity of #{args[0]}" if @capacity[p] > 0 && v > @capacity[p]
      @current = @current.dup; @current[p] = v; @history = []; puts "marking #{mark(@current)}"
    when 'ENABLED' then puts 'enabled: ' + listing(names(enabled(@current)))
    when 'FIRE'
      ts = args.map { |name| @transitions.index(name) || (raise "unknown transition #{name}") }
      ts.each_with_index { |t,i| if (why = reason(@current,t)); puts "step #{i+1}: #{args[i]} not enabled (#{why}) at #{mark(@current)}"; return; end; commit(t) }
      puts "fired #{ts.size} -> #{mark(@current)}"
    when 'UNDO'
      k = number(args[0],1,1000); raise "invalid count #{args[0]}" unless k
      raise "cannot undo #{k}: history size #{@history.size}" if k > @history.size
      @current = @history[-k]; @history.pop(k); puts "marking #{mark(@current)}"
    when 'SIMULATE'
      steps = number(args[0],1,1000); x = number(args[1],1,2147483646)
      raise "invalid steps #{args[0]}" unless steps
      raise "invalid seed #{args[1]}" unless x
      raise "invalid mode #{args[2]}" unless %w[PRIORITY RANDOM].include?(args[2])
      counts = Array.new(@transitions.size,0); done = 0
      while done < steps
        e = enabled(@current); if e.empty?; puts "dead (steps=#{done})"; break; end
        if args[2] == 'RANDOM'; x = x * 48271 % 2147483647; t = e[x % e.size]; else; t = e.max_by { |u| [@priority[u],-u] }; end
        commit(t); counts[t] += 1; done += 1; puts "step #{done}: #{@transitions[t]} -> #{mark(@current)}"
      end
      puts "completed (steps=#{steps})" if done == steps
      puts 'counts: ' + @transitions.each_index.map { |t| "#{@transitions[t]}=#{counts[t]}" }.join(' ')
    when 'CONFLICTS'
      structural = []; effective = []
      @transitions.each_index { |u| ((u+1)...@transitions.size).each { |v| pair = "#{@transitions[u]}/#{@transitions[v]}"; structural << pair if @places.each_index.any? { |p| @pre[p][u] > 0 && @pre[p][v] > 0 }; effective << pair if !reason(@current,u) && !reason(@current,v) && (reason(fire(@current,u),v) || reason(fire(@current,v),u)) } }
      puts 'structural: ' + listing(structural), 'effective: ' + listing(effective)
    when 'REACH', 'GRAPH' then reach(limit,cmd == 'GRAPH')
    when 'COVER' then cover(limit)
    when 'PATH'
      entries = args[1].split(','); raise "target needs #{@places.size} entries" unless entries.size == @places.size
      target = entries.map { |s| if s == '*'; [0,-1]; else; plus = s.end_with?('+'); v = number(plus ? s[0...-1] : s,0,9999999999); raise "invalid target entry #{s}" unless v; [v,plus ? -1 : v]; end }
      g = graph(@current,limit,target)
      if g[:found]; k = g[:found]; sequence = names(path(g,k)); puts "reached #{mark(g[:states][k])} length=#{sequence.size}" + (sequence.empty? ? '' : ': ' + sequence.join(' '))
      elsif g[:aborted]; puts "search limit #{limit} exceeded"
      else; puts "unreachable (markings explored: #{g[:states].size})"; end
    when 'INCIDENCE'
      rows = [[''] + @transitions] + @places.each_index.map { |p| [@places[p]] + @transitions.each_index.map { |t| (@post[p][t]-@pre[p][t]).to_s } }
      widths = rows.transpose.map { |col| col.map(&:size).max }
      rows.each { |r| puts r.each_index.map { |i| i.zero? ? r[i].ljust(widths[i]) : r[i].rjust(widths[i]) }.join('  ').rstrip }
    when 'PINV','TINV' then invariants(cmd == 'TINV')
    when 'SIPHONS','TRAPS'
      raise 'more than 12 places' if @places.size > 12
      values = sets(cmd == 'TRAPS'); puts "minimal #{cmd == 'TRAPS' ? 'traps' : 'siphons'}: #{values.size}"
      values.each { |s| puts "  #{set_text(s)} tokens=#{@current.each_index.sum { |p| s & (1 << p) != 0 ? @current[p] : 0 }}" }
    when 'CLASSIFY' then classify
    when 'WORKFLOW' then workflow(limit)
    when 'SHOW'
      @places.each_index { |p| puts "place #{@places[p]} tokens=#{@initial[p]} capacity=#{@capacity[p].zero? ? 'none' : @capacity[p]}" }
      @transitions.each_index { |t| lists = [@pre,@post,@inhibit].map { |m| a = @places.each_index.filter_map { |p| "#{@places[p]}:#{m[p][t]}" if m[p][t] > 0 }; a.empty? ? '-' : a.join(',') }; puts "transition #{@transitions[t]} priority=#{@priority[t]} pre=#{lists[0]} post=#{lists[1]} inhibit=#{lists[2]}" }
    end
  end
end
blocks = STDIN.gets.to_i
blocks.times do
  net = Net.new(STDIN.gets.split[1])
  loop do
    line = STDIN.gets.chomp; break if line == 'END NET'
    begin; net.define(line.split); rescue RuntimeError => e; puts 'error: ' + e.message; end
  end
  net.summary
  STDIN.gets.to_i.times { begin; net.execute(STDIN.gets.split); rescue RuntimeError => e; puts 'error: ' + e.message; end }
end
