require 'fileutils'
require 'set'
require_relative 'predicates'
require_relative 'triangulation'
require_relative 'voronoi'
require_relative 'proximity'
require_relative 'plot'

OUTPUT_SECTIONS = {
  'triangulation.txt' => %w[input summary insertions triangles edges hull convex_layers quality],
  'voronoi.txt' => %w[vertices voronoi_edges cells],
  'derived.txt' => %w[nearest components mst proximity degrees empty_circle extent spanner alpha sites queries],
  'plot.txt' => %w[delaunay_plot voronoi_plot]
}.freeze

def read_points
  points = [nil]
  accepted = {}
  rejected = []
  line_count = 0
  File.foreach('input/points.txt', encoding: 'US-ASCII') do |raw|
    line_count += 1
    line = raw.delete_suffix("\n")
    next if line.empty? || line.start_with?('#')

    fields = line.split(' ')
    if fields.size != 2 || fields.any? { |word| !/\A-?[0-9]+\z/.match?(word) }
      rejected << "reject #{line_count} format"
      next
    end
    point = fields.map { |word| word.to_i(10) }
    if point.any? { |value| !value.between?(0, 1000) }
      rejected << "reject #{line_count} range"
      next
    end
    if accepted.key?(point)
      rejected << "reject #{line_count} duplicate #{accepted[point]}"
      next
    end
    accepted[point] = points.size
    points << point
  end
  [points, line_count, rejected]
end

def read_params
  params = { plot: [61, 31], plot_layers: %w[edges hull sites], sections: ['summary'],
             alpha: [], queries: [] }
  File.foreach('input/params.txt', encoding: 'US-ASCII') do |raw|
    line = raw.delete_suffix("\n")
    next if line.empty? || line.start_with?('#')

    name, *values = line.split(' ')
    if name == 'query'
      params[:queries] << line.delete_prefix('query ')
    elsif %w[plot alpha].include?(name)
      params[name.to_sym] = values.map { |word| word.to_i(10) }
    else
      params[name.to_sym] = values
    end
  end
  params
end

