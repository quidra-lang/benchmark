require 'fileutils'
require_relative 'dataset'
require_relative 'kernels'
require_relative 'loess'
require_relative 'spline'
require_relative 'selection'

class LinearFit
  attr_reader :fitted, :leverage, :edf

  def initialize(points)
    @x = points.map { |x, _y| x / 100.0 }
    y = points.map { |_x, value| value / 100.0 }
    count = points.length
    @xbar = Selection.sum(@x) / count
    ybar = Selection.sum(y) / count
    @sxx = Selection.sum(@x) { |x| (x - @xbar) * (x - @xbar) }
    sxy = Selection.sum(@x.each_index) { |i| (@x[i] - @xbar) * (y[i] - ybar) }
    @slope = sxy / @sxx
    @intercept = ybar - @slope * @xbar
    @fitted = @x.map { |x| @intercept + @slope * x }
    @leverage = @x.map { |x| 1.0 / count + (x - @xbar) * (x - @xbar) / @sxx }
    @edf = 2.0
  end

  def estimate(position)
    @intercept + @slope * (position / 100.0)
  end

  def weights(position)
    @x.map { |x| 1.0 / @x.length + (position / 100.0 - @xbar) * (x - @xbar) / @sxx }
  end
end

class RunningFit
  attr_reader :fitted, :leverage, :edf

  def initialize(points, width, use_median)
    @positions = points.map(&:first)
    count = points.length
    half = (width - 1) / 2
    @windows, @fitted, diagonal = [], [], []
    count.times do |i|
      radius = [half, i, count - 1 - i].min
      left, right = i - radius, i + radius + 1
      values = points[left...right].map(&:last)
      @windows << [left, right]
      value = if use_median
                values.sort[radius] / 100.0
              else
                values.sum.to_f / (100 * values.length).to_f
              end
      @fitted << value
      diagonal << 1.0 / values.length
    end
    @leverage = use_median ? nil : diagonal
    @edf = use_median ? nil : Selection.sum(diagonal)
  end

  def nearest(position)
    @positions.each_index.min_by { |i| [(@positions[i] - position).abs, i] }
  end

  def estimate(position)
    @fitted[nearest(position)]
  end

  def weights(position)
    left, right = @windows[nearest(position)]
    Array.new(@positions.length) { |i| i >= left && i < right ? 1.0 / (right - left) : 0.0 }
  end
end

class IsotonicFit
  attr_reader :fitted, :leverage, :edf, :mode, :direction, :blocks,
              :rss_increasing, :rss_decreasing, :positions

  def initialize(points, mode)
    @positions, @mode = points.map(&:first), mode
    if mode == 'auto'
      increasing = self.class.fit_direction(points, 'increasing')
      decreasing = self.class.fit_direction(points, 'decreasing')
      observed = points.map { |_x, y| y / 100.0 }
      @rss_increasing = Smoothing.residual_square(observed, increasing.first)
      @rss_decreasing = Smoothing.residual_square(observed, decreasing.first)
      @direction = @rss_increasing <= @rss_decreasing ? 'increasing' : 'decreasing'
      @fitted, @blocks = @direction == 'increasing' ? increasing : decreasing
    else
      @direction = mode
      @fitted, @blocks = self.class.fit_direction(points, mode)
    end
    @leverage = nil
    @edf = @blocks.length.to_f
  end

  def self.fit_direction(points, direction)
    blocks = []
    points.each_with_index do |(_x, value), i|
      blocks << [i, i, value, 1]
      while blocks.length >= 2
        left, right = blocks.last(2)
        a, b = left[2] * right[3], right[2] * left[3]
        violates = direction == 'increasing' ? a > b : a < b
        break unless violates

        blocks.pop(2)
        blocks << [left[0], right[1], left[2] + right[2], left[3] + right[3]]
      end
    end
    fitted = Array.new(points.length, 0.0)
    blocks.each do |first, last, total, count|
      value = total.to_f / (100 * count).to_f
      (first..last).each { |i| fitted[i] = value }
    end
    [fitted, blocks]
  end

  def estimate(position)
    after = @positions.bsearch_index { |x| x > position } || @positions.length
    @fitted[[after - 1, 0].max]
  end
