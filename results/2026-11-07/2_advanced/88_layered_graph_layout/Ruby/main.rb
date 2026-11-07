require 'fileutils'
require 'set'
require_relative 'graph_io'
require_relative 'acyclic_layering'
require_relative 'crossing'
require_relative 'coordinates'
require_relative 'canvas'

Edge = Struct.new(:number, :source, :target, :upper, :lower, :reversed, :transitive,
                  :chain, :span, :crossings, :route, :bends, :length, :upper_end, :lower_end)

class GraphLayout
  attr_reader :n, :edges, :vertex_count, :initial_crossings, :final_crossings

  def initialize(graph)
    @graph, @settings = graph, graph.settings
    @ids = graph.nodes.keys.sort
    @numbers = @ids.each_with_index.to_h
    @labels = @ids.map { |id| graph.nodes[id] }
    @n = @ids.size
    @edges = graph.edges.each_with_index.map do |(a, b), i|
      a, b = @numbers[a], @numbers[b]
      Edge.new(i, a, b, a, b, false, false, [], 0, 0, [], 0, 0)
    end
    @names = @ids.map(&:to_s)
    @widths = @labels.map { |s| s.size + 2 }
    @sweeps, @sifts = [], []
    @random = @settings['seed']
  end

  def reachable(start, neighbors)
    found = Set[start]
    pending = [start]
    until pending.empty?
      neighbors[pending.pop].each do |w|
        next if found.include?(w)
        found << w
        pending << w
      end
    end
    found
  end

  def process
    analyze
    prepare_dag
    assign_layers
    insert_dummies
    reduce_crossings
    finish_crossings
    @coordinates = Coordinates.assign(@orders, @upper, @lower, @widths, @n, @settings)
    @x = @coordinates.x
    geometry
    draw_and_route
    find_path
    if @path
      @path.each_cons(2) { |a, b| @canvas.highlight(@drawn.find { |e| e.source == a && e.target == b }.route) }
    end
    @n.times do |v|
      @canvas.box(@labels[v], @bands[@layers[v]], @x[v], @coordinates.left[v], @path&.include?(v))
    end
  end

  def analyze
    up, down = AcyclicLayering.neighbors(@n, @edges.map { |e| [e.source, e.target] })
    @sources = @n.times.count { |v| up[v].empty? && !down[v].empty? }
    @sinks = @n.times.count { |v| down[v].empty? && !up[v].empty? }
    @isolated = @n.times.count { |v| down[v].empty? && up[v].empty? }
    undirected = @n.times.map { |v| up[v] + down[v] }
    remaining = Set.new(0...@n)
    @components = 0
    until remaining.empty?
      remaining.subtract(reachable(remaining.min, undirected))
      @components += 1
    end
    closure = @n.times.map { |v| reachable(v, down) }
    remaining = (0...@n).to_a
    @scc = []
    until remaining.empty?
      v = remaining.first
      group = remaining.select { |w| closure[v].include?(w) && closure[w].include?(v) }
      remaining -= group
      @scc << group if group.size >= 2
    end
  end

  def prepare_dag
    @acyclic = AcyclicLayering.acyclic_order(@n, @edges.map { |e| [e.source, e.target] })
    position = @acyclic.each_with_index.to_h
    @edges.each do |e|
      next unless position[e.source] > position[e.target]
      e.reversed = true
      e.upper, e.lower = e.target, e.source
    end
    _, down = AcyclicLayering.neighbors(@n, @edges.map { |e| [e.upper, e.lower] })
    if @settings['reduce'] == 'on'
      closure = @n.times.map { |v| reachable(v, down) }
      @edges.each do |e|
        e.transitive = !e.reversed && down[e.upper].any? { |w| w != e.lower && closure[w].include?(e.lower) }
      end
    end
    @drawn = @edges.reject(&:transitive)
  end

  def assign_layers
    height, @coffman, @before, @promotion_rounds, @promotions =
      AcyclicLayering.heights(@n, @drawn.map { |e| [e.upper, e.lower] }, @settings)
    levels = height.map { |h| height.max - h }
    used = Set.new(levels)
    @drawn.each { |e| used.merge((levels[e.upper] + 1)...levels[e.lower]) }
    numbers = used.to_a.sort.each_with_index.to_h
    @layers = levels.map { |t| numbers[t] }
    @layer_count = used.size
  end

  def insert_dummies
    @drawn.each do |e|
      first, last = @layers[e.upper], @layers[e.lower]
      e.span = last - first
      e.chain = [e.upper]
      ((first + 1)...last).each do |i|
        v = @layers.size
        @layers << i
        @names << "d#{v - @n + 1}"
        @widths << 1
        e.chain << v
      end
      e.chain << e.lower
    end
    @vertex_count = @layers.size
    @upper, @lower = Array.new(@vertex_count) { [] }, Array.new(@vertex_count) { [] }
    @gaps = Array.new(@layer_count - 1) { [] }
    @drawn.each do |e|
      e.chain.each_cons(2) do |p, q|
        @gaps[@layers[p]] << [p, q, e.number]
        @lower[p] << q
        @upper[q] << p
      end
    end
    @initial = Array.new(@layer_count) { [] }
    visited = Set.new
    visit = lambda do |v|
      unless visited.include?(v)
        visited << v
        @initial[@layers[v]] << v
        @lower[v].each { |w| visit.call(w) }
      end
    end
    @n.times { |v| visit.call(v) }
    @initial_crossings = Crossing.total(@gaps, @initial)
  end

  def copy(orders)
    orders.map(&:dup)
  end

  def reorder(orders, i, reference)
    pos = Crossing.positions(orders)
    current = orders[i]
    movable = current.select { |v| !reference[v].empty? }
    keys = movable.to_h do |v|
      positions = reference[v].map { |w| pos[w] }.sort
      d = positions.size
      key = @settings['heuristic'] == 'barycenter' ? [positions.sum, d] : [positions[(d - 1) / 2] + positions[d / 2], 1]
      [v, key]
    end
    old_position = current.each_with_index.to_h
    movable.sort! do |a, b|
      x, y = keys[a]
      z, w = keys[b]
      comparison = x * w <=> z * y
      comparison.zero? ? old_position[a] <=> old_position[b] : comparison
    end
    next_vertex = movable.each
    orders[i] = current.map { |v| reference[v].empty? ? v : next_vertex.next }
  end

  def exchanges(orders)
    pos = Crossing.positions(orders)
    swaps = 0
    loop do
      changed = false
      orders.each do |layer|
        (0...(layer.size - 1)).each do |j|
          v, w = layer[j], layer[j + 1]
          next unless Crossing.adjacent(v, w, @upper, @lower, pos) > Crossing.adjacent(w, v, @upper, @lower, pos)
          layer[j], layer[j + 1] = w, v
          pos[v], pos[w] = j + 1, j
          swaps += 1
          changed = true
        end
      end
      return swaps unless changed
    end
  end

  def reduce_crossings
    (0..@settings['restarts']).each do |run|
      orders = copy(@initial)
      if run.positive?
        orders.each do |layer|
          (layer.size - 1).downto(1) do |j|
            @random = 48_271 * @random % 2_147_483_647
            k = @random % (j + 1)
            layer[j], layer[k] = layer[k], layer[j]
          end
        end
      end
      count = Crossing.total(@gaps, orders)
      @sweeps << [run, 0, 'initial', 0, 0, count]
      history = [copy(orders)]
      best, best_count, best_sweep = copy(orders), count, 0
      sweep = 1
      loop do
        break if count.zero? || sweep - 1 == @settings['sweeps']
        break if sweep - 1 >= 2 && history[-1] == history[-3]
        before = Crossing.positions(orders)
        indices = sweep.odd? ? (1...@layer_count).to_a : (0...(@layer_count - 1)).to_a.reverse
        indices.each { |i| reorder(orders, i, sweep.odd? ? @upper : @lower) }
        after = Crossing.positions(orders)
        moved = @vertex_count.times.count { |v| before[v] != after[v] }
        swaps = exchanges(orders)
        count = Crossing.total(@gaps, orders)
        @sweeps << [run, sweep, sweep.odd? ? 'down' : 'up', moved, swaps, count]
        history << copy(orders)
        if count < best_count
          best, best_count, best_sweep = copy(orders), count, sweep
        end
        sweep += 1
      end
      if @best_count.nil? || best_count < @best_count
        @orders, @best_count, @best_run, @best_sweep = best, best_count, run, best_sweep
      end
    end
    return unless @settings['sifting'] == 'on'
    round = 0
    loop do
      round += 1
      moves = 0
      @vertex_count.times do |v|
        i = @layers[v]
        original = @orders[i].index(v)
        remaining = @orders[i] - [v]
        costs = (0..remaining.size).map do |p|
          @orders[i] = remaining.dup.insert(p, v)
          Crossing.local(@gaps, @orders, i)
        end
        chosen = costs[original] == costs.min ? original : costs.index(costs.min)
        @orders[i] = remaining.dup.insert(chosen, v)
        moves += 1 if chosen != original
      end
      @sifts << [round, moves, Crossing.total(@gaps, @orders)]
      break if moves.zero?
    end
  end

  def finish_crossings
    @position = Crossing.positions(@orders)
    @gap_crossings = Crossing.gap_counts(@gaps, @orders)
    @final_crossings = @gap_crossings.sum
    @brute = @gaps.sum { |segments| Crossing.brute_force(segments, @position) }
    @gaps.each do |segments|
      segments.combination(2) do |a, b|
        next unless Crossing.cross?(a, b, @position)
        @edges[a[2]].crossings += 1
        @edges[b[2]].crossings += 1
      end
    end
  end

  def tracks(segments)
    bent = segments.select { |p, q, _| @x[p] != @x[q] }
    counts = bent.map(&:first).tally
    buses = bent.group_by { |p, q, _| counts[p] >= 2 ? [0, p] : [1, q] }
    details = buses.map do |(kind, v), members|
      values = members.flat_map { |p, q, _| [@x[p], @x[q]] }
      [values.min, values.max, kind, @x[v], members]
    end.sort_by { |bus| bus.first(4) }
    ends, assigned = [], {}
    details.each do |low, high, _, _, members|
      chosen = ends.index { |last| last + 1 < low } || ends.size
      ends[chosen] = high
      members.each { |p, q, _| assigned[[p, q]] = chosen + 1 }
    end
    gap = [@settings['layer_gap'], ends.size + 2].max
    [ends.size, gap, assigned.transform_values { |t| t + (gap - 2 - ends.size) / 2 }]
  end

  def geometry
    @track_counts, @gap_widths, @offsets = [], [], {}
    @gaps.each do |segments|
      count, gap, offsets = tracks(segments)
      @track_counts << count
      @gap_widths << gap
      @offsets.merge!(offsets)
    end
    @vertical = %w[TB BT].include?(@settings['direction'])
    @thickness = @orders.map { |layer| @vertical ? 1 : layer.map { |v| @widths[v] }.max }
    @bands = [0]
    (@layer_count - 1).times { |i| @bands << @bands[-1] + @thickness[i] + @gap_widths[i] }
    @main = @bands[-1] + @thickness[-1]
    secondary = @vertex_count.times.map { |v| @x[v] + @coordinates.right[v] }.max + 1
    @canvas = Canvas.new(@settings['direction'], @main, secondary)
    @drawn.each do |e|
      e.upper_end = [@bands[@layers[e.upper]] + (@vertical ? 1 : @widths[e.upper]), @x[e.upper]]
      e.lower_end = [@bands[@layers[e.lower]] - 1, @x[e.lower]]
    end
  end

  def draw_and_route
    @vertex_count.times do |v|
      i = @layers[v]
      last = @bands[i] + @thickness[i] - 1
      if v >= @n
        @canvas.main_line(@bands[i], last, @x[v])
      elsif !@vertical && !@lower[v].empty?
        @canvas.main_line(@bands[i] + @widths[v], last, @x[v])
      end
    end
    @gaps.each_with_index do |segments, i|
      segments.each do |p, q, _|
        @canvas.segment(@bands[i] + @thickness[i], @gap_widths[i], @x[p], @x[q], @offsets[[p, q]])
      end
    end
    @drawn.each do |e|
      @canvas.arrow(e.reversed ? e.upper_end : e.lower_end, e.reversed)
      points = [e.upper_end]
      e.chain.each_cons(2) do |p, q|
        next if @x[p] == @x[q]
        i = @layers[p]
        main = @bands[i] + @thickness[i] + @offsets.fetch([p, q])
        points << [main, @x[p]] << [main, @x[q]]
        e.bends += 2
      end
      points << e.lower_end
      e.route = points.map { |point| @canvas.cell(*point) }
      e.route.reverse! if e.reversed
      e.length = 1 + e.route.each_cons(2).sum { |(r, c), (s, d)| (r - s).abs + (c - d).abs }
    end
  end

  def find_path
    return unless @graph.path
    start, goal = @graph.path.map { |id| @numbers[id] }
    following = Array.new(@n) { [] }
    @drawn.each { |e| following[e.source] << e.target }
    parent, queue = { start => nil }, [start]
    until queue.empty?
      v = queue.shift
      following[v].sort.each do |w|
        next if parent.key?(w)
        parent[w] = v
        queue << w
      end
    end
    return unless parent.key?(goal)
    @path = []
    until goal.nil?
      @path.unshift(goal)
      goal = parent[goal]
    end
  end

  def display(vertices)
    vertices.map { |v| @names[v] }.join(' ')
  end

  def edge_name(e)
    "#{@ids[e.source]}->#{@ids[e.target]}"
  end

  def layout_lines
    lines = ["graph #{@graph.name}", 'settings ' + GraphIO::DEFAULTS.keys.map { |k| "#{k}=#{@settings[k]}" }.join(' '),
             'acyclic ' + display(@acyclic)]
    lines << 'labels ' + @coffman.each_with_index.map { |label, v| "#{@names[v]}:#{label}" }.join(' ') if @coffman
    @promotions.each { |round, v, diff| lines << "promote #{round} #{@names[v]} #{diff}" }
    @sweeps.each do |run, sweep, direction, moved, swaps, count|
      line = "sweep #{run} #{sweep} #{direction}"
      line += " moved #{moved} swaps #{swaps}" if sweep.positive?
      lines << line + " crossings #{count}"
    end
    lines << "best run #{@best_run} sweep #{@best_sweep} crossings #{@best_count}"
    @sifts.each { |round, moves, count| lines << "sift #{round} moves #{moves} crossings #{count}" }
    @orders.each_with_index do |vertices, i|
      first, last = @bands[i], @bands[i] + @thickness[i] - 1
      first, last = @main - 1 - last, @main - 1 - first if %w[BT RL].include?(@settings['direction'])
      low = vertices.map { |v| @x[v] - @coordinates.left[v] }.min
      high = vertices.map { |v| @x[v] + @coordinates.right[v] }.max
      positions = vertices.map { |v| "#{@names[v]}@#{@x[v]}" }.join(' ')
      lines << "layer #{i} band #{first} #{last} extent #{low} #{high} : #{positions}"
    end
    @gaps.each_with_index do |segments, i|
      lines << "between #{i} #{i + 1} segments #{segments.size} crossings #{@gap_crossings[i]} tracks #{@track_counts[i]} gap #{@gap_widths[i]}"
    end
    variants = Coordinates::VARIANTS.map { |k| "#{k}=#{@coordinates.blocks[k]}/#{@coordinates.widths[k]}" }.join(' ')
    lines << "bk conflicts #{@coordinates.conflicts.size} #{variants} smallest #{@coordinates.smallest}"
    @orders.flatten.each do |v|
      values = Coordinates::VARIANTS.map { |k| "#{k} #{@coordinates.aligned[k][v]}" }.join(' ')
      lines << "vertex #{@names[v]} layer #{@layers[v]} pos #{@position[v]} #{values} x #{@x[v]}"
    end
    @edges.each do |e|
      line = "edge #{@ids[e.source]} #{@ids[e.target]}"
      if e.transitive
        lines << line + ' transitive'
        next
      end
      line += ' reversed' if e.reversed
      chain = e.reversed ? e.chain.reverse : e.chain
      lines << line + " span #{e.span} crossings #{e.crossings} bends #{e.bends} path #{chain.map { |v| @x[v] }.join(' ')} route #{e.route.map { |p| p.join(',') }.join(' ')}"
    end
    lines << 'end'
  end

  def edge_set_line(kind)
    selected = @edges.select { |e| e.public_send(kind) }
    ([kind.to_s, selected.size] + selected.map { |e| edge_name(e) }).join(' ')
  end

  def statistics_lines
    lines = ["graph #{@graph.name}", "nodes #{@n} edges #{@edges.size} self_loops #{@graph.self_loops} duplicates #{@graph.duplicates}",
             "sources #{@sources} sinks #{@sinks} isolated #{@isolated} components #{@components}"]
    @scc.each { |group| lines << 'scc ' + display(group) }
    lines << edge_set_line(:reversed) << edge_set_line(:transitive)
    max_nodes = @orders.map { |layer| layer.count { |v| v < @n } }.max
    lines << "layers #{@layer_count} max_nodes #{max_nodes} max_vertices #{@orders.map(&:size).max}"
    lines << (@settings['promotion'] == 'on' ? "promotion rounds #{@promotion_rounds} accepted #{@promotions.size} dummies_before #{@before}" : 'promotion off')
    spans = @drawn.map(&:span).tally
    lines << "dummies #{@vertex_count - @n} span_total #{@drawn.sum(&:span)} span_max #{spans.keys.max || 0}"
    lines << (spans.empty? ? 'spans none' : 'spans ' + spans.sort.map { |span, count| "#{span}:#{count}" }.join(' '))
    long = @drawn.select { |e| e.span >= 2 }
    vertical = long.count { |e| e.chain[1...-1].map { |v| @x[v] }.uniq.size == 1 }
    lines << "long_edges #{long.size} vertical #{vertical}"
    lines << "crossings initial #{@initial_crossings} swept #{@best_count} best_run #{@best_run} best_sweep #{@best_sweep} final #{@final_crossings} brute #{@brute}"
    segments = @gaps.flatten(1)
    straight = segments.count { |p, q, _| @x[p] == @x[q] }
    offset = segments.sum { |p, q, _| (@x[p] - @x[q]).abs }
    lines << "segments #{segments.size} straight #{straight} bent #{segments.size - straight} offset #{offset}"
    route = "routes length #{@drawn.sum(&:length)} bends #{@drawn.sum(&:bends)}"
    unless @drawn.empty?
      longest = @drawn.max_by { |e| [e.length, -e.number] }
      route += " longest #{edge_name(longest)} #{longest.length}"
    end
    lines << route
    lines << "canvas width #{@canvas.columns} height #{@canvas.rows} crossing_cells #{@canvas.crossing_cells}"
    if @graph.path
      line = "path #{@graph.path.join(' ')}"
      lines << line + (@path ? " hops #{@path.size - 1} : #{display(@path)}" : ' none')
    end
    lines << 'end'
  end

  def csv_lines
    @sweeps.map { |run, sweep, _, _, _, count| "#{@graph.name},#{run},#{sweep},#{count}" }
  end

  def drawing_lines
    ["graph #{@graph.name} #{@canvas.columns}x#{@canvas.rows}"] + @canvas.drawing
  end
