require 'set'

class Graph
  attr_reader :n, :adj

  def initialize(n)
    @n = n
    @adj = Array.new(n) { Array.new(n, false) }
  end

  def join(u, v)
    @adj[u][v] = @adj[v][u] = true
  end

  def vertices
    (0...@n).to_a
  end

  def neighbors(v)
    vertices.select { |w| @adj[v][w] }
  end

  def edges
    @edges ||= vertices.flat_map { |u| ((u + 1)...@n).select { |v| @adj[u][v] }.map { |v| [u, v] } }
  end

  def degrees
    @degrees ||= vertices.map { |v| neighbors(v).length }
  end

  def refine(colors)
    rounds = 0
    loop do
      signatures = vertices.map { |v| [colors[v], neighbors(v).map { |w| colors[w] }.sort] }
      ordered = signatures.uniq.sort
      fresh = signatures.map { |s| ordered.index(s) }
      return [colors, rounds] if fresh.uniq.length == colors.uniq.length
      colors = fresh
      rounds += 1
    end
  end

  def stable
    @stable ||= refine(degrees.map { |d| degrees.uniq.sort.index(d) })
  end

  def individualize(colors, v)
    colors.each_with_index.map { |c, w| c < colors[v] || w == v ? c : c + 1 }
  end

  def leaf_string(labels)
    inverse = Array.new(@n)
    labels.each_with_index { |label, v| inverse[label] = v }
    vertices.flat_map { |u| ((u + 1)...@n).map { |v| @adj[inverse[u]][inverse[v]] ? '1' : '0' } }.join
  end

  def canonical
    return @canonical if @canonical
    nodes = 0
    leaves = 0
    best = nil
    labels = nil
    winners = []
    visit = lambda do |colors|
      nodes += 1
      if colors.uniq.length == @n
        leaves += 1
        string = leaf_string(colors)
        if best.nil? || string > best
          best = string
          labels = colors
          winners = [colors]
        elsif string == best
          winners << colors
        end
      else
        cells = colors.uniq.sort.map { |c| vertices.select { |v| colors[v] == c } }
        cell = cells.select { |c| c.length > 1 }.min_by { |c| [c.length, colors[c.first]] }
        cell.each { |v| visit.call(refine(individualize(colors, v))[0]) }
      end
    end
    visit.call(stable[0])
    @canonical = { nodes: nodes, leaves: leaves, string: best, labels: labels, winners: winners }
  end

  def invariants
    return @invariants if @invariants
    components = []
    seen = []
    vertices.each do |start|
      next if seen.include?(start)
      queue = [start]
      seen << start
      queue.each do |u|
        neighbors(u).each do |v|
          next if seen.include?(v)
          seen << v
          queue << v
        end
      end
      components << queue.length
    end
    girth = nil
    eccentricities = []
    bipartite = true
    vertices.each do |start|
      distance = Array.new(@n)
      parent = Array.new(@n)
      distance[start] = 0
      queue = [start]
      queue.each do |u|
        neighbors(u).each do |v|
          if distance[v].nil?
            distance[v] = distance[u] + 1
            parent[v] = u
            queue << v
          elsif parent[u] != v
            length = distance[u] + distance[v] + 1
            girth = length if girth.nil? || length < girth
          end
          bipartite = false if !distance[v].nil? && distance[u] % 2 == distance[v] % 2
        end
      end
      eccentricities << distance.compact.max
    end
    triangles = vertices.combination(3).count { |a, b, c| @adj[a][b] && @adj[a][c] && @adj[b][c] }
    @invariants = {
      degrees: degrees.sort.reverse, triangles: triangles, sizes: components.sort.reverse,
      components: components.length, girth: girth || 'none',
      diameter: components.length == 1 ? eccentricities.max : 'INF',
      radius: components.length == 1 ? eccentricities.min : 'INF', bipartite: bipartite ? 'yes' : 'no'
    }
  end

  def clique
    @n.downto(1) do |size|
      found = vertices.combination(size).find { |set| set.combination(2).all? { |u, v| @adj[u][v] } }
      return found if found
    end
  end

  def coloring
    1.upto(@n) do |limit|
      colors = Array.new(@n, -1)
      search = lambda do |v, maximum|
        return true if v == @n
        0.upto([limit - 1, maximum + 1].min) do |c|
          next if (0...v).any? { |w| @adj[v][w] && colors[w] == c }
          colors[v] = c
          return true if search.call(v + 1, [maximum, c].max)
        end
        colors[v] = -1
        false
      end
      return [limit, colors] if search.call(0, -1)
    end
  end