class Report
  include Predicates
  include Voronoi
  include Proximity

  def initialize(points, line_count, rejected, params)
    @points = points
    @n = points.size - 1
    @line_count = line_count
    @rejected = rejected
    @params = params
    @site_at = (1..@n).to_h { |site| [points[site], site] }
    @shortest_paths = {}
  end

  def analyze
    build_triangulation
    analyze_triangles
    analyze_voronoi
    analyze_proximity
    analyze_extent
    analyze_layers
    analyze_spanner
    analyze_alpha
    @answers = @params[:queries].map { |query| answer_query(query) }
    draw_plots
  end

  def build_triangulation
    @mesh = Triangulation.new(@points)
    @insertions = (4..@n).map { |site| [site, @mesh.insert(site)] }
    @triangles = [nil, *@mesh.triangles]
    @t = @triangles.size - 1
    @edge_triangles = {}
    @triangles.drop(1).each_with_index do |(a, b, c), index|
      [[a, b], [b, c], [c, a]].each { |edge| @edge_triangles[edge] = index + 1 }
    end
    @edges = @mesh.directed.keys.map(&:sort).uniq.sort
    @e = @edges.size
    @length2 = @edges.to_h { |i, j| [[i, j], d2(@points[i], @points[j])] }
    @hull_next = @mesh.hull_edges.to_h
    @hull_prev = @hull_next.invert
    start = @hull_next.keys.min
    @hull = [start]
    @hull << @hull_next[@hull.last] until @hull_next[@hull.last] == start
    @h = @hull.size
    @hull_edges = @hull.zip(@hull.rotate)
    @hull_perimeter = 0.0
    @hull_area2 = 0
    @hull_edges.each do |first, second|
      x1, y1 = @points[first]
      x2, y2 = @points[second]
      @hull_perimeter += Math.sqrt(d2(@points[first], @points[second]))
      @hull_area2 += x1 * y2 - x2 * y1
    end
    adjacent = Array.new(@n + 1) { [] }
    @edges.each do |first, second|
      adjacent[first] << second
      adjacent[second] << first
    end
    @neighbors = @points.each_index.map do |site|
      neighbor_order(site, adjacent[site], @mesh.directed, @hull_next) if site.positive?
    end
    @degree = [0] + @neighbors.drop(1).map(&:size)
  end

  def analyze_triangles
    @area2 = [0]
    @kind = [nil]
    @min_angles = [0.0]
    @max_angles = [0.0]
    @angle_bins = Array.new(6, 0)
    @min_angle_total = 0.0
    @triangles.drop(1).each do |a, b, c|
      pa, pb, pc = @points.values_at(a, b, c)
      area = orient(pa, pb, pc)
      products = [dot(pa, pb, pc), dot(pb, pc, pa), dot(pc, pa, pb)]
      lengths = [d2(pb, pc), d2(pc, pa), d2(pa, pb)]
      kind = if products.include?(0)
               'right'
             elsif products.min.negative?
               'obtuse'
             else
               'acute'
             end
      shortest = (0..2).min_by { |index| lengths[index] }
      longest = (0..2).max_by { |index| lengths[index] }
      minimum = Math.atan2(area, products[shortest]) * 180.0 / Math::PI
      maximum = Math.atan2(area, products[longest]) * 180.0 / Math::PI
      @area2 << area
      @kind << kind
      @min_angles << minimum
      @max_angles << maximum
      @min_angle_total += minimum
      @angle_bins[(minimum / 10).floor] += 1
    end
    @kind_counts = @kind.drop(1).tally
    @minimum_triangle = (1..@t).min_by { |number| [@min_angles[number], number] }
    @maximum_triangle = (1..@t).max_by { |number| [@max_angles[number], -number] }
  end

  def analyze_voronoi
    @centers = [nil]
    @radius2 = [0.0]
    @positions = [nil]
    @triangles.drop(1).each do |triangle|
      a, b, c = @points.values_at(*triangle)
      center = circumcenter(a, b, c)
      @centers << center
      @radius2 << squared_radius(a, b, c)
      @positions << position(center, @points, @hull)
    end
    @position_counts = @positions.drop(1).tally
    @duals = {}
    @edges.each do |first, second|
      left = @edge_triangles[[first, second]]
      right = @edge_triangles[[second, first]]
      @duals[[first, second]] = if left && right
                                 "segment #{left} #{right}"
                               else
                                 u, v = left ? [first, second] : [second, first]
                                 dx, dy = outward(@points, u, v)
                                 "ray #{left || right} #{dx} #{dy}"
                               end
    end
    @cells = [nil]
    @cell_total = 0.0
    @clip_total = 0.0
    @largest_cell = nil
    (1..@n).each do |site|
      order = @neighbors[site]
      vertices = order.filter_map { |other| @edge_triangles[[site, other]] }
      clipped = clipped_area(@points, site, order)
      cell = { vertices: vertices, clip: clipped, area: nil }
      if @hull_next.key?(site)
        cell[:incoming] = outward(@points, site, @hull_next[site])
        cell[:outgoing] = outward(@points, @hull_prev[site], site)
      else
        cell[:area] = bounded_area(@points[site], @centers.values_at(*vertices))
        @cell_total += cell[:area]
        @largest_cell = site if @largest_cell.nil? || cell[:area] > @cells[@largest_cell][:area]
      end
      @clip_total += clipped
      @cells << cell
    end
  end

  def analyze_proximity
    @nearest = nearest_neighbors(@points, @neighbors)
    @mutual_pairs = (1..@n).filter_map do |site|
      [site, @nearest[site]] if site < @nearest[site] && @nearest[@nearest[site]] == site
    end
    @closest_pair = @edges.min_by { |edge| [@length2[edge], *edge] }
    @components = nearest_components(@nearest)
    @component_number = Array.new(@n + 1, 0)
    @component_pairs = @components.each_with_index.map do |sites, index|
      sites.each { |site| @component_number[site] = index + 1 }
      first = sites.find { |site| site < @nearest[site] && @nearest[@nearest[site]] == site }
      [first, @nearest[first]]
    end
    @nn_edges = (1..@n).map { |site| [site, @nearest[site]].sort }.to_set
    @mst = kruskal(@points, @edges)
    @mst_set = @mst.to_set
    @mst_length = 0.0
    @mst.each { |edge| @mst_length += Math.sqrt(@length2[edge]) }
    @gabriel = @edges.select { |edge| gabriel_edge?(@points, edge, @mesh.directed) }.to_set
    @rng = @edges.select { |edge| relative_neighbor_edge?(@points, edge) }.to_set
    @graph_degrees = { gg: @gabriel, rng: @rng, mst: @mst }.to_h do |name, edges|
      degrees = Array.new(@n + 1, 0)
      edges.each do |first, second|
        degrees[first] += 1
        degrees[second] += 1
      end
      [name, degrees]
    end
  end

  def circle_relation(support, site)
    case support.size
    when 1
      support.first == site ? 0 : -1
    when 2
      first, second = support
      -dot(@points[site], @points[first], @points[second])
    else
      a, b, c = @points.values_at(*support)
      incircle(a, b, c, @points[site])
    end
  end

  def circle_order(first, second, third)
    if orient(@points[first], @points[second], @points[third]).positive?
      [first, second, third]
    else
      [first, third, second]
    end
  end

  def enclosing_circle
    support = nil
    @hull.each_with_index do |first, i|
      next if support && circle_relation(support, first) >= 0

      support = [first]
      i.times do |j|
        second = @hull[j]
        next if circle_relation(support, second) >= 0

        support = [first, second]
        j.times do |k|
          third = @hull[k]
          support = circle_order(first, second, third) if circle_relation(support, third).negative?
        end
      end
    end
    boundary = (1..@n).select { |site| circle_relation(support, site).zero? }
    diameter = boundary.combination(2).find do |first, second|
      boundary.all? { |site| dot(@points[site], @points[first], @points[second]).zero? }
    end
    if diameter
      first, second = @points.values_at(*diameter)
      center = [first[0] + second[0], first[1] + second[1], 2]
      radius2 = d2(first, second).fdiv(4)
    else
      a, b, c = @points.values_at(*circle_order(*boundary))
      center = circumcenter(a, b, c)
      radius2 = squared_radius(a, b, c)
    end
    [center, radius2, boundary]
  end

  def analyze_extent
    @empty_candidates = (1..@t).select { |number| @positions[number] == 'inside' }
    @empty_vertex = @empty_candidates.max_by { |number| [@radius2[number], -number] }
    @diameter = nil
    @diameter2 = -1
    (1...@n).each do |first|
      (first + 1..@n).each do |second|
        length2 = d2(@points[first], @points[second])
        next unless length2 > @diameter2

        @diameter = [first, second]
        @diameter2 = length2
      end
    end
    @width = nil
    @width_edge = nil
    @hull_edges.each do |first, second|
      maximum = @hull.map { |site| orient(@points[first], @points[second], @points[site]) }.max
      width = maximum / Math.sqrt(d2(@points[first], @points[second]))
      if @width.nil? || width < @width
        @width = width
        @width_edge = [first, second]
      end
    end
    @enclosing_center, @enclosing_radius2, @enclosing_sites = enclosing_circle
  end

  def analyze_layers
    remaining = (1..@n).to_a
    @layers = []
    @depth = Array.new(@n + 1, 0)
    until remaining.empty?
      if remaining.size <= 2
        layer = remaining.sort
      else
        ordered = remaining.sort_by { |site| @points[site] }
        lower = []
        ordered.each do |site|
          lower.pop while lower.size >= 2 && orient(
            @points[lower[-2]], @points[lower[-1]], @points[site]
          ) <= 0
          lower << site
        end
        upper = []
        ordered.reverse_each do |site|
          upper.pop while upper.size >= 2 && orient(
            @points[upper[-2]], @points[upper[-1]], @points[site]
          ) <= 0
          upper << site
        end
        layer = lower[0...-1] + upper[0...-1]
        layer = layer.rotate(layer.index(layer.min))
      end
      @layers << layer
      layer.each { |site| @depth[site] = @layers.size }
      remaining -= layer
    end
  end

  def shortest_from(site)
    @shortest_paths[site] ||= dijkstra(@points, @neighbors, site)
  end

  def analyze_spanner
    @pair_count = @n * (@n - 1) / 2
    @maximum_stretch = nil
    @stretch_pair = nil
    @stretch_length = 0.0
    @stretch_distance = 0.0
    total = 0.0
    (1...@n).each do |first|
      distances, = shortest_from(first)
      (first + 1..@n).each do |second|
        length = distances[second]
        distance = Math.sqrt(d2(@points[first], @points[second]))
        stretch = length / distance
        total += stretch
        if @maximum_stretch.nil? || stretch > @maximum_stretch
          @maximum_stretch = stretch
          @stretch_pair = [first, second]
          @stretch_length = length
          @stretch_distance = distance
        end
      end
    end
    @mean_stretch = total / @pair_count
  end

  def analyze_alpha
    @alpha_results = @params[:alpha].map do |alpha|
      selected = (1..@t).select { |number| @radius2[number] <= alpha }
      incidence = Hash.new(0)
      area2 = 0
      selected.each do |number|
        a, b, c = @triangles[number]
        area2 += @area2[number]
        [[a, b], [b, c], [c, a]].each { |edge| incidence[edge.sort] += 1 }
      end
      edges = incidence.keys.to_set
      @gabriel.each { |edge| edges.add(edge) if @length2[edge] <= 4 * alpha }
      sets = Proximity::DisjointSets.new(@n)
      incident_sites = Set.new
      edges.to_a.sort.each do |first, second|
        sets.union(first, second)
        incident_sites.merge([first, second])
      end
      { alpha: alpha, triangles: selected.size, edges: edges.size,
        boundary: incidence.values.count(1), dangling: edges.count { |edge| incidence[edge].zero? },
        isolated: @n - incident_sites.size, components: sets.count,
        holes: sets.count - (@n - edges.size + selected.size), area2: area2 }
    end
  end

  def locate_query(query)
    nearest = (1..@n).min_by { |site| [d2(@points[site], query), site] }
    if @site_at.key?(query)
      location = "vertex #{@site_at[query]}"
    else
      edge = @edges.find do |first, second|
        orient(@points[first], @points[second], query).zero? && dot(query, @points[first], @points[second]).negative?
      end
      triangle = @triangles.drop(1).find do |a, b, c|
        [[a, b], [b, c], [c, a]].all? { |u, v| orient(@points[u], @points[v], query).positive? }
      end unless edge
      location = if edge
                   "edge #{edge.join(' ')}"
                 elsif triangle
                   "triangle #{triangle.join(' ')}"
                 else
                   'outside'
                 end
    end
    "#{location} nearest #{nearest} d2 #{d2(@points[nearest], query)}"
  end

  def walk_query(query)
    path, outside = @mesh.visibility_walk(query, @triangles, @edge_triangles)
    stopping = outside ? "outside #{outside.join(' ')}" : "triangle #{path.last}"
    "steps #{path.size - 1} #{stopping} path #{path.join(' ')}"
  end

  def natural_query(query)
    selected = @triangles.drop(1).select do |triangle|
      a, b, c = @points.values_at(*triangle)
      incircle(a, b, c, query).positive?
    end
    sites = selected.flatten.uniq.sort
    "triangles #{selected.size} sites #{sites.empty? ? '-' : sites.join(' ')}"
  end

  def route_query(first, second)
    path, length = greedy_route(@points, @neighbors, first, second)
    "hops #{path.size - 1} length #{real(length)} path #{path.join(' ')}"
  end

  def path_query(first, second)
    distances, previous = shortest_from(first)
    path = [second]
    path << previous[path.last] until path.last == first
    path.reverse!
    length = distances[second]
    stretch = first == second ? '-' : real(length / Math.sqrt(d2(@points[first], @points[second])))
    "length #{real(length)} stretch #{stretch} hops #{path.size - 1} sites #{path.join(' ')}"
  end

  def neighbors_query(site)
    "degree #{@degree[site]} sites #{@neighbors[site].join(' ')}"
  end

  def edge_query(first, second)
    edge = [first, second].sort
    if @length2.key?(edge)
      gabriel = @gabriel.include?(edge) ? 'yes' : 'no'
      rng = @rng.include?(edge) ? 'yes' : 'no'
      mst = @mst_set.include?(edge) ? 'yes' : 'no'
      return "delaunay len2 #{@length2[edge]} gabriel #{gabriel} rng #{rng} mst #{mst} dual #{@duals[edge]}"
    end
    a, b = @points.values_at(first, second)
    crossings = @edges.filter_map do |u, v|
      p, q = @points.values_at(u, v)
      if orient(a, b, p) * orient(a, b, q) < 0 && orient(p, q, a) * orient(p, q, b) < 0
        "#{u}-#{v}"
      end
    end
    ["missing crossings #{crossings.size}", *crossings].join(' ')
  end

  def answer_query(query)
    name, *values = query.split(' ')
    arguments = values.map { |word| word.to_i(10) }
    if %w[route path neighbors edge].include?(name)
      return "#{query} error unknown_site" if arguments.any? { |site| !site.between?(1, @n) }
      return "#{query} error same_site" if name == 'edge' && arguments[0] == arguments[1]
    end
    answer = case name
             when 'locate' then locate_query(arguments)
             when 'walk' then walk_query(arguments)
             when 'natural' then natural_query(arguments)
             when 'route' then route_query(*arguments)
             when 'path' then path_query(*arguments)
             when 'neighbors' then neighbors_query(*arguments)
             when 'edge' then edge_query(*arguments)
             end
    "#{query} #{answer}"
  end

  def draw_plots
    canvas = Canvas.new(*@params[:plot])
    @params[:plot_layers].each do |layer|
      case layer
      when 'sites'
        @points.drop(1).each { |point| canvas.mark(point, 'o') }
      when 'circle'
        canvas.mark(@centers[@empty_vertex], '@') if @empty_vertex
      else
        edges, character = { 'edges' => [@edges, '.'], 'mst' => [@mst, '*'],
                             'hull' => [@hull_edges, '#'] }.fetch(layer)
        edges.each { |first, second| canvas.line(@points[first], @points[second], character) }
      end
    end
    @delaunay_plot = canvas.framed
    canvas = Canvas.new(*@params[:plot])
    canvas.draw_voronoi(@points)
    @voronoi_plot = canvas.framed
  end

  def real(value)
    format('%.3f', value)
  end

  def section_input
    ["lines #{@line_count}", "accepted #{@n}", "rejected #{@rejected.size}", *@rejected]
  end

  def section_summary
    maximum = if @insertions.empty?
                'max_flips none'
              else
                site, insertion = @insertions.max_by { |s, item| [item[:flips], -s] }
                "max_flips #{site} #{insertion[:flips]}"
              end
    ["sites #{@n}", "triangles #{@t}", "edges #{@e}", "hull_vertices #{@h}",
     "interior_sites #{@n - @h}", "euler #{@n - @e + @t}",
     "flips #{@insertions.sum { |_, item| item[:flips] }}",
     "outside_insertions #{@insertions.count { |_, item| item[:kind] == 'outside' }}", maximum,
     "acute #{@kind_counts.fetch('acute', 0)}", "right #{@kind_counts.fetch('right', 0)}",
     "obtuse #{@kind_counts.fetch('obtuse', 0)}"]
  end

  def section_insertions
    lines = ["init #{@mesh.initial.join(' ')}"]
    @insertions.each do |site, insertion|
      description = if insertion[:kind] == 'inside'
                      "inside #{insertion[:containing].join(' ')}"
                    else
                      "outside #{insertion[:visible]}"
                    end
      lines << "insert #{site} #{description} flips #{insertion[:flips]} " \
        "triangles #{insertion[:triangle_count]} hull #{insertion[:hull_count]}"
    end
    lines
  end

  def section_triangles
    @triangles.drop(1).each_with_index.map do |(a, b, c), index|
      number = index + 1
      adjacent = [[c, b], [a, c], [b, a]].map { |edge| @edge_triangles.fetch(edge, '-') }
      "tri #{number} #{a} #{b} #{c} area2 #{@area2[number]} #{@kind[number]} adj #{adjacent.join(' ')}"
    end
  end

  def section_edges
    @edges.map do |first, second|
      left = @edge_triangles.fetch([first, second], '-')
      right = @edge_triangles.fetch([second, first], '-')
      kind = left != '-' && right != '-' ? 'inner' : 'hull'
      "edge #{first} #{second} #{kind} len2 #{@length2[[first, second]]} left #{left} right #{right}"
    end
  end

  def section_hull
    ["hull_vertices #{@h}", "order #{@hull.join(' ')}", "perimeter #{real(@hull_perimeter)}",
     "area2 #{@hull_area2}"]
  end

  def section_convex_layers
    lines = ["layers #{@layers.size}"]
    @layers.each_with_index do |layer, index|
      lines << "layer #{index + 1} size #{layer.size} sites #{layer.join(' ')}"
    end
    lines
  end

  def section_quality
    lines = ["min_angle #{real(@min_angles[@minimum_triangle])} tri #{@minimum_triangle}",
             "max_angle #{real(@max_angles[@maximum_triangle])} tri #{@maximum_triangle}",
             "mean_min_angle #{real(@min_angle_total / @t)}"]
    lines + @angle_bins.each_with_index.map { |count, index| "bin #{index * 10} #{(index + 1) * 10} #{count}" }
  end

  def section_vertices
    lines = %w[inside on outside].map { |name| "#{name} #{@position_counts.fetch(name, 0)}" }
    (1..@t).each do |number|
      x, y, denominator = @centers[number]
      lines << "v #{number} #{fraction(x, denominator)} #{fraction(y, denominator)} " \
        "r #{real(Math.sqrt(@radius2[number]))} #{@positions[number]}"
    end
    lines
  end

  def section_voronoi_edges
    ["segments #{@e - @h}", "rays #{@h}"] + @edges.map { |edge| "ve #{edge.join(' ')} #{@duals[edge]}" }
  end

  def section_cells
    lines = ["bounded #{@n - @h}", "unbounded #{@h}", "total_area #{real(@cell_total)}",
             "clip_total #{real(@clip_total)}"]
    lines << if @largest_cell
               "largest #{@largest_cell} area #{real(@cells[@largest_cell][:area])}"
             else
               'largest none'
             end
    @cells.drop(1).each_with_index do |cell, index|
      site = index + 1
      vertices = cell[:vertices].join(' ')
      count = cell[:vertices].size
      lines << if cell[:area].nil?
                 "cell #{site} unbounded #{count} clip #{real(cell[:clip])} " \
                   "from #{cell[:incoming].join(' ')} vertices #{vertices} to #{cell[:outgoing].join(' ')}"
               else
                 "cell #{site} bounded #{count} area #{real(cell[:area])} " \
                   "clip #{real(cell[:clip])} vertices #{vertices}"
               end
    end
    lines
  end

  def section_nearest
    lines = ["mutual_pairs #{@mutual_pairs.size}",
             "closest_pair #{@closest_pair.join(' ')} d2 #{@length2[@closest_pair]}"]
    (1..@n).each do |site|
      other = @nearest[site]
      mutual = @nearest[other] == site ? 'mutual' : '-'
      lines << "nn #{site} #{other} d2 #{d2(@points[site], @points[other])} #{mutual}"
    end
    lines
  end

  def section_components
    lines = ["components #{@components.size}"]
    @components.each_with_index do |sites, index|
      lines << "component #{index + 1} size #{sites.size} pair #{@component_pairs[index].join(' ')} sites #{sites.join(' ')}"
    end
    lines
  end

  def section_mst
    longest = @mst.last
    lines = ["edges #{@n - 1}", "total_length #{real(@mst_length)}",
             "longest #{longest.join(' ')} len2 #{@length2[longest]}"]
    lines + @mst.map { |edge| "mst #{edge.join(' ')} len2 #{@length2[edge]}" }
  end

  def section_proximity
    lines = ["delaunay #{@e}", "gabriel #{@gabriel.size}", "rng #{@rng.size}",
             "mst #{@n - 1}", "nn #{@nn_edges.size}"]
    @edges.each do |edge|
      lines << "rng_extra #{edge.join(' ')} len2 #{@length2[edge]}" if @rng.include?(edge) && !@mst_set.include?(edge)
    end
    lines
  end

  def section_degrees
    counts = @degree.drop(1).tally
    lines = ["min #{counts.keys.min}", "max #{counts.keys.max}"]
    counts.keys.sort.each do |degree|
      lines << "degree #{degree} count #{counts[degree]}"
    end
    lines
  end

  def section_empty_circle
    lines = ["candidates #{@empty_candidates.size}"]
    return [*lines, 'none'] unless @empty_vertex

    x, y, denominator = @centers[@empty_vertex]
    lines + ["vertex #{@empty_vertex}", "center #{fraction(x, denominator)} #{fraction(y, denominator)}",
             "radius #{real(Math.sqrt(@radius2[@empty_vertex]))}", "sites #{@triangles[@empty_vertex].join(' ')}"]
  end

  def section_extent
    x, y, denominator = @enclosing_center
    ["diameter #{@diameter.join(' ')} d2 #{@diameter2}", "width #{real(@width)} edge #{@width_edge.join(' ')}",
     "enclosing_center #{fraction(x, denominator)} #{fraction(y, denominator)}",
     "enclosing_radius #{real(Math.sqrt(@enclosing_radius2))}", "enclosing_sites #{@enclosing_sites.join(' ')}"]
  end

  def section_spanner
    ["pairs #{@pair_count}",
     "max_stretch #{real(@maximum_stretch)} pair #{@stretch_pair.join(' ')} " \
       "length #{real(@stretch_length)} distance #{real(@stretch_distance)}", "mean_stretch #{real(@mean_stretch)}"]
  end

  def section_alpha
    @alpha_results.map do |result|
      "alpha #{result[:alpha]} triangles #{result[:triangles]} edges #{result[:edges]} " \
        "boundary #{result[:boundary]} dangling #{result[:dangling]} isolated #{result[:isolated]} " \
        "components #{result[:components]} holes #{result[:holes]} area2 #{result[:area2]}"
    end
  end

  def section_sites
    (1..@n).map do |site|
      x, y = @points[site]
      place = @hull_next.key?(site) ? 'hull' : 'inner'
      "site #{site} #{x} #{y} #{place} dt #{@degree[site]} gg #{@graph_degrees[:gg][site]} " \
        "rng #{@graph_degrees[:rng][site]} mst #{@graph_degrees[:mst][site]} nn #{@nearest[site]} " \
        "comp #{@component_number[site]} depth #{@depth[site]}"
    end
  end

  def section_queries = @answers
  def section_delaunay_plot = @delaunay_plot
  def section_voronoi_plot = @voronoi_plot

  def write
    owners = OUTPUT_SECTIONS.flat_map { |filename, sections| sections.map { |section| [section, filename] } }.to_h
    contents = OUTPUT_SECTIONS.to_h { |filename, _| [filename, []] }
    @params[:sections].each do |section|
      lines = contents.fetch(owners.fetch(section))
      lines << "[#{section}]"
      lines.concat(public_send("section_#{section}"))
    end
    FileUtils.mkdir_p('output')
    contents.each do |filename, lines|
      text = lines.empty? ? '' : lines.join("\n") + "\n"
      File.write(File.join('output', filename), text, encoding: 'US-ASCII')
    end
  end
end

if $PROGRAM_NAME == __FILE__
  points, line_count, rejected = read_points
  report = Report.new(points, line_count, rejected, read_params)
  report.analyze
  report.write
end