end

class Minstd
  def initialize(seed)
    @state = seed
  end

  def index(count)
    @state = 48_271 * @state % 2_147_483_647
    @state % count
  end
end

module Smoothing
  module_function

  def residual_square(observed, fitted)
    Selection.sum(observed.each_index) do |i|
      error = observed[i] - fitted[i]
      error * error
    end
  end

  def methods_in_order(settings)
    %w[linear running_mean running_median] +
      settings['KERNELS'].map { |name| "nw_#{name}" } +
      settings['KERNELS'].map { |name| "ll_#{name}" } +
      settings['LOESS_DEGREES'].map { |degree| "loess#{degree}" } + %w[spline isotonic]
  end

  def parameters_for(method, settings)
    case method
    when /^running_/ then settings['WINDOWS']
    when /^(nw_|ll_)/ then settings['BANDWIDTHS']
    when /^loess/ then settings['SPANS']
    when 'spline' then settings['LAMBDAS']
    else []
    end
  end

  def fit_model(method, parameter, points, settings, direction, robust: true, diagnostics: true)
    return LinearFit.new(points) if method == 'linear'
    return RunningFit.new(points, parameter.to_i, method == 'running_median') if method.start_with?('running_')
    return IsotonicFit.new(points, direction) if method == 'isotonic'

    positions = points.map(&:first)
    values = points.map { |_x, y| y / 100.0 }
    if method.start_with?('nw_', 'll_')
      KernelFit.new(positions, values, Dataset.hundredths(parameter), method[3..],
                    method.start_with?('ll_'), diagnostics: diagnostics)
    elsif method.start_with?('loess')
      iterations = robust ? settings['ROBUST_ITERATIONS'] : 0
      LoessFit.new(positions, values, Dataset.hundredths(parameter), method[5..].to_i,
                   iterations, diagnostics: diagnostics)
    else
      SplineFit.new(positions, values, parameter.to_f, diagnostics: diagnostics)
    end
  end

  def validation_predictions(method, parameter, points, settings, direction, folds)
    predictions = Array.new(points.length)
    folds.times do |group|
      training = points.each_index.filter_map { |i| points[i] if i % folds != group }
      model = fit_model(method, parameter, training, settings, direction,
                        robust: false, diagnostics: false)
      group.step(points.length - 1, folds) { |i| predictions[i] = model.estimate(points[i][0]) }
    end
    predictions
  end

  def select_models(points, settings, methods, isotonic_mode)
    observed = points.map { |_x, y| y / 100.0 }
    methods.to_h do |method|
      candidates = parameters_for(method, settings).map do |parameter|
        candidate = fit_model(method, parameter, points, settings, isotonic_mode, robust: false)
        score = if method == 'spline'
                  Selection.generalized(observed, candidate.fitted, candidate.edf)
                else
                  predicted = validation_predictions(method, parameter, points, settings,
                                                     isotonic_mode, points.length)
                  Selection.cross_validation(observed, predicted)
                end
        { parameter: parameter, score: score, edf: candidate.edf, selected: false }
      end
      if candidates.empty?
        parameter = method == 'linear' ? '-' : isotonic_mode
      else
        best = Selection.choose(candidates)
        candidates[best][:selected] = true
        parameter = candidates[best][:parameter]
      end
      model = fit_model(method, parameter, points, settings, isotonic_mode)
      direction = method == 'isotonic' ? model.direction : isotonic_mode
      parameter = direction if method == 'isotonic'
      loo = if !candidates.empty? && method != 'spline'
              candidates[best][:score]
            else
              predicted = validation_predictions(method, parameter, points, settings, direction, points.length)
              Selection.cross_validation(observed, predicted)
            end
      kfold = validation_predictions(method, parameter, points, settings, direction, settings['CV_FOLDS'])
      [method, { model: model, parameter: parameter, loo: loo,
                 kfold: Selection.cross_validation(observed, kfold), candidates: candidates,
                 gcv: method == 'spline' ? candidates[best][:score] : nil }]
    end
  end

  def quantiles(residuals)
    ordered = residuals.sort
    Array.new(5) do |k|
      index, remainder = ((ordered.length - 1) * k).divmod(4)
      value = ordered[index]
      value += remainder / 4.0 * (ordered[index + 1] - ordered[index]) unless remainder.zero?
      value
    end
  end

  def residual_runs(residuals)
    signs = residuals.reject(&:zero?).map { |value| value > 0 ? 1 : -1 }
    positive, negative = signs.count(1), signs.count(-1)
    count = positive + negative
    runs = 1 + signs.each_cons(2).count { |a, b| a != b }
    product = 2 * positive * negative
    mean = 1 + product.to_f / count.to_f
    variance = (product * (product - count)).to_f / (count * count * (count - 1)).to_f
    [runs, positive, negative, (runs - mean) / Math.sqrt(variance)]
  end

  def turning_count(grid_values)
    differences = grid_values.compact.each_cons(2).map { |a, b| b - a }.reject(&:zero?)
    differences.each_cons(2).count { |a, b| (a > 0) != (b > 0) }
  end

  def diagnostics(method, model, observed, grid_values, linear_rss)
    residuals = observed.each_index.map { |i| observed[i] - model.fitted[i] }
    count = observed.length
    rss = Selection.sum(residuals) { |value| value * value }
    mean = Selection.sum(observed) / count
    tss = Selection.sum(observed) { |y| (y - mean) * (y - mean) }
    edf = model.edf
    df = edf.nil? ? nil : count - edf
    rse = edf.nil? ? nil : Math.sqrt(rss / df)
    nonlinear = if method != 'linear' && !edf.nil? && edf > 2
                  ((linear_rss - rss) / (edf - 2)) / (rss / df)
                end
    residual_mean = Selection.sum(residuals) / count
    centered = residuals.map { |value| value - residual_mean }
    denominator = Selection.sum(centered) { |value| value * value }
    acf = (1..5).map do |lag|
      Selection.sum(0...(count - lag)) { |i| centered[i] * centered[i + lag] } / denominator
    end
    dw = Selection.sum(1...count) { |i| (residuals[i] - residuals[i - 1]) * (residuals[i] - residuals[i - 1]) } / rss
    largest = residuals.each_index.max_by { |i| [residuals[i].abs, -i] }
    { residuals: residuals, rss: rss, edf: edf, df: df, rse: rse, r2: 1 - rss / tss,
      f_nonlinear: nonlinear, acf: acf, dw: dw, runs: residual_runs(residuals),
      largest: largest, quantiles: quantiles(residuals), turning: turning_count(grid_values) }
  end

  def agreements(entries, methods, ranking, grid)
    best = entries[ranking.first][:grid_values]
    methods.reject { |method| method == ranking.first }.to_h do |method|
      own = entries[method][:grid_values]
      pairs = grid.each_index.filter_map do |i|
        [i, (own[i] - best[i]).abs] unless own[i].nil? || best[i].nil?
      end
      maximum = pairs.max_by { |i, delta| [delta, -i] }
      rms = Math.sqrt(Selection.sum(pairs) { |_i, delta| delta * delta } / pairs.length)
      [method, [pairs.length, rms, maximum[1], grid[maximum[0]]]]
    end
  end

  def spline_slopes(values, grid)
    slopes = (1...(grid.length - 1)).map do |i|
      [i, (values[i + 1] - values[i - 1]) / ((grid[i + 1] - grid[i - 1]) / 100.0)]
    end
    maximum = slopes.max_by { |i, slope| [slope, -i] }
    minimum = slopes.min_by { |i, slope| [slope, i] }
    [maximum[1], grid[maximum[0]], minimum[1], grid[minimum[0]]]
  end

  def outliers_and_influence(entries, ranking, threshold)
    method = ranking.find { |name| !entries[name][:model].leverage.nil? }
    model, stats = entries[method].values_at(:model, :diagnostics)
    standardized, cooks = {}, {}
    model.leverage.each_with_index do |leverage, i|
      next unless leverage < 1

      value = stats[:residuals][i] / (stats[:rse] * Math.sqrt(1 - leverage))
      standardized[i] = value
      cooks[i] = value * value * leverage / ((1 - leverage) * model.edf)
    end
    outliers = standardized.keys.select { |i| standardized[i].abs > threshold }
                           .sort_by { |i| [-standardized[i].abs, i] }
    influential = cooks.keys.sort_by { |i| [-cooks[i], i] }.first(3)
    { method: method, standardized: standardized, cooks: cooks, outliers: outliers, influential: influential }
  end

  def variability_bands(model, rse, grid, z)
    grid.map do |position|
      value = model.estimate(position)
      next [nil, nil, nil, nil] if value.nil?

      se = rse * Math.sqrt(Selection.sum(model.weights(position)) { |weight| weight * weight })
      [value, se, value - z * se, value + z * se]
    end
  end

  def band_summary(entry, positions, bands, z)
    errors = bands.filter_map { |value, se, _lower, _upper| se unless value.nil? }
    rse = entry[:diagnostics][:rse]
    covered = positions.each_index.count do |i|
      se = rse * Math.sqrt(Selection.sum(entry[:model].weights(positions[i])) { |weight| weight * weight })
      entry[:diagnostics][:residuals][i].abs <= z * Math.sqrt(rse * rse + se * se)
    end
    [Selection.sum(errors) / errors.length, covered]
  end

  def bootstrap_intervals(entry, grid, count, trim, generator)
    model, stats = entry.values_at(:model, :diagnostics)
    residuals = stats[:residuals]
    mean = Selection.sum(residuals) / residuals.length
    centered = residuals.map { |value| value - mean }
    estimates = Array.new(grid.length) { [] }
    count.times do
      response = model.fitted.map { |value| value + centered[generator.index(centered.length)] }
      fit = model.fit_values(response)
      grid.each_with_index { |position, i| estimates[i] << model.evaluate_fit(fit, position) }
    end
    grid.each_index.map do |i|
      values = estimates[i]
      average = Selection.sum(values) / count
      variance = Selection.sum(values) { |value| (value - average) * (value - average) } / (count - 1)
      ordered = values.sort
      [model.estimate(grid[i]), Math.sqrt(variance), ordered[trim], ordered[count - trim - 1]]
    end
  end

  def analyze_series(points, settings, methods, mode, generator)
    positions = points.map(&:first)
    values = points.map { |_x, y| y / 100.0 }
    count = settings['GRID_POINTS']
    grid = Array.new(count) { |k| positions[0] + k * (positions[-1] - positions[0]) / (count - 1) }
    entries = select_models(points, settings, methods, mode)
    linear_rss = residual_square(values, entries['linear'][:model].fitted)
    entries.each do |method, entry|
      entry[:grid_values] = grid.map { |position| entry[:model].estimate(position) }
      entry[:diagnostics] = diagnostics(method, entry[:model], values, entry[:grid_values], linear_rss)
    end
    ranking = methods.each_with_index.sort_by { |method, i| [entries[method][:loo], i] }.map(&:first)
    bands, summaries = {}, {}
    settings['BAND_METHODS'].each do |method|
      entry = entries[method]
      bands[method] = variability_bands(entry[:model], entry[:diagnostics][:rse], grid, settings['BAND_Z'])
      summaries[method] = band_summary(entry, positions, bands[method], settings['BAND_Z'])
    end
    repetitions, trim, _seed = settings['BOOTSTRAP']
    bands['spline_bootstrap'] = bootstrap_intervals(entries['spline'], grid, repetitions, trim, generator)
    { points: points, grid: grid, entries: entries, ranking: ranking,
      agreement: agreements(entries, methods, ranking, grid),
      slope: spline_slopes(entries['spline'][:grid_values], grid),
      outlier: outliers_and_influence(entries, ranking, settings['OUTLIER_THRESHOLD']),
      bands: bands, band_summary: summaries }
  end

  def real(value, places = 4)
    return 'NA' if value.nil?

    result = format("%.#{places}f", value)
    zero = format("%.#{places}f", 0.0)
    result == "-#{zero}" ? zero : result
  end

  def position_text(value)
    whole, fraction = value.abs.divmod(100)
    (value < 0 ? '-' : '') + format('%d.%02d', whole, fraction)
  end

  def real_list(values)
    values.map { |value| real(value) }.join(' ')
  end

  def write_lines(name, lines)
    File.write(File.join('output', name), lines.join("\n") + "\n", encoding: 'US-ASCII')
  end

  def join_blocks(blocks)
    blocks.flat_map.with_index { |block, i| i.zero? ? block : [''] + block }
  end

  def selection_lines(analyses, methods)
    lines = ['series,method,parameter,score,edf,selected']
    analyses.each do |name, analysis|
      methods.each do |method|
        analysis[:entries][method][:candidates].each do |candidate|
          lines << [name, method, candidate[:parameter], real(candidate[:score]),
                    real(candidate[:edf]), candidate[:selected] ? '1' : '0'].join(',')
        end
      end
    end
    lines
  end

  def fit_lines(analyses, methods)
    lines = ['series,x,' + methods.join(',')]
    analyses.each do |name, analysis|
      analysis[:grid].each_with_index do |position, i|
        values = methods.map { |method| real(analysis[:entries][method][:grid_values][i]) }
        lines << ([name, position_text(position)] + values).join(',')
      end
    end
    lines
  end

  def prediction_lines(analyses, tests, methods)
    lines = ['series,x,' + methods.join(',')]
    tests.each do |name, position|
      values = methods.map { |method| real(analyses[name][:entries][method][:model].estimate(position)) }
      lines << ([name, position_text(position)] + values).join(',')
    end
    lines
  end

  def band_lines(analyses, settings)
    lines = ['series,method,x,fit,se,lower,upper']
    analyses.each do |name, analysis|
      (settings['BAND_METHODS'] + ['spline_bootstrap']).each do |method|
        analysis[:grid].each_with_index do |position, i|
          values = analysis[:bands][method][i].map { |value| real(value) }
          lines << ([name, method, position_text(position)] + values).join(',')
        end
      end
    end
    lines
  end

  def method_diagnostic_lines(method, entry, points)
    stats = entry[:diagnostics]
    first = "method #{method} parameter #{entry[:parameter]} loo #{real(entry[:loo])}"
    first += " gcv #{real(entry[:gcv])}" if method == 'spline'
    runs, positive, negative, z = stats[:runs]
    largest = stats[:largest]
    lines = [first,
             "  rss #{real(stats[:rss])} edf #{real(stats[:edf])} df #{real(stats[:df])} " \
             "rse #{real(stats[:rse])} r2 #{real(stats[:r2])} f_nonlinear #{real(stats[:f_nonlinear])}",
             "  acf #{real_list(stats[:acf])} dw #{real(stats[:dw])}",
             "  runs #{runs} positive #{positive} negative #{negative} z #{real(z)}",
             "  max_residual #{real(stats[:residuals][largest])} at #{position_text(points[largest][0])} turning #{stats[:turning]}",
             '  quantiles ' + real_list(stats[:quantiles])]
    if method.start_with?('loess')
      model = entry[:model]
      model.records.each do |iteration, scale, zero_count, change|
        lines << "  robust #{iteration} scale #{real(scale)} zero_weight #{zero_count} max_change #{real(change)}"
      end
      zero_points = points.each_index.filter_map { |i| position_text(points[i][0]) if model.rho[i].zero? }
      lines << '  zero_weight_points ' + (zero_points.empty? ? 'none' : zero_points.join(' '))
    end
    lines
  end

  def comparison_diagnostic_lines(analysis, methods)
    entries, ranking = analysis.values_at(:entries, :ranking)
    lines = ['ranking']
    ranking.each_with_index do |method, i|
      lines << "  #{i + 1} #{method} #{real(entries[method][:loo])} kfold #{real(entries[method][:kfold])}"
    end
    lines << 'agreement with ' + ranking.first
    methods.each do |method|
      next if method == ranking.first

      count, rms, maximum, position = analysis[:agreement][method]
      lines << "  #{method} points #{count} rms #{real(rms)} max #{real(maximum)} at #{position_text(position)}"
    end
    maximum, at_max, minimum, at_min = analysis[:slope]
    lines << "slope spline max #{real(maximum)} at #{position_text(at_max)} min #{real(minimum)} at #{position_text(at_min)}"
    lines
  end

  def outlier_diagnostic_lines(analysis, settings)
    data = analysis[:outlier]
    entry = analysis[:entries][data[:method]]
    model, residuals, points = entry[:model], entry[:diagnostics][:residuals], analysis[:points]
    lines = ["outliers method #{data[:method]} threshold #{real(settings['OUTLIER_THRESHOLD'], 2)}"]
    data[:outliers].each do |i|
      lines << "  x #{position_text(points[i][0])} y #{position_text(points[i][1])} " \
               "fit #{real(model.fitted[i])} residual #{real(residuals[i])} standardized #{real(data[:standardized][i])}"
    end
    lines << '  none' if data[:outliers].empty?
    lines << 'influence method ' + data[:method]
    data[:influential].each do |i|
      lines << "  x #{position_text(points[i][0])} lev #{real(model.leverage[i])} cook #{real(data[:cooks][i])}"
    end
    lines << 'bands'
    settings['BAND_METHODS'].each do |method|
      mean_se, covered = analysis[:band_summary][method]
      lines << "  #{method} mean_se #{real(mean_se)} coverage #{covered} of #{points.length}"
    end
    lines
  end

  def diagnostics_block(name, analysis, methods, settings)
    points = analysis[:points]
    low, high = points.map(&:last).minmax
    lines = ["series #{name} n #{points.length} x #{position_text(points[0][0])} #{position_text(points[-1][0])} " \
             "y #{position_text(low)} #{position_text(high)}"]
    methods.each { |method| lines.concat(method_diagnostic_lines(method, analysis[:entries][method], points)) }
    lines.concat(comparison_diagnostic_lines(analysis, methods))
    lines.concat(outlier_diagnostic_lines(analysis, settings))
  end

  def isotonic_block(name, analysis)
    entry = analysis[:entries]['isotonic']
    model = entry[:model]
    first = "series #{name} direction #{model.direction} mode #{model.mode}"
    if model.mode == 'auto'
      first += " rss_increasing #{real(model.rss_increasing)} rss_decreasing #{real(model.rss_decreasing)}"
    end
    lines = [first, "blocks #{model.blocks.length} rss #{real(entry[:diagnostics][:rss])} loo #{real(entry[:loo])}"]
    model.blocks.each_with_index do |(start, stop, total, count), i|
      lines << "block #{i + 1} x #{position_text(model.positions[start])} #{position_text(model.positions[stop])} " \
               "count #{count} value #{real(total.to_f / (100 * count).to_f)}"
    end
    lines
  end

  def framed(grid)
    border = '+' + '-' * grid[0].length + '+'
    [border] + grid.map { |row| '|' + row.join + '|' } + [border]
  end

  def histogram_lines(standardized)
    counts = Array.new(14, 0)
    standardized.each_value do |value|
      index = if value < -3
                0
              elsif value >= 3
                13
              else
                1 + ((value + 3) / 0.5).floor
              end
      counts[index] += 1
    end
    counts.each_with_index.map do |count, i|
      lower = i.zero? ? '-inf' : real(-3 + 0.5 * (i - 1), 2)
      upper = i == 13 ? 'inf' : real(-3 + 0.5 * i, 2)
      "#{lower} #{upper} #{count} |" + '#' * count
    end
  end

  def plot_block(name, analysis, settings)
    points = analysis[:points]
    width, height = settings['PLOT_SIZE']
    xa, xb = points[0][0], points[-1][0]
    ya, yb = points.map(&:last).minmax
    columns = points.map { |x, _y| [width - 1, width * (x - xa) / (xb - xa)].min }
    grid = Array.new(height) { Array.new(width, ' ') }
    points.each_with_index do |(_x, y), i|
      row = [height - 1, height * (yb - y) / (yb - ya)].min
      grid[row][columns[i]] = '.'
    end
    ymin, ymax = ya / 100.0, yb / 100.0
    settings['PLOT_METHODS'].each_with_index do |method, i|
      model, digit = analysis[:entries][method][:model], (i + 1).to_s
      width.times do |column|
        position = xa + (2 * column + 1) * (xb - xa) / (2 * width)
        value = model.estimate(position)
        next if value.nil?

        row = (height * (ymax - value) / (ymax - ymin)).floor.clamp(0, height - 1)
        grid[row][column] = [' ', '.', digit].include?(grid[row][column]) ? digit : '*'
      end
    end
    cells = grid.map(&:join).join
    legend = settings['PLOT_METHODS'].each_with_index.map { |method, i| "#{i + 1} #{method}" }.join(' ')
    lines = ["plot #{name} size #{width}x#{height} x #{position_text(xa)} #{position_text(xb)} " \
             "y #{position_text(ya)} #{position_text(yb)}", 'legend . data ' + legend]
    lines.concat(framed(grid))
    lines << "cells data #{cells.count('.')} curve #{cells.count('1-9')} overlap #{cells.count('*')}"
    method = analysis[:ranking].first
    residuals = analysis[:entries][method][:diagnostics][:residuals]
    limit = residuals.map(&:abs).max
    grid = Array.new(height) { Array.new(width, ' ') }
    grid[height / 2] = Array.new(width, '-')
    residuals.each_with_index do |residual, i|
      row = (height * ((limit - residual) / (2 * limit))).floor.clamp(0, height - 1)
      grid[row][columns[i]] = 'o'
    end
    lines.concat(['', "residuals #{name} method #{method} limit #{real(limit)}"])
    lines.concat(framed(grid))
    lines.concat(['', "histogram #{name} method #{analysis[:outlier][:method]}"])
    lines.concat(histogram_lines(analysis[:outlier][:standardized]))
  end

  def main
    series, tests, settings = Dataset.read
    methods = methods_in_order(settings)
    generator = Minstd.new(settings['BOOTSTRAP'][2])
    analyses = {}
    series.each_with_index do |(name, points), i|
      analyses[name] = analyze_series(points, settings, methods, settings['ISOTONIC'][i], generator)
    end
    FileUtils.mkdir_p('output')
    write_lines('selection.csv', selection_lines(analyses, methods))
    write_lines('fits.csv', fit_lines(analyses, methods))
    write_lines('predictions.csv', prediction_lines(analyses, tests, methods))
    write_lines('bands.csv', band_lines(analyses, settings))
    write_lines('diagnostics.txt', join_blocks(analyses.map do |name, analysis|
      diagnostics_block(name, analysis, methods, settings)
    end))
    write_lines('isotonic.txt', join_blocks(analyses.map { |name, analysis| isotonic_block(name, analysis) }))
    write_lines('plots.txt', join_blocks(settings['PLOT_SERIES'].map { |name| plot_block(name, analyses[name], settings) }))
  end
end

Smoothing.main if $PROGRAM_NAME == __FILE__
