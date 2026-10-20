# frozen_string_literal: true

require_relative 'dataset'
require_relative 'distances'
require_relative 'agglomerative'
require_relative 'dendrogram'
require_relative 'validation'

class HierarchicalAnalysis
  def initialize
    data = Dataset.read
    @features = data[:features]
    @ids = data[:ids]
    @labels = data[:labels]
    @original = data[:values]
    @n = @ids.length
    @p = @features.length
    @observations = (0...@n).to_a
    @classes = @labels.uniq.sort
    @targets = @labels.map { |label| @classes.index(label) }
    settings = data[:settings]
    @distance_type = settings.fetch('DISTANCE').first
    @standardize = settings.fetch('STANDARDIZE').first
    @linkages = settings.fetch('LINKAGES')
    @cut_heights = settings.fetch('CUT_HEIGHTS').map(&:to_f)
    @cut_counts = settings.fetch('CUT_K').map(&:to_i)
    @inconsistency_depth, @last_count = settings.fetch('INCONSISTENCY').map(&:to_i)
    @gap_max = settings.fetch('GAP_MAX_K').first.to_i
    @list_size = settings.fetch('LIST_SIZE').first.to_i
    @width = settings.fetch('DENDROGRAM_WIDTH').first.to_i
    @compare_linkage = settings.fetch('COMPARE_LINKAGE').first
    @replicates, @percent, @seed = settings.fetch('SUBSAMPLES').map(&:to_i)
    @refine_limit = settings.fetch('REFINE_ITERATIONS').first.to_i
    @means, @deviations = Distances.statistics(@original)
    @vectors = Distances.standardize(@original, @means, @deviations, @standardize == 'yes')
    @distance = Distances.matrix(@vectors, @distance_type)
    @pairs = @observations.combination(2).to_a
    @distance_values = @pairs.map { |i, j| @distance[i][j] }
    @overall = centroid(@vectors, @observations)
  end

  def real(value)
    return '-' if value.nil?

    text = format('%.4f', value)
    text == '-0.0000' ? '0.0000' : text
  end

  def rounded(value)
    Rational(real(value))
  end

  def real_list(values)
    values.map { |value| real(value) }.join(' ')
  end

  def ari_text(value)
    "#{value.numerator}/#{value.denominator} #{real(value.to_f)}"
  end

  def total(values)
    result = 0.0
    values.each { |value| result += value }
    result
  end

  def centroid(vectors, members)
    vectors.first.each_index.map do |feature|
      value = 0.0
      members.each { |i| value += vectors[i][feature] }
      value / members.length
    end
  end

  def groups(partition)
    result = Array.new(partition.max) { [] }
    partition.each_with_index { |group, i| result[group - 1] << i }
    result
  end

  def build_tree(matrix, method)
    count = matrix.length
    merges = Agglomerative.cluster(matrix, method)
    members = Array.new(count) { |i| [i] }
    heights = Array.new(count, 0.0)
    maxima = Array.new(count, 0.0)
    depths = Array.new(count, 0)
    joins = Array.new(count)
    cophenetic = Array.new(count) { Array.new(count, 0.0) }
    merges.each do |a, b, height, _size|
      members[a].each do |i|
        members[b].each { |j| cophenetic[i][j] = cophenetic[j][i] = height }
      end
      joins[a] = height if a < count
      joins[b] = height if b < count
      members << (members[a] + members[b]).sort
      heights << height
      maxima << [height, maxima[a], maxima[b]].max
      depths << 1 + [depths[a], depths[b]].max
    end
    { count: count, merges: merges, members: members, heights: heights, maxima: maxima,
      depths: depths, joins: joins, cophenetic: cophenetic, order: Dendrogram.leaf_order(merges, count) }
  end

  def cut(tree, k: nil, height: nil)
    count = tree[:count]
    active = (0...count).to_a
    tree[:merges].each_with_index do |(a, b, _height, _size), step|
      node = count + step
      selected = k.nil? ? tree[:maxima][node] <= height : step < count - k
      next unless selected

      active.delete(a)
      active.delete(b)
      active << node
    end
    positions = Array.new(count)
    tree[:order].each_with_index { |leaf, position| positions[leaf] = position }
    active.sort_by! { |node| tree[:members][node].map { |i| positions[i] }.min }
    partition = Array.new(count)
    active.each_with_index do |node, index|
      tree[:members][node].each { |i| partition[i] = index + 1 }
    end
    partition
  end

  def evaluate(partition, matrix = @distance)
    members = groups(partition)
    count = members.length
    centers = members.map { |group| centroid(@vectors, group) }
    silhouettes = Validation.silhouettes(partition, matrix)
    silhouette = silhouettes && total(silhouettes) / @n
    diameter = 0.0
    separation = nil
    @pairs.each do |i, j|
      value = matrix[i][j]
      if partition[i] == partition[j]
        diameter = value if value > diameter
      elsif separation.nil? || value < separation
        separation = value
      end
    end
    dunn = count >= 2 && diameter.positive? ? separation / diameter : nil
    wss = 0.0
    @observations.each { |i| wss += Distances.squared(@vectors[i], centers[partition[i] - 1]) }
    bss = 0.0
    members.each_with_index { |group, g| bss += group.length * Distances.squared(centers[g], @overall) }
    ch = count >= 2 && count < @n ? (bss / (count - 1)) / (wss / (@n - count)) : nil
    table = Validation.contingency(partition.map { |group| group - 1 }, @targets, count, @classes.length)
    matched = table.sum(&:max)
    { partition: partition, groups: members, sizes: members.map(&:length), centers: centers,
      silhouettes: silhouettes, silhouette: silhouette, dunn: dunn, wss: wss, ch: ch,
      table: table, matched: matched, ari: Validation.ari(partition, @targets) }
  end

  def evaluation_text(evaluation)
    "sizes #{evaluation[:sizes].join(' ')} silhouette #{real(evaluation[:silhouette])} " \
      "dunn #{real(evaluation[:dunn])} wss #{real(evaluation[:wss])} ch #{real(evaluation[:ch])} " \
      "ari #{ari_text(evaluation[:ari])}"
  end

  def analyze(method)
    tree = build_tree(@distance, method)
    cophenetic = @pairs.map { |i, j| tree[:cophenetic][i][j] }
    path = 0.0
    tree[:order].each_cons(2) { |i, j| path += @distance[i][j] }
    upper_heights = tree[:maxima].drop(@n).sort
    gaps = (2..@gap_max).map { |k| upper_heights[@n - k] - upper_heights[@n - k - 1] }
    suggested = (2..@gap_max).min_by { |k| [-rounded(gaps[k - 2]), k] }
    height_cuts = @cut_heights.map { |height| evaluate(cut(tree, height: height)) }
    count_cuts = @cut_counts.to_h { |k| [k, evaluate(cut(tree, k: k))] }
    { method: method, tree: tree, cophenetic: cophenetic,
      correlation: Validation.correlation(@distance_values, cophenetic), path: path,
      gaps: gaps, suggested: suggested, height_cuts: height_cuts, count_cuts: count_cuts,
      label_cut: evaluate(cut(tree, k: @classes.length)) }
  end

  def data_summary
    minimum = @pairs.min_by { |i, j| [@distance[i][j], i, j] }
    maximum = @pairs.min_by { |i, j| [-@distance[i][j], i, j] }
    @dmax = @distance[maximum[0]][maximum[1]]
    @neighbors = @observations.map do |i|
      @observations.reject { |j| j == i }.min_by { |j| [@distance[i][j], j] }
    end
    nearest_mean = 0.0
    @observations.each { |i| nearest_mean += @distance[i][@neighbors[i]] }
    nearest_mean /= @n
    mutual = @observations.count { |i| i < @neighbors[i] && @neighbors[@neighbors[i]] == i }
    lines = ["data n #{@n} features #{@p} classes #{@classes.length} distance #{@distance_type} standardize #{@standardize}"]
    @features.each_with_index do |feature, index|
      lines << "feature #{feature} mean #{real(@means[index])} sd #{real(@deviations[index])}"
    end
    lines << "distances pairs #{@pairs.length} min #{real(@distance[minimum[0]][minimum[1]])} " \
             "#{@ids[minimum[0]]} #{@ids[minimum[1]]} max #{real(@dmax)} #{@ids[maximum[0]]} " \
             "#{@ids[maximum[1]]} mean #{real(total(@distance_values) / @pairs.length)}"
    lines << "nearest_neighbors mean #{real(nearest_mean)} reciprocal_pairs #{mutual}"
    lines << "labels #{evaluation_text(evaluate(@targets.map { |target| target + 1 }))}"
    lines
  end

  def feature_correlations
    columns = @features.each_index.map { |feature| @original.map { |row| row[feature] } }
    lines = ["correlation #{@features.join(' ')}"]
    @features.each_with_index do |feature, i|
      values = columns.map { |column| Validation.correlation(columns[i], column) }
      lines << "#{feature} #{real_list(values)}"
    end
    lines
  end

  def histogram
    bins = Array.new(10, 0)
    @distance_values.each { |value| bins[[9, (10 * value / @dmax).floor].min] += 1 }
    maximum = bins.max
    lines = ['histogram']
    bins.each_with_index do |count, bin|
      line = "#{real(bin * @dmax / 10)} #{real((bin + 1) * @dmax / 10)} #{count}"
      length = count * 50 / maximum
      line += ' ' + '#' * length if length.positive?
      lines << line
    end
    lines
  end

  def inconsistency(tree, step)
    sequence = []
    stack = [[@n + step - 1, @inconsistency_depth]]
    until stack.empty?
      node, depth = stack.pop
      next if depth.zero?

      a, b, height = tree[:merges][node - @n]
      sequence << height
      stack << [b, depth - 1] if b >= @n
      stack << [a, depth - 1] if a >= @n
    end
    mean = total(sequence) / sequence.length
    deviation = coefficient = 0.0
    if sequence.length > 1
      square = 0.0
      sequence.each { |value| square += (value - mean) * (value - mean) }
      deviation = Math.sqrt(square / (sequence.length - 1))
      coefficient = (tree[:merges][step - 1][2] - mean) / deviation
    end
    [mean, deviation, sequence.length, coefficient]
  end

  def linkage_details(analysis)
    tree = analysis[:tree]
    merges = tree[:merges]
    heights = merges.map { |merge| merge[2] }
    inversions = (1...merges.length).select { |index| heights[index] < heights[index - 1] }
    lines = ["linkage #{analysis[:method]}",
             "cophenetic #{real(analysis[:correlation])} leaf_path #{real(analysis[:path])}",
             "heights min #{real(heights.min)} max #{real(heights.max)} inversions #{inversions.length}"]
    inversions.each do |index|
      lines << "inversion step #{index + 1} height #{real(heights[index])} previous #{real(heights[index - 1])}"
    end
    lines << "gaps #{real_list(analysis[:gaps])}"
    lines << "suggested_k #{analysis[:suggested]}"
    late = @observations.sort_by { |i| [-tree[:joins][i], i] }.first(@list_size)
    lines << "late_joiners #{late.map { |i| "#{@ids[i]}:#{real(tree[:joins][i])}" }.join(' ')}"
    kinds = Array.new(3, 0)
    merges.each { |a, b, _height, _size| kinds[[a, b].count { |child| child >= @n }] += 1 }
    lines << "merges leaf_leaf #{kinds[0]} leaf_cluster #{kinds[1]} cluster_cluster #{kinds[2]} depth #{tree[:depths].last}"
    matched = analysis[:label_cut][:matched]
    lines << "label_cut k #{@classes.length} purity #{matched}/#{@n} #{real(matched.to_f / @n)}"
    lines << "inconsistency depth #{@inconsistency_depth}"
    (@n - @last_count...@n).each do |step|
      mean, deviation, count, coefficient = inconsistency(tree, step)
      lines << "step #{step} height #{real(heights[step - 1])} mean #{real(mean)} sd #{real(deviation)} " \
               "count #{count} coefficient #{real(coefficient)}"
    end
    analysis[:height_cuts].each_with_index do |evaluation, index|
      lines << "cut height #{real(@cut_heights[index])} clusters #{evaluation[:sizes].length} #{evaluation_text(evaluation)}"
    end
    analysis[:count_cuts].each { |k, evaluation| lines << "cut k #{k} #{evaluation_text(evaluation)}" }
    lines
  end

  def representative(parents, value)
    value = parents[value] until parents[value] == value
    value
  end

  def mst_details
    analysis = @analyses.find { |item| item[:method] == 'single' }
    edges = Agglomerative.prim(@distance)
    weight = 0.0
    edges.each { |_a, _b, value| weight += value }
    sorted = edges.each_index.sort_by { |index| [edges[index][2], index] }.map { |index| edges[index] }
    match = sorted.each_with_index.all? do |edge, index|
      (edge[2] - analysis[:tree][:merges][index][2]).abs <= 0.000000001
    end
    links = edges.map { |a, b, _value| [a, b].sort }
    nearest_edges = @observations.count { |i| links.include?([i, @neighbors[i]].sort) }
    lines = ["mst total #{real(weight)} heights #{match ? 'match' : 'mismatch'} nn_edges #{nearest_edges}/#{@n}"]
    @cut_counts.each do |k|
      parents = @observations.dup
      sorted.first(@n - k).each { |a, b, _value| parents[representative(parents, a)] = representative(parents, b) }
      partition = analysis[:count_cuts][k][:partition]
      agree = @pairs.all? do |i, j|
        (representative(parents, i) == representative(parents, j)) == (partition[i] == partition[j])
      end
      lines << "mst partition k #{k} #{agree ? 'match' : 'mismatch'}"
    end
    lines
  end

  def compare_distances
    lines = ["compare linkage #{@compare_linkage} k #{@classes.length}"]
    %w[euclidean manhattan correlation].each do |type|
      matrix = Distances.matrix(@vectors, type)
      tree = build_tree(matrix, @compare_linkage)
      actual = @pairs.map { |i, j| matrix[i][j] }
      implied = @pairs.map { |i, j| tree[:cophenetic][i][j] }
      correlation = Validation.correlation(actual, implied)
      evaluation = evaluate(cut(tree, k: @classes.length), matrix)
      lines << "metric #{type} cophenetic #{real(correlation)} silhouette #{real(evaluation[:silhouette])} " \
               "ari #{ari_text(evaluation[:ari])}"
    end
    lines
  end

  def linkage_comparisons
    correlations = ['cophenetic_matrix', "linkage #{@linkages.join(' ')}"]
    agreement = ["agreement k #{@classes.length}", "linkage #{@linkages.join(' ')}"]
    @analyses.each do |left|
      values = @analyses.map { |right| Validation.correlation(left[:cophenetic], right[:cophenetic]) }
      correlations << "#{left[:method]} #{real_list(values)}"
      values = @analyses.map { |right| Validation.ari(left[:label_cut][:partition], right[:label_cut][:partition]).to_f }
      agreement << "#{left[:method]} #{real_list(values)}"
    end
    [correlations, agreement]
  end

  def selection
    ranking = @analyses.each_index.sort_by { |i| [-rounded(@analyses[i][:correlation]), i] }
    lines = ['summary', "cophenetic_ranking #{ranking.map { |i| @analyses[i][:method] }.join(' ')}"]
    @cut_counts.each do |k|
      best = @analyses.each_index.min_by { |i| [-@analyses[i][:count_cuts][k][:ari], i] }
      analysis = @analyses[best]
      lines << "best_ari k #{k} #{analysis[:method]} #{ari_text(analysis[:count_cuts][k][:ari])}"
    end
    @selected = nil
    @analyses.each do |analysis|
      best_k = @cut_counts.min_by { |k| [-rounded(analysis[:count_cuts][k][:silhouette]), k] }
      lines << "best_silhouette #{analysis[:method]} k #{best_k} #{real(analysis[:count_cuts][best_k][:silhouette])}"
      @cut_counts.each do |k|
        evaluation = analysis[:count_cuts][k]
        next unless @selected.nil? || evaluation[:ari] > @selected[:ari]

        @selected_analysis = analysis
        @selected = evaluation
        @kappa = k
      end
    end
    @lambda = @selected_analysis[:method]
    lines << "selected #{@lambda} k #{@kappa}"
    lines
  end

  def cluster_separation(left, right)
    value = nil
    left.each do |i|
      right.each do |j|
        distance = @distance[i][j]
        value = distance if value.nil? || distance < value
      end
    end
    value
  end

  def cluster_details
    lines = ["selected linkage #{@lambda} k #{@kappa} ari #{ari_text(@selected[:ari])} " \
             "silhouette #{real(@selected[:silhouette])}"]
    @majorities = []
    @selected[:groups].each_with_index do |members, g|
      counts = @selected[:table][g]
      majority = counts.each_index.min_by { |t| [-counts[t], t] }
      @majorities << majority
      silhouette = total(members.map { |i| @selected[:silhouettes][i] }) / members.length
      medoid = members.min_by { |i| [total(members.map { |j| @distance[i][j] }), i] }
      pair = members.combination(2).min_by { |i, j| [-@distance[i][j], i, j] }
      diameter = pair ? "#{real(@distance[pair[0]][pair[1]])} #{@ids[pair[0]]} #{@ids[pair[1]]}" : '0.0000 - -'
      neighbors = @selected[:groups].each_with_index.filter_map do |other, h|
        [h + 1, cluster_separation(members, other)] unless g == h
      end
      nearest, separation = neighbors.min_by { |number, distance| [distance, number] }
      lines << "cluster #{g + 1} size #{members.length} silhouette #{real(silhouette)} majority #{@classes[majority]} " \
               "purity #{counts[majority]}/#{members.length} #{real(counts[majority].to_f / members.length)}"
      lines << "  mean #{real_list(centroid(@original, members))}"
      lines << "  medoid #{@ids[medoid]} diameter #{diameter} nearest #{nearest} separation #{real(separation)}"
    end
    lines
  end

  def centroid_distances
    lines = ['centroid_distances']
    @selected[:centers].each_with_index do |center, g|
      distances = @selected[:centers].map { |other| Math.sqrt(Distances.squared(center, other)) }
      lines << "#{g + 1} #{real_list(distances)}"
    end
    lines
  end

  def profile_bars
    width = @features.map(&:length).max
    lines = ['profile_bars']
    @selected[:groups].each_with_index do |members, g|
      lines << "cluster #{g + 1}"
      @features.each_with_index do |feature, f|
        value = 0.0
        members.each { |i| value += (@original[i][f] - @means[f]) / @deviations[f] }
        value /= members.length
        length = [10, (value.abs * 4).floor].min
        left = value.negative? ? ' ' * (10 - length) + '#' * length : ' ' * 10
        right = value.negative? ? ' ' * 10 : '#' * length + ' ' * (10 - length)
        lines << "#{feature.ljust(width)} #{left}|#{right} #{real(value)}"
      end
    end
    lines
  end

  def contingency_details
    table = @selected[:table]
    lines = ['contingency', "cluster #{@classes.join(' ')} total"]
    table.each_with_index { |row, g| lines << "#{g + 1} #{row.join(' ')} #{row.sum}" }
    columns = Array.new(@classes.length, 0)
    table.each { |row| row.each_with_index { |value, t| columns[t] += value } }
    lines << "total #{columns.join(' ')} #{@n}"
    matched = @selected[:matched]
    lines << "purity #{matched}/#{@n} #{real(matched.to_f / @n)}"
    lines
  end

  def misplaced
    lines = ['misplaced']
    @observations.each do |i|
      group = @selected[:partition][i]
      majority = @majorities[group - 1]
      next if @targets[i] == majority

      lines << "#{@ids[i]} label #{@labels[i]} cluster #{group} majority #{@classes[majority]}"
    end
    lines << "count #{lines.length - 1}"
    lines
  end

  def weakest
    observations = @observations.sort_by { |i| [@selected[:silhouettes][i], i] }.first(@list_size)
    ['weakest'] + observations.map do |i|
      "#{@ids[i]} label #{@labels[i]} cluster #{@selected[:partition][i]} silhouette #{real(@selected[:silhouettes][i])}"
    end
  end

  def feature_ratios
    ratios = @features.each_index.map do |f|
      between = 0.0
      @selected[:groups].each_with_index do |members, g|
        difference = @selected[:centers][g][f] - @overall[f]
        between += members.length * difference * difference
      end
      within = 0.0
      @observations.each do |i|
        difference = @vectors[i][f] - @selected[:centers][@selected[:partition][i] - 1][f]
        within += difference * difference
      end
      (between / (@kappa - 1)) / (within / (@n - @kappa))
    end
    order = @features.each_index.sort_by { |f| [-rounded(ratios[f]), f] }
    ['features'] + order.each_with_index.map do |f, rank|
      "#{rank + 1} #{@features[f]} f_ratio #{real(ratios[f])}"
    end
  end

  def last_merges
    tree = @selected_analysis[:tree]
    lines = ['top_merges']
    (@n - @last_count...@n).each do |step|
      a, b, height = tree[:merges][step - 1]
      children = [a, b].map do |node|
        counts = Array.new(@classes.length, 0)
        tree[:members][node].each { |i| counts[@targets[i]] += 1 }
        "#{node} #{tree[:members][node].length} #{counts.join('/')}"
      end
      lines << "step #{step} height #{real(height)} a #{children[0]} b #{children[1]}"
    end
    lines
  end

  def drop_features
    lines = ['drop_feature']
    @features.each_with_index do |feature, removed|
      vectors = @vectors.map { |row| row.each_with_index.filter_map { |value, f| value unless f == removed } }
      tree = build_tree(Distances.matrix(vectors, @distance_type), @lambda)
      partition = cut(tree, k: @kappa)
      agreement = Validation.ari(partition, @selected[:partition])
      labels = Validation.ari(partition, @targets)
      lines << "#{feature} ari_selected #{ari_text(agreement)} ari_labels #{ari_text(labels)}"
    end
    lines
  end

  def refinement
    centers = @selected[:centers].map(&:dup)
    partition = @selected[:partition].dup
    iterations = 0
    1.upto(@refine_limit) do |iteration|
      iterations = iteration
      assignment = @vectors.map do |vector|
        best = 0
        smallest = Distances.squared(vector, centers[0])
        1.upto(@kappa - 1) do |g|
          distance = Distances.squared(vector, centers[g])
          if distance < smallest
            best = g
            smallest = distance
          end
        end
        best + 1
      end
      break if assignment == partition

      partition = assignment
      members = Array.new(@kappa) { [] }
      partition.each_with_index { |g, i| members[g - 1] << i }
      members.each_with_index { |group, g| centers[g] = centroid(@vectors, group) unless group.empty? }
    end
    changed = @observations.count { |i| partition[i] != @selected[:partition][i] }
    evaluation = evaluate(partition)
    ["refinement max_iterations #{@refine_limit}",
     "iterations #{iterations} changed #{changed} wss #{real(@selected[:wss])} -> #{real(evaluation[:wss])}",
     "sizes #{evaluation[:sizes].join(' ')} silhouette #{real(evaluation[:silhouette])}",
     "ari_selected #{ari_text(Validation.ari(partition, @selected[:partition]))} ari_labels #{ari_text(evaluation[:ari])}"]
  end

  def stability
    lines = ["stability replicates #{@replicates} percent #{@percent} seed #{@seed}"]
    state = @seed
    size = @n * @percent / 100
    ari_total = 0.0
    jaccard_totals = Array.new(@kappa, 0.0)
    1.upto(@replicates) do |replicate|
      shuffled = @observations.dup
      size.times do |t|
        state = 48_271 * state % 2_147_483_647
        j = t + state % (@n - t)
        shuffled[t], shuffled[j] = shuffled[j], shuffled[t]
      end
      sample = shuffled.first(size).sort
      matrix = sample.map { |i| sample.map { |j| @distance[i][j] } }
      partition = cut(build_tree(matrix, @lambda), k: @kappa)
      restricted = sample.map { |i| @selected[:partition][i] }
      agreement = Validation.ari(partition, restricted)
      sample_groups = groups(partition).map { |members| members.map { |u| sample[u] } }
      jaccards = @selected[:groups].map do |members|
        intersection = members & sample
        next Rational(0, 1) if intersection.empty?

        sample_groups.map do |group|
          common = (intersection & group).length
          Rational(common, intersection.length + group.length - common)
        end.max
      end
      ari_total += agreement.to_f
      jaccards.each_with_index { |value, g| jaccard_totals[g] += value.to_f }
      lines << "replicate #{replicate} size #{size} ari #{ari_text(agreement)} jaccard #{real_list(jaccards.map(&:to_f))}"
    end
    lines << "mean_ari #{real(ari_total / @replicates)}"
    lines << "mean_jaccard #{real_list(jaccard_totals.map { |value| value / @replicates })}"
    lines
  end

  def distance_map
    shades = '@%#*+=-:. '.chars
    order = @selected_analysis[:tree][:order]
    frame = '+' + '-' * @n + '+'
    lines = ["distance_map #{@lambda}", frame]
    order.each do |i|
      row = order.map { |j| shades[[9, (10 * @distance[i][j] / @dmax).floor].min] }.join
      lines << '|' + row + '|'
    end
    lines << frame
  end

  def profiles
    [cluster_details, centroid_distances, profile_bars, contingency_details, misplaced, weakest,
     feature_ratios, last_merges, drop_features, refinement, stability, distance_map]
  end

  def newick(analysis)
    tree = analysis[:tree]
    strings = @ids.dup
    tree[:merges].each do |a, b, height, _size|
      upper, lower = tree[:members][a].first < tree[:members][b].first ? [a, b] : [b, a]
      upper_length = height - tree[:heights][upper]
      lower_length = height - tree[:heights][lower]
      strings << "(#{strings[upper]}:#{real(upper_length)},#{strings[lower]}:#{real(lower_length)})"
    end
    "#{analysis[:method]} #{strings.last};"
  end

  def linkage_rows
    rows = ['method,step,a,b,height,size']
    @analyses.each do |analysis|
      analysis[:tree][:merges].each_with_index do |(a, b, height, size), step|
        rows << [analysis[:method], step + 1, a, b, real(height), size].join(',')
      end
    end
    rows
  end

  def cluster_rows
    header = %w[id label]
    partitions = []
    @analyses.each do |analysis|
      analysis[:height_cuts].each_with_index do |evaluation, index|
        header << "#{analysis[:method]}_h#{index + 1}"
        partitions << evaluation[:partition]
      end
      analysis[:count_cuts].each do |k, evaluation|
        header << "#{analysis[:method]}_k#{k}"
        partitions << evaluation[:partition]
      end
    end
    [header.join(',')] + @observations.map do |i|
      ([@ids[i], @labels[i]] + partitions.map { |partition| partition[i] }).join(',')
    end
  end

  def dendrograms
    @analyses.map do |analysis|
      tree = analysis[:tree]
      maximum = tree[:merges].map { |merge| merge[2] }.max
      lines = ["dendrogram #{analysis[:method]} height_max #{real(maximum)} width #{@width}"]
      lines.concat(Dendrogram.draw(tree[:merges], @ids, @labels, tree[:order], @width, @cut_heights))
      @cut_heights.each do |height|
        column = Dendrogram.column(height, maximum, @width)
        lines << "cut #{real(height)} column #{column > @width ? '-' : column}"
      end
      lines
    end
  end

  def separate(parts)
    parts.each_with_index.flat_map { |part, index| index.zero? ? part : [''] + part }
  end

  def run
    @analyses = @linkages.map { |method| analyze(method) }
    validation = [data_summary, feature_correlations, histogram]
    @analyses.each { |analysis| validation << linkage_details(analysis) }
    validation << mst_details if @linkages.include?('single')
    validation << compare_distances
    validation.concat(linkage_comparisons)
    validation << selection
    profile_parts = profiles
    Dir.mkdir('output') unless Dir.exist?('output')
    Dataset.write('output/linkage.csv', linkage_rows)
    Dataset.write('output/clusters.csv', cluster_rows)
    Dataset.write('output/dendrogram.txt', separate(dendrograms))
    Dataset.write('output/trees.txt', @analyses.map { |analysis| newick(analysis) })
    Dataset.write('output/validation.txt', separate(validation))
    Dataset.write('output/profiles.txt', separate(profile_parts))
  end
end

HierarchicalAnalysis.new.run
