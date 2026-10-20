require "fileutils"
require_relative "dataset"
require_relative "estimators"
require_relative "group_tests"
require_relative "cox"
require_relative "plot"
require_relative "numerics"

class SurvivalAnalysis
  include Numerics
  include Estimators
  include GroupTests

  def number(value, digits = 4)
    return "NA" if value.nil?

    text = format("%.*f", digits, value)
    text == "-0.#{'0' * digits}" ? text[1..] : text
  end

  def day(value)
    value.nil? ? "NA" : value.to_s
  end

  def build_collections(subjects, groups)
    collections = groups.to_h do |group|
      [group, subjects.select { |subject| subject.group == group }]
    end
    collections["all"] = subjects
    collections
  end

  def percentile_time(rows, threshold, column = :survival)
    row = rows.find do |entry|
      value = entry[:survival].zero? ? 0.0 : entry[column]
      !value.nil? && value <= threshold
    end
    row && row[:time]
  end

  def restricted_mean(rows, tau)
    selected = rows.select { |row| row[:time] <= tau }
    times = [0] + selected.map { |row| row[:time] } + [tau]
    survival = [1.0] + selected.map { |row| row[:survival] }
    rectangles = survival.each_with_index.map { |value, i| value * (times[i + 1] - times[i]) }
    tails = Array.new(rectangles.length, 0.0)
    tails[-1] = rectangles.last
    (tails.length - 2).downto(0) { |i| tails[i] = rectangles[i] + tails[i + 1] }
    variance = 0.0
    selected.each_with_index do |row, index|
      risk, events = row.values_at(:risk, :events)
      i = index + 1
      variance += tails[i] * tails[i] * (events.to_f / (risk * (risk - events)))
    end
    estimate = tails.first
    error = Math.sqrt(variance)
    [estimate, error, estimate - Z95 * error, estimate + Z95 * error]
  end

  def collection_summary(subjects, params)
    rows = kaplan_meier(subjects)
    life = life_table(subjects, *params[:life_table])
    events = subjects.sum(&:event)
    person_days = subjects.sum(&:time)
    rate = (1000 * events).to_f / person_days
    eta = Z95 / Math.sqrt(events)
    reverse = subjects.map do |subject|
      copy = subject.dup
      copy.event = 1 - subject.event
      copy
    end
    followup = percentile_time(kaplan_meier(reverse), 0.5)
    life_median = nil
    previous = 1.0
    life.each do |row|
      if row[:survival] <= 0.5
        life_median = row[:start] + params[:life_table][0] * (previous - 0.5) / (previous - row[:survival])
        break
      end
      previous = row[:survival]
    end
    percentiles = [[25, 0.75], [50, 0.5], [75, 0.25]].map do |percentile, threshold|
      [percentile, percentile_time(rows, threshold), percentile_time(rows, threshold, :lower),
       percentile_time(rows, threshold, :upper)]
    end
    {
      rows: rows, life: life, subjects: subjects.length, events: events,
      censored: subjects.length - events, maximum: subjects.map(&:time).max,
      person_days: person_days, rate: rate, rate_lower: Math.exp(Math.log(rate) - eta),
      rate_upper: Math.exp(Math.log(rate) + eta), followup: followup, life_median: life_median,
      percentiles: percentiles, rmst: restricted_mean(rows, params[:tau])
    }
  end

  def km_table_lines(name, subjects, summary, params)
    lines = [
      "group #{name} subjects #{summary[:subjects]} events #{summary[:events]} " \
      "censored #{summary[:censored]} max_time #{summary[:maximum]}",
      "person_days #{summary[:person_days]} rate #{number(summary[:rate])} " \
      "lower #{number(summary[:rate_lower])} upper #{number(summary[:rate_upper])}",
      "followup_median #{day(summary[:followup])}",
      "life_table_median #{number(summary[:life_median])}"
    ]
    summary[:percentiles].each do |percentile, time, lower, upper|
      lines << "percentile #{percentile} time #{day(time)} lower #{day(lower)} upper #{day(upper)}"
    end
    estimate, error, lower, upper = summary[:rmst]
    lines << "rmst tau #{params[:tau]} estimate #{number(estimate)} se #{number(error)} " \
             "lower #{number(lower)} upper #{number(upper)}"
    params[:report_times].each do |time|
      row = row_at(summary[:rows], time)
      risk = subjects.count { |subject| subject.time >= time }
      events = subjects.count { |subject| subject.time <= time && subject.event == 1 }
      lines << "at #{time} at_risk #{risk} events #{events} survival #{number(row[:survival])} " \
               "std_err #{number(row[:se])} lower #{number(row[:lower])} upper #{number(row[:upper])} " \
               "cum_hazard #{number(row[:hazard])} hazard_se #{number(row[:hazard_se])}"
    end
    columns = %w[time at_risk events censored survival std_err lower upper cum_haz haz_se]
    lines << columns.map { |column| column.rjust(9) }.join
    summary[:rows].each do |row|
      fields = row.values_at(:time, :risk, :events, :censored).map(&:to_s)
      fields.concat(row.values_at(:survival, :se, :lower, :upper, :hazard, :hazard_se).map { |value| number(value) })
      lines << fields.map { |value| value.rjust(9) }.join
    end
    lines
  end

  def life_table_lines(summaries)
    lines = ["group,interval,at_risk,events,withdrawn,exposed,q,survival,std_err,hazard"]
    summaries.each do |name, summary|
      summary[:life].each do |row|
        fields = [name, "#{row[:start]}-#{row[:end]}"] + row.values_at(:risk, :events, :withdrawn)
        fields << number(row[:exposed], 1)
        fields.concat(row.values_at(:q, :survival, :se, :hazard).map { |value| number(value) })
        lines << fields.join(",")
      end
    end
    lines
  end

  def baseline_summary(name, subjects)
    count = subjects.length
    mean = subjects.sum(&:age).to_f / count
    deviation = Math.sqrt(total(subjects.map { |subject| (subject.age - mean) * (subject.age - mean) }) / (count - 1))
    ages = subjects.map(&:age).sort
    median = (ages[(count - 1).div(2)] + ages[count.div(2)]) / 2.0
    males = subjects.count { |subject| subject.sex == "M" }
    stages = (1..4).map { |stage| subjects.count { |subject| subject.stage == stage } }
    "  group #{name} subjects #{count} age_mean #{number(mean)} age_sd #{number(deviation)} " \
    "age_median #{number(median, 1)} male #{males} stage #{stages.join(' ')}"
  end

  def kruskal_wallis(subjects, groups, collections)
    ranked = subjects.sort_by { |subject| [subject.age, subject.id] }
    ranks = {}
    ties = position = 0
    ranked.chunk(&:age).each do |_, batch|
      finish = position + batch.length
      rank = (position + 1 + finish) / 2.0
      batch.each { |subject| ranks[subject.id] = rank }
      size = batch.length
      ties += size * size * size - size
      position = finish
    end
    weighted = 0.0
    groups.each do |group|
      rank_sum = total(collections[group].map { |subject| ranks[subject.id] })
      weighted += rank_sum * rank_sum / collections[group].length
    end
    count = subjects.length
    raw = 12 * weighted / (count * (count + 1)) - 3 * (count + 1)
    raw / (1.0 - ties.to_f / (count * count * count - count))
  end

  def levels_of(subjects, variable)
    subjects.map { |subject| subject[variable] }.uniq.sort
  end

  def contingency_test(subjects, groups, collections, variable)
    levels = levels_of(subjects, variable)
    counts = levels.map { |level| subjects.count { |subject| subject[variable] == level } }
    statistic = 0.0
    groups.each do |group|
      members = collections[group]
      levels.zip(counts).each do |level, column_count|
        observed = members.count { |subject| subject[variable] == level }
        expected = (members.length * column_count).to_f / subjects.length
        statistic += (observed - expected) * (observed - expected) / expected
      end
    end
    [statistic, (groups.length - 1) * (levels.length - 1)]
  end

  def baseline_lines(subjects, groups, collections)
    lines = ["baseline"]
    collections.each { |name, rows| lines << baseline_summary(name, rows) }
    statistic = kruskal_wallis(subjects, groups, collections)
    degrees = groups.length - 1
    lines << "  age kruskal_wallis chisq #{number(statistic)} df #{degrees} p #{number(chi_square_p(statistic, degrees))}"
    %w[sex stage].each do |variable|
      statistic, degrees = contingency_test(subjects, groups, collections, variable)
      lines << "  #{variable} chisq #{number(statistic)} df #{degrees} p #{number(chi_square_p(statistic, degrees))}"
    end
    lines
  end

  def group_lines(test)
    test[:groups].each_with_index.map do |group, index|
      observed, expected = test[:observed][index], test[:expected][index]
      "  group #{group} events #{test[:events][index]} observed #{number(observed)} expected #{number(expected)} " \
      "o_minus_e #{number(observed - expected)} variance #{number(test[:covariance][index][index])}"
    end
  end

  def test_fields(test)
    "chisq #{number(test[:statistic])} df #{test[:degrees]} p #{number(test[:p])}"
  end

  def overall_lines(subjects, groups)
    lines = []
    tests = {}
    WEIGHTS.each do |weight|
      test = weighted_test(subjects, groups, weight, subjects.length)
      tests[weight] = test
      lines << "test #{weight} #{test_fields(test)}"
      lines.concat(group_lines(test))
    end
    logrank = tests["logrank"]
    trend = total(groups.each_index.map { |g| (g + 1) * (logrank[:observed][g] - logrank[:expected][g]) })
    variance = total(groups.each_index.map do |g|
      total(groups.each_index.map { |h| ((g + 1) * (h + 1)) * logrank[:covariance][g][h] })
    end)
    statistic = trend * trend / variance
    lines << "test logrank_trend chisq #{number(statistic)} df 1 p #{number(chi_square_p(statistic, 1))}"
    lines
  end

  def stratified_lines(subjects, groups, variable)
    levels = levels_of(subjects, variable)
    strata = levels.map { |level| subjects.select { |subject| subject[variable] == level } }
    lines = []
    WEIGHTS.each do |weight|
      tests = strata.map { |rows| weighted_test(rows, groups, weight, subjects.length) }
      combined = combine_strata(tests, groups)
      lines << "stratified #{weight} by #{variable} #{test_fields(combined)}"
      levels.each_with_index do |level, index|
        rows, test = strata[index], tests[index]
        lines << "  stratum #{level} subjects #{rows.length} events #{rows.sum(&:event)} " \
                 "chisq #{number(test[:statistic])} p #{number(test[:p])}"
      end
      lines.concat(group_lines(combined))
    end
    lines
  end

  def landmark_lines(subjects, groups, landmark)
    selected = subjects.select { |subject| subject.time > landmark }
    test = weighted_test(selected, groups, "logrank", subjects.length)
    ["landmark #{landmark} subjects #{selected.length} #{test_fields(test)}"] + group_lines(test)
  end

  def two_group_comparison(subjects, groups, population_size)
    test = weighted_test(subjects, groups, "logrank", population_size)
    observed, expected = test.values_at(:observed, :expected)
    ratio = (observed[1] / expected[1]) / (observed[0] / expected[0])
    variance = 1.0 / expected[0] + 1.0 / expected[1]
    logarithm = Math.log(ratio)
    test.merge(ratio: ratio, log_ratio: logarithm, variance: variance,
               lower: Math.exp(logarithm - Z95 * Math.sqrt(variance)),
               upper: Math.exp(logarithm + Z95 * Math.sqrt(variance)))
  end

  def pairwise_lines(subjects, groups)
    pairs = groups.combination(2).to_a
    tests = pairs.map do |pair|
      selected = subjects.select { |subject| pair.include?(subject.group) }
      two_group_comparison(selected, pair, subjects.length)
    end
    adjusted = Array.new(pairs.length, 0.0)
    previous = 0.0
    order = pairs.each_index.sort_by { |index| [tests[index][:p], index] }
    order.each_with_index do |index, rank|
      candidate = (pairs.length - rank) * tests[index][:p]
      previous = [previous, [1.0, candidate].min].max
      adjusted[index] = previous
    end
    lines = ["pairwise logrank adjust holm"]
    pairs.each_with_index do |(first, second), index|
      test = tests[index]
      lines << "  #{first} #{second} chisq #{number(test[:statistic])} p #{number(test[:p])} " \
               "p_holm #{number(adjusted[index])} hr #{number(test[:ratio])} " \
               "lower #{number(test[:lower])} upper #{number(test[:upper])}"
    end
    lines
  end

  def subgroup_lines(subjects, groups, variables)
    lines = ["subgroups reference #{groups.first}"]
    variables.each do |variable|
      levels = levels_of(subjects, variable)
      groups.drop(1).each do |group|
        pair = [groups.first, group]
        tests = levels.map do |level|
          selected = subjects.select { |subject| subject[variable] == level && pair.include?(subject.group) }
          test = two_group_comparison(selected, pair, subjects.length)
          lines << "  #{variable} #{level} #{group} subjects #{selected.length} events #{selected.sum(&:event)} " \
                   "hr #{number(test[:ratio])} lower #{number(test[:lower])} upper #{number(test[:upper])} p #{number(test[:p])}"
          test
        end
        weights = tests.map { |test| 1.0 / test[:variance] }
        mean = total(weights.each_index.map { |i| weights[i] * tests[i][:log_ratio] }) / total(weights)
        statistic = total(weights.each_index.map do |i|
          weights[i] * (tests[i][:log_ratio] - mean) * (tests[i][:log_ratio] - mean)
        end)
        degrees = levels.length - 1
        lines << "  #{variable} #{group} heterogeneity chisq #{number(statistic)} df #{degrees} " \
                 "p #{number(chi_square_p(statistic, degrees))}"
      end
    end
    lines
  end

  def difference_fields(difference, error)
    statistic = difference / error
    "difference #{number(difference)} se #{number(error)} lower #{number(difference - Z95 * error)} " \
    "upper #{number(difference + Z95 * error)} z #{number(statistic)} " \
    "p #{number(chi_square_p(statistic * statistic, 1))}"
  end

  def rmst_difference_lines(groups, summaries, tau)
    lines = ["rmst_difference tau #{tau} reference #{groups.first}"]
    control_mean, control_error = summaries[groups.first][:rmst]
    groups.drop(1).each do |group|
      mean, error = summaries[group][:rmst]
      combined_error = Math.sqrt(error * error + control_error * control_error)
      lines << "  #{group} #{difference_fields(mean - control_mean, combined_error)}"
    end
    lines
  end

  def rate_ratio_lines(groups, summaries)
    lines = ["rate_ratio reference #{groups.first}"]
    control = summaries[groups.first]
    groups.drop(1).each do |group|
      summary = summaries[group]
      ratio = summary[:rate] / control[:rate]
      error = Math.sqrt(1.0 / summary[:events] + 1.0 / control[:events])
      logarithm = Math.log(ratio)
      statistic = logarithm / error
      lower = Math.exp(logarithm - Z95 * error)
      upper = Math.exp(logarithm + Z95 * error)
      lines << "  #{group} ratio #{number(ratio)} lower #{number(lower)} upper #{number(upper)} " \
               "z #{number(statistic)} p #{number(chi_square_p(statistic * statistic, 1))}"
    end
    lines
  end

  def survival_difference_lines(groups, summaries, times)
    lines = ["survival_difference reference #{groups.first}"]
    times.each do |time|
      control = row_at(summaries[groups.first][:rows], time)
      groups.drop(1).each do |group|
        row = row_at(summaries[group][:rows], time)
        difference = row[:survival] - control[:survival]
        error = Math.sqrt(row[:se] * row[:se] + control[:se] * control[:se])
        lines << "  at #{time} #{group} #{difference_fields(difference, error)}"
      end
    end
    lines
  end

  def comparison_sections(subjects, params, collections, summaries)
    groups = params[:groups]
    [
      baseline_lines(subjects, groups, collections),
      overall_lines(subjects, groups),
      stratified_lines(subjects, groups, params[:strata]),
      landmark_lines(subjects, groups, params[:landmark]),
      pairwise_lines(subjects, groups),
      subgroup_lines(subjects, groups, params[:subgroups]),
      rmst_difference_lines(groups, summaries, params[:tau]),
      rate_ratio_lines(groups, summaries),
      survival_difference_lines(groups, summaries, params[:report_times])
    ]
  end

  def covariate_vectors(subjects, names)
    subjects.map do |subject|
      names.map do |name|
        case name
        when "age", "stage" then subject[name]
        when "male" then subject.sex == "M" ? 1 : 0
        else subject.group == name ? 1 : 0
        end
      end
    end
  end

  def coefficient_fields(coefficient, error)
    statistic = coefficient / error
    lower = Math.exp(coefficient - Z95 * error)
    upper = Math.exp(coefficient + Z95 * error)
    "coef #{number(coefficient)} se #{number(error)} z #{number(statistic)} " \
    "p #{number(chi_square_p(statistic * statistic, 1))} hr #{number(Math.exp(coefficient))} " \
    "lower #{number(lower)} upper #{number(upper)}"
  end

  def coefficient_lines(names, beta, covariance)
    lines = names.each_with_index.map do |name, index|
      "term #{name} #{coefficient_fields(beta[index], Math.sqrt(covariance[index][index]))}"
    end
    group_indices = names.each_index.reject { |index| %w[age male stage].include?(names[index]) }
    group_indices.combination(2).each do |first, second|
      coefficient = beta[second] - beta[first]
      error = Math.sqrt(covariance[second][second] + covariance[first][first] - 2 * covariance[first][second])
      lines << "contrast #{names[second]} vs #{names[first]} #{coefficient_fields(coefficient, error)}"
    end
    lines
  end

  def cox_test_lines(subjects, vectors, names, model)
    beta, final, null = model.values_at(:beta, :final, :null)
    size = names.length
    likelihood_ratio = 2 * (final[:loglik] - null[:loglik])
    wald = total(beta.each_index.map do |c|
      beta[c] * total(beta.each_index.map { |d| final[:information][c][d] * beta[d] })
    end)
    solution = solve(null[:information], null[:score])
    score = total(beta.each_index.map { |c| null[:score][c] * solution[c] })
    lines = [["likelihood_ratio", likelihood_ratio], ["wald", wald], ["score", score]].map do |label, statistic|
      "#{label} chisq #{number(statistic)} df #{size} p #{number(chi_square_p(statistic, size))}"
    end
    names.each_with_index do |name, index|
      likelihood = if size == 1
                     null[:loglik]
                   else
                     reduced = vectors.map { |values| values[0, index] + values[(index + 1)..] }
                     Cox.fit(subjects, reduced)[:final][:loglik]
                   end
      statistic = 2 * (final[:loglik] - likelihood)
      lines << "drop #{name} loglik #{number(likelihood)} chisq #{number(statistic)} df 1 " \
               "p #{number(chi_square_p(statistic, 1))}"
    end
    lines
  end

  def concordance_line(subjects, vectors, predictors)
    comparable = concordant = tied = 0
    subjects.each_with_index do |first, i|
      next unless first.event == 1

      subjects.each_with_index do |second, j|
        next if i == j
        next unless first.time < second.time || (first.time == second.time && second.event.zero?)

        comparable += 1
        if vectors[i] == vectors[j]
          tied += 1
        elsif predictors[i] > predictors[j]
          concordant += 1
        end
      end
    end
    value = (2 * concordant + tied).to_f / (2 * comparable)
    "concordance #{number(value)} comparable #{comparable} concordant #{concordant} tied #{tied}"
  end

  def proportional_hazards_lines(subjects, vectors, names, evaluation)
    events = subjects.each_index.select { |i| subjects[i].event == 1 }
    events.sort_by! { |i| [subjects[i].time, subjects[i].id] }
    count = events.length
    mean_time = events.sum { |i| subjects[i].time }.to_f / count
    names.each_with_index.map do |name, column|
      residuals = events.map do |i|
        sums = evaluation[:event_sums][subjects[i].time]
        vectors[i][column] - sums[:s1][column] / sums[:s0]
      end
      mean_residual = total(residuals) / count
      sxy = sxx = syy = 0.0
      events.zip(residuals).each do |i, residual|
        x = residual - mean_residual
        y = subjects[i].time - mean_time
        sxy += x * y
        sxx += x * x
        syy += y * y
      end
      correlation = sxy / Math.sqrt(sxx * syy)
      statistic = 0.5 * Math.log((1.0 + correlation) / (1.0 - correlation)) * Math.sqrt(count - 3)
      "ph_check #{name} rho #{number(correlation)} z #{number(statistic)} " \
      "p #{number(chi_square_p(statistic * statistic, 1))}"
    end
  end

  def baseline_hazard(evaluation)
    cumulative = 0.0
    evaluation[:event_sums].keys.sort.map do |time|
      sums = evaluation[:event_sums][time]
      cumulative += sums[:events] / sums[:s0]
      [time, cumulative]
    end
  end

  def hazard_at(rows, time)
    row = rows.reverse_each.find { |event_time, _| event_time <= time }
    row ? row[1] : 0.0
  end

  def residual_lines(subjects, evaluation, hazard, count)
    residuals = subjects.each_with_index.map do |subject, i|
      martingale = subject.event - hazard_at(hazard, subject.time) * Math.exp(evaluation[:predictors][i])
      deviance = if subject.event == 1
                   Math.sqrt(-2 * (martingale + Math.log(1.0 - martingale)))
                 else
                   Math.sqrt(-2 * martingale)
                 end
      deviance = -deviance unless martingale.positive?
      [subject, martingale, deviance]
    end
    residuals.sort_by! { |subject, _, deviance| [-deviance.abs, subject.id] }
    lines = ["residuals top #{count}"]
    residuals.first(count).each do |subject, martingale, deviance|
      lines << "  id #{subject.id} group #{subject.group} time #{subject.time} event #{subject.event} " \
               "martingale #{number(martingale)} deviance #{number(deviance)}"
    end
    lines
  end

  def adjusted_survival_lines(vectors, names, beta, groups, times, hazard)
    means = {}
    names.each_with_index do |name, column|
      means[name] = vectors.sum { |x| x[column] }.to_f / vectors.length if %w[age male stage].include?(name)
    end
    fields = means.empty? ? "none" : means.map { |name, value| "#{name} #{number(value)}" }.join(" ")
    lines = ["adjusted_survival mean #{fields}"]
    risks = groups.to_h do |group|
      representative = names.map { |name| means.key?(name) ? means[name] : name == group ? 1 : 0 }
      predictor = total(beta.each_index.map { |c| beta[c] * representative[c] })
      [group, Math.exp(predictor)]
    end
    times.each do |time|
      cumulative = hazard_at(hazard, time)
      fields = groups.map { |group| "#{group} #{number(Math.exp(-cumulative * risks[group]))}" }.join(" ")
      lines << "  at #{time} #{fields}"
    end
    medians = groups.map do |group|
      row = hazard.find { |_, cumulative| Math.exp(-cumulative * risks[group]) <= 0.5 }
      "#{group} #{day(row&.first)}"
    end
    lines << "  median #{medians.join(' ')}"
  end

  def cox_lines(subjects, params)
    names = params[:covariates]
    vectors = covariate_vectors(subjects, names)
    model = Cox.fit(subjects, vectors)
    final = model[:final]
    covariance = inverse(final[:information])
    lines = ["cox covariates #{names.join(' ')} subjects #{subjects.length} events #{subjects.sum(&:event)} " \
             "event_times #{final[:event_sums].length}"]
    model[:iterations].each do |iteration, likelihood, beta|
      lines << "iter #{iteration} loglik #{number(likelihood)} beta #{beta.map { |value| number(value) }.join(' ')}"
    end
    lines << "final loglik #{number(final[:loglik])} null_loglik #{number(model[:null][:loglik])}"
    lines.concat(coefficient_lines(names, model[:beta], covariance))
    lines.concat(cox_test_lines(subjects, vectors, names, model))
    lines << concordance_line(subjects, vectors, final[:predictors])
    lines.concat(proportional_hazards_lines(subjects, vectors, names, final))
    hazard = baseline_hazard(final)
    lines.concat(residual_lines(subjects, final, hazard, params[:residuals]))
    lines.concat(adjusted_survival_lines(vectors, names, model[:beta], params[:groups], params[:report_times], hazard))
    lines
  end

  def plot_lines(params, collections, summaries)
    groups = params[:groups]
    width, height, time_limit, divisions = params[:plot]
    estimates = groups.to_h { |group| [group, summaries[group][:rows]] }
    legend = groups.each_with_index.map { |group, i| "#{('A'.ord + i).chr} #{group}" }.join(" ")
    lines = ["km_plot width #{width} height #{height} time #{time_limit}", "legend #{legend}"]
    lines.concat(SurvivalPlot.curve_lines(groups, collections, estimates, width, height, time_limit))
    lines << "time 0 to #{time_limit} days, #{time_limit.div(width)} days per column"
    times = Array.new(divisions + 1) { |i| i * time_limit.div(divisions) }
    lines << "at_risk #{times.join(' ')}"
    groups.each do |group|
      counts = times.map { |time| collections[group].count { |subject| subject.time >= time } }
      lines << "#{group} #{counts.join(' ')}"
    end
    lines
  end

  def join_sections(sections)
    sections.each_with_object([]) do |section, lines|
      lines << "" unless lines.empty?
      lines.concat(section)
    end
  end

  def write_lines(path, lines)
    File.binwrite(path, lines.join("\n") + "\n")
  end

  def run
    subjects, params = Dataset.read("input")
    collections = build_collections(subjects, params[:groups])
    summaries = collections.to_h { |name, rows| [name, collection_summary(rows, params)] }
    FileUtils.mkdir_p("output")
    tables = collections.map { |name, rows| km_table_lines(name, rows, summaries[name], params) }
    write_lines("output/km_tables.txt", join_sections(tables))
    write_lines("output/life_table.csv", life_table_lines(summaries))
    write_lines("output/tests.txt", join_sections(comparison_sections(subjects, params, collections, summaries)))
    write_lines("output/cox.txt", cox_lines(subjects, params))
    write_lines("output/km_plot.txt", plot_lines(params, collections, summaries))
  end
end

SurvivalAnalysis.new.run if $PROGRAM_NAME == __FILE__
