module GraphIO
  DEFAULTS = { 'layering' => 'longest', 'width' => 4, 'promotion' => 'off',
               'heuristic' => 'barycenter', 'sweeps' => 12, 'node_sep' => 2,
               'dummy_sep' => 1, 'layer_gap' => 3, 'direction' => 'TB',
               'sifting' => 'off', 'reduce' => 'off', 'restarts' => 0, 'seed' => 1 }.freeze
  CHOICES = { 'layering' => %w[longest coffman], 'promotion' => %w[on off],
              'heuristic' => %w[barycenter median], 'direction' => %w[TB BT LR RL],
              'sifting' => %w[on off], 'reduce' => %w[on off] }.freeze
  RANGES = { 'width' => 1..40, 'sweeps' => 0..50, 'node_sep' => 1..9,
             'dummy_sep' => 1..9, 'layer_gap' => 2..9, 'restarts' => 0..9,
             'seed' => 1..2_147_483_646 }.freeze
  Graph = Struct.new(:name, :settings, :nodes, :edges, :path, :self_loops, :duplicates, :error)

  def self.value(name, word)
    return word if CHOICES[name]&.include?(word)
    return unless RANGES.key?(name) && /\A[0-9]{1,10}\z/.match?(word)
    number = word.to_i
    number if RANGES[name].cover?(number)
  end

  def self.lines(file)
    File.foreach(File.join('input', file)).with_index(1) do |line, number|
      line = line.chomp
      yield number, line.split(' ') unless line.empty? || line.start_with?('#')
    end
  end

  def self.read
    defaults = DEFAULTS.dup
    lines('params.txt') { |_, (name, word)| defaults[name] = value(name, word) }
    graphs = []
    graph = nil
    lines('graphs.txt') do |number, fields|
      kind, first, second = fields
      if kind == 'GRAPH'
        graph = Graph.new(first, defaults.dup, {}, [], nil, 0, 0, nil)
        graphs << graph
        next
      end
      if kind == 'END'
        graph.error = ['no_nodes', number] if graph.error.nil? && graph.nodes.empty?
        next
      end
      next if graph.error
      error = nil
      case kind
      when 'OPTION'
        setting = value(first, second)
        setting.nil? ? error = 'bad_option' : graph.settings[first] = setting
      when 'NODE'
        id = first.to_i
        if graph.nodes.key?(id)
          error = 'duplicate_node'
        elsif graph.nodes.size == 40
          error = 'too_many_nodes'
        else
          graph.nodes[id] = second
        end
      else
        a, b = first.to_i, second.to_i
        if !graph.nodes.key?(a) || !graph.nodes.key?(b)
          error = 'unknown_node'
        elsif kind == 'PATH'
          graph.path = [a, b]
        elsif a == b
          graph.self_loops += 1
        elsif graph.edges.include?([a, b])
          graph.duplicates += 1
        else
          graph.edges << [a, b]
        end
      end
      graph.error = [error, number] if error
    end
    graphs
  end
end
