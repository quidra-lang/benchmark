class CircuitError < StandardError
end

Element = Struct.new(:name, :type, :nodes, :value, :reference)

def fraction(value)
  value.denominator == 1 ? value.numerator.to_s : "#{value.numerator}/#{value.denominator}"
end

def formatted(value)
  scaled = value.numerator.abs * 1_000_000 / value.denominator
  decimal = (value.negative? ? '-' : '') + (scaled / 1_000_000).to_s + '.' + (scaled % 1_000_000).to_s.rjust(6, '0')
  fraction(value) + ' (' + decimal + ')'
end

def rational_number(text)
  multiplier = Rational(1)
  { 'meg' => Rational(1_000_000), 'k' => Rational(1000), 'm' => Rational(1, 1000), 'u' => Rational(1, 1_000_000) }.each do |suffix, value|
    next unless text.end_with?(suffix)
    text = text.delete_suffix(suffix)
    multiplier = value
    break
  end
  return nil unless text.match?(/\A-?[0-9]+(?:\.[0-9]+|\/[0-9]+)?\z/)
  return nil if text.include?('/') && text.split('/')[1].to_i == 0
  Rational(text) * multiplier
end

def solve(matrix, rhs)
  n = rhs.length
  rows = matrix.each_with_index.map { |row, i| row + [rhs[i]] }
  n.times do |k|
    pivot = (k...n).find { |i| rows[i][k] != 0 }
    return nil unless pivot
    rows[k], rows[pivot] = rows[pivot], rows[k] if pivot != k
    divisor = rows[k][k]
    rows[k] = rows[k].map { |entry| entry / divisor }
    n.times do |i|
      next if i == k || rows[i][k] == 0
      factor = rows[i][k]
      rows[i] = rows[i].each_with_index.map { |entry, j| entry - factor * rows[k][j] }
    end
  end
  rows.map(&:last)
end

def reachable(start, edges)
  seen = Set[start]
  queue = [start]
  until queue.empty?
    node = queue.shift
    edges.each do |a, b|
      next unless a == node || b == node
      other = a == node ? b : a
      next if seen.include?(other)
      seen << other
      queue << other
    end
  end
  seen
end

class Groups
  def initialize(nodes)
    @parent = nodes.to_h { |node| [node, node] }
  end

  def find(node)
    @parent[node] = find(@parent[node]) unless @parent[node] == node
    @parent[node]
  end

  def join(a, b)
    a, b = find(a), find(b)
    @parent[[a, b].max] = [a, b].min
  end
end

