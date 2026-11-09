require_relative 'dataset'
require_relative 'gaussian'
require_relative 'em'
require_relative 'kmeans'
require_relative 'report'

module MixtureAnalysis
  module_function

  def ordered_sum(sequence)
    total = 0.0
    sequence.each { |value| total += value }
    total
  end

  def entropy(probabilities)
    -ordered_sum(probabilities.map { |r| r.zero? ? 0.0 : r * Math.log(r) })
  end

  def largest(values) = values.each_index.max_by { |i| [values[i], -i] }
  def dec(value, places = 4) = Report.decimal(value, places)
  def vals(values) = Report.values(values)
  def rounded(value) = dec(value).to_f
  def key(model) = [model[:k], model[:type]]
  def label(model) = "K=#{model[:k]} type=#{model[:type]}"

  def summarize(fitted, k, type, type_index, n, tolerance)
    p = case type
        when 'FULL' then 6 * k - 1
        when 'TIED' then 3 * k + 2
        when 'DIAG' then 5 * k - 1
        when 'SPHERICAL' then 4 * k - 1
        end
    assignment = fitted[:records].map { |r| largest(r[:r]) }
    total_entropy = ordered_sum(fitted[:records].map { |r| entropy(r[:r]) })
    trace = fitted[:trace]
    settled = trace.each_index.find { |t| trace[t..].all? { |l| (l - trace.last).abs <= tolerance } }
    increments = (1...trace.length).map { |t| trace[t] - trace[t - 1] }
    increase = largest(increments) + 1
    violations = (1...trace.length).select { |t| trace[t] < trace[t - 1] - 0.000001 * trace[t - 1].abs }
    bic = -2 * fitted[:loglik] + p * Math.log(n)
    fitted.merge(k: k, type: type, type_index: type_index, parameters: p, assignment: assignment,
                 sizes: k.times.map { |j| assignment.count(j) }, entropy: total_entropy,
                 mean_entropy: total_entropy / n, bic: bic, aic: -2 * fitted[:loglik] + 2 * p,
                 icl: bic + 2 * total_entropy, settled: settled,
                 increase: [increase, increments[increase - 1]], violations: violations)
  end

  def fit(points, initial, k, type, type_index, params)
    summarize(EM.fit(points, initial, type, params[:iterations], params[:regularization]),
              k, type, type_index, points.length, params[:settle_tolerance])
  end

  def ranking(models, criterion)
    models.sort_by { |m| [rounded(m[criterion]), m[:parameters], m[:k], m[:type_index]] }
  end

  def contingency(left, right, rows, columns)
    table = Array.new(rows) { Array.new(columns, 0) }
    left.each_index { |i| table[left[i]][right[i]] += 1 }
    table
  end

  def choose2(n) = n * (n - 1) / 2

  def ari(left, right, rows, columns)
    table = contingency(left, right, rows, columns)
    shared = table.flatten.inject(0) { |s, n| s + choose2(n) }
    row_total = table.inject(0) { |s, row| s + choose2(row.inject(0, :+)) }
    column_total = table.transpose.inject(0) { |s, col| s + choose2(col.inject(0, :+)) }
    z = choose2(left.length)
    numerator = 2 * (z * shared - row_total * column_total)
    denominator = z * (row_total + column_total) - 2 * row_total * column_total
    denominator.zero? ? Rational(1, 1) : Rational(numerator, denominator)
  end

  def ari_text(value) = "#{value.numerator}/#{value.denominator} #{dec(value.to_f)}"

  def centroid(points, indices)
    sx = sy = 0.0
    indices.each { |i| sx += points[i][0]; sy += points[i][1] }
    [sx / indices.length, sy / indices.length]
  end

  def metrics(points, labels, count)
    clusters = count.times.map { |k| labels.each_index.select { |i| labels[i] == k } }
    occupied = clusters.each_index.reject { |k| clusters[k].empty? }
    return {silhouette: nil, cluster_silhouettes: Array.new(count), ch: nil, db: nil} if occupied.length < 2
    centers = clusters.map { |indices| indices.empty? ? nil : centroid(points, indices) }
    distances = points.map { |p| points.map { |q| KMeans.distance(p, q) } }
    silhouettes = points.each_index.map do |i|
      own = clusters[labels[i]]
      next 0.0 if own.length == 1
      a = ordered_sum(own.reject { |j| j == i }.map { |j| distances[i][j] }) / (own.length - 1)
      b = occupied.reject { |k| k == labels[i] }.map do |k|
        ordered_sum(clusters[k].map { |j| distances[i][j] }) / clusters[k].length
      end.min
      (b - a) / [a, b].max
    end
    center = centroid(points, points.each_index.to_a)
    between = ordered_sum(occupied.map { |k| clusters[k].length * KMeans.distance2(centers[k], center) })
    within = ordered_sum(points.each_index.map { |i| KMeans.distance2(points[i], centers[labels[i]]) })
    g = occupied.length
    ch = (between / (g - 1)) / (within / (points.length - g))
    scatter = centers.each_index.map do |k|
      next nil if clusters[k].empty?
      ordered_sum(clusters[k].map { |i| KMeans.distance(points[i], centers[k]) }) / clusters[k].length
    end
    db = ordered_sum(occupied.map do |k|
      occupied.reject { |j| j == k }.map { |j| (scatter[k] + scatter[j]) / KMeans.distance(centers[k], centers[j]) }.max
    end) / g
    {silhouette: ordered_sum(silhouettes) / points.length,
     cluster_silhouettes: clusters.map { |is| is.empty? ? nil : ordered_sum(is.map { |i| silhouettes[i] }) / is.length },
     ch: ch, db: db}
  end

  def best_matching(model, km)
    k = model[:k]
    table = contingency(model[:assignment], km[:assignment], k, k)
    permutations = (0...k).to_a.permutation.to_a
    best = permutations.min_by do |perm|
      agreement = k.times.inject(0) { |s, j| s + table[perm[j]][j] }
      [-agreement, perm]
    end
    agreement = k.times.inject(0) { |s, j| s + table[best[j]][j] }
    [best, agreement, table]
  end

  def model_block(m)
    lines = ["model #{label(m)}", "parameters #{m[:parameters]}", "loglik #{dec(m[:loglik])}",
             "bic #{dec(m[:bic])}", "aic #{dec(m[:aic])}", "icl #{dec(m[:icl])}",
             "mean_entropy #{dec(m[:mean_entropy])}", "settled_at #{m[:settled]}",
             "largest_increase iteration #{m[:increase][0]} value #{dec(m[:increase][1])}",
             "violations #{m[:violations].length}", "sizes #{m[:sizes].join(' ')}"]
    m[:k].times do |k|
      mixture = m[:model]
      geometry = Gaussian.eigen(mixture[:covariances][k])
      lines << "component #{k + 1} weight #{dec(mixture[:weights][k])} mean #{vals(mixture[:means][k])} cov #{vals(mixture[:covariances][k])} axes #{vals(geometry[:axes])} angle #{dec(geometry[:angle])}"
    end
    lines
  end

  def ranking_block(rankings)
    ranks = rankings.transform_values { |models| models.each_with_index.to_h { |m, i| [key(m), i + 1] } }
    selected = rankings[:bic].first
    lines = ['ranking by bic', 'rank K type parameters loglik bic delta_bic aic aic_rank icl icl_rank']
    rankings[:bic].each_with_index do |m, i|
      lines << "#{i + 1} #{m[:k]} #{m[:type]} #{m[:parameters]} #{dec(m[:loglik])} #{dec(m[:bic])} #{dec(rounded(m[:bic]) - rounded(selected[:bic]))} #{dec(m[:aic])} #{ranks[:aic][key(m)]} #{dec(m[:icl])} #{ranks[:icl][key(m)]}"
    end
    {selected: :bic, best_aic: :aic, best_icl: :icl}.each { |name, criterion| lines << "#{name} #{label(rankings[criterion].first)}" }
    lines
  end

  def per_k_blocks(models, kmeans, points, params)
    previous = nil
    params[:k].map do |k|
      best = ranking(models.select { |m| m[:k] == k }, :bic).first
      km = kmeans[k]
      gmm_stats, km_stats = metrics(points, best[:assignment], k), metrics(points, km[:assignment], k)
      lines = ["K=#{k} type=#{best[:type]} bic #{dec(best[:bic])}",
               "  kmeans iterations #{km[:iterations]} inertia #{dec(km[:inertia])}",
               "  ari #{ari_text(ari(best[:assignment], km[:assignment], k, k))}"]
      {silhouette: :silhouette, calinski_harabasz: :ch, davies_bouldin: :db}.each do |name, metric|
        lines << "  #{name} gmm #{Report.optional(gmm_stats[metric])} kmeans #{Report.optional(km_stats[metric])}"
      end
      if previous
        table = contingency(previous[:assignment], best[:assignment], previous[:k], k)
        parents, shared = [], []
        k.times do |j|
          counts = table.map { |row| row[j] }
          parent = largest(counts)
          parents << (counts[parent].zero? ? '-' : parent + 1)
          shared << counts[parent]
        end
        lines << "  parents K=#{previous[:k]} #{parents.join(' ')} shared #{shared.join(' ')}"
      end
      previous = best
      lines
    end
  end

  def details_block(model, points, edges, stats)
    mixture = model[:model]
    lines = ['selected components']
    model[:k].times do |k|
      mean, cov = mixture[:means][k], mixture[:covariances][k]
      geometry = Gaussian.eigen(cov)
      members = points.each_index.select { |i| model[:assignment][i] == k }
      q = points.map { |p| Gaussian.mahalanobis(p, mean, cov) }
      boundaries = [0.0] + edges + [Float::INFINITY]
      observed, expected = [], []
      boundaries.each_cons(2) do |lo, hi|
        observed << members.count { |i| lo <= Math.sqrt(q[i]) && Math.sqrt(q[i]) < hi }
        upper = hi.infinite? ? 0.0 : Math.exp(-hi * hi / 2)
        expected << members.length * (Math.exp(-lo * lo / 2) - upper)
      end
      chi = ordered_sum(observed.each_index.map { |i| (observed[i] - expected[i]) * (observed[i] - expected[i]) / expected[i] })
      soft = ordered_sum(model[:records].map { |r| r[:r][k] })
      lines.concat(["component #{k + 1} weight #{dec(mixture[:weights][k])} size #{members.length} soft_size #{dec(soft)} mean #{vals(mean)}",
                    "  cov #{vals(cov)} corr #{dec(geometry[:correlation])}",
                    "  eigen #{vals(geometry[:eigenvalues])} direction #{vals(geometry[:direction])} angle #{dec(geometry[:angle])}",
                    "  axes_1sigma #{vals(geometry[:axes])} axes_2sigma #{vals(geometry[:axes].map { |a| 2 * a })}",
                    "  inside_1sigma #{members.count { |i| q[i] <= 1 }} inside_2sigma #{members.count { |i| q[i] <= 4 }} area_1sigma #{dec(geometry[:area])}",
                    "  silhouette #{Report.optional(stats[:cluster_silhouettes][k])}",
                    "  gof observed #{observed.join(' ')} expected #{vals(expected)} chi2 #{dec(chi)}"])
    end
    lines
  end

  def overlap_block(model)
    lines = ['overlap']
    (0...model[:k]).to_a.combination(2) do |a, b|
      mixture = model[:model]
      d = Gaussian.bhattacharyya(mixture[:means][a], mixture[:covariances][a], mixture[:means][b], mixture[:covariances][b])
      shared = ordered_sum(model[:records].map { |r| r[:r][a] * r[:r][b] })
      lines << "#{a + 1}-#{b + 1} bhattacharyya #{dec(d)} coefficient #{dec(Math.exp(-d))} shared #{dec(shared)}"
    end
    lines << 'none' if model[:k] == 1
    lines
  end

  def cluster_probabilities(clusters, record)
    clusters.map { |cluster| ordered_sum(cluster.map { |k| record[:r][k] }) }
  end

  def merged_entropy(clusters, records)
    ordered_sum(records.map { |r| entropy(cluster_probabilities(clusters, r)) })
  end

  def merging_block(model)
    clusters = model[:k].times.map { |k| [k] }
    lines = ['merging', "start entropy #{dec(merged_entropy(clusters, model[:records]))}"]
    step = 0
    while clusters.length > 1
      candidates = (0...clusters.length).to_a.combination(2).map do |a, b|
        proposed = clusters.map(&:dup)
        proposed[a] = (proposed[a] + proposed[b]).sort
        proposed.delete_at(b)
        ent = merged_entropy(proposed, model[:records])
        [rounded(ent), a, b, ent, proposed]
      end
      _, a, b, ent, proposed = candidates.min_by { |row| row.first(3) }
      assignment = model[:records].map { |r| largest(cluster_probabilities(proposed, r)) }
      sizes = proposed.each_index.map { |j| assignment.count(j) }
      names = [clusters[a], clusters[b]].map { |c| c.map { |j| j + 1 }.join('+') }
      step += 1
      lines << "step #{step} merge #{names.join(' ')} entropy #{dec(ent)} sizes #{sizes.join(' ')}"
      clusters = proposed
    end
    lines
  end

  def kmeans_block(model, km, ids)
    k = model[:k]
    perm, agreement, table = best_matching(model, km)
    lines = ["kmeans K=#{k}", "iterations #{km[:iterations]}", "inertia #{dec(km[:inertia])}", "sizes #{km[:sizes].join(' ')}"]
    km[:centers].each_with_index { |c, j| lines << "center #{j + 1} #{vals(c)}" }
    lines << 'contingency'
    lines.concat(table.map { |row| row.join(' ') })
    lines.concat(["ari #{ari_text(ari(model[:assignment], km[:assignment], k, k))}",
                  "matching #{perm.map { |j| j + 1 }.join(' ')}", "agreement #{agreement}/#{ids.length} #{dec(agreement.to_f / ids.length)}"])
    disagreements = 0
    ids.each_index do |i|
      next if perm[km[:assignment][i]] == model[:assignment][i]
      disagreements += 1
      lines << "disagree #{ids[i]} gmm #{model[:assignment][i] + 1} kmeans #{km[:assignment][i] + 1} max #{dec(model[:records][i][:r].max)}"
    end
    lines << "disagreements #{disagreements}"
    lines
  end

  def refit_block(model, km, points, params)
    initial = {weights: [], means: km[:centers], covariances: []}
    model[:k].times do |k|
      members = points.each_index.select { |i| km[:assignment][i] == k }
      mx, my = km[:centers][k]
      a = b = c = 0.0
      members.each do |i|
        dx, dy = points[i][0] - mx, points[i][1] - my
        a += dx * dx
        b += dx * dy
        c += dy * dy
      end
      n = members.length
      initial[:weights] << n.to_f / points.length
      initial[:covariances] << [a / n + params[:regularization], b / n, c / n + params[:regularization]]
    end
    fitted = fit(points, initial, model[:k], model[:type], model[:type_index], params)
    ["refit_from_kmeans #{label(model)}", "loglik #{dec(fitted[:loglik])} bic #{dec(fitted[:bic])} settled_at #{fitted[:settled]}",
     "sizes #{fitted[:sizes].join(' ')}", "ari_vs_selected #{ari_text(ari(model[:assignment], fitted[:assignment], model[:k], model[:k]))}"]
  end

  def cross_validation_block(model, points, initial, params)
    folds = params[:cv_folds]
    lines = ["cross_validation #{label(model)} folds #{folds}"]
    test_means = []
    folds.times do |f|
      training, testing = [], []
      points.each_with_index { |point, i| (i % folds == f ? testing : training) << point }
      fitted = EM.fit(training, initial[model[:k]], model[:type], params[:iterations], params[:regularization])
      _, likelihood = EM.expectation(testing, fitted[:model])
      mean = likelihood / testing.length
      test_means << mean
      lines << "fold #{f + 1} train #{training.length} test #{testing.length} train_loglik #{dec(fitted[:loglik] / training.length)} test_loglik #{dec(mean)}"
    end
    lines << "mean_test_loglik #{dec(ordered_sum(test_means) / folds)}"
    lines
  end

  def unusual_blocks(model, points, ids, params)
    records = model[:records]
    uncertain = points.each_index.select { |i| records[i][:r].max < params[:uncertain_threshold] }
    uncertain.sort_by! { |i| [rounded(records[i][:r].max), i] }
    lines = ["uncertain threshold #{dec(params[:uncertain_threshold])}"]
    uncertain.each do |i|
      lines << "#{ids[i]} component #{model[:assignment][i] + 1} max #{dec(records[i][:r].max)} responsibilities #{vals(records[i][:r])}"
    end
    lines << "count #{uncertain.length}"
    outliers = points.each_index.select { |i| records[i][:lp] < params[:low_density_threshold] }
    outliers.sort_by! { |i| [rounded(records[i][:lp]), i] }
    other = ["outliers threshold #{dec(params[:low_density_threshold])}"]
    outliers.each do |i|
      k = model[:assignment][i]
      q = Gaussian.mahalanobis(points[i], model[:model][:means][k], model[:model][:covariances][k])
      other << "#{ids[i]} component #{k + 1} log_density #{dec(records[i][:lp])} q #{dec(q)}"
    end
    other << "count #{outliers.length}"
    [lines, other]
  end

  def maps(model, points, params)
    width, height = params[:map_size]
    xmin, xmax = params[:map_x]
    ymin, ymax = params[:map_y]
    sx, sy = (xmax - xmin) / width, (ymax - ymin) / height
    cell = lambda do |point|
      c, r = ((point[0] - xmin) / sx).floor, ((ymax - point[1]) / sy).floor
      [c, r] if c >= 0 && c < width && r >= 0 && r < height
    end
    mixture, k_count = model[:model], model[:k]
    grid = Array.new(height) do |r|
      Array.new(width) do |c|
        point = [xmin + (c + 0.5) * sx, ymax - (r + 0.5) * sy]
        scores = k_count.times.map { |k| Gaussian.log_density(point, mixture[:weights][k], mixture[:means][k], mixture[:covariances][k]) }
        maximum = scores.max
        exponentials = scores.map { |score| Math.exp(score - maximum) }
        total = ordered_sum(exponentials)
        responsibilities = exponentials.map { |e| e / total }
        {density: ordered_sum(scores.map { |score| Math.exp(score) }), region: largest(scores),
         entropy: entropy(responsibilities), q: k_count.times.map { |k| Gaussian.mahalanobis(point, mixture[:means][k], mixture[:covariances][k]) }}
      end
    end
    maximum = grid.flatten.map { |g| g[:density] }.max
    mass = ordered_sum(grid.flatten.map { |g| g[:density] }) * sx * sy
    counts = Array.new(10, 0)
    density = grid.map do |row|
      row.map do |g|
        level = [(10 * g[:density] / maximum).floor, 9].min
        counts[level] += 1
        Report::LEVELS[level]
      end
    end
    mixture[:means].each_with_index do |mean, k|
      position = cell.call(mean)
      density[position[1]][position[0]] = (k + 1).to_s if position
    end
    region = grid.map { |row| row.map { |g| (g[:region] + 1).to_s } }
    uncertainty = grid.map do |row|
      row.map { |g| k_count == 1 ? ' ' : Report::LEVELS[(10 * g[:entropy] / Math.log(k_count)).floor.clamp(0, 9)] }
    end
    occupants = Array.new(height) { Array.new(width) { [] } }
    outside = 0
    points.each_with_index do |point, i|
      position = cell.call(point)
      if position
        occupants[position[1]][position[0]] << model[:assignment][i]
      else
        outside += 1
      end
    end
    point_map = Array.new(height) do |r|
      Array.new(width) do |c|
        labels = occupants[r][c].uniq
        next labels.length == 1 ? (labels.first + 1).to_s : '*' unless labels.empty?
        contour = k_count.times.any? do |k|
          grid[r][c][:q][k] <= 4 && [[c - 1, r], [c + 1, r], [c, r - 1], [c, r + 1]].any? do |cc, rr|
            cc >= 0 && cc < width && rr >= 0 && rr < height && grid[rr][cc][:q][k] > 4
          end
        end
        contour ? '.' : ' '
      end
    end
    lines = ["density #{label(model)}", "x #{dec(xmin)} #{dec(xmax)} y #{dec(ymin)} #{dec(ymax)} grid #{width}x#{height}",
             "max_density #{dec(maximum, 6)} mass_in_map #{dec(mass)}"] + Report.framed(density)
    10.times { |l| lines << "level #{l} \"#{Report::LEVELS[l]}\" from #{dec(l * maximum / 10, 6)} cells #{counts[l]}" }
    [['regions', region], ['uncertainty', uncertainty], ['points', point_map]].each do |name, rows|
      lines.concat(['', name] + Report.framed(rows))
    end
    lines << "outside #{outside}"
    lines
  end

  def main
    ids, points, params, initial = Dataset.read_all
    models = params[:k].flat_map do |k|
      params[:types].each_with_index.map { |type, i| fit(points, initial[k], k, type, i, params) }
    end
    rankings = [:bic, :aic, :icl].to_h { |criterion| [criterion, ranking(models, criterion)] }
    selected = rankings[:bic].first
    kmeans = params[:k].to_h do |k|
      [k, KMeans.fit(points, initial[k][:means], params[:kmeans_max_iterations])]
    end
    km = kmeans[selected[:k]]
    Report.write_blocks('models.txt', models.map { |m| model_block(m) })
    trace = ['K,type,iteration,loglik']
    models.each { |m| m[:trace].each_with_index { |l, t| trace << "#{m[:k]},#{m[:type]},#{t},#{dec(l)}" } }
    Report.write_lines('loglik_trace.csv', trace)
    assignments = ['id,component,max_responsibility,log_density,kmeans_cluster']
    ids.each_index do |i|
      record = selected[:records][i]
      assignments << "#{ids[i]},#{selected[:assignment][i] + 1},#{dec(record[:r].max)},#{dec(record[:lp])},#{km[:assignment][i] + 1}"
    end
    Report.write_lines('assignments.csv', assignments)
    best_types = ['best K per type']
    params[:types].each do |type|
      subset = models.select { |m| m[:type] == type }
      best_types << "#{type} bic #{ranking(subset, :bic).first[:k]} aic #{ranking(subset, :aic).first[:k]} icl #{ranking(subset, :icl).first[:k]}"
    end
    violations = ['violations']
    models.each do |m|
      m[:violations].each { |t| violations << "#{label(m)} iteration #{t} previous #{dec(m[:trace][t - 1])} current #{dec(m[:trace][t])}" }
    end
    violations << 'none' if violations.length == 1
    blocks = [ranking_block(rankings), best_types] + per_k_blocks(models, kmeans, points, params)
    blocks.concat([violations, details_block(selected, points, params[:gof_edges], metrics(points, selected[:assignment], selected[:k])),
                   overlap_block(selected), merging_block(selected), kmeans_block(selected, km, ids),
                   refit_block(selected, km, points, params), cross_validation_block(selected, points, initial, params)])
    blocks.concat(unusual_blocks(selected, points, ids, params))
    Report.write_blocks('selection.txt', blocks)
    Report.write_lines('density_map.txt', maps(selected, points, params))
  end
end

MixtureAnalysis.main if $PROGRAM_NAME == __FILE__