end

def main
  layouts, stats, csv, drawings = [], [], ['graph,run,sweep,crossings'], []
  totals = Hash.new(0)
  GraphIO.read.each do |graph|
    totals['graphs'] += 1
    if graph.error
      kind, number = graph.error
      error = ["graph #{graph.name}", "error #{kind} line #{number}", 'end']
      layouts.concat(error)
      stats.concat(error)
      drawings << ["graph #{graph.name} error #{kind}"]
      totals['errors'] += 1
      next
    end
    layout = GraphLayout.new(graph)
    layout.process
    layouts.concat(layout.layout_lines)
    stats.concat(layout.statistics_lines)
    csv.concat(layout.csv_lines)
    drawings << layout.drawing_lines
    totals['laid_out'] += 1
    totals['nodes'] += layout.n
    totals['edges'] += layout.edges.size
    totals['dummies'] += layout.vertex_count - layout.n
    totals['crossings_initial'] += layout.initial_crossings
    totals['crossings_final'] += layout.final_crossings
  end
  keys = %w[graphs laid_out errors nodes edges dummies crossings_initial crossings_final]
  stats << 'summary ' + keys.map { |key| "#{key} #{totals[key]}" }.join(' ')
  FileUtils.mkdir_p('output')
  { 'layout.txt' => layouts.join("\n"), 'stats.txt' => stats.join("\n"),
    'crossings.csv' => csv.join("\n"), 'drawings.txt' => drawings.map { |d| d.join("\n") }.join("\n\n") }.each do |file, text|
    File.write(File.join('output', file), text.empty? ? '' : text + "\n")
  end
end

main if $PROGRAM_NAME == __FILE__
