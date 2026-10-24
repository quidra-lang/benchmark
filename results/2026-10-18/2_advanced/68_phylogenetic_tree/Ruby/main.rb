require_relative 'alignment'
require_relative 'distances'
require_relative 'tree_building'
require_relative 'parsimony'
require_relative 'tree_io'

module Phylogeny
  extend self
  NJ_METHODS = %w[NJ_P NJ_JC NJ_K2P].freeze
  METHODS = [*NJ_METHODS, 'ME', 'MP', 'CONSENSUS'].freeze

  def real(value, places) = TreeIO.real(value, places)
  def symbols(mask, count) = TreeIO.symbols(mask, count)
  def bits(mask) = mask.digits(2).count(1)
  def ordered_sum(values)
    total = 0.0
    values.each { |value| total += value }
    total
  end

  def read_parameters
    File.readlines('input/params.txt', chomp: true).to_h do |line|
      key, *values = line.split(' ')
      value = if %w[replicates seed max_missing_percent low_sites].include?(key)
                values.first.to_i
              elsif key == 'saturation_distance'
                values.first.to_f
              elsif key == 'exhaustive_taxa'
                values
              else
                values.first
              end
      [key, value]
    end
  end

  def check_records(records, maximum_missing)
    length = records.first[2].size
    seen, accepted, rejected = Set.new, [], []
    records.each do |line, name, sequence|
      reason = 'duplicate name' if seen.include?(name)
      seen << name
      unless reason
        bad = sequence.chars.each_with_index.find { |char, _| !Alignment::BASE_SETS.key?(char) }
        reason = "invalid character #{bad[0]} at column #{bad[1] + 1}" if bad
      end
      reason ||= "length mismatch #{sequence.size}" if sequence.size != length
      missing = sequence.count('-N')
      reason ||= "too many missing #{missing}" if 100 * missing > maximum_missing * length
      if reason
        rejected << [line, name, reason]
      else
        accepted << [name, sequence]
      end
      reason = nil
    end
    [accepted, rejected, length]
  end

  def summary_lines(records, rejected, names, sequences, patterns)
    lines = ["INPUT records #{records.size} accepted #{names.size} rejected #{rejected.size} columns #{sequences.first.size}"]
    rejected.each { |line, name, reason| lines << "REJECT line #{line} #{name} #{reason}" }
    columns = (0...sequences.first.size).map do |c|
      sequences.map { |sequence| sequence[c] }.select { |char| Alignment::BASES.include?(char) }.tally
    end
    composition = Array.new(4, 0)
    names.zip(sequences).each do |name, sequence|
      counts = Hash.new(0).merge(sequence.chars.tally)
      bases = Alignment::BASES.chars.sum { |base| counts[base] }
      ambiguous = Alignment::AMBIGUOUS.chars.sum { |char| counts[char] }
      unique = sequence.chars.each_with_index.count do |char, c|
        Alignment::BASES.include?(char) && columns[c][char] == 1 && columns[c].values.sum > 1
      end
      lines << "TAXON #{name} bases #{bases} ambiguous #{ambiguous} missing #{counts['-'] + counts['N']} unique #{unique} gc #{real((counts['C'] + counts['G']).fdiv(bases), 4)}"
      Alignment::BASES.chars.each_with_index { |base, i| composition[i] += counts[base] }
    end
    lines << 'COLUMNS ' + Alignment.classify_columns(sequences).map { |key, count| "#{key} #{count}" }.join(' ')
    lines << "PATTERNS #{patterns.patterns.size}"
    lines << 'COMPOSITION ' + Alignment::BASES.chars.zip(composition).map { |base, count| "#{base} #{real(count.fdiv(composition.sum), 4)}" }.join(' ')
    lines
  end

  def matrix_lines(names, matrix)
    width = names.map(&:size).max
    names.zip(matrix).map { |name, row| name.ljust(width) + ' ' + row.map { |value| real(value, 5) }.join(' ') }
  end

  def parsimony_bounds(patterns)
    maximum = 0
    minima = patterns.encoded.zip(patterns.weights).map do |pattern, weight|
      minimum = (1..15).select { |mask| pattern.all? { |set| !(mask & set).zero? } }.map { |mask| bits(mask) }.min - 1
      maximum += [1, 2, 4, 8].map { |base| pattern.count { |set| (set & base).zero? } }.min * weight
      minimum
    end
    columns = patterns.columns.map { |index| minima[index] }
    [columns.sum, maximum, columns]
  end

  def bme_length(tree, matrix)
    total = 0.0
    tree.taxa.each do |a|
      steps = TreeBuilding.path_distances(tree, a, unit: true)
      tree.taxa.each { |b| total += matrix[a][b] / (2.0**(steps[b] - 1)) if a < b }
    end
    total
  end

  def stepwise(taxa, size, patterns, outgroup)
    tree = TreeBuilding.star(size, taxa.first(3))
    initial = current = Parsimony.score(tree, patterns, outgroup)
    additions, evaluated = [], 0
    taxa.drop(3).each do |taxon|
      best, chosen, selected_mask, ties = nil, nil, nil, 0
      Parsimony.branches(tree, outgroup).each do |mask, a, b|
        candidate = Parsimony.insert(tree, a, b, taxon)
        value = Parsimony.score(candidate, patterns, outgroup)
        evaluated += 1
        if best.nil? || value < best
          best, chosen, selected_mask, ties = value, candidate, mask, 1
        elsif value == best
          ties += 1
        end
      end
      tree, current = chosen, best
      additions << [taxon, selected_mask, current, ties]
    end
    { tree: tree, initial: initial, score: current, additions: additions, evaluated: evaluated, taxa: taxa }
  end

  def hill_climb(tree, objective, outgroup, value)
    tree = tree.copy
    evaluated, moves = 0, []
    loop do
      improved = false
      Parsimony.nni_candidates(tree, outgroup).each do |mask, swap, candidate|
        candidate_value = objective.call(candidate)
        evaluated += 1
        next unless candidate_value < value
        tree, value = candidate, candidate_value
        moves << [mask, swap, value]
        improved = true
        break
      end
      break unless improved
    end
    { tree: tree, value: value, moves: moves, evaluated: evaluated }
  end

  def consensus_tree(size, taxa, outgroup, clades)
    tree = TreeBuilding::Tree.new(size, taxa)
    root = tree.internal
    nodes = clades.to_a.sort.to_h { |mask| [mask, tree.internal] }
    nodes.each do |mask, node|
      containers = nodes.keys.select { |other| other != mask && (other & mask) == mask }
      tree.connect(containers.empty? ? root : nodes[containers.min_by { |other| bits(other) }], node)
    end
    taxa.each do |taxon|
      containers = nodes.keys.select { |mask| !(mask & (1 << taxon)).zero? }
      tree.connect(containers.empty? ? root : nodes[containers.min_by { |mask| bits(mask) }], taxon)
    end
    tree
  end

  def exhaustive_search(taxa, names, patterns, outgroup, matrix)
    trees = [TreeBuilding.star(names.size, taxa.first(3))]
    taxa.drop(3).each do |taxon|
      trees = trees.flat_map do |tree|
        Parsimony.branches(tree, outgroup).map { |_, a, b| Parsimony.insert(tree, a, b, taxon) }
      end
    end
    histogram = Hash.new(0)
    records = trees.map do |tree|
      score = Parsimony.score(tree, patterns, outgroup)
      histogram[score] += 1
      { tree: tree, score: score, bme: bme_length(tree, matrix),
        newick: TreeIO.newick(tree, names, outgroup), splits: tree.rooted(outgroup).splits }
    end
    best_score = histogram.keys.min
    optimal = records.select { |record| record[:score] == best_score }.sort_by { |record| record[:newick] }
    common = optimal.map { |record| record[:splits] }.reduce { |a, b| a & b }
    strict = consensus_tree(names.size, taxa, outgroup, common)
    best_bme = records.min_by { |record| [record[:bme], record[:newick]] }
    second_bme = records.reject { |record| record.equal?(best_bme) }.map { |record| record[:bme] }.min
    initial = stepwise(taxa, names.size, patterns, outgroup)
    heuristic = hill_climb(initial[:tree], ->(tree) { Parsimony.score(tree, patterns, outgroup) }, outgroup, initial[:score])
    { taxa: taxa, records: records, histogram: histogram, best_score: best_score, optimal: optimal,
      strict: strict, best_bme: best_bme, second_bme: second_bme, heuristic: heuristic[:value] }
  end

  def likelihood_sites(tree, names, patterns, outgroup)
    rooted = tree.rooted(outgroup)
    children = TreeIO.child_order(rooted, names)
    transition = rooted.order.drop(1).to_h do |node|
      e = Math.exp(-4 * tree.adjacent[node][rooted.parents[node]] / 3.0)
      [node, Array.new(4) { |a| Array.new(4) { |b| a == b ? 0.25 + 0.75 * e : 0.25 - 0.25 * e } }]
    end
    values = patterns.encoded.map do |pattern|
      partial, upward = {}, {}
      rooted.order.reverse_each do |node|
        partial[node] = if node < tree.size
                          Array.new(4) { |base| (pattern[node] & (1 << base)).zero? ? 0.0 : 1.0 }
                        else
                          result = Array.new(4, 1.0)
                          children[node].each { |child| 4.times { |base| result[base] *= upward[child][base] } }
                          result
                        end
        unless node == rooted.root
          upward[node] = Array.new(4) do |a|
            ordered_sum((0...4).map { |b| transition[node][a][b] * partial[node][b] })
          end
        end
      end
      Math.log(ordered_sum(partial[rooted.root].map { |value| 0.25 * value }))
    end
    patterns.columns.map { |index| values[index] }
  end

  def likelihood_lines(names, patterns, trees, outgroup, main_method, low_count, site_logs)
    length = patterns.columns.size
    lines = ["LIKELIHOOD columns #{length} patterns #{patterns.patterns.size}"]
    NJ_METHODS.each do |method|
      total = ordered_sum(site_logs[method])
      lines << "TREE #{method} loglik #{real(total, 4)} per_site #{real(total / length, 4)}"
    end
    NJ_METHODS.combination(2) do |a, b|
      deltas = site_logs[a].zip(site_logs[b]).map { |x, y| x - y }
      difference = ordered_sum(deltas)
      mean = difference / length
      se = Math.sqrt(length.fdiv(length - 1) * ordered_sum(deltas.map { |delta| (delta - mean)**2 }))
      lines << "KH #{a} #{b} difference #{real(difference, 4)} se #{real(se, 4)} z #{real(difference / se, 4)}"
    end
    lowest = (0...length).sort_by { |c| [real(site_logs[main_method][c], 4).to_f, c] }.first(low_count)
    changes = Parsimony.pattern_scores(trees[main_method], patterns, outgroup)
    lines << "LOWEST #{main_method} sites #{low_count}"
    lowest.each do |column|
      index = patterns.columns[column]
      lines << "SITE #{column + 1} loglik #{real(site_logs[main_method][column], 4)} changes #{changes[index]} pattern #{patterns.patterns[index]}"
    end
    lines
  end

  def bootstrap(names, sequences, parameters, main_tree, main_matrix, outgroup)
    count, length = names.size, sequences.first.size
    replicates, state = parameters.values_at('replicates', 'seed')
    support, main_splits = Hash.new(0), main_tree.rooted(outgroup).splits
    lines = ["BOOTSTRAP model #{parameters['model']} replicates #{replicates} seed #{state}"]
    identical = 0
    1.upto(replicates) do |replicate|
      weights = Array.new(length, 0)
      length.times do
        state = 48271 * state % 2_147_483_647
        weights[state % length] += 1
      end
      pairs = Distances.all_pairs(sequences, weights)
      matrix, = Distances.build_matrix(pairs, count, parameters['model'], parameters['saturation_distance'])
      splits = TreeBuilding.neighbor_joining(matrix, 0...count).rooted(outgroup).splits
      splits.each { |mask| support[mask] += 1 }
      rf = (splits ^ main_splits).size
      identical += 1 if rf.zero?
      lines << "REPLICATE #{replicate} distinct #{weights.count(&:positive?)} rf #{rf}"
    end
    lines << "IDENTICAL #{identical}"
    main_splits.sort_by { |mask| symbols(mask, count) }.each { |mask| lines << "SUPPORT #{symbols(mask, count)} #{support[mask]}" }
    support.keys.sort_by { |mask| [-support[mask], symbols(mask, count)] }.each { |mask| lines << "SPLIT #{symbols(mask, count)} #{support[mask]}" }
    majority = support.keys.select { |mask| 2 * support[mask] > replicates }
    consensus = consensus_tree(count, (0...count).to_a, outgroup, majority)
    lines << 'CONSENSUS ' + TreeIO.newick(consensus, names, outgroup, support: support)
    count.times do |taxon|
      next if taxon == outgroup
      tree = TreeBuilding.neighbor_joining(main_matrix, (0...count).reject { |other| other == taxon })
      reduced = main_splits.map { |mask| mask & ~(1 << taxon) }.select { |mask| bits(mask).between?(2, count - 3) }.to_set
      lines << "JACKKNIFE #{names[taxon]} rf #{(tree.rooted(outgroup).splits ^ reduced).size}"
    end
    [consensus, support, lines]
  end

  def clock_lines(names, sequences, outgroup, main_method, main_tree)
    ingroup = (0...names.size).reject { |taxon| taxon == outgroup }
    pairs, rejected = [], 0
    ingroup.combination(2) do |i, j|
      m1 = m2 = 0
      sequences.first.size.times do |c|
        a, b, o = sequences[i][c], sequences[j][c], sequences[outgroup][c]
        next unless [a, b, o].all? { |char| Alignment::BASES.include?(char) } && a != b
        m1 += 1 if b == o
        m2 += 1 if a == o
      end
      reject = 1000 * (m1 - m2)**2 > 3841 * (m1 + m2)
      rejected += 1 if reject
      chi = (m1 + m2).zero? ? '-' : real(((m1 - m2)**2).fdiv(m1 + m2), 4)
      pairs << "RRT #{names[i]} #{names[j]} m1 #{m1} m2 #{m2} chi2 #{chi} #{reject ? 'reject' : 'ok'}"
    end
    lines = ["RELATIVE_RATE outgroup #{names[outgroup]} pairs #{pairs.size} rejected #{rejected}", *pairs]
    paths = TreeBuilding.path_distances(main_tree, main_tree.rooted(outgroup).root)
    mean = ordered_sum(ingroup.map { |taxon| paths[taxon] }) / ingroup.size
    sd = Math.sqrt(ordered_sum(ingroup.map { |taxon| (paths[taxon] - mean)**2 }) / (ingroup.size - 1))
    lines << "ROOT_TO_TIP #{main_method} mean #{real(mean, 5)} sd #{real(sd, 5)} cv #{real(sd / mean, 4)}"
    ingroup.each { |taxon| lines << "TIP #{names[taxon]} #{real(paths[taxon], 5)}" }
    lines
  end

  def quartet_topologies(splits, count)
    (0...count).to_a.combination(4).map do |a, b, c, d|
      quartet = [a, b, c, d].sum { |taxon| 1 << taxon }
      result = 0
      [b, c, d].each_with_index do |other, index|
        side = (1 << a) | (1 << other)
        if splits.any? { |mask| [side, quartet ^ side].include?(mask & quartet) }
          result = index + 1
          break
        end
      end
      result
    end
  end

  def comparison_lines(names, patterns, trees, matrices, main_matrix, main_method, outgroup,
                       support, replicates, nj_scores, mp_score, mp_changes, site_logs, patristic)
    splits = trees.transform_values { |tree| tree.rooted(outgroup).splits }
    lines = METHODS.map do |method|
      tree = trees[method]
      supported = splits[method].count { |mask| 2 * support[mask] > replicates }
      score = bme = length = negative = sse = likelihood = '-'
      unless method == 'CONSENSUS'
        score = nj_scores[method] || (method == 'MP' ? mp_score : Parsimony.score(tree, patterns, outgroup))
        bme = real(bme_length(tree, main_matrix), 5)
      end
      if NJ_METHODS.include?(method)
        length = real(ordered_sum(Parsimony.branches(tree, outgroup).map { |_, a, b| tree.adjacent[a][b] }), 5)
        negative = tree.negative
        matrix = matrices[method.delete_prefix('NJ_')]
        sse = real(ordered_sum((0...names.size).to_a.combination(2).map { |a, b| (matrix[a][b] - patristic[method][a][b])**2 }), 6)
        likelihood = real(ordered_sum(site_logs[method]), 4)
      elsif method == 'MP'
        length = real(mp_score.fdiv(patterns.columns.size), 5)
      end
      "TREE #{method} splits #{splits[method].size} supported #{supported} parsimony #{score} bme #{bme} length #{length} negative #{negative} sse #{sse} loglik #{likelihood}"
    end
    lines << 'RF ' + METHODS.join(' ')
    METHODS.each { |a| lines << a + ' ' + METHODS.map { |b| (splits[a] ^ splits[b]).size }.join(' ') }
    quartets = splits.transform_values { |set| quartet_topologies(set, names.size) }
    lines << 'QUARTET ' + METHODS.join(' ')
    METHODS.each { |a| lines << a + ' ' + METHODS.map { |b| quartets[a].zip(quartets[b]).count { |x, y| x != y } }.join(' ') }
    lengths = trees[main_method].rooted(outgroup).branch_lengths
    changes = Parsimony.branches(trees['MP'], outgroup).to_h { |mask, a, b| [mask, mp_changes[[a, b].sort]] }
    splits.values.reduce(Set.new, :|).sort_by { |mask| symbols(mask, names.size) }.each do |mask|
      marks = METHODS.map { |method| splits[method].include?(mask) ? '+' : '-' }.join
      length = lengths.key?(mask) ? real(lengths[mask], 5) : '-'
      change = changes.fetch(mask, '-')
      lines << "CLADE #{symbols(mask, names.size)} support #{support[mask]} trees #{marks} length #{length} changes #{change}"
    end
    lines
  end

  def hypothesis_lines(names, trees, outgroup, support, exhaustive)
    numbers = names.each_with_index.to_h
    ingroup = ((1 << names.size) - 1) ^ (1 << outgroup)
    exhaustive_ingroup = exhaustive[:taxa].reject { |taxon| taxon == outgroup }.sum { |taxon| 1 << taxon }
    splits = trees.transform_values { |tree| tree.rooted(outgroup).splits }
    lines = []
    File.foreach('input/clades.txt') do |line|
      hypothesis, *members = line.split
      unknown = members.find { |name| !numbers.key?(name) }
      if unknown || members.include?(names[outgroup])
        lines << "INVALID #{hypothesis} #{unknown ? "unknown taxon #{unknown}" : 'contains outgroup'}"
        next
      end
      mask = members.sum { |name| 1 << numbers[name] }
      lines << "CLADE #{hypothesis} taxa #{bits(mask)} support #{support[mask]}"
      METHODS.each do |method|
        common = (splits[method].to_a + [ingroup]).select { |clade| (clade & mask) == mask }.min_by { |clade| bits(clade) }
        intruders = names.each_with_index.filter_map { |name, taxon| name unless (common & ~mask & (1 << taxon)).zero? }
        lines << "TEST #{hypothesis} #{method} monophyletic #{common == mask ? 'yes' : 'no'} mrca #{bits(common)} intruders #{intruders.empty? ? '-' : intruders.join(',')}"
      end
      subset = mask & exhaustive_ingroup
      unless bits(subset) >= 2 && bits(subset) < bits(exhaustive_ingroup)
        lines << "SUBSET #{hypothesis} untestable"
        next
      end
      included, excluded = exhaustive[:records].partition { |record| record[:splits].include?(subset) }
      lines << "SUBSET #{hypothesis} taxa #{bits(subset)} with #{included.map { |record| record[:score] }.min} without #{excluded.map { |record| record[:score] }.min} bme_with #{real(included.map { |record| record[:bme] }.min, 5)} bme_without #{real(excluded.map { |record| record[:bme] }.min, 5)}"
    end
    lines
  end

  def distance_lines(names, pairs, matrices, saturated, main_method, patristic, me_start, me, exhaustive)
    totals = [0, 0, 0]
    pair_block = pairs.map do |a, b, n, s, v|
      [n, s, v].each_with_index { |value, i| totals[i] += value }
      "PAIR #{names[a]} #{names[b]} sites #{n} transitions #{s} transversions #{v}"
    end
    pair_block << "TOTAL sites #{totals[0]} transitions #{totals[1]} transversions #{totals[2]}"
    blocks = [pair_block]
    Distances::MODELS.each do |model|
      block = ["MODEL #{model}", *matrix_lines(names, matrices[model])]
      saturated[model].each { |a, b, n| block << "SATURATED #{names[a]} #{names[b]} sites #{n}" }
      blocks << block
    end
    blocks << ["PATRISTIC #{main_method}", *matrix_lines(names, patristic[main_method])]
    evolution = ["ME start #{main_method} length #{real(me_start, 5)}"]
    me[:moves].each { |mask, swap, value| evolution << "NNI edge #{symbols(mask, names.size)} swap #{swap} length #{real(value, 5)}" }
    evolution << "ME moves #{me[:moves].size} evaluated #{me[:evaluated]} length #{real(me[:value], 5)}"
    best = exhaustive[:best_bme]
    evolution << "EXHAUSTIVE taxa #{exhaustive[:taxa].size} trees #{exhaustive[:records].size} best #{real(best[:bme], 5)} second #{real(exhaustive[:second_bme], 5)}"
    evolution << "BEST #{best[:newick]} parsimony #{best[:score]}"
    blocks << evolution
    blocks.each_with_index.flat_map { |block, i| i.zero? ? block : ['', *block] }
  end

  def score_line(method, score, minimum, maximum)
    "TREE #{method} score #{score} ci #{real(minimum.fdiv(score), 4)} ri #{real((maximum - score).fdiv(maximum - minimum), 4)}"
  end

  def parsimony_lines(names, outgroup, minimum, maximum, minima, nj_scores, initial, search, ancestors, changes, exhaustive)
    lines = ["BOUNDS minimum #{minimum} maximum #{maximum}"]
    NJ_METHODS.each { |method| lines << score_line(method, nj_scores[method], minimum, maximum) }
    lines << "START #{initial[:taxa].first(3).map { |taxon| names[taxon] }.join(' ')} score #{initial[:initial]}"
    initial[:additions].each { |taxon, mask, value, ties| lines << "ADD #{names[taxon]} edge #{symbols(mask, names.size)} score #{value} ties #{ties}" }
    lines << "STEPWISE score #{initial[:score]} evaluated #{initial[:evaluated]}"
    search[:moves].each { |mask, swap, value| lines << "NNI edge #{symbols(mask, names.size)} swap #{swap} score #{value}" }
    lines << "SEARCH moves #{search[:moves].size} evaluated #{search[:evaluated]} score #{search[:value]}"
    lines << score_line('MP', search[:value], minimum, maximum)
    lines << 'MP ' + TreeIO.newick(search[:tree], names, outgroup, lengths: true)
    histogram = Hash.new(0).merge(changes.tally)
    0.upto(changes.max) { |value| lines << "CHANGES #{value} columns #{histogram[value]}" }
    lines << "HOMOPLASY columns #{changes.zip(minima).count { |value, lower| value > lower }} extra #{search[:value] - minimum}"
    rooted = search[:tree].rooted(outgroup)
    ancestral_records = ancestors.map { |node, sequence| [symbols(node == rooted.root ? rooted.ingroup : rooted.masks[node], names.size), sequence] }
    ancestral_records.sort.each { |symbol, sequence| lines << "ANCESTOR #{symbol} #{sequence}" }
    lines << ''
    lines << "EXHAUSTIVE taxa #{exhaustive[:taxa].size} trees #{exhaustive[:records].size} best #{exhaustive[:best_score]} optimal #{exhaustive[:optimal].size}"
    exhaustive[:histogram].sort.each { |value, count| lines << "SCORE #{value} trees #{count}" }
    exhaustive[:optimal].each { |record| lines << "OPTIMAL #{record[:newick]} bme #{real(record[:bme], 5)}" }
    lines << 'STRICT ' + TreeIO.newick(exhaustive[:strict], names, outgroup)
    lines << "HEURISTIC score #{exhaustive[:heuristic]} optimal #{exhaustive[:heuristic] == exhaustive[:best_score] ? 'yes' : 'no'}"
    lines
  end

  def main
    parameters = read_parameters
    records = Alignment.read_fasta
    accepted, rejected, length = check_records(records, parameters['max_missing_percent'])
    names, sequences = accepted.transpose
    count = names.size
    outgroup = names.index(parameters['outgroup'])
    patterns = Alignment::Patterns.new(sequences)
    pairs = Distances.all_pairs(sequences, Array.new(length, 1))
    matrices, saturated, nj_trees = {}, {}, {}
    Distances::MODELS.zip(NJ_METHODS).each do |model, method|
      matrices[model], saturated[model] = Distances.build_matrix(pairs, count, model, parameters['saturation_distance'])
      nj_trees[method] = TreeBuilding.neighbor_joining(matrices[model], 0...count)
    end
    main_method = 'NJ_' + parameters['model']
    main_tree, main_matrix = nj_trees[main_method], matrices[parameters['model']]
    me_start = bme_length(main_tree, main_matrix)
    me = hill_climb(main_tree, ->(tree) { bme_length(tree, main_matrix) }, outgroup, me_start)
    addition_order = [outgroup, *(0...count).reject { |taxon| taxon == outgroup }]
    initial = stepwise(addition_order, count, patterns, outgroup)
    mp = hill_climb(initial[:tree], ->(tree) { Parsimony.score(tree, patterns, outgroup) }, outgroup, initial[:score])
    ancestors, branch_changes, column_changes = Parsimony.reconstruct(mp[:tree], patterns, outgroup)
    branch_changes.each { |(a, b), changes| mp[:tree].connect(a, b, changes.fdiv(length)) }
    minimum, maximum, minima = parsimony_bounds(patterns)
    nj_scores = nj_trees.transform_values { |tree| Parsimony.score(tree, patterns, outgroup) }
    exhaustive_taxa = [outgroup, *(0...count).select { |taxon| taxon != outgroup && parameters['exhaustive_taxa'].include?(names[taxon]) }]
    exhaustive = exhaustive_search(exhaustive_taxa, names, patterns, outgroup, main_matrix)
    site_logs = nj_trees.transform_values { |tree| likelihood_sites(tree, names, patterns, outgroup) }
    consensus, support, bootstrap_report = bootstrap(names, sequences, parameters, main_tree, main_matrix, outgroup)
    trees = nj_trees.merge('ME' => me[:tree], 'MP' => mp[:tree], 'CONSENSUS' => consensus)
    patristic = nj_trees.transform_values { |tree| TreeBuilding.patristic_matrix(tree) }
    newicks, cladograms = [], []
    METHODS.each do |method|
      newicks << method + ' ' + TreeIO.newick(trees[method], names, outgroup, lengths: NJ_METHODS.include?(method) || method == 'MP', support: method == 'CONSENSUS' ? support : nil)
      cladograms << '' unless cladograms.empty?
      cladograms.concat(["TREE #{method}", *TreeIO.cladogram(trees[method], names, outgroup, support)])
    end
    outputs = {
      'summary.txt' => summary_lines(records, rejected, names, sequences, patterns),
      'distances.txt' => distance_lines(names, pairs, matrices, saturated, main_method, patristic, me_start, me, exhaustive),
      'trees.nwk' => newicks, 'cladograms.txt' => cladograms,
      'parsimony.txt' => parsimony_lines(names, outgroup, minimum, maximum, minima, nj_scores, initial, mp, ancestors, column_changes, exhaustive),
      'likelihood.txt' => likelihood_lines(names, patterns, nj_trees, outgroup, main_method, parameters['low_sites'], site_logs),
      'bootstrap.txt' => bootstrap_report,
      'clock.txt' => clock_lines(names, sequences, outgroup, main_method, main_tree),
      'comparison.txt' => comparison_lines(names, patterns, trees, matrices, main_matrix, main_method, outgroup, support, parameters['replicates'], nj_scores, mp[:value], branch_changes, site_logs, patristic),
      'hypotheses.txt' => hypothesis_lines(names, trees, outgroup, support, exhaustive)
    }
    outputs.each { |filename, lines| TreeIO.write_lines(filename, lines) }
  end
end

Phylogeny.main if __FILE__ == $PROGRAM_NAME
