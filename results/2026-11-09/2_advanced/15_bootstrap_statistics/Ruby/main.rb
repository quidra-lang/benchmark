require_relative 'dataset'
require_relative 'minstd'
require_relative 'resampling'
require_relative 'tests'
require_relative 'report'

class BootstrapStudy
  GROUP_STATISTICS = %w[mean median trimmed_mean sd].freeze
  PAIR_STATISTICS = %w[mean_diff median_ratio hodges_lehmann cohen_d].freeze
  TEST_STATISTICS = %w[mean median ranksum absdev].freeze

  def initialize
    @groups, @before, @after, @settings = Dataset.read
    @differences = @before.each_index.map { |index| @after[index] - @before[index] }
    by_name = @groups.to_h { |group| [group[:name], group] }
    @pairs = @settings[:compare].each_with_index.map do |names, index|
      { first: by_name.fetch(names[0]), second: by_name.fetch(names[1]),
        name: names.join('-'), index: index }
    end
    @bootstrap = @settings[:bootstrap]
    @permutations = @settings[:permutations]
    @tail = 100 - @settings[:confidence]
    @low_rank = (@bootstrap + 1) * @tail / 200
    @high_rank = @bootstrap + 1 - @low_rank
    @z_low = Resampling.phi_inverse(@tail / 200.0)
    @generator = Minstd.new(@settings[:seed])
  end

  def real(value)
    Report.real(value)
  end

  def descriptive_series(name, sample, low, high, kind)
    size = sample.length
    center, median, trimmed, deviation = Resampling.statistics(sample)
    m2, m3, m4 = Resampling.moments(sample)
    q1 = Resampling.quantile_numerator(sample, 25)
    q3 = Resampling.quantile_numerator(sample, 75)
    outliers = sample.each_index.select do |index|
      value = 200 * sample[index]
      value < 5 * q1 - 3 * q3 || value > 5 * q3 - 3 * q1
    end
    retained = sample.each_with_index.filter_map { |value, index| value unless outliers.include?(index) }
    whisker_low, whisker_high = retained.minmax
    delta = 100 * (high - low)
    position = ->(value) { (120 * (value - 100 * low) + delta) / (2 * delta) }
    band = Array.new(61, '.')
    (position.call(100 * whisker_low)..position.call(100 * whisker_high)).each { |index| band[index] = '-' }
    (position.call(q1)..position.call(q3)).each { |index| band[index] = '=' }
    band[position.call(Resampling.quantile_numerator(sample, 50))] = '|'
    outliers.each { |index| band[position.call(100 * sample[index])] = 'o' }
    wins = Resampling.winsorized(sample)
    percentiles = [5, 10, 90, 95].map { |percentile| Resampling.quantile_numerator(sample, percentile) / 10_000.0 }
    lines = [
      "#{kind} #{name}", "n #{size}", "mean #{real(center)}", "median #{real(median)}",
      "trimmed_mean #{real(trimmed)} trim #{size / 10}",
      "winsorized_mean #{real(Resampling.mean(wins))} winsorized_sd #{real(Resampling.sd(wins))}",
      "sd #{real(deviation)}", "se_mean #{real(deviation / Math.sqrt(size))}",
      "cv #{real(deviation / center)}", "skewness #{real(m3 / (m2 * Math.sqrt(m2)))}",
      "kurtosis #{real(m4 / (m2 * m2) - 3)}", "mad #{real(Resampling.mad(sample))}",
      "min #{real(sample.min / 100.0)}", "q1 #{real(q1 / 10_000.0)}", "q3 #{real(q3 / 10_000.0)}",
      "iqr #{real((q3 - q1) / 10_000.0)}", "max #{real(sample.max / 100.0)}",
      "percentiles p05 #{real(percentiles[0])} p10 #{real(percentiles[1])} p90 #{real(percentiles[2])} p95 #{real(percentiles[3])}",
      "whiskers #{real(whisker_low / 100.0)} #{real(whisker_high / 100.0)}",
      "outliers #{Report.number_list(outliers.map { |index| index + 1 })}", "box #{band.join}"
    ]
    if kind == 'group'
      by_stem = sample.sort.group_by { |value| value / 100 }
      (sample.min / 100..sample.max / 100).each do |stem|
        leaves = by_stem.fetch(stem, []).map { |value| (value % 100) / 10 }.join
        lines << (leaves.empty? ? "stem #{stem}" : "stem #{stem} #{leaves}")
      end
    end
    lines
  end

  def descriptive_lines
    all_values = @groups.flat_map { |group| group[:values] }
    low, high = all_values.minmax
    lines = ["groups #{@groups.length} observations #{all_values.length}"]
    @groups.each do |group|
      lines.concat(descriptive_series(group[:name], group[:values], low, high, 'group'))
    end
    lines << "paired subjects #{@before.length}"
    paired_low, paired_high = (@before + @after).minmax
    lines.concat(descriptive_series('before', @before, paired_low, paired_high, 'series'))
    lines.concat(descriptive_series('after', @after, paired_low, paired_high, 'series'))
    lines.concat(descriptive_series('diff', @differences, *@differences.minmax, 'series'))
    lines
  end

  def append_statistics(series, values)
    values.each_with_index { |value, index| series[index] << value }
  end

  def ordinary_bootstraps
    @groups.each do |group|
      sample = group[:values]
      size = sample.length
      group[:estimate] = Resampling.statistics(sample)
      group[:ordinary] = Array.new(4) { [] }
      group[:samples] = []
      group[:without] = Array.new(size) { [] }
      @bootstrap.times do |replicate|
        indices = Resampling.ordinary_indices(size, @generator)
        values = indices.map { |index| sample[index] }
        group[:samples] << values
        append_statistics(group[:ordinary], Resampling.statistics(values))
        chosen = Array.new(size, false)
        indices.each { |index| chosen[index] = true }
        size.times { |index| group[:without][index] << replicate unless chosen[index] }
      end
    end
    @pairs.each do |pair|
      first = pair[:first]
      second = pair[:second]
      pair[:estimate] = Resampling.pair_statistics(first[:values], second[:values])
      pair[:ordinary] = Array.new(4) { [] }
      @bootstrap.times do |replicate|
        values = Resampling.pair_statistics(first[:samples][replicate], second[:samples][replicate])
        append_statistics(pair[:ordinary], values)
      end
    end
  end

  def balanced_bootstraps
    @groups.each do |group|
      sample = group[:values]
      group[:balanced] = Array.new(4) { [] }
      Resampling.balanced_indices(sample.length, @bootstrap, @generator).each do |indices|
        values = indices.map { |index| sample[index] }
        append_statistics(group[:balanced], Resampling.statistics(values))
      end
    end
  end

  def paired_bootstrap
    @paired_estimates = [Resampling.mean(@differences), Resampling.correlation(@before, @after)]
    @paired_replicates = [[], []]
    @bootstrap.times do
      indices = Resampling.ordinary_indices(@before.length, @generator)
      differences = indices.map { |index| @differences[index] }
      before = indices.map { |index| @before[index] }
      after = indices.map { |index| @after[index] }
      append_statistics(@paired_replicates, [Resampling.mean(differences), Resampling.correlation(before, after)])
    end
  end

  def bootstrap_summary(estimate, values)
    average, se = Resampling.average_and_se(values)
    sorted = values.sort
    low = sorted[@low_rank - 1]
    high = sorted[@high_rank - 1]
    { estimate: estimate, se: se, bias: average - estimate, low: low, high: high,
      basic_low: 2 * estimate - high, basic_high: 2 * estimate - low, sorted: sorted }
  end

  def prepare_summaries
    @groups.each do |group|
      group[:summary] = group[:ordinary].each_with_index.map do |values, index|
        bootstrap_summary(group[:estimate][index], values)
      end
      group[:balanced_summary] = group[:balanced].each_with_index.map do |values, index|
        bootstrap_summary(group[:estimate][index], values)
      end
    end
    @pairs.each do |pair|
      pair[:summary] = pair[:ordinary].each_with_index.map do |values, index|
        bootstrap_summary(pair[:estimate][index], values)
      end
    end
    @paired_summaries = @paired_replicates.each_with_index.map do |values, index|
      bootstrap_summary(@paired_estimates[index], values)
    end
  end

  def bootstrap_row(name, statistic, summary)
    values = %i[estimate se bias low high basic_low basic_high].map { |key| real(summary[key]) }
    ([name, statistic] + values).join(',')
  end

  def bootstrap_lines
    lines = ['group,statistic,estimate,se,bias,percentile_lo,percentile_hi,basic_lo,basic_hi']
    @groups.each do |group|
      GROUP_STATISTICS.each_with_index do |statistic, index|
        lines << bootstrap_row(group[:name], statistic, group[:summary][index])
      end
      GROUP_STATISTICS.each_with_index do |statistic, index|
        lines << bootstrap_row(group[:name], "balanced_#{statistic}", group[:balanced_summary][index])
      end
    end
    @pairs.each do |pair|
      PAIR_STATISTICS.each_with_index do |statistic, index|
        lines << bootstrap_row(pair[:name], statistic, pair[:summary][index])
      end
    end
    lines
  end

  def histogram(name, statistic, values, summary)
    low, high = values.minmax
    bins = @settings[:bins]
    counts = Array.new(bins, 0)
    values.each { |value| counts[Report.bin(value, low, high, bins) - 1] += 1 }
    top = counts.max
    estimate = summary[:estimate]
    estimate_bin = Report.bin(estimate, low, high, bins) if estimate >= low && estimate <= high
    marks = Array.new(bins) { [] }
    marks[Report.bin(summary[:low], low, high, bins) - 1] << 'L'
    marks[estimate_bin - 1] << 'E' if estimate_bin
    marks[Report.bin(summary[:high], low, high, bins) - 1] << 'H'
    convergence = (1..4).map do |quarter|
      count = quarter * @bootstrap / 4
      "#{count}:#{real(Resampling.average_and_se(values.first(count)).last)}"
    end
    lines = [
      "histogram #{name} #{statistic} min #{real(low)} max #{real(high)} width #{real((high - low) / bins)} top #{top} estimate_bin #{estimate_bin || 'none'}",
      "convergence #{convergence.join(' ')}"
    ]
    bins.times do |index|
      edge = low + (high - low) * index / bins
      fields = ['bin', index + 1, real(edge), counts[index]]
      bar = Report.bar(counts[index], top)
      fields << bar unless bar.empty?
      fields.concat(marks[index])
      lines << fields.join(' ')
    end
    lines
  end

  def histogram_lines
    lines = []
    [@groups, @pairs].each do |collection|
      statistics = collection.equal?(@groups) ? GROUP_STATISTICS : PAIR_STATISTICS
      collection.each do |entry|
        statistics.each_with_index do |statistic, index|
          lines.concat(histogram(entry[:name], statistic, entry[:ordinary][index], entry[:summary][index]))
        end
      end
    end
    lines
  end

  def jackknife_moments(values)
    average = Resampling.float_sum(values) / values.length
    squares = 0.0
    values.each do |value|
      deviation = value - average
      squares += deviation * deviation
    end
    { average: average, variance: (values.length - 1) * squares / values.length }
  end

  def bca_line(statistic, estimate, replicates, deleted, moment)
    below = replicates.count { |value| value < estimate }
    z0 = Resampling.phi_inverse(below.to_f / @bootstrap)
    v2 = v3 = 0.0
    deleted.each do |value|
      influence = moment[:average] - value
      v2 += influence * influence
      v3 += influence * influence * influence
    end
    acceleration = v3 / (6 * v2 * Math.sqrt(v2))
    alpha = lambda do |z|
      Resampling.phi(z0 + (z0 + z) / (1 - acceleration * (z0 + z)))
    end
    first = ((@bootstrap + 1) * alpha.call(@z_low)).floor.clamp(1, @bootstrap)
    second = (@bootstrap + 1 - ((@bootstrap + 1) * (1 - alpha.call(-@z_low))).floor).clamp(1, @bootstrap)
    sorted = replicates.sort
    "bca #{statistic} below #{below} z0 #{real(z0)} acceleration #{real(acceleration)} ranks #{first} #{second} interval #{real(sorted[first - 1])} #{real(sorted[second - 1])}"
  end

  def group_jackknife_lines(group)
    sample = group[:values]
    size = sample.length
    deleted = Array.new(4) { [] }
    size.times { |index| append_statistics(deleted, Resampling.statistics(Resampling.without(sample, index))) }
    moments = deleted.map { |values| jackknife_moments(values) }
    lines = ["group #{group[:name]} n #{size}"]
    GROUP_STATISTICS.each_with_index do |statistic, index|
      estimate = group[:estimate][index]
      moment = moments[index]
      bias = (size - 1) * (moment[:average] - estimate)
      lines << "jackknife #{statistic} estimate #{real(estimate)} average #{real(moment[:average])} bias #{real(bias)} se #{real(Math.sqrt(moment[:variance]))}"
    end
    GROUP_STATISTICS.each_with_index do |statistic, index|
      lines << bca_line(statistic, group[:estimate][index], group[:ordinary][index], deleted[index], moments[index])
    end
    omitted_errors = []
    GROUP_STATISTICS.each_with_index do |statistic, index|
      errors = group[:without].map do |replicates|
        values = replicates.map { |replicate| group[:ordinary][index][replicate] }
        Resampling.average_and_se(values).last
      end
      omitted_errors << errors
      moment = jackknife_moments(errors)
      lines << "after_bootstrap #{statistic} se #{real(group[:summary][index][:se])} average #{real(moment[:average])} se_of_se #{real(Math.sqrt(moment[:variance]))}"
    end
    counts = group[:without].map(&:length)
    lines << "without min #{counts.min} max #{counts.max}"
    total = sample.sum
    ranking = sample.each_index.sort_by { |index| [-(size * sample[index] - total).abs, index] }.first(5)
    ranking.each_with_index do |index, rank|
      values = group[:without][index].map { |replicate| group[:ordinary][0][replicate] - group[:estimate][0] }.sort
      quantiles = [5, 50, 95].map { |percentile| values[(percentile * values.length + 99) / 100 - 1] }
      influence = (size - 1) * (moments[0][:average] - deleted[0][index])
      lines << "influence #{rank + 1} obs #{index + 1} value #{real(sample[index] / 100.0)} l #{real(influence)} without #{counts[index]} se #{real(omitted_errors[0][index])} q05 #{real(quantiles[0])} q50 #{real(quantiles[1])} q95 #{real(quantiles[2])}"
    end
    lines
  end

  def pair_jackknife_lines(pair)
    first = pair[:first][:values]
    second = pair[:second][:values]
    parts = [Array.new(4) { [] }, Array.new(4) { [] }]
    first.each_index do |index|
      append_statistics(parts[0], Resampling.pair_statistics(Resampling.without(first, index), second))
    end
    second.each_index do |index|
      append_statistics(parts[1], Resampling.pair_statistics(first, Resampling.without(second, index)))
    end
    PAIR_STATISTICS.each_with_index.map do |statistic, index|
      estimate = pair[:estimate][index]
      bias = variance = 0.0
      parts.each do |part|
        values = part[index]
        moment = jackknife_moments(values)
        bias += (values.length - 1) * (moment[:average] - estimate)
        variance += moment[:variance]
      end
      "pair #{pair[:name]} #{statistic} estimate #{real(estimate)} bias #{real(bias)} se #{real(Math.sqrt(variance))}"
    end
  end

  def jackknife_lines
    @groups.flat_map { |group| group_jackknife_lines(group) } +
      @pairs.flat_map { |pair| pair_jackknife_lines(pair) }
  end

  def permutation_statistics(records, first_size)
    first_records = records.first(first_size)
    second_records = records.drop(first_size)
    first = first_records.map(&:first)
    second = second_records.map(&:first)
    first_median = Resampling.median_twice(first)
    second_median = Resampling.median_twice(second)
    first_deviations = first.sum { |value| (2 * value - first_median).abs }
    second_deviations = second.sum { |value| (2 * value - second_median).abs }
    [Tests.contrast(first, second), first_median - second_median,
     first_records.sum(&:last) - first_size * (records.length + 1),
     second.length * first_deviations - first.length * second_deviations]
  end

  def test_result(extreme, greater, count, offset = 1)
    two_sided = Report.p_value(extreme + offset, count + offset)
    one_sided = Report.p_value(greater + offset, count + offset)
    "extreme #{extreme} greater #{greater} p_two #{two_sided} p_greater #{one_sided}"
  end

  def power_line(first, second)
    simulations, permutations = @settings[:power]
    rejections = 0
    simulations.times do
      x = Resampling.ordinary_indices(first.length, @generator).map { |index| first[index] }
      y = Resampling.ordinary_indices(second.length, @generator).map { |index| second[index] }
      combined = x + y
      observed = Tests.contrast(x, y).abs
      extreme = 0
      permutations.times do
        shuffled = @generator.shuffle(combined.dup)
        statistic = Tests.contrast(shuffled.first(first.length), shuffled.drop(first.length)).abs
        extreme += 1 if statistic >= observed
      end
      rejections += 1 if 100 * (extreme + 1) <= @tail * (permutations + 1)
    end
    power = rejections.to_f / simulations
    se = Math.sqrt(power * (1 - power) / simulations)
    "power sims #{simulations} perms #{permutations} rejections #{rejections} power #{real(power)} se #{real(se)}"
  end

  def exact_lines(first, second)
    size = @settings[:pilot]
    x = first.first(size)
    y = second.first(size)
    combined = x + y
    ranks = Tests.doubled_ranks(combined)
    rank_sum = ranks.first(size).sum
    observed = [Tests.contrast(x, y), rank_sum - size * (2 * size + 1)]
    extreme = [0, 0]
    greater = [0, 0]
    frequencies = Hash.new(0)
    total = combined.sum
    count = 0
    Tests.position_choices(2 * size, size).each do |positions|
      sum = positions.sum { |index| combined[index] }
      values = [size * sum - size * (total - sum),
                positions.sum { |index| ranks[index] } - size * (2 * size + 1)]
      2.times do |index|
        extreme[index] += 1 if values[index].abs >= observed[index].abs
        greater[index] += 1 if values[index] >= observed[index]
      end
      frequencies[values[0].abs] += 1
      count += 1
    end
    critical = nil
    cumulative = 0
    frequencies.keys.sort.reverse_each do |value|
      cumulative += frequencies[value]
      break if 100 * cumulative > @tail * count

      critical = [value, cumulative]
    end
    critical_line = if critical
                      "critical diff #{real(critical[0].to_f / (100 * size * size))} attained #{Report.p_value(critical[1], count)}"
                    else
                      'critical diff none attained none'
                    end
    ["exact size #{size} splits #{count}",
     "mean diff #{real(Resampling.mean_difference(x, y))} #{test_result(extreme[0], greater[0], count, 0)}",
     "ranksum w #{real(rank_sum / 2.0)} u #{real((rank_sum - size * (size + 1)) / 2.0)} #{test_result(extreme[1], greater[1], count, 0)}",
     critical_line]
  end

  def studentized_lines(pair)
    first = pair[:first][:values]
    second = pair[:second][:values]
    first_size = first.length
    second_size = second.length
    sx = pair[:first][:estimate][3]
    sy = pair[:second][:estimate][3]
    vx = sx * sx / first_size
    vy = sy * sy / second_size
    se0 = Math.sqrt(vx + vy)
    estimate = pair[:estimate][0]
    statistic = estimate / se0
    values = Array.new(@bootstrap) do |replicate|
      first_sd = pair[:first][:ordinary][3][replicate]
      second_sd = pair[:second][:ordinary][3][replicate]
      denominator = Math.sqrt(first_sd * first_sd / first_size + second_sd * second_sd / second_size)
      (pair[:ordinary][0][replicate] - estimate) / denominator
    end
    extreme = values.count { |value| value.abs >= statistic.abs }
    sorted = values.sort
    low = estimate - sorted[@high_rank - 1] * se0
    high = estimate - sorted[@low_rank - 1] * se0
    degrees = (vx + vy) * (vx + vy) / (vx * vx / (first_size - 1) + vy * vy / (second_size - 1))
    pooled = Resampling.pooled_sd(first, second)
    cohen = pair[:estimate][3]
    hedges = cohen * (1 - 3.0 / (4 * (first_size + second_size - 2) - 1))
    greater = equal = 0
    first.each do |value|
      second.each do |other|
        greater += 1 if value > other
        equal += 1 if value == other
      end
    end
    language_effect = (2 * greater + equal).to_f / (2 * first_size * second_size)
    ["bootstrap_t t #{real(statistic)} df #{real(degrees)} extreme #{extreme} p #{Report.p_value(extreme + 1, @bootstrap + 1)} interval #{real(low)} #{real(high)}",
     "effect pooled_sd #{real(pooled)} cohen_d #{real(cohen)} hedges_g #{real(hedges)} cles #{real(language_effect)}"]
  end

  def comparison_lines(pair)
    first = pair[:first][:values]
    second = pair[:second][:values]
    combined = first + second
    records = combined.zip(Tests.doubled_ranks(combined))
    observed = permutation_statistics(records, first.length)
    extreme = Array.new(4, 0)
    greater = Array.new(4, 0)
    @permutations.times do
      values = permutation_statistics(@generator.shuffle(records.dup), first.length)
      4.times do |index|
        extreme[index] += 1 if values[index].abs >= observed[index].abs
        greater[index] += 1 if values[index] >= observed[index]
      end
    end
    pair[:extreme] = extreme
    rank_sum = records.first(first.length).sum(&:last)
    values = [
      "mean diff #{real(pair[:estimate][0])}", "median diff #{real(observed[1] / 200.0)}",
      "ranksum w #{real(rank_sum / 2.0)} u #{real((rank_sum - first.length * (first.length + 1)) / 2.0)}",
      "absdev diff #{real(observed[3].to_f / (200 * first.length * second.length))}"
    ]
    lines = ["compare #{pair[:first][:name]} #{pair[:second][:name]}",
             "permutation n #{first.length} #{second.length} perms #{@permutations}"]
    values.each_with_index do |value, index|
      lines << "#{value} #{test_result(extreme[index], greater[index], @permutations)}"
    end
    lines << power_line(first, second)
    lines.concat(exact_lines(first, second))
    lines.concat(studentized_lines(pair))
    lines
  end

  def holm_lines
    lines = []
    denominator = @permutations + 1
    TEST_STATISTICS.each_with_index do |statistic, index|
      ordered = @pairs.sort_by { |pair| [pair[:extreme][index], pair[:index]] }
      adjusted = 0
      ordered.each_with_index do |pair, rank|
        numerator = pair[:extreme][index] + 1
        adjusted = [adjusted, [denominator, (@pairs.length - rank) * numerator].min].max
        decision = 100 * adjusted <= @tail * denominator ? 'reject' : 'retain'
        lines << "holm #{statistic} rank #{rank + 1} #{pair[:first][:name]} #{pair[:second][:name]} p #{Report.p_value(numerator, denominator)} adjusted #{Report.p_value(adjusted, denominator)} #{decision}"
      end
    end
    lines
  end

  def summary_text(summary)
    "se #{real(summary[:se])} bias #{real(summary[:bias])} percentile #{real(summary[:low])} #{real(summary[:high])} basic #{real(summary[:basic_low])} #{real(summary[:basic_high])}"
  end

  def sign_flip_lines
    nonzero = @differences.reject(&:zero?).map(&:abs)
    ranks = Tests.doubled_ranks(nonzero)
    cursor = 0
    signed = @differences.map do |difference|
      if difference.zero?
        0
      else
        rank = ranks[cursor]
        cursor += 1
        difference.positive? ? rank : -rank
      end
    end
    observed = [@differences.sum, signed.sum]
    extreme = [0, 0]
    greater = [0, 0]
    @permutations.times do
      totals = [0, 0]
      @differences.each_index do |index|
        sign = @generator.draw.odd? ? -1 : 1
        totals[0] += sign * @differences[index]
        totals[1] += sign * signed[index]
      end
      2.times do |index|
        extreme[index] += 1 if totals[index].abs >= observed[index].abs
        greater[index] += 1 if totals[index] >= observed[index]
      end
    end
    positive_ranks = signed.select(&:positive?).sum
    ["signflip flips #{@permutations}",
     "mean diff #{real(@paired_estimates[0])} #{test_result(extreme[0], greater[0], @permutations)}",
     "signedrank w_plus #{real(positive_ranks / 2.0)} #{test_result(extreme[1], greater[1], @permutations)}"]
  end

  def paired_lines
    size = @differences.length
    center = @paired_estimates[0]
    deviation = Resampling.sd(@differences)
    statistic = center / (deviation / Math.sqrt(size))
    correlation = @paired_estimates[1]
    z = 0.5 * Math.log((1 + correlation) / (1 - correlation))
    half_width = -@z_low / Math.sqrt(size - 3)
    fisher = [z - half_width, z + half_width].map do |value|
      exponential = Math.exp(2 * value)
      (exponential - 1) / (exponential + 1)
    end
    lines = [
      "paired subjects #{size} positive #{@differences.count(&:positive?)} negative #{@differences.count(&:negative?)} zero #{@differences.count(&:zero?)}",
      "paired before #{real(Resampling.mean(@before))} after #{real(Resampling.mean(@after))} diff #{real(center)} sd_diff #{real(deviation)} t #{real(statistic)} dz #{real(center / deviation)}",
      "paired_bootstrap #{summary_text(@paired_summaries[0])}",
      "correlation r #{real(correlation)} #{summary_text(@paired_summaries[1])} fisher #{real(fisher[0])} #{real(fisher[1])}"
    ]
    lines.concat(sign_flip_lines)
  end

  def welch_values(means)
    group_count = @groups.length
    weights = @groups.map { |group| group[:values].length / (group[:estimate][3] * group[:estimate][3]) }
    total_weight = Resampling.float_sum(weights)
    weighted_total = 0.0
    weights.each_with_index { |weight, index| weighted_total += weight * means[index] }
    center = weighted_total / total_weight
    numerator = correction = 0.0
    weights.each_with_index do |weight, index|
      deviation = means[index] - center
      numerator += weight * (deviation * deviation)
      remainder = 1 - weight / total_weight
      correction += (remainder * remainder) / (@groups[index][:values].length - 1)
    end
    average = numerator / (group_count - 1)
    statistic = average / (1 + 2 * (group_count - 2) * correction / (group_count * group_count - 1))
    degrees = (group_count * group_count - 1) / (3 * correction)
    [statistic, degrees]
  end

  def rational_differences(samples, pairs)
    pairs.map do |first, second|
      [Tests.contrast(samples[first], samples[second]).abs, samples[first].length * samples[second].length]
    end
  end

  def anova_permutation_lines(samples, observed, ranks, correction, observed_h)
    sizes = samples.map(&:length)
    records = samples.flatten.zip(ranks)
    pairs = Tests.position_choices(samples.length, 2).to_a
    differences = rational_differences(samples, pairs)
    extreme = Array.new(pairs.length, 0)
    maximum_extreme = Array.new(pairs.length, 0)
    f_extreme = h_extreme = 0
    @permutations.times do
      groups = Tests.divide(@generator.shuffle(records.dup), sizes)
      permuted = groups.map { |group| group.map(&:first) }
      result = Tests.anova(permuted)
      rank_groups = groups.map { |group| group.map(&:last) }
      h = Tests.kruskal(rank_groups, sizes, correction)
      f_extreme += 1 if result[:f] >= observed[:f] - 0.000000001 * observed[:f]
      h_extreme += 1 if h >= observed_h - 0.000000001 * observed_h
      permuted_differences = rational_differences(permuted, pairs)
      maximum = permuted_differences.max do |first, second|
        (first[0] * second[1]) <=> (second[0] * first[1])
      end
      differences.each_with_index do |difference, index|
        value = permuted_differences[index]
        extreme[index] += 1 if value[0] * difference[1] >= difference[0] * value[1]
        maximum_extreme[index] += 1 if maximum[0] * difference[1] >= difference[0] * maximum[1]
      end
    end
    lines = ["anova_permutation perms #{@permutations} f_extreme #{f_extreme} f_p #{Report.p_value(f_extreme + 1, @permutations + 1)} h_extreme #{h_extreme} h_p #{Report.p_value(h_extreme + 1, @permutations + 1)}"]
    pairs.each_with_index do |(first, second), index|
      difference = Resampling.mean_difference(samples[first], samples[second])
      lines << "pairwise #{@groups[first][:name]} #{@groups[second][:name]} diff #{real(difference)} extreme #{extreme[index]} p #{Report.p_value(extreme[index] + 1, @permutations + 1)} maxt #{maximum_extreme[index]} adjusted #{Report.p_value(maximum_extreme[index] + 1, @permutations + 1)}"
    end
    lines
  end

  def anova_lines
    samples = @groups.map { |group| group[:values] }
    sizes = samples.map(&:length)
    count = sizes.sum
    group_count = samples.length
    result = Tests.anova(samples)
    msw = result[:ssw] / (count - group_count)
    eta = result[:ssb] / (result[:ssb] + result[:ssw])
    omega = (result[:ssb] - (group_count - 1) * msw) / (result[:ssb] + result[:ssw] + msw)
    eta_replicates = Array.new(@bootstrap) do |replicate|
      bootstrap_samples = @groups.map { |group| group[:samples][replicate] }
      values = Tests.anova(bootstrap_samples)
      values[:ssb] / (values[:ssb] + values[:ssw])
    end
    eta_summary = bootstrap_summary(eta, eta_replicates)
    welch, degrees = welch_values(result[:means])
    combined = samples.flatten
    ranks = Tests.doubled_ranks(combined)
    ties = Tests.equal_counts(combined).values.select { |size| size >= 2 }
    tie_total = ties.sum { |size| size * size * size - size }
    correction = 1 - tie_total.to_f / (count * count * count - count)
    h = Tests.kruskal(Tests.divide(ranks, sizes), sizes, correction)
    lines = [
      "anova groups #{group_count} observations #{count} ssb #{real(result[:ssb])} ssw #{real(result[:ssw])} df #{group_count - 1} #{count - group_count} f #{real(result[:f])} eta_squared #{real(eta)} omega_squared #{real(omega)}",
      "eta_bootstrap #{summary_text(eta_summary)}", "welch f #{real(welch)} df #{group_count - 1} #{real(degrees)}",
      "kruskal h #{real(h)} tie_groups #{ties.length}"
    ]
    lines.concat(anova_permutation_lines(samples, result, ranks, correction, h))
  end

  def run
    descriptives = descriptive_lines
    ordinary_bootstraps
    balanced_bootstraps
    paired_bootstrap
    prepare_summaries
    jackknife = jackknife_lines
    histograms = histogram_lines
    test_lines = @pairs.flat_map { |pair| comparison_lines(pair) }
    test_lines.concat(holm_lines)
    test_lines.concat(paired_lines)
    test_lines.concat(anova_lines)
    Report.write('descriptives.txt', descriptives)
    Report.write('bootstrap.csv', bootstrap_lines)
    Report.write('jackknife.txt', jackknife)
    Report.write('tests.txt', test_lines)
    Report.write('histograms.txt', histograms)
  end
end

BootstrapStudy.new.run
