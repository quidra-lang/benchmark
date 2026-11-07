require_relative 'dataset'
require_relative 'matrix'
require_relative 'eigen'
require_relative 'pca'
require_relative 'plot'

class PcaReport
  STRATEGIES = %w[listwise mean].freeze
  SCALINGS = %w[covariance correlation].freeze
  CRITERIA = %w[kaiser broken_stick parallel cumulative].freeze
  MINSTD_MULTIPLIER = 48_271
  MINSTD_MODULUS = 2_147_483_647
  LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
  NEIGHBORS = [[-1, 0], [1, 0], [0, -1], [0, 1]].freeze

  Summary = Data.define(:observed, :missing, :mean, :sd, :minimum, :maximum)
  AnalysisData = Data.define(:ids, :values)
  Fit = Data.define(:data, :means, :matrix, :scales, :correlation, :eigen)
  Adequacy = Data.define(:msa, :kmo, :determinant, :bartlett, :freedom)
  Variance = Data.define(:total, :average, :ratios, :cumulative, :broken_stick,
                        :parallel, :errors, :separated, :retention)
  Rotation = Data.define(:criteria, :columns, :squares, :closest, :congruences)
  Observation = Data.define(:id, :z, :scores, :residuals, :t2, :spe, :flag)
  Sensitivity = Data.define(:strategy, :scaling, :rows, :sweeps, :eigenvalues,
                           :cumulative, :agreement)

  def initialize(dataset)
    @data = dataset.data
    @supplementary = dataset.supplementary
    @settings = dataset.settings
    @names = @data.names
    @size = @names.length
    @summaries = Array.new(@size) do |j|
      variable_summary(@data.rows.map { |row| row[j] }.compact)
    end
    @observed_means = @summaries.map(&:mean)
    @incomplete = @data.ids.each_index.filter_map do |i|
      @data.ids[i] if @data.rows[i].include?(nil)
    end
    @fit = decompose(analysis_data(@settings.missing), @settings.scaling)
    @ids = @fit.data.ids
    @rows = @ids.length
    @eigenvalues = @fit.eigen.values
    @vectors = @fit.eigen.vectors
    @strongest = strongest_pairs
    @adequacy = sampling_adequacy(@fit.correlation)
    @power = Eigen.power_iteration(@fit.matrix, @vectors)
    parallel = parallel_analysis
    @variance = variance_table(parallel)
    rule = @settings.components
    @components = CRITERIA.include?(rule) ? [@variance.retention[rule], 1].max : rule.to_i
    compute_loadings
    @rotation = varimax
    @observations = @ids.each_with_index.map { |id, i| observation(id, @fit.data.values[i]) }
    @projections = @supplementary.ids.each_with_index.map do |id, i|
      observation(id, @supplementary.rows[i])
    end
    @sensitivity = STRATEGIES.product(SCALINGS).map do |strategy, scaling|
      sensitivity(strategy, scaling)
    end
  end

  def write(directory)
    Dir.mkdir(directory) unless Dir.exist?(directory)
    {
      'eigen.txt' => eigen_file,
      'loadings.csv' => loadings_file,
      'scores.csv' => scores_file,
      'outliers.txt' => outliers_file,
      'plots.txt' => plots_file
    }.each do |name, lines|
      File.write(File.join(directory, name), lines.join("\n") + "\n")
    end
  end

  private

  def real(value, digits = 4)
    text = format('%.*f', digits, value)
    text.to_f.zero? ? text.delete_prefix('-') : text
  end

  def reals(values)
    values.map { |value| real(value) }
  end

  def component_names(prefix, count)
    (1..count).map { |k| "#{prefix}#{k}" }
  end

  def join_sections(sections)
    sections.each_with_object([]) do |section, lines|
      lines << '' unless lines.empty?
      lines.concat(section)
    end
  end

  def top_indices(values, count)
    values.each_index.sort_by { |i| [-values[i], i] }.first(count)
  end

  def largest_index(values)
    values.each_index.max_by { |i| [values[i], -i] }
  end

  def smallest_index(values)
    values.each_index.min_by { |i| [values[i], i] }
  end

  def congruence(first, second)
    MatrixOps.dot(first, second) / Math.sqrt(MatrixOps.dot(first, first) * MatrixOps.dot(second, second))
  end

  def explained_ratios(values)
    total = MatrixOps.total(values)
    values.map { |value| value / total }
  end

  def cumulative_ratios(ratios)
    running = 0.0
    ratios.map { |ratio| running += ratio }
  end

  def first_crossing(ratios, thresholds)
    ratios.each_index.find { |k| ratios[k] <= thresholds[k] } || ratios.length
  end

  def flag_text(t2, spe)
    flag = ''
    flag += 'T' if t2 > @settings.t2_limit
    flag += 'Q' if spe > @settings.spe_limit
    flag.empty? ? '-' : flag
  end

  def variable_summary(observed)
    count = observed.length
    mean = MatrixOps.total(observed) / count
    squares = MatrixOps.total(observed.map { |x| (x - mean) * (x - mean) })
    Summary.new(count, @data.rows.length - count, mean,
                Math.sqrt(squares / (count - 1)), observed.min, observed.max)
  end

  def analysis_data(strategy)
    ids = []
    values = []
    @data.rows.each_with_index do |row, i|
      next if strategy == 'listwise' && row.include?(nil)

      ids << @data.ids[i]
      values << row.each_with_index.map { |value, j| value.nil? ? @observed_means[j] : value }
    end
    AnalysisData.new(ids, values)
  end

  def decompose(data, scaling)
    means = PCA.means(data.values)
    covariance = PCA.covariance(data.values, means)
    deviations = PCA.standard_deviations(covariance)
    correlation = PCA.correlation(covariance, deviations)
    matrix = scaling == 'covariance' ? covariance : correlation
    scales = scaling == 'covariance' ? Array.new(@size, 1.0) : deviations
    Fit.new(data, means, matrix, scales, correlation, Eigen.jacobi(matrix))
  end

  def strongest_pairs
    pairs = (0...@size).flat_map { |j| ((j + 1)...@size).map { |k| [j, k] } }
    strengths = pairs.map { |j, k| @fit.correlation[j][k].abs }
    top_indices(strengths, @settings.top_rows).map { |i| pairs[i] }
  end

  def sampling_adequacy(correlation)
    inverse, determinant = MatrixOps.gauss_jordan(correlation)
    partial = Array.new(@size) do |j|
      Array.new(@size) do |k|
        j == k ? 0.0 : -inverse[j][k] / Math.sqrt(inverse[j][j] * inverse[k][k])
      end
    end
    rr = Array.new(@size, 0.0)
    pp = Array.new(@size, 0.0)
    @size.times do |j|
      @size.times do |k|
        next if j == k

        rr[j] += correlation[j][k] * correlation[j][k]
        pp[j] += partial[j][k] * partial[j][k]
      end
    end
    msa = Array.new(@size) { |j| rr[j] / (rr[j] + pp[j]) }
    total_rr = MatrixOps.total(rr)
    total_pp = MatrixOps.total(pp)
    kmo = total_rr / (total_rr + total_pp)
    bartlett = -(@rows - 1 - (2 * @size + 5) / 6.0) * Math.log(determinant)
    Adequacy.new(msa, kmo, determinant, bartlett, @size * (@size - 1) / 2)
  end

  def parallel_analysis
    state = @settings.seed
    totals = Array.new(@size, 0.0)
    @settings.parallel_iterations.times do
      values = Array.new(@rows) do
        Array.new(@size) do
          state = MINSTD_MULTIPLIER * state % MINSTD_MODULUS
          state.to_f / MINSTD_MODULUS
        end
      end
      covariance = PCA.covariance(values, PCA.means(values))
      correlation = PCA.correlation(covariance, PCA.standard_deviations(covariance))
      ratios = explained_ratios(Eigen.jacobi(correlation).values)
      @size.times { |k| totals[k] += ratios[k] }
    end
    totals.map { |total| total / @settings.parallel_iterations }
  end

  def variance_table(parallel)
    total = MatrixOps.total(@eigenvalues)
    average = total / @size
    ratios = explained_ratios(@eigenvalues)
    cumulative = cumulative_ratios(ratios)
    broken = (1..@size).map do |k|
      MatrixOps.total((k..@size).map { |i| 1.0 / i }) / @size
    end
    errors = @eigenvalues.map { |value| value * Math.sqrt(2.0 / @rows) }
    separated = Array.new(@size) do |k|
      [k - 1, k + 1].select { |h| h >= 0 && h < @size }.all? do |h|
        (@eigenvalues[k] - @eigenvalues[h]).abs > errors[k]
      end
    end
    retention = {
      'kaiser' => @eigenvalues.count { |value| value > average },
      'broken_stick' => first_crossing(ratios, broken),
      'parallel' => first_crossing(ratios, parallel),
      'cumulative' => cumulative.index { |value| value >= @settings.cumulative_target } + 1
    }
    Variance.new(total, average, ratios, cumulative, broken, parallel, errors, separated, retention)
  end

  def compute_loadings
    @loadings = Array.new(@size) do |j|
      Array.new(@size) { |k| @vectors[k][j] * Math.sqrt(@eigenvalues[k]) }
    end
    @communalities = []
    @circle = []
    @loadings.each_with_index do |row, j|
      diagonal = @fit.matrix[j][j]
      squares = MatrixOps.total(row.first(@components).map { |value| value * value })
      @communalities << squares / diagonal
      @circle << row.first(2).map { |value| value / Math.sqrt(diagonal) }
    end
  end

  def varimax_criterion(g)
    total = 0.0
    @components.times do |k|
      q4 = MatrixOps.total(g.map { |row| (row[k] * row[k]) * (row[k] * row[k]) })
      q2 = MatrixOps.total(g.map { |row| row[k] * row[k] })
      total += q4 / @size - (q2 / @size) * (q2 / @size)
    end
    total
  end

  def rotate_pair(g, a, b)
    phi = g.map { |row| row[a] * row[a] - row[b] * row[b] }
    psi = g.map { |row| 2 * row[a] * row[b] }
    sa = MatrixOps.total(phi)
    sb = MatrixOps.total(psi)
    sc = MatrixOps.total(phi.each_index.map { |j| phi[j] * phi[j] - psi[j] * psi[j] })
    sd = MatrixOps.total(phi.each_index.map { |j| 2 * phi[j] * psi[j] })
    numerator = sd - 2 * sa * sb / @size
    denominator = sc - (sa * sa - sb * sb) / @size
    omega = Math.sqrt(numerator * numerator + denominator * denominator)
    return if omega.zero?

    cos4 = denominator / omega
    sin4 = numerator / omega
    cos2 = Math.sqrt((1 + cos4) / 2)
    sin2 = cos2.zero? ? 1.0 : sin4 / (2 * cos2)
    cos1 = Math.sqrt((1 + cos2) / 2)
    sin1 = sin2 / (2 * cos1)
    g.each do |row|
      first, second = row[a], row[b]
      row[a] = cos1 * first + sin1 * second
      row[b] = -sin1 * first + cos1 * second
    end
  end

  def varimax
    etas = @loadings.map do |row|
      Math.sqrt(MatrixOps.total(row.first(@components).map { |value| value * value }))
    end
    g = @loadings.each_with_index.map do |row, j|
      row.first(@components).map { |value| value / etas[j] }
    end
    criteria = [varimax_criterion(g)]
    @settings.varimax_cycles.times do
      (@components - 1).times do |a|
        ((a + 1)...@components).each { |b| rotate_pair(g, a, b) }
      end
      criteria << varimax_criterion(g)
    end
    columns = Array.new(@components) do |k|
      MatrixOps.orient(Array.new(@size) { |j| g[j][k] * etas[j] })
    end
    squares = columns.map { |values| MatrixOps.dot(values, values) }
    order = squares.each_index.sort_by { |k| [-squares[k], k] }
    columns = order.map { |k| columns[k] }
    squares = order.map { |k| squares[k] }
    originals = Array.new(@components) { |k| MatrixOps.column(@loadings, k) }
    closest = []
    congruences = []
    columns.each do |rotated|
      values = originals.map { |original| congruence(rotated, original).abs }
      best = largest_index(values)
      closest << best
      congruences << values[best]
    end
    Rotation.new(criteria, columns, squares, closest, congruences)
  end

  def observation(id, values)
    z = PCA.standardize(values, @fit.means, @fit.scales)
    scores = PCA.scores(z, @vectors)
    residuals = PCA.residuals(z, scores, @vectors, @components)
    t2 = PCA.hotelling_t2(scores, @eigenvalues, @components)
    spe = MatrixOps.dot(residuals, residuals)
    Observation.new(id, z, scores, residuals, t2, spe, flag_text(t2, spe))
  end

  def quality(observation)
    retained = observation.scores.first(@components)
    MatrixOps.dot(retained, retained) / MatrixOps.dot(observation.z, observation.z)
  end

  def t2_contributions(observation)
    observation.z.each_with_index.map do |value, j|
      weight = 0.0
      @components.times { |k| weight += (observation.scores[k] / @eigenvalues[k]) * @vectors[k][j] }
      value * weight
    end
  end

  def nearest_row(projection)
    distances = @observations.map do |observation|
      differences = Array.new(@components) { |k| projection.scores[k] - observation.scores[k] }
      MatrixOps.dot(differences, differences)
    end
    nearest = smallest_index(distances)
    [nearest, Math.sqrt(distances[nearest])]
  end

  def sensitivity(strategy, scaling)
    fit = decompose(analysis_data(strategy), scaling)
    cumulative = cumulative_ratios(explained_ratios(fit.eigen.values))[@components - 1]
    agreement = Array.new(@components) { |k| MatrixOps.dot(fit.eigen.vectors[k], @vectors[k]).abs }
    Sensitivity.new(strategy, scaling, fit.data.ids.length, fit.eigen.sweeps,
                    fit.eigen.values.first(@components), cumulative, agreement)
  end

  def summary_section
    incomplete = @incomplete.empty? ? '0 -' : [@incomplete.length, *@incomplete].join(' ')
    [
      "pca rows #{@data.ids.length} used #{@rows} variables #{@size}" \
        " missing #{@settings.missing} scaling #{@settings.scaling}",
      "incomplete #{incomplete}"
    ]
  end

  def variable_section
    lines = ['variable observed missing mean sd min max msa']
    @names.each_with_index do |name, j|
      summary = @summaries[j]
      values = reals([summary.mean, summary.sd, summary.minimum, summary.maximum, @adequacy.msa[j]])
      lines << [name, summary.observed, summary.missing, *values].join(' ')
    end
    lines << "adequacy kmo #{real(@adequacy.kmo)} determinant #{real(@adequacy.determinant, 6)}" \
             " bartlett #{real(@adequacy.bartlett)} df #{@adequacy.freedom}"
    lines
  end

  def matrix_section
    lines = ["matrix #{@settings.scaling}"]
    @names.each_with_index { |name, j| lines << [name, *reals(@fit.matrix[j])].join(' ') }
    pairs = @strongest.map { |j, k| "#{@names[j]}:#{@names[k]}:#{real(@fit.correlation[j][k])}" }
    lines << ['strongest', *pairs].join(' ')
    lines
  end

  def eigenvalue_section
    variance = @variance
    lines = [
      "jacobi sweeps #{@fit.eigen.sweeps}",
      "eigenvalues total #{real(variance.total)} average #{real(variance.average)}",
      'k eigenvalue ratio cumulative broken_stick parallel se separated'
    ]
    @size.times do |k|
      values = reals([@eigenvalues[k], variance.ratios[k], variance.cumulative[k],
                      variance.broken_stick[k], variance.parallel[k], variance.errors[k]])
      lines << [k + 1, *values, variance.separated[k] ? 'yes' : 'no'].join(' ')
    end
    counts = CRITERIA.map { |name| "#{name} #{variance.retention[name]}" }.join(' ')
    lines << "retention #{counts} target #{real(@settings.cumulative_target)}"
    lines << "components #{@components} rule #{@settings.components}"
    lines
  end

  def eigenvector_section
    lines = ['eigenvectors', ['variable', *component_names('pc', @size)].join(' ')]
    @names.each_with_index do |name, j|
      lines << [name, *reals(@vectors.map { |vector| vector[j] })].join(' ')
    end
    lines
  end

  def power_section
    lines = ["power_iteration iterations #{Eigen::POWER_ITERATIONS}", 'k jacobi power agree_at match']
    matches = 0
    @power.each_with_index do |component, k|
      match = (component.value - @eigenvalues[k]).abs <= 1e-8 * @eigenvalues[0] &&
              MatrixOps.max_difference(component.vector, @vectors[k]) <= 0.000001
      matches += 1 if match
      lines << [k + 1, real(@eigenvalues[k]), real(component.value),
                component.agreement || '-', match ? 'yes' : 'no'].join(' ')
    end
    lines << "cross_check #{matches}/#{@size}"
    lines
  end

  def score_section
    lines = ['scores', 'component sd min min_id max max_id contributors']
    denominator = @rows - 1
    @components.times do |k|
      scores = @observations.map { |row| row.scores[k] }
      sd = Math.sqrt(MatrixOps.dot(scores, scores) / denominator)
      low = smallest_index(scores)
      high = largest_index(scores)
      contributions = scores.map { |t| t * t / (denominator * @eigenvalues[k]) }
      parts = ["pc#{k + 1}", real(sd), real(scores[low]), @ids[low], real(scores[high]), @ids[high]]
      top_indices(contributions, @settings.top_rows).each do |i|
        parts << "#{@ids[i]}:#{real(contributions[i])}"
      end
      lines << parts.join(' ')
    end
    lines
  end

  def varimax_section
    lines = ["varimax components #{@components} cycles #{@settings.varimax_cycles}"]
    @rotation.criteria.each_with_index { |value, cycle| lines << "cycle #{cycle} criterion #{real(value, 6)}" }
    @components.times do |k|
      ss = @rotation.squares[k]
      lines << "rc#{k + 1} ss #{real(ss)} ratio #{real(ss / @variance.total)}" \
               " closest pc#{@rotation.closest[k] + 1} congruence #{real(@rotation.congruences[k])}"
    end
    lines
  end

  def sensitivity_section
    lines = ['sensitivity', 'missing scaling rows sweeps eigenvalues cumulative congruence']
    @sensitivity.each do |result|
      lines << [result.strategy, result.scaling, result.rows, result.sweeps,
                *reals(result.eigenvalues), real(result.cumulative), *reals(result.agreement)].join(' ')
    end
    lines
  end

  def eigen_file
    join_sections([summary_section, variable_section, matrix_section, eigenvalue_section,
                   eigenvector_section, power_section, score_section, varimax_section, sensitivity_section])
  end

  def loadings_file
    header = ['variable', *component_names('pc', @components), 'communality', *component_names('rc', @components)]
    lines = [header.join(',')]
    @names.each_with_index do |name, j|
      values = @loadings[j].first(@components) + [@communalities[j]] + @rotation.columns.map { |column| column[j] }
      lines << [name, *reals(values)].join(',')
    end
    lines
  end

  def scores_file
    lines = [['id', 'set', *component_names('pc', @components)].join(',')]
    [['data', @observations], ['supplementary', @projections]].each do |set, rows|
      rows.each { |row| lines << [row.id, set, *reals(row.scores.first(@components))].join(',') }
    end
    lines
  end

  def diagnostics_section
    lines = [
      "diagnostics components #{@components} t2_limit #{real(@settings.t2_limit)}" \
        " spe_limit #{real(@settings.spe_limit)}",
      'id t2 spe quality flag'
    ]
    @observations.each do |row|
      lines << [row.id, *reals([row.t2, row.spe, quality(row)]), row.flag].join(' ')
    end
    flags = @observations.map(&:flag)
    t2 = flags.count { |flag| flag.include?('T') }
    spe = flags.count { |flag| flag.include?('Q') }
    both = flags.count('TQ')
    any = flags.count { |flag| flag != '-' }
    lines << "flagged t2 #{t2} spe #{spe} both #{both} any #{any}"
    lines
  end

  def top_section(label, values, contributions)
    lines = ["top #{label}", "rank id #{label} variable contribution"]
    top_indices(values, @settings.top_rows).each_with_index do |i, rank|
      variable = largest_index(contributions[i])
      lines << [rank + 1, @ids[i], real(values[i]), @names[variable], real(contributions[i][variable])].join(' ')
    end
    lines
  end

  def reconstruction_section
    lines = ['reconstruction', 'k mean_spe max_spe max_id']
    (1...@size).each do |k|
      errors = @observations.map do |row|
        residuals = PCA.residuals(row.z, row.scores, @vectors, k)
        MatrixOps.dot(residuals, residuals)
      end
      worst = largest_index(errors)
      lines << [k, real(MatrixOps.total(errors) / @rows), real(errors[worst]), @ids[worst]].join(' ')
    end
    lines
  end

  def supplementary_section
    header = ['id', *component_names('pc', @components), 't2', 'spe', 'flag', 'nearest', 'distance']
    lines = ['supplementary', header.join(' ')]
    @projections.each do |row|
      nearest, distance = nearest_row(row)
      values = reals(row.scores.first(@components) + [row.t2, row.spe])
      lines << [row.id, *values, row.flag, @ids[nearest], real(distance)].join(' ')
    end
    lines
  end

  def outliers_file
    join_sections([
      diagnostics_section,
      top_section('t2', @observations.map(&:t2), @observations.map { |row| t2_contributions(row) }),
      top_section('spe', @observations.map(&:spe), @observations.map { |row| row.residuals.map { |e| e * e } }),
      reconstruction_section,
      supplementary_section
    ])
  end

  def draw_axes(grid, center)
    row, col = center
    grid[row].fill('-')
    grid.each { |line| line[col] = '|' }
    grid[row][col] = '+'
  end

  def draw_points(grid, cells)
    counts = Array.new(grid.length) { Array.new(grid[0].length, 0) }
    cells.each { |row, col| counts[row][col] += 1 }
    counts.each_with_index do |line, row|
      line.each_with_index do |count, col|
        next if count.zero?

        grid[row][col] = if count == 1
                          '.'
                        elsif count <= 3
                          'o'
                        else
                          '@'
                        end
      end
    end
  end

  def mark_cells(grid, cells, character)
    cells.each { |row, col| grid[row][col] = character }
  end

  def inside_circle(row, col, center, radius)
    horizontal = col - center[1]
    vertical = 2 * (row - center[0])
    horizontal * horizontal + vertical * vertical <= radius * radius
  end

  def scree_section
    width = @settings.scree_width
    first = @eigenvalues[0]
    kaiser = Plot.rounded_position(@variance.average / first, width)
    lines = ["scree width #{width} kaiser_column #{kaiser}"]
    @eigenvalues.each_with_index do |value, k|
      length = Plot.rounded_position(value / first, width)
      broken = Plot.rounded_position(@variance.broken_stick[k] * @variance.total / first, width)
      lines << "#{Plot.scree_line(length, kaiser, broken, width)} pc#{k + 1} #{real(value)}"
    end
    lines
  end

  def biplot_section
    width = @settings.biplot_width
    height = @settings.biplot_height
    points = @observations + @projections
    x_limit = points.map { |point| point.scores[0].abs }.max
    y_limit = points.map { |point| point.scores[1].abs }.max
    x_loading = @loadings.map { |row| row[0].abs }.max
    y_loading = @loadings.map { |row| row[1].abs }.max
    scale = 0.9 * [x_limit / x_loading, y_limit / y_loading].min
    origin = Plot.biplot_cell(0.0, 0.0, x_limit, y_limit, width, height)
    tips = @loadings.map do |row|
      Plot.biplot_cell(scale * row[0], scale * row[1], x_limit, y_limit, width, height)
    end
    cells = points.map do |point|
      Plot.biplot_cell(point.scores[0], point.scores[1], x_limit, y_limit, width, height)
    end
    data_cells = cells.first(@rows)
    grid = Plot.grid(height, width)
    draw_axes(grid, origin)
    tips.each { |tip| mark_cells(grid, Plot.shaft_cells(origin, tip), Plot.shaft_character(origin, tip)) }
    draw_points(grid, data_cells)
    flagged = data_cells.each_with_index.filter_map { |cell, i| cell if @observations[i].flag != '-' }
    mark_cells(grid, flagged, 'X')
    mark_cells(grid, cells.drop(@rows), '*')
    tips.each_with_index { |tip, j| mark_cells(grid, [tip], LETTERS[j]) }
    lines = [
      "biplot pc1 pc2 width #{width} height #{height}",
      "x #{real(-x_limit)} #{real(x_limit)} y #{real(-y_limit)} #{real(y_limit)} arrow_scale #{real(scale)}"
    ] + Plot.framed(grid)
    @names.each_with_index do |name, j|
      lines << [LETTERS[j], name, *reals(@loadings[j].first(2))].join(' ')
    end
    lines
  end

  def circle_section
    radius = @settings.circle_radius
    center = [radius / 2 + 1, radius + 1]
    grid = Plot.grid(radius + 3, 2 * radius + 3)
    draw_axes(grid, center)
    grid.each_with_index do |line, row|
      line.each_index do |col|
        next unless inside_circle(row, col, center, radius)

        boundary = NEIGHBORS.any? { |dr, dc| !inside_circle(row + dr, col + dc, center, radius) }
        line[col] = '.' if boundary
      end
    end
    @circle.each_with_index do |(first, second), j|
      mark_cells(grid, [Plot.circle_cell(first, second, radius)], LETTERS[j])
    end
    lines = ["circle radius #{radius}"] + Plot.framed(grid)
    @names.each_with_index do |name, j|
      first, second = @circle[j]
      lines << [LETTERS[j], name, *reals([first, second, first * first + second * second])].join(' ')
    end
    lines
  end

  def diagnostic_section
    width = @settings.diagnostic_width
    height = @settings.diagnostic_height
    t2_max = 2 * @settings.t2_limit
    spe_max = 2 * @settings.spe_limit
    grid = Plot.grid(height, width)
    limit = Plot.diagnostic_cell(@settings.t2_limit, @settings.spe_limit, t2_max, spe_max, width, height)
    draw_axes(grid, limit)
    data_cells = @observations.map do |row|
      Plot.diagnostic_cell(row.t2, row.spe, t2_max, spe_max, width, height)
    end
    supplementary_cells = @projections.map do |row|
      Plot.diagnostic_cell(row.t2, row.spe, t2_max, spe_max, width, height)
    end
    draw_points(grid, data_cells)
    mark_cells(grid, supplementary_cells, '*')
    header = "diagnostic width #{width} height #{height} t2_max #{real(t2_max)} spe_max #{real(spe_max)}"
    [header] + Plot.framed(grid)
  end

  def plots_file
    join_sections([scree_section, biplot_section, circle_section, diagnostic_section])
  end
end

PcaReport.new(Dataset.load('input')).write('output') if $PROGRAM_NAME == __FILE__
