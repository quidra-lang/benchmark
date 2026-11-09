# frozen_string_literal: true

require_relative 'graph_io'
require_relative 'components'
require_relative 'pagerank'
require_relative 'hits'
require_relative 'report'

class LinkAnalysis
  REGIONS = %w[CORE IN OUT TUBE IN_TENDRIL OUT_TENDRIL OTHER].freeze
  QUANTITIES = %i[in_degree pagerank cheirank authority hub trustrank harmonic].freeze

  def initialize
    data = GraphIO.read
    @pages, @records, @queries, @settings = data.pages, data.links, data.queries, data.settings
    @n = @pages.length
    @nodes = (0...@n).to_a
    @index = @pages.each_with_index.to_h { |page, index| [page.id, index] }
    @hosts = @pages.map(&:host).uniq.sort
    host_index = @hosts.each_with_index.to_h
    @host_of = @pages.map { |page| host_index[page.host] }
    @damping = @settings[:damping]
    @iterations = @settings[:pagerank_iterations]
    @tolerance = @settings[:tolerance]
    @top_k = @settings[:top_k]
    @trusted = @settings[:trusted].map { |id| @index[id] }.sort
    @convergence = []
    @pair_count = (@n * (@n - 1)).div(2)
  end

  def read_links
    @lookup = Array.new(@n) { {} }
    @edges = []
    @ignored = []
    @ignored_counts = Hash.new(0)
    @records.each do |record|
      source, destination = @index[record.source], @index[record.destination]
      reason = if source.nil? || destination.nil?
                 'unknown'
               elsif source == destination
                 'self'
               elsif @lookup[source][destination]
                 'duplicate'
               end
      if reason
        @ignored << [record, reason]
        @ignored_counts[reason] += 1
        next
      end
      @lookup[source][destination] = true
      @edges << [source, destination]
    end
    @edges.sort!
    @outgoing = Array.new(@n) { [] }
    @incoming = Array.new(@n) { [] }
    @edges.each do |source, destination|
      @outgoing[source] << destination
      @incoming[destination] << source
    end
    @incoming.each(&:sort!)
    @weighted = @edges.map { |source, destination| [source, destination, 1] }
    @inter_host = @edges.select { |source, destination| @host_of[source] != @host_of[destination] }
    @dangling = @nodes.select { |vertex| @outgoing[vertex].empty? }
    @no_incoming = @nodes.select { |vertex| @incoming[vertex].empty? }
    @reciprocal = @edges.count { |source, destination| @lookup[destination][source] }
  end

  def undirected_statistics
    @undirected = @nodes.map { |vertex| (@outgoing[vertex] + @incoming[vertex]).uniq.sort }
    adjacency = @undirected.map { |neighbours| neighbours.to_h { |other| [other, true] } }
    @undirected_links = @undirected.sum(&:length).div(2)
    @triangles = 0
    @wedges = 0
    @clustering_pages = 0
    clustering_sum = 0.0
    @nodes.each do |vertex|
      degree = @undirected[vertex].length
      next if degree < 2

      pairs = (degree * (degree - 1)).div(2)
      closed = @undirected[vertex].combination(2).count { |first, second| adjacency[first][second] }
      @triangles += closed
      @wedges += pairs
      @clustering_pages += 1
      clustering_sum += closed.to_f / pairs
    end
    @average_clustering = clustering_sum / @clustering_pages
    @kcore = Array.new(@n, 0)
    remaining = Array.new(@n, true)
    degrees = @undirected.map(&:length)
    left = @n
    level = 0
    while left > 0
      vertex = @nodes.find { |candidate| remaining[candidate] && degrees[candidate] <= level }
      if vertex.nil?
        level += 1
        next
      end
      @kcore[vertex] = level
      remaining[vertex] = false
      left -= 1
      @undirected[vertex].each { |other| degrees[other] -= 1 if remaining[other] }
    end
    @degeneracy = @kcore.max
  end

  def component_statistics
    @scc = Components.strong(@outgoing)
    @component = Array.new(@n)
    @scc.each_with_index { |group, index| group.each { |vertex| @component[vertex] = index } }
    @core = @scc.each_index.min_by { |index| [-@scc[index].length, index] }
    @component_in = Array.new(@scc.length, 0)
    @component_out = Array.new(@scc.length, 0)
    condensation = Array.new(@scc.length) { {} }
    @edges.each do |source, destination|
      first, second = @component[source], @component[destination]
      next if first == second

      @component_out[first] += 1
      @component_in[second] += 1
      condensation[first][second] = true
    end
    condensation = condensation.map { |destinations| destinations.keys.sort }
    @condensation_links = condensation.sum(&:length)
    incoming = Array.new(@scc.length, 0)
    condensation.each { |destinations| destinations.each { |destination| incoming[destination] += 1 } }
    queue = incoming.each_index.select { |index| incoming[index].zero? }
    depth = Array.new(@scc.length, 0)
    cursor = 0
    while cursor < queue.length
      source = queue[cursor]
      cursor += 1
      condensation[source].each do |destination|
        depth[destination] = [depth[destination], depth[source] + 1].max
        incoming[destination] -= 1
        queue << destination if incoming[destination].zero?
      end
    end
    @condensation_depth = depth.max
    @weak = Components.weak(@undirected)
  end

  def bowtie
    from_core = Components.reachable(@outgoing, @scc[@core])
    to_core = Components.reachable(@incoming, @scc[@core])
    @region = Array.new(@n)
    @nodes.each do |vertex|
      @region[vertex] = if @component[vertex] == @core
                          0
                        elsif to_core[vertex]
                          1
                        elsif from_core[vertex]
                          2
                        end
    end
    from_in = Components.reachable(@outgoing, @nodes.select { |vertex| @region[vertex] == 1 })
    to_out = Components.reachable(@incoming, @nodes.select { |vertex| @region[vertex] == 2 })
    @nodes.each do |vertex|
      next unless @region[vertex].nil?

      @region[vertex] = if from_in[vertex] && to_out[vertex]
                          3
                        elsif from_in[vertex]
                          4
                        elsif to_out[vertex]
                          5
                        else
                          6
                        end
    end
    @region_pages = REGIONS.each_index.map { |region| @nodes.select { |vertex| @region[vertex] == region } }
    @region_links = Array.new(REGIONS.length) { Array.new(REGIONS.length, 0) }
    @edges.each { |source, destination| @region_links[@region[source]][@region[destination]] += 1 }
  end

  def distance_statistics
    @harmonic = Array.new(@n, 0.0)
    @distance_counts = Hash.new(0)
    @reachable_pairs = 0
    @distance_sum = 0
    @diameter = 0
    @nodes.each do |source|
      distances = Components.distances(@outgoing, [source])
      @nodes.each do |destination|
        distance = distances[destination]
        next unless distance > 0

        @reachable_pairs += 1
        @distance_sum += distance
        @distance_counts[distance] += 1
        @harmonic[destination] += 1.0 / distance
        if distance > @diameter
          @diameter = distance
          @diameter_pair = [source, destination]
        end
      end
    end
    cumulative = 0
    @effective_diameter = (1..@diameter).find do |distance|
      cumulative += @distance_counts[distance]
      10 * cumulative >= 9 * @reachable_pairs
    end
    @trust_distance = Components.distances(@outgoing, @trusted)
  end

  def total(values, nodes = @nodes)
    result = 0.0
    nodes.each { |vertex| result += values[vertex] }
    result
  end

  def rank_scores(values)
    rounded = values.map { |value| Report.scaled(value) }
    order = values.each_index.sort_by { |vertex| [-rounded[vertex], vertex] }
    ranks = Array.new(values.length)
    order.each_with_index { |vertex, index| ranks[vertex] = index + 1 }
    { values: values, rounded: rounded, order: order, ranks: ranks,
      top: order.select { |vertex| rounded[vertex] > 0 }.first(@top_k) }
  end

  def compute_pagerank(heading, edges, seeds, damping: @damping, count: @n)
    result = PageRank.compute(count, edges, seeds, damping, @iterations, @tolerance)
    @convergence << [heading, result]
    result
  end

  def global_scores
    damping = Report.real(@damping, 4)
    page = compute_pagerank("pagerank damping #{damping}", @weighted, @nodes)
    reversed = @edges.map { |source, destination| [destination, source, 1] }
    chei = compute_pagerank("cheirank damping #{damping}", reversed, @nodes)
    trust = compute_pagerank("trustrank damping #{damping} seeds #{@trusted.length}", @weighted, @trusted)
    hits = HITS.compute(@n, @nodes, @inter_host, @settings[:hits_iterations])
    @rankings = { pagerank: rank_scores(page.values), cheirank: rank_scores(chei.values),
                  authority: rank_scores(hits[:authority]), hub: rank_scores(hits[:hub]),
                  trustrank: rank_scores(trust.values), harmonic: rank_scores(@harmonic) }
    @page_rank = @rankings[:pagerank][:ranks]
    @page_values = page.values
    @trust_values = trust.values
    @trust_ratio = @nodes.map { |vertex| trust.values[vertex] / page.values[vertex] }
    @global_top = @rankings[:pagerank][:order].first(@top_k)
    @contributions = @nodes.map do |destination|
      @incoming[destination].map do |source|
        [source, (@damping * @page_values[source]) / @outgoing[source].length]
      end.sort_by { |source, value| [-Report.scaled(value), source] }.first(3)
    end
  end

  def kendall(first, second)
    net = 0
    @nodes.combination(2) do |left, right|
      x = first[left] <=> first[right]
      y = second[left] <=> second[right]
      next if x.zero? || y.zero?

      net += x == y ? 1 : -1
    end
    net
  end

  def comparisons
    @correlation_values = { in_degree: @incoming.map(&:length) }
    @rankings.each { |name, ranking| @correlation_values[name] = ranking[:rounded] }
    @sweeps = @settings[:damping_sweep].map do |damping|
      result = compute_pagerank("sweep damping #{Report.real(damping, 4)}", @weighted, @nodes, damping: damping)
      ranking = rank_scores(result.values)
      shifts = @nodes.map { |vertex| (ranking[:ranks][vertex] - @page_rank[vertex]).abs }
      { damping: damping, ranking: ranking, overlap: (@global_top & ranking[:order].first(@top_k)).length,
        footrule: shifts.sum, kendall: kendall(@rankings[:pagerank][:rounded], ranking[:rounded]),
        largest: @nodes.min_by { |vertex| [-shifts[vertex], vertex] } }
    end
    @suspects = @rankings[:pagerank][:order].first(@settings[:spam_top]).select do |vertex|
      Report.real(@trust_ratio[vertex], 4).to_f < @settings[:spam_threshold]
    end
    @suspect_hosts = @suspects.map { |vertex| @pages[vertex].host }.uniq.sort
    return if @suspects.empty?

    demoted_edges = @edges.reject do |source, destination|
      @host_of[source] == @host_of[destination] && @suspect_hosts.include?(@pages[source].host)
    end
    @removed_links = @edges.length - demoted_edges.length
    weighted = demoted_edges.map { |source, destination| [source, destination, 1] }
    result = compute_pagerank("demoted damping #{Report.real(@damping, 4)}", weighted, @nodes)
    @demoted = rank_scores(result.values)
  end

  def representative(parent, vertex)
    while parent[vertex] != vertex
      parent[vertex] = parent[parent[vertex]]
      vertex = parent[vertex]
    end
    vertex
  end

  def salsa_side(degrees, connections)
    parent = @nodes.dup
    connections.each do |neighbours|
      next if neighbours.empty?

      root = representative(parent, neighbours.first)
      neighbours.drop(1).each { |other| parent[representative(parent, other)] = root }
    end
    side = @nodes.select { |vertex| degrees[vertex] > 0 }
    groups = {}
    side.each { |vertex| (groups[representative(parent, vertex)] ||= []) << vertex }
    values = Array.new(@n, 0.0)
    groups.each_value do |group|
      edges = group.sum { |vertex| degrees[vertex] }
      denominator = side.length * edges
      group.each { |vertex| values[vertex] = (group.length * degrees[vertex]).to_f / denominator }
    end
    values
  end

  def salsa(edges)
    outgoing = Array.new(@n) { [] }
    incoming = Array.new(@n) { [] }
    edges.each do |source, destination|
      outgoing[source] << destination
      incoming[destination] << source
    end
    { authority: salsa_side(incoming.map(&:length), outgoing),
      hub: salsa_side(outgoing.map(&:length), incoming) }
  end

  def related_counts(vertex, authority:)
    counts = Array.new(@n, 0)
    neighbours = authority ? @incoming[vertex] : @outgoing[vertex]
    neighbours.each do |other|
      list = authority ? @outgoing[other] : @incoming[other]
      list.each { |candidate| counts[candidate] += 1 unless candidate == vertex }
    end
    order = @nodes.select { |candidate| counts[candidate] > 0 }.sort_by { |candidate| [-counts[candidate], candidate] }
    { vertex: vertex, neighbours: neighbours.length, counts: counts, top: order.first(@top_k) }
  end

  def process_queries
    @query_results = @queries.each_with_index.map do |query, index|
      matches = @nodes.select do |vertex|
        query.words.all? do |word|
          word.start_with?('-') ? !@pages[vertex].words.include?(word[1..]) : @pages[vertex].words.include?(word)
        end
      end.sort_by { |vertex| @page_rank[vertex] }
      roots = matches.first(@settings[:root_limit])
      base_set = roots.to_h { |vertex| [vertex, true] }
      roots.each do |vertex|
        (@outgoing[vertex].first(@settings[:neighbor_limit]) + @incoming[vertex].first(@settings[:neighbor_limit])).each do |other|
          base_set[other] = true
        end
      end
      base = base_set.keys.sort
      internal = @edges.select { |source, destination| base_set[source] && base_set[destination] }
      edges = internal.select { |source, destination| @host_of[source] != @host_of[destination] }
      seeds = query.seeds.map { |id| @index[id] }.sort
      result = compute_pagerank("personalized query #{index + 1} damping #{Report.real(@damping, 4)}", @weighted, seeds)
      personal = rank_scores(result.values)
      info = { query: query, matches: matches, roots: roots, base: base, links: edges.length,
               dropped: internal.length - edges.length, personal: personal,
               reach: Components.reachable(@outgoing, seeds).count(true), seed_mass: total(result.values, seeds),
               overlap: (personal[:top] & @global_top).length }
      unless edges.empty?
        hits = HITS.compute(@n, base, edges, @settings[:hits_iterations])
        salsa = salsa(edges)
        info[:authority] = rank_scores(hits[:authority])
        info[:hub] = rank_scores(hits[:hub])
        info[:salsa_authority] = rank_scores(salsa[:authority])
        info[:salsa_hub] = rank_scores(salsa[:hub])
        info[:related] = related_counts(info[:authority][:top].first, authority: true)
        info[:coupled] = related_counts(info[:hub][:top].first, authority: false)
      end
      info
    end
  end

  def host_graph
    groups = @hosts.each_index.map { |host| @nodes.select { |vertex| @host_of[vertex] == host } }
    weights = Hash.new(0)
    internal = Array.new(@hosts.length, 0)
    outgoing_counts = Array.new(@hosts.length, 0)
    incoming_counts = Array.new(@hosts.length, 0)
    @edges.each do |source, destination|
      first, second = @host_of[source], @host_of[destination]
      if first == second
        internal[first] += 1
      else
        weights[[first, second]] += 1
        outgoing_counts[first] += 1
        incoming_counts[second] += 1
      end
    end
    edges = weights.keys.sort.map { |first, second| [first, second, weights[[first, second]]] }
    adjacency = Array.new(@hosts.length) { [] }
    edges.each { |first, second, _weight| adjacency[first] << second }
    @host_components = Components.strong(adjacency)
    @host_edges = edges
    @host_reciprocal = edges.count { |first, second, _weight| weights.key?([second, first]) }
    result = compute_pagerank("host_pagerank damping #{Report.real(@damping, 4)} hosts #{@hosts.length}",
                              edges, @hosts.each_index.to_a, count: @hosts.length)
    @host_ranking = rank_scores(result.values)
    @host_info = groups.each_with_index.map do |vertices, host|
      density = vertices.length >= 2 ? internal[host].to_f / (vertices.length * (vertices.length - 1)) : 0.0
      { pages: vertices.length, core: vertices.count { |vertex| @region[vertex].zero? }, internal: internal[host],
        density: density, outgoing: outgoing_counts[host], incoming: incoming_counts[host],
        dangling: vertices.count { |vertex| @outgoing[vertex].empty? }, page_sum: total(@page_values, vertices),
        top: vertices.min_by { |vertex| @page_rank[vertex] } }
    end
  end

  def ids(vertices)
    vertices.map { |vertex| @pages[vertex].id }
  end

  def rank_lines(ranking, vertices = ranking[:top])
    vertices.each_with_index.map do |vertex, index|
      page = @pages[vertex]
      "#{index + 1} #{page.id} #{Report.real(ranking[:values][vertex])} #{page.host} #{page.title}"
    end
  end

  def distribution(values)
    counts = Hash.new(0)
    values.each { |value| counts[value] += 1 }
    counts.sort.map { |value, count| "#{value} #{count}" }
  end

  def graph_lines
    in_degrees, out_degrees = @incoming.map(&:length), @outgoing.map(&:length)
    lines = ["pages #{@n}", "hosts #{@hosts.length}", "link_rows #{@records.length}", "links #{@edges.length}"]
    %w[unknown self duplicate].each { |reason| lines << "ignored_#{reason} #{@ignored_counts[reason]}" }
    @ignored.each { |record, reason| lines << "ignored line #{record.line} #{record.source},#{record.destination} #{reason}" }
    lines << "intra_host_links #{@edges.length - @inter_host.length}"
    lines << "inter_host_links #{@inter_host.length}"
    lines << "mean_degree #{Report.real(@edges.length.to_f / @n, 4)}"
    lines << "reciprocity #{Report.fraction(@reciprocal, @edges.length)}"
    lines << ['dangling', @dangling.length, *ids(@dangling)].join(' ')
    lines << ['no_in_links', @no_incoming.length, *ids(@no_incoming)].join(' ')
    lines << ['max_in_degree', in_degrees.max, 'pages', *ids(@nodes.select { |vertex| in_degrees[vertex] == in_degrees.max })].join(' ')
    lines << ['max_out_degree', out_degrees.max, 'pages', *ids(@nodes.select { |vertex| out_degrees[vertex] == out_degrees.max })].join(' ')
    lines.concat(['', 'in_degree_distribution'] + distribution(in_degrees))
    lines.concat(['', 'out_degree_distribution'] + distribution(out_degrees))
    lines.concat(['', "undirected_links #{@undirected_links}", "transitivity #{Report.fraction(@triangles, @wedges)}",
                  "average_clustering #{Report.real(@average_clustering, 4)} pages #{@clustering_pages}",
                  "degeneracy #{@degeneracy} pages #{@kcore.count(@degeneracy)}", 'core_distribution'])
    lines.concat(distribution(@kcore))
    lines << ''
    lines << "strong_components #{@scc.length} largest #{@scc[@core].length} singletons #{@scc.count { |group| group.length == 1 }} condensation_links #{@condensation_links}"
    lines << "weak_components #{@weak.length} largest #{@weak.map(&:length).max}"
    lines << "condensation_depth #{@condensation_depth}"
    @scc.each_with_index do |vertices, index|
      next if vertices.length == 1

      line = "scc #{index + 1} size #{vertices.length} min #{@pages[vertices.first].id} incoming #{@component_in[index]} outgoing #{@component_out[index]} pagerank #{Report.real(total(@page_values, vertices))}"
      line += ' sink' if @component_out[index].zero?
      lines << line
    end
    lines.concat(['', "bowtie core_scc #{@core + 1}"])
    @region_pages.each_with_index do |vertices, index|
      line = "#{REGIONS[index]} #{vertices.length} pagerank #{Report.real(total(@page_values, vertices))}"
      line += " top #{@pages[vertices.min_by { |vertex| @page_rank[vertex] }].id}" unless vertices.empty?
      line += ' pages ' + ids(vertices).join(' ') if vertices.length.between?(1, 10)
      lines << line
    end
    lines << 'region_links'
    REGIONS.each_index do |first|
      REGIONS.each_index do |second|
        count = @region_links[first][second]
        lines << "#{REGIONS[first]} #{REGIONS[second]} #{count}" if count > 0
      end
    end
    lines.concat(['', 'distances', "reachable_pairs #{@reachable_pairs}",
                  "average #{Report.fraction(@distance_sum, @reachable_pairs)}",
                  "diameter #{@diameter} from #{@pages[@diameter_pair[0]].id} to #{@pages[@diameter_pair[1]].id}",
                  "effective_diameter #{@effective_diameter}"])
    1.upto(@diameter) { |distance| lines << "#{distance} #{@distance_counts[distance]}" }
    lines
  end

  def pagerank_lines
    lines = ['id,in_degree,out_degree,scc,region,kcore,harmonic,pagerank,pagerank_rank,cheirank,cheirank_rank,authority,hub,trustrank,trust_ratio,trust_distance']
    @nodes.each do |vertex|
      lines << [@pages[vertex].id, @incoming[vertex].length, @outgoing[vertex].length, @component[vertex] + 1,
                REGIONS[@region[vertex]], @kcore[vertex], Report.real(@harmonic[vertex]), Report.real(@page_values[vertex]),
                @page_rank[vertex], Report.real(@rankings[:cheirank][:values][vertex]), @rankings[:cheirank][:ranks][vertex],
                Report.real(@rankings[:authority][:values][vertex]), Report.real(@rankings[:hub][:values][vertex]),
                Report.real(@trust_values[vertex]), Report.real(@trust_ratio[vertex], 4), @trust_distance[vertex]].join(',')
    end
    lines
  end

  def join_blocks(blocks)
    lines = []
    blocks.each_with_index do |block, index|
      lines << '' if index > 0
      lines.concat(block)
    end
    lines
  end

  def ranking_lines
    page_block = ["pagerank top #{@top_k}"] + rank_lines(@rankings[:pagerank])
    page_block << "dangling_mass #{Report.real(total(@page_values, @dangling))}"
    @rankings[:pagerank][:top].each do |vertex|
      fields = ['contributors', @pages[vertex].id]
      @contributions[vertex].each { |source, value| fields.concat([@pages[source].id, Report.real(value)]) }
      page_block << fields.join(' ')
    end
    blocks = [page_block]
    %i[cheirank authority hub trustrank harmonic].each do |name|
      blocks << ["#{name} top #{@top_k}"] + rank_lines(@rankings[name])
    end
    correlation = ['correlation']
    QUANTITIES.combination(2) do |first, second|
      correlation << "#{first} #{second} #{Report.fraction(kendall(@correlation_values[first], @correlation_values[second]), @pair_count)}"
    end
    blocks << correlation
    sweep_lines = ['damping_sweep']
    @sweeps.each do |sweep|
      largest = sweep[:largest]
      sweep_lines << "damping #{Report.real(sweep[:damping], 4)} overlap #{sweep[:overlap]} footrule #{sweep[:footrule]} kendall #{Report.fraction(sweep[:kendall], @pair_count)} largest_shift #{@pages[largest].id} #{@page_rank[largest]} #{sweep[:ranking][:ranks][largest]}"
      sweep_lines << ['top', *ids(sweep[:ranking][:order].first(@top_k))].join(' ')
    end
    blocks << sweep_lines
    spam = ["spam top #{@settings[:spam_top]} threshold #{Report.real(@settings[:spam_threshold], 4)}"]
    @suspects.each do |vertex|
      spam << "suspect #{@pages[vertex].id} rank #{@page_rank[vertex]} pagerank #{Report.real(@page_values[vertex])} trustrank #{Report.real(@trust_values[vertex])} trust_ratio #{Report.real(@trust_ratio[vertex], 4)} trust_distance #{@trust_distance[vertex]} kcore #{@kcore[vertex]} #{@pages[vertex].host}"
    end
    spam.concat(["count #{@suspects.length}", 'trust_by_distance'])
    distances = @trust_distance.uniq.reject { |distance| distance == -1 }.sort
    distances << -1 if @trust_distance.include?(-1)
    distances.each do |distance|
      vertices = @nodes.select { |vertex| @trust_distance[vertex] == distance }
      label = distance == -1 ? 'unreachable' : distance.to_s
      spam << "#{label} pages #{vertices.length} trustrank #{Report.real(total(@trust_values, vertices))} pagerank #{Report.real(total(@page_values, vertices))}"
    end
    blocks << spam
    if @suspects.empty?
      blocks << ['demotion none']
    else
      demotion = ["demotion hosts #{@suspect_hosts.join(' ')} removed_links #{@removed_links}"]
      @demoted[:top].each_with_index do |vertex, index|
        page = @pages[vertex]
        demotion << "#{index + 1} #{page.id} #{Report.real(@demoted[:values][vertex])} was #{@page_rank[vertex]} #{page.host} #{page.title}"
      end
      @suspects.each { |vertex| demotion << "suspect #{@pages[vertex].id} before #{@page_rank[vertex]} after #{@demoted[:ranks][vertex]}" }
      blocks << demotion
    end
    hosts = ["host_graph hosts #{@hosts.length} links #{@host_edges.length} reciprocal #{@host_reciprocal} strong_components #{@host_components.length} largest #{@host_components.map(&:length).max}",
             "host_links top #{@top_k}"]
    @host_edges.sort_by { |first, second, weight| [-weight, first, second] }.first(@top_k).each do |first, second, weight|
      hosts << "#{@hosts[first]} #{@hosts[second]} #{weight}"
    end
    blocks << hosts
    join_blocks(blocks)
  end

  def convergence_lines
    lines = ["iterations #{@iterations} tolerance #{Report.real(@tolerance, 10)}"]
    @convergence.each do |heading, result|
      lines.concat(['', heading])
      result.changes.each_with_index do |change, index|
        lines << "iteration #{index + 1} l1 #{Report.real(change, 10)}" if (index + 1) % 10 == 0
      end
      lines << "converged_at #{result.converged || 'none'}"
    end
    lines
  end

  def counted_lines(info)
    info[:top].each_with_index.map do |vertex, index|
      page = @pages[vertex]
      "#{index + 1} #{page.id} #{info[:counts][vertex]} #{page.host} #{page.title}"
    end
  end

  def query_lines
    blocks = @query_results.each_with_index.map do |info, index|
      query = info[:query]
      lines = ["query #{index + 1} words #{query.words.join(' ')} seeds #{query.seeds.join(' ')}",
               "matched #{info[:matches].length} root #{info[:roots].length} base #{info[:base].length} links #{info[:links]} dropped_intra_host #{info[:dropped]}", 'results']
      lines.concat(rank_lines(@rankings[:pagerank], info[:matches].first(@top_k)))
      lines << "personalized reach #{info[:reach]} seed_mass #{Report.real(info[:seed_mass])}"
      lines.concat(rank_lines(info[:personal]))
      lines << "overlap_with_global #{info[:overlap]}"
      if info[:links].zero?
        lines << 'hits none'
        next lines
      end
      [['hits authorities', :authority], ['hits hubs', :hub],
       ['salsa authorities', :salsa_authority], ['salsa hubs', :salsa_hub]].each do |heading, name|
        lines << heading
        lines.concat(rank_lines(info[name]))
      end
      authority_overlap = (info[:authority][:top] & info[:salsa_authority][:top]).length
      hub_overlap = (info[:hub][:top] & info[:salsa_hub][:top]).length
      authority_hosts = info[:authority][:top].map { |vertex| @pages[vertex].host }.uniq.length
      lines << "hits_salsa_overlap authorities #{authority_overlap} hubs #{hub_overlap} authority_hosts #{authority_hosts}"
      related, coupled = info[:related], info[:coupled]
      lines << "related_to #{@pages[related[:vertex]].id} citing #{related[:neighbours]}"
      lines.concat(counted_lines(related))
      lines << "coupled_to #{@pages[coupled[:vertex]].id} cited #{coupled[:neighbours]}"
      lines.concat(counted_lines(coupled))
      lines
    end
    join_blocks(blocks)
  end

  def host_lines
    lines = ['host,pages,core_pages,internal_links,internal_density,outgoing_links,incoming_links,dangling_pages,page_score_sum,top_page,score,rank']
    @hosts.each_with_index do |host, index|
      info = @host_info[index]
      lines << [host, info[:pages], info[:core], info[:internal], Report.real(info[:density], 4), info[:outgoing],
                info[:incoming], info[:dangling], Report.real(info[:page_sum]), @pages[info[:top]].id,
                Report.real(@host_ranking[:values][index]), @host_ranking[:ranks][index]].join(',')
    end
    lines
  end

  def run
    read_links
    undirected_statistics
    component_statistics
    bowtie
    distance_statistics
    global_scores
    comparisons
    process_queries
    host_graph
    Report.write('graph_stats.txt', graph_lines)
    Report.write('pagerank.csv', pagerank_lines)
    Report.write('rankings.txt', ranking_lines)
    Report.write('convergence.txt', convergence_lines)
    Report.write('queries.txt', query_lines)
    Report.write('hosts.csv', host_lines)
  end
end

LinkAnalysis.new.run if $PROGRAM_NAME == __FILE__
