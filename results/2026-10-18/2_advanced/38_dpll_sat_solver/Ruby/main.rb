require_relative 'cnf_io'
require_relative 'encoders'
require_relative 'preprocess'
require_relative 'dpll'
require_relative 'report'

class SatJobs
  include SatReport

  ARGUMENTS = {
    'SOLVE' => [:file], 'ENUM' => %i[file limit], 'CORE' => [:file],
    'QUEENS' => %i[small limit], 'PIGEON' => %i[small small limit],
    'COLOR' => %i[graph color limit], 'CHROMATIC' => %i[graph color]
  }.freeze

  def load_graphs
    graphs = {}
    current = nil
    File.foreach('input/graphs.txt', chomp: true).with_index(1) do |line, number|
      if current.nil?
        next if line.empty? || line.start_with?('#')
        _, name, vertices = line.split(' ')
        current = {name: name, vertices: vertices.to_i, edges: [], invalid: nil}
      elsif line == 'END'
        current[:edges].sort!
        graphs[current[:name]] = current
        current = nil
      elsif current[:invalid].nil?
        tokens = line.split(' ', -1)
        reason = nil
        if tokens.length != 2 || tokens.any? { |token| !CnfIO.valid_number?(token) }
          reason = 'bad edge line'
        else
          a, b = tokens.map(&:to_i)
          pair = [a, b].sort
          if !a.between?(1, current[:vertices]) || !b.between?(1, current[:vertices])
            reason = 'vertex out of range'
          elsif a == b
            reason = 'self loop'
          elsif current[:edges].include?(pair)
            reason = 'duplicate edge'
          else
            current[:edges] << pair
          end
        end
        current[:invalid] = "#{reason} at line #{number}" if reason
      end
    end
    graphs
  end

  def load_jobs
    jobs = []
    File.foreach('input/jobs.txt', chomp: true) do |line|
      next if line.empty? || line.start_with?('#')
      command, *args = line.split(' ')
      jobs << {number: jobs.length + 1, text: line, command: command, args: args}
    end
    jobs
  end

  def validation_error(job, graphs)
    command, args = job.values_at(:command, :args)
    return "unknown command #{command}" unless ARGUMENTS.key?(command)
    return 'wrong argument count' unless args.length == ARGUMENTS[command].length
    args.zip(ARGUMENTS[command]).each do |token, kind|
      case kind
      when :file
        return "bad file name #{token}" unless /\A[a-z0-9_]{1,20}\.cnf\z/.match?(token)
      when :graph
        return "unknown graph #{token}" unless graphs.key?(token)
        return "invalid graph #{token}: #{graphs[token][:invalid]}" if graphs[token][:invalid]
      else
        return "bad number #{token}" unless CnfIO.valid_number?(token)
        return "out of range #{token}" unless token.to_i.between?(1, {small: 8, color: 6, limit: 200}.fetch(kind))
      end
    end
    nil
  end

  def empty_stats
    {decisions: 0, propagations: 0, conflicts: 0, max_depth: 0}
  end

  def accumulate(target, source)
    %i[decisions propagations conflicts].each { |key| target[key] += source[key] }
    target[:max_depth] = [target[:max_depth], source[:max_depth]].max
  end

  def solve(variables, clauses, limit)
    prep = Preprocess.simplify(variables, clauses, limit == 1)
    models, blocks, trace = [], [], []
    stats = empty_stats
    rounds = 0
    stop = prep[:empty_clause] ? 'preprocess' : 'limit'
    unless prep[:empty_clause]
      while models.length < limit
        rounds += 1
        model, events, counters = DPLL.run(variables, prep[:clauses] + blocks)
        trace = events if rounds == 1
        accumulate(stats, counters)
        if model.nil?
          stop = 'all'
          break
        end
        prep[:fixed].each { |v, value| model[v] = value }
        models << model
        blocks << prep[:active].map { |v| model[v] ? -v : v }
      end
    end
    {variables: variables, clauses: clauses, preparation: prep, models: models,
     status: models.empty? ? 'UNSAT' : 'SAT', rounds: rounds, stop: stop,
     stats: stats, trace: trace, removed: prep[:counts][:removed]}
  end

  def true_literal?(model, literal)
    literal.positive? ? model[literal] : !model[-literal]
  end

  def satisfies?(model, clauses)
    clauses.all? { |clause| clause.any? { |literal| true_literal?(model, literal) } }
  end

  def analyze(solution)
    models, clauses, variables = solution.values_at(:models, :clauses, :variables)
    return nil if models.empty?
    failure = nil
    models.each_with_index do |model, i|
      clauses.each_with_index do |clause, j|
        unless clause.any? { |literal| true_literal?(model, literal) }
          failure = [i + 1, j + 1]
          break
        end
      end
      break if failure
    end
    first = models.first
    distribution = clauses.map { |clause| clause.count { |literal| true_literal?(first, literal) } }
    safe = (1..variables).select do |v|
      flipped = first.dup
      flipped[v] = !flipped[v]
      satisfies?(flipped, clauses)
    end
    distances = models.combination(2).map { |a, b| (1..variables).count { |v| a[v] != b[v] } }
    backbone = (1..variables).filter_map do |v|
      (first[v] ? v : -v) if models.all? { |model| model[v] == first[v] }
    end
    {failure: failure, distribution: distribution, safe: safe, distances: distances, backbone: backbone}
  end

  def unsat_core(variables, clauses)
    remaining = (1..clauses.length).to_a
    decisions = conflicts = 0
    (1..clauses.length).each do |remove|
      candidates = remaining.reject { |number| number == remove }.map { |number| clauses[number - 1] }
      result = solve(variables, candidates, 1)
      decisions += result[:stats][:decisions]
      conflicts += result[:stats][:conflicts]
      remaining.delete(remove) if result[:status] == 'UNSAT'
    end
    {clauses: remaining, decisions: decisions, conflicts: conflicts}
  end

  def execute(job, graphs)
    job[:error] = validation_error(job, graphs)
    return if job[:error]
    command, args = job.values_at(:command, :args)
    if command == 'CHROMATIC'
      job[:graph] = graphs[args[0]]
      job[:attempts] = []
      job[:aggregate_stats] = empty_stats
      job[:aggregate_rounds] = job[:aggregate_removed] = 0
      (1..args[1].to_i).each do |colors|
        variables, clauses = Encoders.coloring(job[:graph], colors)
        attempt = solve(variables, clauses, 1).merge(colors: colors)
        job[:attempts] << attempt
        accumulate(job[:aggregate_stats], attempt[:stats])
        job[:aggregate_rounds] += attempt[:rounds]
        job[:aggregate_removed] += attempt[:removed]
        job[:solution] = attempt
        job[:colors] = colors
        break if attempt[:status] == 'SAT'
      end
    else
      case command
      when 'SOLVE', 'ENUM', 'CORE'
        begin
          variables, clauses = CnfIO.read(args[0])
        rescue ArgumentError => e
          job[:error] = e.message
          return
        end
        limit = command == 'ENUM' ? args[1].to_i : 1
      when 'QUEENS'
        variables, clauses = Encoders.queens(args[0].to_i)
        limit = args[1].to_i
      when 'PIGEON'
        variables, clauses = Encoders.pigeon(args[0].to_i, args[1].to_i)
        limit = args[2].to_i
      when 'COLOR'
        job[:graph] = graphs[args[0]]
        job[:colors] = args[1].to_i
        variables, clauses = Encoders.coloring(job[:graph], job[:colors])
        limit = args[2].to_i
      end
      job[:solution] = result = solve(variables, clauses, limit)
      job[:aggregate_stats] = result[:stats]
      job[:aggregate_rounds] = result[:rounds]
      job[:aggregate_removed] = result[:removed]
      job[:core] = unsat_core(variables, clauses) if command == 'CORE' && result[:status] == 'UNSAT'
    end
    job[:analysis] = analyze(job[:solution])
  end

  def greedy_coloring(graph)
    neighbors = Array.new(graph[:vertices] + 1) { [] }
    graph[:edges].each { |a, b| neighbors[a] << b; neighbors[b] << a }
    colors = Array.new(graph[:vertices] + 1, 0)
    (1..graph[:vertices]).sort_by { |v| [-neighbors[v].length, v] }.each do |v|
      used = neighbors[v].map { |other| colors[other] }
      color = 1
      color += 1 while used.include?(color)
      colors[v] = color
    end
    colors.drop(1)
  end

  def heading(job)
    "JOB #{job[:number]} #{job[:text]}"
  end

  def graph_summary(graph)
    degree = graph[:edges].flatten.tally.values.max || 0
    named(vertices: graph[:vertices], edges: graph[:edges].length,
          max_degree: degree, greedy: greedy_coloring(graph).max)
  end

  def preprocessing_lines(prep)
    lines = ["preprocess #{named(pure: prep[:pure] ? 'on' : 'off', **prep[:counts])}"]
    lines << "removed_clauses #{named(**prep[:records].transform_values { |ids| number_list(ids) })}"
    if prep[:empty_clause]
      lines << "simplified empty_clause=#{prep[:empty_clause]}"
    else
      lengths = prep[:clauses].map(&:length)
      lines << 'simplified ' + named(
        clauses: lengths.length, literals: lengths.sum, lengths: frequency(lengths),
        fixed: prep[:fixed].length, active: prep[:active].length
      )
      literals = prep[:fixed].sort.map { |v, value| value ? v : -v }
      lines << "fixed literals=#{number_list(literals)}"
    end
    lines
  end

  def model_analysis_lines(solution, analysis, chromatic: false)
    return [] unless analysis
    lines = if analysis[:failure]
              ["verify failed model=#{analysis[:failure][0]} clause=#{analysis[:failure][1]}"]
            else
              ['verify ok ' + named(
                models: solution[:models].length, clauses: solution[:clauses].length,
                true_literals: frequency(analysis[:distribution])
              )]
            end
    lines << "flips #{named(safe: analysis[:safe].length, variables: number_list(analysis[:safe]))}"
    unless chromatic
      distances = analysis[:distances]
      unless distances.empty?
        lines << "diversity #{named(pairs: distances.length, min_distance: distances.min, max_distance: distances.max)}"
      end
      if solution[:stop] == 'all'
        lines << "backbone #{named(size: analysis[:backbone].length, literals: number_list(analysis[:backbone]))}"
      end
    end
    lines
  end

  def result_lines(job)
    lines = [heading(job)]
    return lines << "error #{job[:error]}" if job[:error]
    solution = job[:solution]
    lines << "graph #{graph_summary(job[:graph])}" if job[:graph]
    if job[:command] == 'CHROMATIC'
      job[:attempts].each do |attempt|
        lines << 'attempt ' + named(
          k: attempt[:colors], clauses: attempt[:clauses].length, removed: attempt[:removed],
          result: attempt[:status], stop: attempt[:stop], **attempt[:stats]
        )
      end
      chromatic = solution[:status] == 'SAT' ? job[:colors] : '-'
      lines << "result #{solution[:status]} chromatic=#{chromatic} attempts=#{job[:attempts].length}"
      lines << "search #{named(**job[:aggregate_stats])}"
      lines.concat(model_analysis_lines(solution, job[:analysis], chromatic: true))
    else
      lengths = solution[:clauses].map(&:length)
      lines << "formula #{named(variables: solution[:variables], clauses: lengths.length, literals: lengths.sum, lengths: frequency(lengths))}"
      lines.concat(preprocessing_lines(solution[:preparation]))
      lines << "result #{solution[:status]} #{named(models: solution[:models].length, rounds: solution[:rounds], stop: solution[:stop])}"
      lines << "search #{named(**solution[:stats])}"
      if solution[:rounds].positive?
        trace = solution[:trace]
        text = trace.empty? ? '-' : trace.first(12).join(' ')
        text += " +#{trace.length - 12}" if trace.length > 12
        lines << "trace #{text}"
      end
      lines.concat(model_analysis_lines(solution, job[:analysis]))
      if job[:core]
        core = job[:core]
        lines << 'core ' + named(
          size: core[:clauses].length, decisions: core[:decisions], conflicts: core[:conflicts],
          clauses: number_list(core[:clauses])
        )
      end
    end
    lines
  end

  def summary_lines(jobs, valid)
    sat = valid.count { |job| job[:solution][:status] == 'SAT' }
    lines = ["SUMMARY #{named(jobs: jobs.length, sat: sat, unsat: valid.length - sat, error: jobs.length - valid.length)}"]
    lines << 'totals ' + named(
      models: valid.sum { |job| job[:solution][:models].length },
      rounds: valid.sum { |job| job[:aggregate_rounds] },
      decisions: valid.sum { |job| job[:aggregate_stats][:decisions] },
      propagations: valid.sum { |job| job[:aggregate_stats][:propagations] },
      conflicts: valid.sum { |job| job[:aggregate_stats][:conflicts] },
      removed_clauses: valid.sum { |job| job[:aggregate_removed] }
    )
    ARGUMENTS.each_key do |command|
      members = valid.select { |job| job[:command] == command }
      next if members.empty?
      count = members.count { |job| job[:solution][:status] == 'SAT' }
      totals = %i[decisions propagations conflicts].to_h { |key| [key, members.sum { |job| job[:aggregate_stats][key] }] }
      lines << "command #{command} #{named(jobs: members.length, sat: count, unsat: members.length - count, **totals)}"
    end
    {hardest: :conflicts, deepest: :max_depth, busiest: :propagations}.each do |label, key|
      next if valid.empty?
      job = valid.min_by { |item| [-item[:aggregate_stats][key], item[:number]] }
      lines << "#{label} job=#{job[:number]} #{key}=#{job[:aggregate_stats][key]}"
    end
    lines
  end

  def queen_variants(columns)
    n = columns.length
    variants = Array.new(8) { Array.new(n) }
    columns.each_with_index do |c, index|
      r = index + 1
      [[r, c], [c, n + 1 - r], [n + 1 - r, n + 1 - c], [n + 1 - c, r],
       [r, n + 1 - c], [n + 1 - r, c], [c, r], [n + 1 - c, n + 1 - r]].each_with_index do |(row, col), i|
        variants[i][row - 1] = col
      end
    end
    variants
  end

  def classify(positions)
    groups = {}
    assignments = positions.each_with_index.map do |values, index|
      canonical, orbit = yield(values)
      group = groups[canonical] ||= {number: groups.length + 1, first: index + 1,
                                    found: 0, canonical: canonical, orbit: orbit}
      group[:found] += 1
      [values, group[:number], group[:first] == index + 1]
    end
    [assignments, groups.values]
  end

  def queens_lines(job)
    n = job[:args][0].to_i
    solution = job[:solution]
    positions = solution[:models].map { |model| Encoders.positions(model, n, n) }
    assignments, groups = classify(positions) do |values|
      variants = queen_variants(values)
      [variants.min, variants.uniq.length]
    end
    lines = ["QUEENS job=#{job[:number]} n=#{n}"]
    assignments.each_with_index do |(values, group, first), index|
      lines << "solution #{index + 1} columns=#{number_list(values)} class=#{group}"
      lines.concat(board(values)) if first
    end
    groups.each do |group|
      lines << "class #{group[:number]} " + named(
        orbit: group[:orbit], found: group[:found], first: group[:first],
        canonical: number_list(group[:canonical])
      )
    end
    lines << "summary #{named(solutions: positions.length, stop: solution[:stop], classes: groups.length)}"
  end

  def pigeon_lines(job)
    pigeons, holes = job[:args].first(2).map(&:to_i)
    solution = job[:solution]
    lines = ["PIGEON job=#{job[:number]} pigeons=#{pigeons} holes=#{holes}"]
    solution[:models].each_with_index do |model, index|
      places = Encoders.positions(model, pigeons, holes)
      empty = (1..holes).reject { |hole| places.include?(hole) }
      lines << "assignment #{index + 1} holes=#{number_list(places)} empty=#{number_list(empty)}"
    end
    expected = pigeons > holes ? 0 : (0...pigeons).reduce(1) { |product, i| product * (holes - i) }
    lines << "summary #{named(assignments: solution[:models].length, stop: solution[:stop], expected: expected)}"
  end

  def coloring_lines(job)
    graph, colors, solution = job.values_at(:graph, :colors, :solution)
    positions = solution[:models].map { |model| Encoders.positions(model, graph[:vertices], colors) }
    assignments, groups = classify(positions) do |values|
      numbering = {}
      canonical = values.map { |color| numbering[color] ||= numbering.length + 1 }
      [canonical, nil]
    end
    lines = ["#{job[:command]} job=#{job[:number]} graph=#{graph[:name]} vertices=#{graph[:vertices]} edges=#{graph[:edges].length} colors=#{colors}"]
    greedy = greedy_coloring(graph)
    lines << "greedy used=#{greedy.max} colors=#{number_list(greedy)}"
    assignments.each_with_index do |(values, group, _), index|
      sizes = (1..colors).map { |color| values.count(color) }
      lines << "coloring #{index + 1} colors=#{number_list(values)} used=#{values.uniq.length} sizes=#{number_list(sizes)} class=#{group}"
    end
    groups.each do |group|
      lines << "class #{group[:number]} #{named(found: group[:found], first: group[:first], canonical: number_list(group[:canonical]))}"
    end
    lines << "summary #{named(colorings: positions.length, stop: solution[:stop], classes: groups.length)}"
  end

  def run
    graphs = load_graphs
    jobs = load_jobs
    jobs.each { |job| execute(job, graphs) }
    valid = jobs.reject { |job| job[:error] }
    write_paragraphs('results.txt', jobs.map { |job| result_lines(job) } << summary_lines(jobs, valid))
    model_paragraphs = valid.filter_map do |job|
      next if job[:solution][:models].empty?
      lines = [heading(job)]
      job[:solution][:models].each_with_index do |model, index|
        lines << "model #{index + 1}"
        lines.concat(CnfIO.model_lines(model))
      end
      lines
    end
    write_paragraphs('models.txt', model_paragraphs)
    boards = valid.filter_map do |job|
      case job[:command]
      when 'QUEENS' then queens_lines(job)
      when 'PIGEON' then pigeon_lines(job)
      when 'COLOR', 'CHROMATIC' then coloring_lines(job)
      end
    end
    write_paragraphs('boards.txt', boards)
    csv = ['job,command,status,variables,clauses,removed_clauses,decisions,propagations,conflicts,max_depth,models,rounds']
    valid.each do |job|
      result = job[:solution]
      csv << [job[:number], job[:command], result[:status], result[:variables], result[:clauses].length,
              job[:aggregate_removed], *job[:aggregate_stats].values_at(:decisions, :propagations, :conflicts, :max_depth),
              result[:models].length, job[:aggregate_rounds]].join(',')
    end
    write_lines('stats.csv', csv)
  end
end

SatJobs.new.run if $PROGRAM_NAME == __FILE__