class Circuit
  COUNTS = { '.OP' => 0, '.CURRENT' => 1, '.VOLTAGE' => 2, '.POWER' => 0, '.KCL' => 1,
             '.THEVENIN' => 2, '.NORTON' => 2, '.MAXPOWER' => 2, '.TF' => 2, '.SENS' => 1,
             '.ZPARAM' => 4, '.SUPERPOSITION' => 1, '.SWEEP' => 5, '.MATRIX' => 0, '.REQ' => 2,
             '.REDUCE' => 2, '.CHECK' => 0, '.ALTER' => 2, '.DELETE' => 1, '.CLEAR' => 0,
             '.NODES' => 0, '.PRINT' => 0 }.freeze
  ANALYSES = %w[.OP .CURRENT .VOLTAGE .POWER .KCL .THEVENIN .NORTON .MAXPOWER .TF .SENS .ZPARAM .SUPERPOSITION].freeze

  def initialize
    @elements = []
  end

  def nodes
    @elements.flat_map(&:nodes).uniq.reject { |node| node == '0' }.sort
  end

  def sources
    @elements.select { |element| %w[V E H].include?(element.type) }
  end

  def element(name)
    @elements.find { |item| item.name == name } || raise(CircuitError, "unknown element #{name}")
  end

  def node(name)
    raise CircuitError, "unknown node #{name}" unless name == '0' || nodes.include?(name)
  end

  def number(text)
    rational_number(text) || raise(CircuitError, "invalid value #{text}")
  end

  def add(words)
    name = words[0]
    type = name[0]
    raise CircuitError, "unknown element type #{name}" unless %w[R V I E G F H].include?(type)
    count = %w[E G].include?(type) ? 6 : %w[F H].include?(type) ? 5 : 4
    raise CircuitError, "wrong field count for #{name}" unless words.length == count
    raise CircuitError, "duplicate element #{name}" if @elements.any? { |item| item.name == name }
    terminals = words[1, %w[E G].include?(type) ? 4 : 2]
    terminals.each do |terminal|
      raise CircuitError, "invalid node #{terminal}" unless terminal.match?(/\A(?:0|[a-z][a-z0-9]{0,7})\z/)
    end
    reference = %w[F H].include?(type) ? words[3] : nil
    if reference && !@elements.any? { |item| item.name == reference && item.type == 'V' }
      raise CircuitError, "unknown voltage source #{reference}"
    end
    value = number(words[-1])
    raise CircuitError, "nonpositive resistance #{name}" if type == 'R' && value <= 0
    @elements << Element.new(name, type, terminals, value, reference)
    []
  end

  def grounding
    reachable('0', @elements.select { |item| %w[R V E H].include?(item.type) }.map { |item| item.nodes[0, 2] })
  end

  def voltage_loops
    groups = Groups.new(['0'] + nodes)
    result = []
    sources.each do |item|
      a, b = item.nodes
      result << item.name if groups.find(a) == groups.find(b)
      groups.join(a, b)
    end
    result
  end

  def structure_check
    names = nodes
    raise CircuitError, 'no nodes' if names.empty?
    grounded = grounding
    floating = names.find { |name| !grounded.include?(name) }
    raise CircuitError, "floating node #{floating}" if floating
    loop_name = voltage_loops.first
    raise CircuitError, "voltage source loop at #{loop_name}" if loop_name
  end

  def equations(overrides = {})
    labels = nodes + sources.map(&:name)
    index = labels.each_with_index.to_h
    n = labels.length
    matrix = Array.new(n) { Array.new(n, Rational(0)) }
    rhs = Array.new(n, Rational(0))
    put = lambda do |row, column, value|
      matrix[index[row]][index[column]] += value if row != '0' && column != '0'
    end
    put_rhs = lambda do |row, value|
      rhs[index[row]] += value unless row == '0'
    end
    @elements.each do |item|
      a, b, c, d = item.nodes
      value = overrides.fetch(item.name, item.value)
      s = item.name
      case item.type
      when 'R'
        g = 1 / value
        put.call(a, a, g)
        put.call(b, b, g)
        put.call(a, b, -g)
        put.call(b, a, -g)
      when 'I'
        put_rhs.call(a, -value)
        put_rhs.call(b, value)
      when 'G'
        put.call(a, c, value)
        put.call(b, d, value)
        put.call(a, d, -value)
        put.call(b, c, -value)
      when 'F'
        put.call(a, item.reference, value)
        put.call(b, item.reference, -value)
      else
        put.call(a, s, 1)
        put.call(s, a, 1)
        put.call(b, s, -1)
        put.call(s, b, -1)
        case item.type
        when 'V'
          put_rhs.call(s, value)
        when 'E'
          put.call(s, c, -value)
          put.call(s, d, value)
        when 'H'
          put.call(s, item.reference, -value)
        end
      end
    end
    [matrix, rhs, labels, index]
  end

  def potential(solution, index, name)
    name == '0' ? Rational(0) : solution[index[name]]
  end

  def current(item, solution, index)
    a, b, c, d = item.nodes
    case item.type
    when 'R' then (potential(solution, index, a) - potential(solution, index, b)) / item.value
    when 'V', 'E', 'H' then solution[index[item.name]]
    when 'I' then item.value
    when 'G' then item.value * (potential(solution, index, c) - potential(solution, index, d))
    when 'F' then item.value * solution[index[item.reference]]
    end
  end

  def injection(matrix, index, a, b)
    rhs = Array.new(matrix.length, Rational(0))
    rhs[index[a]] += 1 unless a == '0'
    rhs[index[b]] -= 1 unless b == '0'
    solve(matrix, rhs)
  end

  def source_solution(matrix, index, item, unit = false)
    rhs = Array.new(matrix.length, Rational(0))
    value = unit ? Rational(1) : item.value
    if item.type == 'V'
      rhs[index[item.name]] += value
    else
      a, b = item.nodes
      rhs[index[a]] -= value unless a == '0'
      rhs[index[b]] += value unless b == '0'
    end
    solve(matrix, rhs)
  end

  def analysis(command, args)
    case command
    when '.CURRENT'
      element(args[0])
    when '.VOLTAGE', '.THEVENIN', '.NORTON', '.MAXPOWER', '.ZPARAM'
      args.each { |name| node(name) }
    when '.KCL', '.SENS', '.SUPERPOSITION'
      node(args[0])
    when '.TF'
      node(args[0])
      source = element(args[1])
      raise CircuitError, "not an independent source #{source.name}" unless %w[V I].include?(source.type)
    end
    structure_check
    matrix, rhs, _, index = equations
    solution = solve(matrix, rhs) || raise(CircuitError, 'singular matrix')
    voltage = ->(name, values = solution) { potential(values, index, name) }
    lines = []
    case command
    when '.OP'
      nodes.each { |name| lines << "V(#{name}) = #{formatted(voltage.call(name))}" }
      sources.each { |item| lines << "I(#{item.name}) = #{formatted(solution[index[item.name]])}" }
    when '.CURRENT'
      lines << "I(#{args[0]}) = #{formatted(current(element(args[0]), solution, index))}"
    when '.VOLTAGE'
      lines << "V(#{args[0]},#{args[1]}) = #{formatted(voltage.call(args[0]) - voltage.call(args[1]))}"
    when '.POWER'
      absorbed = delivered = total = Rational(0)
      @elements.each do |item|
        power = (voltage.call(item.nodes[0]) - voltage.call(item.nodes[1])) * current(item, solution, index)
        absorbed += power if power > 0
        delivered -= power if power < 0
        total += power
        lines << "P(#{item.name}) = #{formatted(power)}"
      end
      lines += ["absorbed = #{formatted(absorbed)}", "delivered = #{formatted(delivered)}", "total = #{formatted(total)}"]
    when '.KCL'
      a = args[0]
      total = Rational(0)
      @elements.each do |item|
        x, y = item.nodes
        next unless x == a || y == a
        value = x == y ? Rational(0) : (x == a ? 1 : -1) * current(item, solution, index)
        total += value
        lines << "I(#{item.name}) leaving #{a} = #{formatted(value)}"
      end
      lines << "sum = #{formatted(total)}"
    when '.THEVENIN', '.NORTON', '.MAXPOWER'
      a, b = args
      vth = voltage.call(a) - voltage.call(b)
      z = injection(matrix, index, a, b)
      rth = voltage.call(a, z) - voltage.call(b, z)
      if command == '.NORTON'
        raise CircuitError, 'zero thevenin resistance' if rth == 0
        lines = ["In = #{formatted(vth / rth)}", "Rn = #{formatted(rth)}"]
      elsif command == '.MAXPOWER'
        raise CircuitError, 'nonpositive thevenin resistance' if rth <= 0
        lines = ["RL = #{formatted(rth)}", "Pmax = #{formatted(vth * vth / (4 * rth))}"]
      else
        lines = ["Vth = #{formatted(vth)}", "Rth = #{formatted(rth)}"]
      end
    when '.TF'
      a, name = args
      item = element(name)
      z = source_solution(matrix, index, item, true)
      lines << "gain = #{formatted(voltage.call(a, z))}"
      if item.type == 'V'
        j = z[index[name]]
        lines << (j == 0 ? 'input resistance = INFINITE' : "input resistance = #{formatted(-1 / j)}")
      else
        lines << "input resistance = #{formatted(voltage.call(item.nodes[1], z) - voltage.call(item.nodes[0], z))}"
      end
      lines << "output resistance = #{formatted(voltage.call(a, injection(matrix, index, a, '0')))}"
    when '.SENS'
      a = args[0]
      @elements.each do |item|
        d = Array.new(matrix.length, Rational(0))
        add = ->(row, value) { d[index[row]] += value unless row == '0' }
        x, y, c, e = item.nodes
        case item.type
        when 'R'
          t = current(item, solution, index) / item.value
          add.call(x, t)
          add.call(y, -t)
        when 'I'
          add.call(x, -1)
          add.call(y, 1)
        when 'G', 'F'
          t = item.type == 'G' ? voltage.call(c) - voltage.call(e) : solution[index[item.reference]]
          add.call(x, -t)
          add.call(y, t)
        when 'V'
          add.call(item.name, 1)
        when 'E'
          add.call(item.name, voltage.call(c) - voltage.call(e))
        when 'H'
          add.call(item.name, solution[index[item.reference]])
        end
        lines << "dV(#{a})/d#{item.name} = #{formatted(voltage.call(a, solve(matrix, d)))}"
      end
    when '.ZPARAM'
      a, b, c, d = args
      z1 = injection(matrix, index, a, b)
      z2 = injection(matrix, index, c, d)
      lines = ["z11 = #{formatted(voltage.call(a, z1) - voltage.call(b, z1))}",
               "z12 = #{formatted(voltage.call(a, z2) - voltage.call(b, z2))}",
               "z21 = #{formatted(voltage.call(c, z1) - voltage.call(d, z1))}",
               "z22 = #{formatted(voltage.call(c, z2) - voltage.call(d, z2))}"]
    when '.SUPERPOSITION'
      a = args[0]
      total = Rational(0)
      @elements.select { |item| %w[V I].include?(item.type) }.each do |item|
        value = voltage.call(a, source_solution(matrix, index, item))
        total += value
        lines << "#{item.name}: V(#{a}) = #{formatted(value)}"
      end
      lines << "total: V(#{a}) = #{formatted(total)}"
    end
    lines
  end

  def equivalent(a, b)
    groups = Groups.new(['0'] + nodes)
    @elements.select { |item| item.type == 'V' }.each { |item| groups.join(*item.nodes) }
    a, b = groups.find(a), groups.find(b)
    return ['Req = 0 (0.000000)'] if a == b
    edges = @elements.select { |item| item.type == 'R' }.filter_map do |item|
      x, y = item.nodes.map { |name| groups.find(name) }
      [x, y, 1 / item.value] unless x == y
    end
    connected = reachable(a, edges.map { |x, y, _| [x, y] })
    return ['Req = INFINITE'] unless connected.include?(b)
    labels = (connected.to_a - [b]).sort
    index = labels.each_with_index.to_h
    matrix = Array.new(labels.length) { Array.new(labels.length, Rational(0)) }
    rhs = Array.new(labels.length, Rational(0))
    rhs[index[a]] = Rational(1)
    edges.each do |x, y, g|
      next unless connected.include?(x)
      matrix[index[x]][index[x]] += g unless x == b
      matrix[index[y]][index[y]] += g unless y == b
      if x != b && y != b
        matrix[index[x]][index[y]] -= g
        matrix[index[y]][index[x]] -= g
      end
    end
    ["Req = #{formatted(solve(matrix, rhs)[index[a]])}"]
  end

  def reduce_resistors(a, b)
    return ['Req = 0 (0.000000)'] if a == b
    list = @elements.select { |item| item.type == 'R' }.map(&:dup)
    connected = reachable(a, list.map { |item| item.nodes })
    return ['Req = INFINITE'] unless connected.include?(b)
    list.select! { |item| connected.include?(item.nodes[0]) }
    lines = []
    serial = 0
    loop do
      self_loop = list.index { |item| item.nodes[0] == item.nodes[1] }
      if self_loop
        lines << "remove #{list.delete_at(self_loop).name}"
        next
      end
      degree = Hash.new(0)
      list.each { |item| item.nodes.each { |name| degree[name] += 1 } }
      internal = (degree.keys - [a, b]).sort
      leaf = internal.find { |name| degree[name] == 1 }
      if leaf
        i = list.index { |item| item.nodes.include?(leaf) }
        lines << "remove #{list.delete_at(i).name}"
        next
      end
      pair = nil
      list.each_index do |i|
        j = ((i + 1)...list.length).find { |k| list[i].nodes.sort == list[k].nodes.sort }
        if j
          pair = [i, j]
          break
        end
      end
      if pair
        x, y = pair.map { |i| list[i] }
        value = x.value * y.value / (x.value + y.value)
        terminals = x.nodes
        operator = '||'
      else
        middle = internal.find { |name| degree[name] == 2 }
        break unless middle
        pair = list.each_index.select { |i| list[i].nodes.include?(middle) }
        x, y = pair.map { |i| list[i] }
        terminals = [x.nodes.find { |name| name != middle }, y.nodes.find { |name| name != middle }]
        value = x.value + y.value
        operator = '+'
      end
      serial += 1
      name = "##{serial}"
      lines << "#{name} = #{x.name} #{operator} #{y.name} = #{formatted(value)}"
      list = list.each_with_index.reject { |_, i| pair.include?(i) }.map(&:first)
      list << Element.new(name, 'R', terminals, value)
    end
    lines << (list.length == 1 ? "Req = #{formatted(list[0].value)}" : "not series-parallel: #{list.length} resistors remain")
    lines
  end

  def command(words)
    cmd, *args = words
    raise CircuitError, "unknown command #{cmd}" unless COUNTS.key?(cmd)
    raise CircuitError, "wrong argument count for #{cmd}" unless args.length == COUNTS[cmd]
    return analysis(cmd, args) if ANALYSES.include?(cmd)
    case cmd
    when '.REQ', '.REDUCE'
      args.each { |name| node(name) }
      cmd == '.REQ' ? equivalent(*args) : reduce_resistors(*args)
    when '.SWEEP'
      item = element(args[0])
      from, to, step = args[1, 3].map { |value| number(value) }
      node(args[4])
      raise CircuitError, 'invalid sweep step' if step <= 0
      raise CircuitError, 'invalid sweep range' if from > to
      count = ((to - from) / step).floor + 1
      raise CircuitError, 'too many sweep points' if count > 20
      raise CircuitError, "nonpositive resistance #{item.name}" if item.type == 'R' && from <= 0
      structure_check
      Array.new(count) do |k|
        x = from + k * step
        matrix, rhs, _, index = equations(item.name => x)
        solution = solve(matrix, rhs)
        prefix = "#{item.name} = #{fraction(x)}: "
        prefix + (solution ? "V(#{args[4]}) = #{formatted(potential(solution, index, args[4]))}" : 'singular matrix')
      end
    when '.MATRIX'
      structure_check
      matrix, rhs, labels, = equations
      unknowns = nodes.map { |name| "V(#{name})" } + sources.map { |item| "I(#{item.name})" }
      ["unknowns: #{unknowns.join(' ')}"] + matrix.each_with_index.map { |row, i| "#{labels[i]}: #{row.map { |value| fraction(value) }.join(' ')} | #{fraction(rhs[i])}" }
    when '.CHECK'
      return ['no nodes'] if nodes.empty?
      lines = []
      nodes.each do |name|
        degree = @elements.sum { |item| item.nodes[0, 2].count(name) }
        lines << "dangling node #{name}" if degree < 2
      end
      grounded = grounding
      nodes.each { |name| lines << "floating node #{name}" unless grounded.include?(name) }
      voltage_loops.each { |name| lines << "voltage source loop at #{name}" }
      if lines.empty?
        matrix, rhs, = equations
        lines << 'singular matrix' unless solve(matrix, rhs)
      end
      lines.empty? ? ['ok'] : lines
    when '.ALTER'
      item = element(args[0])
      value = number(args[1])
      raise CircuitError, "nonpositive resistance #{item.name}" if item.type == 'R' && value <= 0
      line = "altered #{item.name}: #{fraction(item.value)} -> #{fraction(value)}"
      item.value = value
      [line]
    when '.DELETE'
      item = element(args[0])
      user = @elements.find { |other| %w[F H].include?(other.type) && other.reference == item.name }
      raise CircuitError, "#{item.name} is referenced by #{user.name}" if user
      @elements.delete(item)
      ["deleted #{item.name}"]
    when '.CLEAR'
      line = "cleared #{@elements.length} elements"
      @elements.clear
      [line]
    when '.NODES'
      return ['no nodes'] if @elements.empty?
      @elements.flat_map(&:nodes).uniq.sort.map do |name|
        "#{name}: #{@elements.select { |item| item.nodes.include?(name) }.map(&:name).join(' ')}"
      end
    when '.PRINT'
      return ['empty netlist'] if @elements.empty?
      @elements.map { |item| ([item.name] + item.nodes + [item.reference, fraction(item.value)].compact).join(' ') }
    end
  end

  def run
    STDIN.each_line.with_index(1) do |input, number|
      line = input.delete_suffix("\n")
      break if line == '.END'
      next if line.start_with?('*')
      begin
        output = line.start_with?('.') ? command(line.split(' ')) : add(line.split(' '))
        output.each { |text| puts text }
      rescue CircuitError => error
        puts "error: line #{number}: #{error.message}"
      end
    end
  end
end

require 'set'
Circuit.new.run