end

class GraphError < StandardError; end

class GraphLab
  SCHEMAS = {
    'GRAPH' => [2, nil, %i[name num], :edge], 'CYCLE' => [2, 2, %i[name num]],
    'PATH' => [2, 2, %i[name num]], 'COMPLETE' => [2, 2, %i[name num]],
    'BIPARTITE' => [3, 3, %i[name num num]], 'STAR' => [2, 2, %i[name num]],
    'WHEEL' => [2, 2, %i[name num]], 'PETERSEN' => [1, 1, %i[name]],
    'HYPERCUBE' => [2, 2, %i[name num]], 'CIRCULANT' => [3, nil, %i[name num], :num],
    'GRID' => [3, 3, %i[name num num]], 'COMPLEMENT' => [2, 2, %i[name graph]],
    'LINE' => [2, 2, %i[name graph]], 'PRODUCT' => [3, 3, %i[name graph graph]],
    'UNION' => [3, 3, %i[name graph graph]], 'RELABEL' => [2, nil, %i[name graph], :num],
    'INDUCED' => [3, nil, %i[name graph], :num], 'CANONIZE' => [2, 2, %i[name graph]],
    'DELETE' => [1, 1, %i[graph]], 'LIST' => [0, 0, []], 'SHOW' => [1, 1, %i[graph]],
    'INVARIANTS' => [1, 1, %i[graph]], 'REFINE' => [1, nil, %i[graph], :num],
    'CANON' => [1, 1, %i[graph]], 'ISO' => [2, 2, %i[graph graph]],
    'AUT' => [1, 1, %i[graph]], 'SUBISO' => [2, 2, %i[graph graph]],
    'CLASSIFY' => [1, 1, %i[num]]
  }.freeze
  NAME = /\A[a-z][a-z0-9]{0,7}\z/
  NUMBER = /\A(?:0|[1-9][0-9]{0,2})\z/
  EDGE = /\A(?:0|[1-9][0-9]{0,2})-(?:0|[1-9][0-9]{0,2})\z/

  def initialize
    @graphs = {}
    @classes = {}
  end

  def validate(command, args)
    schema = SCHEMAS[command]
    raise GraphError, "unknown command #{command}" unless schema
    minimum, maximum, types, tail = schema
    raise GraphError, 'bad arguments' if args.length < minimum || (maximum && args.length > maximum)
    args.each_with_index do |word, i|
      type = types[i] || tail
      regex = type == :num ? NUMBER : (type == :edge ? EDGE : NAME)
      raise GraphError, 'bad arguments' unless regex.match?(word)
    end
    types.each_with_index do |type, i|
      raise GraphError, "no graph #{args[i]}" if type == :graph && !@graphs.key?(args[i])
    end
  end

  def size_check(value, minimum = 1, maximum = 16)
    raise GraphError, 'bad value' if value < minimum
    raise GraphError, 'too large' if value > maximum
  end

  def define(command, args)
    name = args[0]
    number = args[1].to_i
    source = @graphs[args[1]]
    case command
    when 'GRAPH'
      size_check(number)
      graph = Graph.new(number)
      args.drop(2).each do |word|
        u, v = word.split('-').map(&:to_i)
        raise GraphError, "bad edge #{word}" if u >= number || v >= number || u == v
        raise GraphError, "duplicate edge #{word}" if graph.adj[u][v]
        graph.join(u, v)
      end
    when 'PATH', 'CYCLE', 'COMPLETE', 'STAR', 'WHEEL', 'CIRCULANT'
      minimum = %w[CYCLE WHEEL CIRCULANT].include?(command) ? 3 : 1
      size_check(number, minimum, %w[STAR WHEEL].include?(command) ? 15 : 16)
      n = number + (%w[STAR WHEEL].include?(command) ? 1 : 0)
      graph = Graph.new(n)
      case command
      when 'PATH', 'CYCLE'
        (0...(n - 1)).each { |v| graph.join(v, v + 1) }
        graph.join(n - 1, 0) if command == 'CYCLE'
      when 'COMPLETE'
        graph.vertices.combination(2) { |u, v| graph.join(u, v) }
      when 'STAR', 'WHEEL'
        (1...n).each { |v| graph.join(0, v) }
        if command == 'WHEEL'
          (1...(n - 1)).each { |v| graph.join(v, v + 1) }
          graph.join(n - 1, 1)
        end
      when 'CIRCULANT'
        jumps = args.drop(2).map(&:to_i)
        if jumps.any? { |j| j.zero? || 2 * j > n } || jumps.each_cons(2).any? { |a, b| a >= b }
          raise GraphError, 'bad value'
        end
        graph.vertices.each { |v| jumps.each { |j| graph.join(v, (v + j) % n) } }
      end
    when 'BIPARTITE', 'GRID'
      a, b = args.drop(1).map(&:to_i)
      raise GraphError, 'bad value' if a.zero? || b.zero?
      size_check(command == 'GRID' ? a * b : a + b)
      graph = Graph.new(command == 'GRID' ? a * b : a + b)
      a.times do |x|
        b.times do |y|
          if command == 'BIPARTITE'
            graph.join(x, a + y)
          else
            graph.join(x * b + y, x * b + y + 1) if y + 1 < b
            graph.join(x * b + y, (x + 1) * b + y) if x + 1 < a
          end
        end
      end
    when 'PETERSEN'
      graph = Graph.new(10)
      5.times do |i|
        graph.join(i, (i + 1) % 5)
        graph.join(i, i + 5)
        graph.join(5 + i, 5 + (i + 2) % 5)
      end
    when 'HYPERCUBE'
      size_check(number, 1, 4)
      graph = Graph.new(2**number)
      graph.vertices.each { |v| number.times { |bit| graph.join(v, v ^ (1 << bit)) } }
    when 'COMPLEMENT'
      graph = Graph.new(source.n)
      source.vertices.combination(2) { |u, v| graph.join(u, v) unless source.adj[u][v] }
    when 'LINE'
      raise GraphError, 'no edges' if source.edges.empty?
      size_check(source.edges.length)
      graph = Graph.new(source.edges.length)
      graph.vertices.combination(2) { |u, v| graph.join(u, v) unless (source.edges[u] & source.edges[v]).empty? }
    when 'PRODUCT', 'UNION'
      other = @graphs[args[2]]
      size_check(command == 'PRODUCT' ? source.n * other.n : source.n + other.n)
      if command == 'PRODUCT'
        graph = Graph.new(source.n * other.n)
        source.vertices.each { |x| other.edges.each { |u, v| graph.join(x * other.n + u, x * other.n + v) } }
        other.vertices.each { |y| source.edges.each { |u, v| graph.join(u * other.n + y, v * other.n + y) } }
      else
        graph = Graph.new(source.n + other.n)
        source.edges.each { |u, v| graph.join(u, v) }
        other.edges.each { |u, v| graph.join(source.n + u, source.n + v) }
      end
    when 'RELABEL', 'CANONIZE'
      labels = command == 'CANONIZE' ? source.canonical[:labels] : args.drop(2).map(&:to_i)
      raise GraphError, 'bad permutation' unless labels.sort == source.vertices
      graph = Graph.new(source.n)
      source.edges.each { |u, v| graph.join(labels[u], labels[v]) }
    when 'INDUCED'
      selected = args.drop(2).map(&:to_i)
      raise GraphError, 'bad vertices' if selected.any? { |v| v >= source.n } || selected.uniq.length != selected.length
      graph = Graph.new(selected.length)
      graph.vertices.combination(2) { |u, v| graph.join(u, v) if source.adj[selected[u]][selected[v]] }
    end
    verb = @graphs.key?(name) ? 'redefined' : 'defined'
    @graphs[name] = graph
    puts "#{verb} #{name} n #{graph.n} m #{graph.edges.length}"
  end

  def show_invariants(name, graph)
    inv = graph.invariants
    puts "invariants #{name}"
    puts "degrees #{inv[:degrees].join(' ')}"
    puts "edges #{graph.edges.length} triangles #{inv[:triangles]}"
    puts "components #{inv[:components]} sizes #{inv[:sizes].join(' ')}"
    puts "girth #{inv[:girth]} diameter #{inv[:diameter]} radius #{inv[:radius]}"
    puts "bipartite #{inv[:bipartite]}"
    if graph.n > 12
      puts 'clique -', 'chromatic -'
    else
      clique = graph.clique
      count, colors = graph.coloring
      puts "clique #{clique.length} #{clique.join(' ')}"
      puts "chromatic #{count} #{colors.join(' ')}"
    end
  end

  def isomorphism(a, b)
    av = a.invariants
    bv = b.invariants
    tests = [[:vertices, a.n, b.n], [:edges, a.edges.length, b.edges.length],
             [:degrees, av[:degrees], bv[:degrees]], [:triangles, av[:triangles], bv[:triangles]],
             [:components, av[:components], bv[:components]], [:girth, av[:girth], bv[:girth]],
             [:diameter, av[:diameter], bv[:diameter]], [:bipartite, av[:bipartite], bv[:bipartite]]]
    tests.each do |kind, x, y|
      next if x == y
      puts "not isomorphic #{kind}#{kind == :degrees ? '' : " #{x} #{y}"}"
      return
    end
    profile = ->(g) { [g.stable[1], g.stable[0].uniq.sort.map { |c| g.stable[0].count(c) }] }
    if profile.call(a) != profile.call(b)
      puts 'not isomorphic refinement'
    elsif a.canonical[:string] != b.canonical[:string]
      puts 'not isomorphic canonical'
    else
      inverse = Array.new(b.n)
      b.canonical[:labels].each_with_index { |label, v| inverse[label] = v }
      puts 'isomorphic'
      puts "mapping #{a.canonical[:labels].map { |c| inverse[c] }.join(' ')}"
    end
  end

  def automorphisms(name, graph)
    canon = graph.canonical
    inverse = Array.new(graph.n)
    canon[:labels].each_with_index { |label, v| inverse[label] = v }
    vertex_parent = graph.vertices
    edge_parent = (0...graph.edges.length).to_a
    find = lambda do |parents, x|
      x = parents[x] while parents[x] != x
      x
    end
    unite = lambda { |parents, x, y| parents[find.call(parents, x)] = find.call(parents, y) }
    edge_index = graph.edges.each_with_index.to_h
    canon[:winners].each do |labels|
      mapping = labels.map { |label| inverse[label] }
      graph.vertices.each { |v| unite.call(vertex_parent, v, mapping[v]) }
      graph.edges.each_with_index do |(u, v), i|
        unite.call(edge_parent, i, edge_index[[mapping[u], mapping[v]].sort])
      end
    end
    vertex_orbits = graph.vertices.group_by { |v| find.call(vertex_parent, v) }.values.sort_by(&:first)
    edge_orbits = (0...graph.edges.length).group_by { |i| find.call(edge_parent, i) }.values.sort_by(&:first)
    puts "aut #{name} order #{canon[:winners].length}"
    puts "vertex orbits #{vertex_orbits.length}"
    vertex_orbits.each { |orbit| puts "orbit #{orbit.join(' ')}" }
    puts "edge orbits #{edge_orbits.length}"
    edge_orbits.each { |orbit| puts "orbit #{orbit.map { |i| graph.edges[i].join('-') }.join(' ')}" }
    puts "transitive vertex #{vertex_orbits.length == 1 ? 'yes' : 'no'} edge #{edge_orbits.length == 1 ? 'yes' : 'no'}"
  end

  def subiso(pattern_name, target_name, pattern, target)
    count = 0
    induced_count = 0
    examples = []
    mapping = []
    search = lambda do |depth, induced|
      if depth == pattern.n
        count += 1
        induced_count += 1 if induced
        examples << [mapping.dup, induced] if examples.length < 5
        return
      end
      target.vertices.each do |v|
        next if mapping.include?(v)
        next unless (0...depth).all? { |u| !pattern.adj[depth][u] || target.adj[v][mapping[u]] }
        still_induced = induced && (0...depth).all? { |u| pattern.adj[depth][u] == target.adj[v][mapping[u]] }
        mapping << v
        search.call(depth + 1, still_induced)
        mapping.pop
      end
    end
    search.call(0, true) if pattern.n <= target.n
    order = pattern.canonical[:winners].length
    puts "subiso #{pattern_name} #{target_name} embeddings #{count} induced #{induced_count}"
    puts "copies #{count / order} induced #{induced_count / order}"
    examples.each { |map, induced| puts "embedding #{map.join(' ')}#{induced ? ' induced' : ''}" }
  end

  def classify(n)
    size_check(n, 1, 5)
    unless @classes.key?(n)
      levels = [Set['0' * (n * (n - 1) / 2)]]
      (n * (n - 1) / 2).times do |m|
        next_level = Set.new
        levels[m].each do |string|
          base_edges = (0...n).to_a.combination(2).to_a
          string.each_char.with_index do |bit, extra|
            next unless bit == '0'
            graph = Graph.new(n)
            base_edges.each_with_index { |(u, v), i| graph.join(u, v) if string[i] == '1' || i == extra }
            next_level << graph.canonical[:string]
          end
        end
        levels << next_level
      end
      @classes[n] = levels
    end
    levels = @classes[n]
    puts "classify #{n} total #{levels.sum(&:length)}"
    levels.each_with_index do |strings, m|
      puts "edges #{m} count #{strings.length} #{strings.to_a.sort.map { |s| s.empty? ? '-' : s }.join(' ')}"
    end
  end

  def execute(line)
    command, *args = line.split(' ')
    validate(command, args)
    if SCHEMAS[command][2][0] == :name
      define(command, args)
      return
    end
    name = args[0]
    graph = @graphs[name]
    case command
    when 'DELETE'
      @graphs.delete(name)
      puts "deleted #{name}"
    when 'LIST'
      puts "graphs #{@graphs.length}"
      @graphs.keys.sort.each { |key| puts "#{key} n #{@graphs[key].n} m #{@graphs[key].edges.length}" }
    when 'SHOW'
      puts "graph #{name} n #{graph.n} m #{graph.edges.length}"
      graph.vertices.each do |v|
        neighbors = graph.neighbors(v)
        puts "#{v}:#{neighbors.empty? ? '' : " #{neighbors.join(' ')}"}"
      end
    when 'INVARIANTS'
      show_invariants(name, graph)
    when 'REFINE'
      selected = args.drop(1).map(&:to_i)
      raise GraphError, 'bad vertices' if selected.any? { |v| v >= graph.n }
      colors, rounds = graph.stable
      selected.each do |v|
        raise GraphError, "singleton #{v}" if colors.count(colors[v]) == 1
        colors, added = graph.refine(graph.individualize(colors, v))
        rounds += added
      end
      puts "refine #{name} rounds #{rounds} cells #{colors.uniq.length}"
      colors.uniq.sort.each { |c| puts "#{c}: #{graph.vertices.select { |v| colors[v] == c }.join(' ')}" }
    when 'CANON'
      result = graph.canonical
      puts "canon #{name} nodes #{result[:nodes]} leaves #{result[:leaves]}"
      puts "labels #{result[:labels].join(' ')}"
      puts "string #{result[:string].empty? ? '-' : result[:string]}"
    when 'ISO'
      isomorphism(graph, @graphs[args[1]])
    when 'AUT'
      automorphisms(name, graph)
    when 'SUBISO'
      subiso(name, args[1], graph, @graphs[args[1]])
    when 'CLASSIFY'
      classify(name.to_i)
    end
  rescue GraphError => error
    puts "error: #{error.message}"
  end
end

lab = GraphLab.new
count = STDIN.gets.to_i
count.times { lab.execute(STDIN.gets.chomp) }
