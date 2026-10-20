require_relative 'dataframe'
require_relative 'formula'
require_relative 'qr_solver'
require_relative 'inference'
require_relative 'diagnostics'

module OLSRegression
  extend self
  include QRSolver
  include Inference

  def table(header, rows, marks = nil)
    rows = rows.map { |row| row.map(&:to_s) }
    all_rows = [header] + rows
    widths = header.each_index.map do |column|
      all_rows.filter_map { |row| row[column]&.length }.max
    end
    marks ||= Array.new(rows.length, '')
    all_rows.each_with_index.map do |row, i|
      line = row[0].ljust(widths[0])
      row.drop(1).each_with_index { |field, j| line += '  ' + field.rjust(widths[j + 1]) }
      mark = i.zero? ? '' : marks[i - 1]
      line += ' ' + mark unless mark.nil? || mark.empty?
      line.rstrip
    end
  end

  def numeric_summary(data, numeric)
    rows = numeric.map do |column|
      values = data.rows.map { |row| row[column] }.compact
      count = values.length
      mean = total(values) / count
      variance = total(values) { |value| (value - mean) * (value - mean) } / (count - 1)
      [column, count, data.rows.length - count, four(mean),
       four(Math.sqrt(variance)), four(values.min), four(values.max)]
    end
    table(%w[column n missing Mean SD Min Max], rows)
  end

  def categorical_summary(data)
    data.columns.filter_map do |column|
      next unless data.kinds[column] == :categorical

      values = data.rows.map { |row| row[column] }.compact
      counts = values.tally
      levels = counts.keys.sort.map { |label| "#{label} #{counts[label]}" }.join(', ')
      "#{column}: #{values.length} values, #{data.rows.length - values.length} missing, " \
        "#{counts.length} levels: #{levels}"
    end
  end

  def correlations(data, numeric)
    rows = numeric.map do |a|
      fields = numeric.map do |b|
        pairs = data.rows.filter_map do |row|
          [row[a], row[b]] unless row[a].nil? || row[b].nil?
        end
        mean_x = total(pairs) { |x, _| x } / pairs.length
        mean_y = total(pairs) { |_, y| y } / pairs.length
        cross = total(pairs) { |x, y| (x - mean_x) * (y - mean_y) }
        square_x = total(pairs) { |x, _| (x - mean_x) * (x - mean_x) }
        square_y = total(pairs) { |_, y| (y - mean_y) * (y - mean_y) }
        four(cross / Math.sqrt(square_x * square_y))
      end
      [a] + fields
    end
    table(['column'] + numeric, rows)
  end

  def data_summary(data)
    numeric = data.columns.select { |column| data.kinds[column] == :numeric }
    ["Data: #{data.rows.length} rows, #{data.columns.length} columns", '', 'Numeric columns:'] +
      numeric_summary(data, numeric) + ['', 'Categorical columns:'] + categorical_summary(data) +
      ['', 'Correlations (pairwise complete observations):'] + correlations(data, numeric) + ['']
  end

  def information_criteria(fitted)
    n = fitted.n
    log_weights = total(fitted.weights) { |weight| Math.log(weight) }
    likelihood = 0.5 * (log_weights - n * (
      Math.log(2.0 * 3.141592653589793) + 1.0 - Math.log(n) + Math.log(fitted.rss)
    ))
    aic = -2.0 * likelihood + 2.0 * (fitted.rank + 1)
    bic = -2.0 * likelihood + Math.log(n) * (fitted.rank + 1)
    [likelihood, aic, bic]
  end

  def residual_quantile(values, proportion)
    position = (values.length - 1) * proportion
    index = position.floor
    return values[index] if index + 1 == values.length

    values[index] + (position - index) * (values[index + 1] - values[index])
  end

  def model_statistics(fitted, confidence)
    n, rank = fitted.n, fitted.rank
    degrees = n - rank
    sigma = Math.sqrt(fitted.rss / degrees)
    weight_sum = total(fitted.weights)
    mean = total(0...n) { |i| fitted.weights[i] * fitted.response[i] } / weight_sum
    tss = total(0...n) do |i|
      fitted.weights[i] * (fitted.response[i] - mean) * (fitted.response[i] - mean)
    end
    r_squared = 1.0 - fitted.rss / tss
    adjusted = 1.0 - (1.0 - r_squared) * (n - 1) / degrees
    statistic = ((tss - fitted.rss) / (rank - 1)) / (fitted.rss / degrees)
    likelihood, aic, bic = information_criteria(fitted)
    press = total(0...n) do |i|
      (fitted.weighted_residual[i] / (1.0 - fitted.leverage[i])) *
        (fitted.weighted_residual[i] / (1.0 - fitted.leverage[i]))
    end
    residuals = fitted.weighted_residual.sort
    quantiles = [0.0, 0.25, 0.5, 0.75, 1.0].map { |p| residual_quantile(residuals, p) }
    { df: degrees, sigma: sigma, weight_sum: weight_sum, tss: tss,
      r_squared: r_squared, adjusted: adjusted, f: statistic,
      p: f_pvalue(statistic, rank - 1, degrees), ll: likelihood, aic: aic, bic: bic,
      press: press, predicted: 1.0 - press / tss, quantiles: quantiles,
      critical: t_quantile(confidence, degrees) }
  end

  def coefficient_inference(fitted, stats)
    accepted = fitted.accepted.each_with_index.to_h
    omega = Array.new(fitted.n) do |i|
      fitted.weighted_residual[i] * fitted.weighted_residual[i] /
        ((1.0 - fitted.leverage[i]) * (1.0 - fitted.leverage[i]))
    end
    fitted.beta.each_with_index.map do |estimate, column|
      next {} if estimate.nil?

      k = accepted[column]
      standard_error = stats[:sigma] * Math.sqrt(fitted.variance[k])
      tvalue = estimate / standard_error
      half_width = stats[:critical] * standard_error
      robust_error = Math.sqrt(total(0...fitted.n) { |i| omega[i] * fitted.g[i][k] * fitted.g[i][k] })
      robust_t = estimate / robust_error
      { estimate: estimate, se: standard_error, t: tvalue, p: t_pvalue(tvalue, stats[:df]),
        lower: estimate - half_width, upper: estimate + half_width, robust_se: robust_error,
        robust_t: robust_t, robust_p: t_pvalue(robust_t, stats[:df]) }
    end
  end

  def sequential_anova(design, fitted)
    residual_degrees = fitted.n - fitted.rank
    design.model.terms.each_with_index.filter_map do |term, index|
      effects = fitted.accepted.each_index.select do |k|
        design.columns[fitted.accepted[k]].term_index == index
      end
      degrees = effects.length
      next if degrees.zero?

      squares = total(effects) { |k| fitted.effects[k] * fitted.effects[k] }
      mean_square = squares / degrees
      statistic = mean_square / (fitted.rss / residual_degrees)
      { name: term.name, df: degrees, ss: squares, ms: mean_square, f: statistic,
        p: f_pvalue(statistic, degrees, residual_degrees) }
    end
  end

  def fit_subset(design, term_indices, tolerance)
    QRSolver::Fit.new(design.subset_matrix(term_indices), design.response, design.weights, tolerance)
  end

  def marginal_tests(design, fitted, term_indices, tolerance)
    residual_degrees = fitted.n - fitted.rank
    design.model.removable(term_indices).map do |index|
      remaining = term_indices.reject { |other| other == index }
      reduced = fit_subset(design, remaining, tolerance)
      degrees = fitted.rank - reduced.rank
      squares = reduced.rss - fitted.rss
      statistic = pvalue = nil
      if degrees.positive?
        statistic = (squares / degrees) / (fitted.rss / residual_degrees)
        pvalue = f_pvalue(statistic, degrees, residual_degrees)
      end
      { index: index, name: design.model.terms[index].name, df: degrees, ss: squares,
        rss: reduced.rss, f: statistic, p: pvalue }
    end
  end

  def variance_inflation(design, fitted, stats, params)
    fitted.accepted.drop(1).map do |column|
      response = fitted.matrix.map { |row| row[column] }
      others = fitted.accepted.reject { |index| index == column }
      matrix = fitted.matrix.map { |row| others.map { |index| row[index] } }
      auxiliary = QRSolver::Fit.new(matrix, response, fitted.weights, params['RANK_TOL'])
      mean = total(0...fitted.n) { |i| fitted.weights[i] * response[i] } / stats[:weight_sum]
      tss = total(0...fitted.n) do |i|
        fitted.weights[i] * (response[i] - mean) * (response[i] - mean)
      end
      r_squared = 1.0 - auxiliary.rss / tss
      vif = 1.0 / (1.0 - r_squared)
      [design.columns[column].name, vif, vif > params['VIF']]
    end
  end

  def reset_test(fitted, tolerance)
    matrix = fitted.matrix.each_with_index.map do |row, i|
      value = fitted.fitted[i]
      fitted.accepted.map { |column| row[column] } + [value * value, value * value * value]
    end
    augmented = QRSolver::Fit.new(matrix, fitted.response, fitted.weights, tolerance)
    added_degrees = augmented.rank - fitted.rank
    residual_degrees = fitted.n - augmented.rank
    statistic = ((fitted.rss - augmented.rss) / added_degrees) / (augmented.rss / residual_degrees)
    [statistic, added_degrees, residual_degrees, f_pvalue(statistic, added_degrees, residual_degrees)]
  end

  def diagnostic_decisions(design, fitted, diagnostic, params)
    rows = diagnostic[:rows]
    dw = diagnostic[:dw]
    dw_label = if dw < params['DURBIN_WATSON']
                 'positive autocorrelation'
               elsif dw > 4.0 - params['DURBIN_WATSON']
                 'negative autocorrelation'
               else
                 'no autocorrelation'
               end
    bp_label = diagnostic[:bp][2] < params['BREUSCH_PAGAN'] ? 'heteroscedastic' : 'homoscedastic'
    jb_label = diagnostic[:jb][1] < params['NORMALITY'] ? 'non-normal' : 'normal'
    # Including the row index in these keys makes all tie rules explicit.
    outlier = (0...fitted.n).min_by { |i| [-rows[i][:studentized].abs, i] }
    unadjusted = t_pvalue(rows[outlier][:studentized], fitted.n - fitted.rank - 1)
    largest_cooks = (0...fitted.n).sort_by { |i| [-rows[i][:cooks], i] }.first(3)
    largest_dfbetas = fitted.accepted.each_with_index.map do |column, k|
      index = (0...fitted.n).min_by { |i| [-rows[i][:dfbetas][k].abs, i] }
      [design.columns[column].name, design.row_numbers[index], rows[index][:dfbetas][k]]
    end
    counts = 'HOCF'.chars.to_h { |flag| [flag, rows.count { |row| row[:flags].include?(flag) }] }
    counts[:any] = rows.count { |row| row[:flags] != '-' }
    { dw_label: dw_label, bp_label: bp_label, jb_label: jb_label, outlier: outlier,
      unadjusted: unadjusted, bonferroni: [1.0, fitted.n * unadjusted].min,
      largest_cooks: largest_cooks, largest_dfbetas: largest_dfbetas, counts: counts }
  end

  def prediction_report(number, design, fitted, stats, prediction_data)
    lines = []
    predicted_count = actual_count = covered_count = 0
    squared_errors = 0.0
    prediction_data.rows.each_with_index do |record, i|
      fields = [number, i + 1]
      unless design.predictable?(record)
        lines << (fields + Array.new(9, 'NA')).join(',')
        next
      end
      predicted_count += 1
      values = design.values(record)
      predicted = total(fitted.accepted) { |column| values[column] * fitted.beta[column] }
      u = Array.new(fitted.rank) do |k|
        total(0...fitted.rank) { |m| values[fitted.accepted[m]] * fitted.inverse[m][k] }
      end
      standard_error = stats[:sigma] * Math.sqrt(total(u) { |value| value * value })
      confidence_width = stats[:critical] * standard_error
      prediction_width = stats[:critical] * Math.sqrt(
        stats[:sigma] * stats[:sigma] + standard_error * standard_error
      )
      lower = predicted - prediction_width
      upper = predicted + prediction_width
      fields.concat([predicted, standard_error, predicted - confidence_width,
                     predicted + confidence_width, lower, upper].map { |value| four(value) })
      actual = record[design.model.response]
      if actual.nil?
        fields.concat(%w[NA NA NA])
      else
        actual_count += 1
        error = actual - predicted
        squared_errors += error * error
        covered = lower <= actual && actual <= upper
        covered_count += 1 if covered
        fields.concat([four(actual), four(error), covered ? 'yes' : 'no'])
      end
      lines << fields.join(',')
    end
    rmse = actual_count.zero? ? nil : Math.sqrt(squared_errors / actual_count)
    [lines, [predicted_count, actual_count, rmse, covered_count]]
  end

  def analyze_model(number, design, params, prediction_data)
    fitted = QRSolver::Fit.new(design.matrix, design.response, design.weights, params['RANK_TOL'])
    stats = model_statistics(fitted, params['CONFIDENCE'])
    diagnostic = Diagnostics.calculate(fitted, params)
    predictions, prediction_check = prediction_report(number, design, fitted, stats, prediction_data)
    { number: number, design: design, fit: fitted, stats: stats,
      coefficients: coefficient_inference(fitted, stats), anova: sequential_anova(design, fitted),
      marginal: marginal_tests(design, fitted, design.model.terms.each_index.to_a, params['RANK_TOL']),
      vif: variance_inflation(design, fitted, stats, params), diagnostics: diagnostic,
      decisions: diagnostic_decisions(design, fitted, diagnostic, params),
      reset: reset_test(fitted, params['RANK_TOL']), predictions: predictions,
      prediction_check: prediction_check }
  end

  def coefficient_tables(report, confidence)
    pairs = report[:design].columns.map(&:name).zip(report[:coefficients])
    rows = pairs.map do |name, coef|
      [name, four(coef[:estimate]), four(coef[:se]), four(coef[:t]), probability(coef[:p])]
    end
    marks = pairs.map { |_, coef| significance(coef[:p]) }
    ordinary = table(['term', 'Estimate', 'Std. Error', 't value', 'Pr(>|t|)'], rows, marks)
    rows = pairs.map { |name, coef| [name, four(coef[:lower]), four(coef[:upper])] }
    intervals = ["Confidence intervals (level #{four(confidence)}, t #{four(report[:stats][:critical])}):"] +
                table(%w[term Lower Upper], rows)
    rows = pairs.map do |name, coef|
      [name, four(coef[:robust_se]), four(coef[:robust_t]), probability(coef[:robust_p])]
    end
    marks = pairs.map { |_, coef| significance(coef[:robust_p]) }
    robust = table(['term', 'Std. Error', 't value', 'Pr(>|t|)'], rows, marks)
    [ordinary, intervals, robust]
  end

  def anova_tables(report)
    stats, fitted = report.values_at(:stats, :fit)
    rows = report[:anova].map do |entry|
      [entry[:name], entry[:df], four(entry[:ss]), four(entry[:ms]), four(entry[:f]), probability(entry[:p])]
    end
    marks = report[:anova].map { |entry| significance(entry[:p]) }
    rows << ['Residuals', stats[:df], four(fitted.rss), four(fitted.rss / stats[:df])]
    sequential = table(['term', 'Df', 'Sum Sq', 'Mean Sq', 'F value', 'Pr(>F)'], rows, marks + [''])
    rows = report[:marginal].map do |entry|
      [entry[:name], entry[:df], four(entry[:ss]), four(entry[:rss]), four(entry[:f]), probability(entry[:p])]
    end
    marks = report[:marginal].map { |entry| significance(entry[:p]) }
    marginal = table(['term', 'Df', 'Sum Sq', 'RSS', 'F value', 'Pr(>F)'], rows, marks)
    [sequential, marginal]
  end

  def diagnostic_summary(report)
    design, fitted, diagnostic, decisions = report.values_at(:design, :fit, :diagnostics, :decisions)
    rows = diagnostic[:rows]
    bp, bp_degrees, bp_pvalue = diagnostic[:bp]
    jb, jb_pvalue, skewness, kurtosis = diagnostic[:jb]
    reset, reset_degrees, reset_residual_df, reset_pvalue = report[:reset]
    outlier = decisions[:outlier]
    counts = decisions[:counts]
    lines = ['Diagnostics:',
             "Durbin-Watson: #{four(diagnostic[:dw])} (#{decisions[:dw_label]})",
             "Breusch-Pagan: #{four(bp)} on #{bp_degrees} DF, " \
               "p-value: #{probability(bp_pvalue)} (#{decisions[:bp_label]})",
             "Jarque-Bera: #{four(jb)} on 2 DF, p-value: #{probability(jb_pvalue)}, " \
               "skewness #{four(skewness)}, kurtosis #{four(kurtosis)} (#{decisions[:jb_label]})",
             "RESET (powers 2 and 3): F #{four(reset)} on #{reset_degrees} and " \
               "#{reset_residual_df} DF, p-value: #{probability(reset_pvalue)}",
             "Outlier test: row #{design.row_numbers[outlier]}, studentized #{four(rows[outlier][:studentized])}, " \
               "unadjusted p-value: #{probability(decisions[:unadjusted])}, " \
               "Bonferroni p-value: #{probability(decisions[:bonferroni])}",
             "Flagged rows: leverage #{counts['H']}, outlier #{counts['O']}, " \
               "cooks #{counts['C']}, dffits #{counts['F']}, any #{counts[:any]}",
             "Largest Cook's distances:"]
    decisions[:largest_cooks].each do |i|
      lines << "row #{design.row_numbers[i]}: cooks_d #{four(rows[i][:cooks])}, " \
               "leverage #{four(fitted.leverage[i])}, studentized #{four(rows[i][:studentized])}, " \
               "flags #{rows[i][:flags]}"
    end
    lines << 'Largest absolute DFBETAS:'
    lines + table(%w[column row DFBETAS], decisions[:largest_dfbetas].map do |name, row_number, value|
      [name, row_number, four(value)]
    end)
  end

  def model_summary(report, total_rows, confidence)
    design, fitted, stats = report.values_at(:design, :fit, :stats)
    aliases = fitted.aliases.map { |j| design.columns[j].name }.join(', ')
    aliases = 'none' if aliases.empty?
    quantiles = stats[:quantiles]
    coefficients, intervals, robust = coefficient_tables(report, confidence)
    sequential, marginal = anova_tables(report)
    lines = ["Model #{report[:number]}: #{design.model.original}",
             'Terms: ' + design.model.terms.map(&:name).join(', '),
             "Weights: #{design.model.weight || 'none'}",
             "Observations: #{fitted.n} used, #{total_rows - fitted.n} dropped",
             "Columns: #{fitted.p}, rank #{fitted.rank}, aliased: #{aliases}", '',
             "Residuals: Min #{four(quantiles[0])}, 1Q #{four(quantiles[1])}, " \
               "Median #{four(quantiles[2])}, 3Q #{four(quantiles[3])}, Max #{four(quantiles[4])}",
             '', 'Coefficients:']
    lines.concat(coefficients)
    lines.concat(['---', "Signif. codes: 0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1", '',
                  "Residual standard error: #{four(stats[:sigma])} on #{stats[:df]} degrees of freedom",
                  "Multiple R-squared: #{four(stats[:r_squared])}, Adjusted R-squared: #{four(stats[:adjusted])}",
                  "F-statistic: #{four(stats[:f])} on #{fitted.rank - 1} and #{stats[:df]} DF, " \
                    "p-value: #{probability(stats[:p])}",
                  "Log-likelihood: #{four(stats[:ll])}, AIC: #{four(stats[:aic])}, BIC: #{four(stats[:bic])}",
                  "PRESS: #{four(stats[:press])}, Predicted R-squared: #{four(stats[:predicted])}", ''])
    lines.concat(intervals)
    lines.concat(['', 'Robust standard errors (HC3):'] + robust)
    lines.concat(['', 'Analysis of variance (sequential):'] + sequential)
    lines.concat(['', 'Marginal F tests (drop one term):'] + marginal)
    lines.concat(['', 'Variance inflation factors:'])
    lines.concat(table(['column', 'VIF'], report[:vif].map { |name, value, _| [name, four(value)] },
                       report[:vif].map { |_, _, high| high ? 'high' : '' }))
    lines + [''] + diagnostic_summary(report)
  end

  def comparison_summary(reports)
    rows = reports.map do |report|
      fitted, stats = report.values_at(:fit, :stats)
      [report[:number], fitted.n, fitted.rank, four(stats[:sigma]), four(stats[:r_squared]),
       four(stats[:adjusted]), four(stats[:predicted]), four(stats[:aic]), four(stats[:bic])]
    end
    table(['model', 'n', 'rank', 'sigma', 'R-squared', 'Adj. R-squared', 'Pred. R-squared', 'AIC', 'BIC'], rows)
  end

  def summary_report(data, reports, params)
    lines = data_summary(data)
    reports.each_with_index do |report, i|
      lines << '' unless i.zero?
      lines.concat(model_summary(report, data.rows.length, params['CONFIDENCE']))
    end
    lines.concat(['', 'Model comparison:'] + comparison_summary(reports) + ['', 'Prediction check:'])
    reports.each do |report|
      predicted, actual, rmse, covered = report[:prediction_check]
      lines << "model #{report[:number]}: #{predicted} predicted, #{actual} with actual values, " \
               "RMSE #{four(rmse)}, inside prediction interval #{covered}"
    end
    lines
  end

  def diagnostics_csv(reports)
    lines = ['model,row,fitted,residual,leverage,studentized,cooks_d,dffits,flags']
    reports.each do |report|
      fitted = report[:fit]
      report[:diagnostics][:rows].each_with_index do |row, i|
        values = [fitted.fitted[i], fitted.residual[i], fitted.leverage[i],
                  row[:studentized], row[:cooks], row[:dffits]]
        lines << ([report[:number], report[:design].row_numbers[i]] +
                  values.map { |value| four(value) } + [row[:flags]]).join(',')
      end
    end
    lines
  end

  def backward_selection(report, params)
    design = report[:design]
    model = design.model
    terms = model.terms.each_index.to_a
    alpha = params['ALPHA_REMOVE']
    lines = ["Backward elimination (model 1, alpha #{four(alpha)}, rows #{design.rows.length})"]
    step = 1
    fitted = report[:fit]
    loop do
      _, aic, = information_criteria(fitted)
      degrees = fitted.n - fitted.rank
      lines << "Step #{step}: #{model.format(terms)} (RSS #{four(fitted.rss)}, df #{degrees}, AIC #{four(aic)})"
      if terms.empty?
        lines << '  stop: no removable terms'
        break
      end
      tests = marginal_tests(design, fitted, terms, params['RANK_TOL'])
      tests.each do |test|
        lines << "  - #{test[:name]}: F #{four(test[:f])} on #{test[:df]} and #{degrees} DF, " \
                 "p-value #{probability(test[:p])}"
      end
      largest = tests.min_by { |test| [-test[:p], test[:index]] }
      if largest[:p] <= alpha
        lines << "  stop: largest p-value #{probability(largest[:p])} is not above #{four(alpha)}"
        break
      end
      lines << "  remove #{largest[:name]}"
      terms = terms.reject { |index| index == largest[:index] }
      fitted = fit_subset(design, terms, params['RANK_TOL'])
      step += 1
    end
    lines + ["Final model: #{model.format(terms)}"]
  end

  def forward_selection(report, params)
    design = report[:design]
    model = design.model
    terms = []
    lines = ["Forward selection by AIC (model 1, rows #{design.rows.length})"]
    step = 1
    loop do
      fitted = fit_subset(design, terms, params['RANK_TOL'])
      _, aic, = information_criteria(fitted)
      lines << "Step #{step}: #{model.format(terms)} (AIC #{four(aic)})"
      candidates = model.candidates(terms)
      if candidates.empty?
        lines << '  stop: no candidate terms remain'
        break
      end
      choices = candidates.map do |index|
        candidate_terms = (terms + [index]).sort
        candidate = fit_subset(design, candidate_terms, params['RANK_TOL'])
        _, candidate_aic, = information_criteria(candidate)
        lines << "  + #{model.terms[index].name}: AIC #{four(candidate_aic)}"
        [index, candidate_aic, candidate_terms]
      end
      index, candidate_aic, candidate_terms = choices.min_by { |choice| [choice[1], choice[0]] }
      if candidate_aic >= aic
        lines << '  stop: no candidate lowers the AIC'
        break
      end
      lines << "  add #{model.terms[index].name}"
      terms = candidate_terms
      step += 1
    end
    lines + ["Final model: #{model.format(terms)}"]
  end

  def best_subsets(report, params)
    design = report[:design]
    model = design.model
    count = model.terms.length
    subsets = (0...(1 << count)).filter_map do |mask|
      terms = (0...count).select { |index| (mask & (1 << index)) != 0 }
      next unless model.hierarchical?(terms)

      fitted = fit_subset(design, terms, params['RANK_TOL'])
      _, aic, bic = information_criteria(fitted)
      [bic, mask, aic, fitted.rank, terms]
    end
    subsets.sort_by! { |bic, mask, _, _, _| [bic, mask] }
    lines = ["Best subsets by BIC (model 1, rows #{design.rows.length}, subsets #{subsets.length})"]
    subsets.first(params['BEST_SUBSETS']).each_with_index do |subset, i|
      bic, _, aic, rank, terms = subset
      lines << "#{i + 1}. BIC #{four(bic)}, AIC #{four(aic)}, rank #{rank}: #{model.format(terms)}"
    end
    lines
  end

  def selection_report(report, params)
    backward_selection(report, params) + [''] + forward_selection(report, params) + [''] +
      best_subsets(report, params)
  end

  def plot_grid(horizontal, vertical, lo, hi, width, height, limit)
    grid = Array.new(height) { Array.new(width, 0) }
    horizontal.zip(vertical).each do |x, y|
      column = [((x - lo) / (hi - lo) * width).floor, width - 1].min
      row = ((limit - y) / (2.0 * limit) * height).floor.clamp(0, height - 1)
      grid[row][column] += 1
    end
    grid
  end

  def plot_frame(grid)
    border = '+' + '-' * grid[0].length + '+'
    lines = grid.each_with_index.map do |row, index|
      empty = index == grid.length / 2 ? '-' : '.'
      cells = row.map { |count| count >= 10 ? '*' : count.positive? ? count.to_s : empty }
      '|' + cells.join + '|'
    end
    [border] + lines + [border]
  end

  def residual_plot(report, params)
    width, height, limit = params['PLOT']
    number, fitted = report.values_at(:number, :fit)
    studentized = report[:diagnostics][:rows].map { |row| row[:studentized] }
    lo, hi = fitted.fitted.minmax
    grid = plot_grid(fitted.fitted, studentized, lo, hi, width, height, limit)
    lines = ["Model #{number}: studentized residuals vs fitted values",
             "fitted #{four(lo)} to #{four(hi)}, studentized #{four(-limit)} to #{four(limit)}"] + plot_frame(grid)
    above = studentized.count { |value| value > 2.0 }
    below = studentized.count { |value| value < -2.0 }
    outside = studentized.count { |value| value.abs > limit }
    lines << "points: #{fitted.n}, above +2: #{above}, below -2: #{below}, outside range: #{outside}"
    lines << 'Histogram of studentized residuals:'
    counts = grid.map { |row| row.inject(0, :+) }
    maximum = counts.max
    counts.each_with_index do |count, index|
      lower = limit - 2.0 * limit * (index + 1) / height
      upper = limit - 2.0 * limit * index / height
      length = (count * 40 + maximum - 1) / maximum
      line = "#{four(lower)} to #{four(upper)}: #{count}"
      line += ' ' + '#' * length if length.positive?
      lines << line
    end
    hi = fitted.leverage.max
    lines.concat(["Model #{number}: studentized residuals vs leverage",
                  "leverage 0.0000 to #{four(hi)}, studentized #{four(-limit)} to #{four(limit)}"])
    lines + plot_frame(plot_grid(fitted.leverage, studentized, 0.0, hi, width, height, limit))
  end

  def predictions_csv(reports)
    ['model,row,fit,se_fit,conf_lower,conf_upper,pred_lower,pred_upper,actual,error,covered'] +
      reports.flat_map { |report| report[:predictions] }
  end

  def plots_report(reports, params)
    reports.each_with_index.flat_map do |report, i|
      (i.zero? ? [] : ['']) + residual_plot(report, params)
    end
  end

  def main
    data = Dataframe.read_csv('input/data.csv')
    model_lines = Dataframe.read_models('input/model.txt')
    prediction_data = Dataframe.read_csv('input/predict.csv', data.kinds)
    params = Dataframe.read_params('input/params.txt')
    reports = model_lines.each_with_index.map do |line, i|
      design = Formula::Design.new(Formula::Model.new(line), data)
      analyze_model(i + 1, design, params, prediction_data)
    end
    contents = {
      'summary.txt' => summary_report(data, reports, params),
      'diagnostics.csv' => diagnostics_csv(reports),
      'selection.txt' => selection_report(reports[0], params),
      'predictions.csv' => predictions_csv(reports),
      'residual_plot.txt' => plots_report(reports, params)
    }
    contents.each { |filename, lines| File.write(File.join('output', filename), lines.join("\n") + "\n") }
  end
end

OLSRegression.main if $PROGRAM_NAME == __FILE__
