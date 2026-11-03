require_relative 'series_io'
require_relative 'decomposition'
require_relative 'smoothing'
require_relative 'autoregression'
require_relative 'evaluation'

module TimeSeriesForecasting
  extend self
  include SeriesIO
  include Decomposition

  METHODS = %w[naive snaive drift ses holt damped hw_add hw_mult decomp_add decomp_mult ar].freeze
  MODELS = (METHODS + ['combo']).freeze
  SMOOTHING_PARAMETERS = {
    'ses' => %i[alpha], 'holt' => %i[alpha beta], 'damped' => %i[alpha beta phi],
    'hw_add' => %i[alpha beta gamma], 'hw_mult' => %i[alpha beta gamma]
  }.freeze
  INTERVAL_FIELDS = %i[forecast lo80 hi80 lo95 hi95].freeze
  ACCURACY_FIELDS = %i[me mae rmse mape smape mase fva cv_rmse cover80 cover95 winkler80 winkler95 rank].freeze

  def rmse(errors)
    Math.sqrt(total(errors.map { |error| error * error }) / errors.length)
  end

  def interpolate_missing(raw)
    values = raw.map { |value| value&.to_f }
    left = 0
    while left < raw.length - 1
      right = left + 1
      right += 1 while raw[right].nil?
      ((left + 1)...right).each do |t|
        values[t] = raw[left] + (raw[right] - raw[left]) * (t - left).to_f / (right - left)
      end
      left = right
    end
    values
  end

  def future_periods(last, horizon)
    Array.new(horizon) { last = next_month(last) }
  end

  def prepare_series(record, events, settings)
    season = settings[:season]
    periods = record[:periods]
    raw = record[:raw]
    values = interpolate_missing(raw)
    missing = raw.each_index.select { |t| raw[t].nil? }
    decomposition = decompose(values, season)
    trend = decomposition[:trend]
    additive = decomposition[:additive]
    residuals = decomposition[:residual_add]
    defined = decomposition[:defined]
    residual_values = defined.map { |t| residuals[t] }
    average = mean(residual_values)
    variance_r = sample_variance(residual_values)
    deviation = Math.sqrt(variance_r)
    past = {}
    periods.each_with_index { |period, t| past[t] = events[period] if events.key?(period) }
    outliers = {}
    defined.each do |t|
      next if missing.include?(t) || past.key?(t)

      difference = residuals[t] - average
      outliers[t] = difference / deviation if difference.abs > settings[:outlier] * deviation
    end
    grouped = {}
    past.each { |t, kind| (grouped[kind] ||= []) << t }
    lifts = grouped.to_h do |kind, times|
      lift = mean(times.map { |t| values[t] / (trend[t] + additive[t % season]) })
      [kind, { occurrences: times.length, lift: }]
    end
    corrected = values.each_with_index.map do |value, t|
      past.key?(t) || outliers.key?(t) ? trend[t] + additive[t % season] : value
    end
    variance_t = sample_variance(defined.map { |t| trend[t] + residuals[t] })
    variance_s = sample_variance(defined.map { |t| additive[t % season] + residuals[t] })
    {
      periods:, raw:, values:, corrected:, missing:, past:, events:, outliers:, lifts:, decomposition:,
      future_periods: future_periods(periods.last, settings[:horizon]),
      strength_trend: [0.0, 1 - variance_r / variance_t].max,
      strength_seasonal: [0.0, 1 - variance_r / variance_s].max
    }
  end

  def decomposition_prediction(model, time)
    base = model[:intercept] + model[:slope] * (time + 1)
    seasonal = model[:seasonal][time % model[:season]]
    model[:name] == 'decomp_add' ? base + seasonal : base * seasonal
  end

  def fit_ar(values, settings)
    candidates = Autoregression::KINDS.map do |kind|
      transformed, offset = Autoregression.difference(values, settings[:season], kind)
      average, variance, = Autoregression.autocorrelation(transformed, 0)
      { kind:, values: transformed, offset:, mean: average, variance: }
    end
    selected = candidates.each_with_index.min_by { |candidate, i| [candidate[:variance], i] }.first
    transformed = selected[:values]
    average, variance, correlations = Autoregression.autocorrelation(transformed, settings[:max_lag])
    coefficients, partial, variances = Autoregression.durbin_levinson(correlations)
    aic = (0..settings[:max_ar]).map { |p| transformed.length * Math.log(variance * variances[p]) + 2 * p }
    order = aic.each_index.min_by { |p| [aic[p], p] }
    fitted_coefficients = coefficients[order]
    {
      kind: selected[:kind], differenced: transformed, offset: selected[:offset], mean: average, order:,
      variances: candidates.map { |candidate| candidate[:variance] }, sigma2: variance * variances[order],
      aic:, coefficients: fitted_coefficients, correlations:, partial:,
      residuals: Autoregression.residuals(transformed, average, fitted_coefficients)
    }
  end

  def parameter_grid(names, settings, index = 0, current = {}, &block)
    if index == names.length
      yield current
    else
      key = names[index]
      settings[key].each do |value|
        parameter_grid(names, settings, index + 1, current.merge(key => value), &block)
      end
    end
  end

  def fit_method(name, values, settings)
    season = settings[:season]
    count = values.length
    model = { name:, series: values, season: }
    case name
    when 'naive'
      errors = (1...count).map { |t| values[t] - values[t - 1] }
    when 'snaive'
      errors = (season...count).map { |t| values[t] - values[t - season] }
    when 'drift'
      model[:slope] = (values.last - values.first) / (count - 1)
      errors = (1...count).map { |t| values[t] - values[t - 1] - model[:slope] }
    when 'decomp_add', 'decomp_mult'
      components = decompose(values, season)
      additive = name == 'decomp_add'
      indices = components[additive ? :additive : :multiplicative]
      adjusted = values.each_with_index.map do |value, t|
        additive ? value - indices[t % season] : value / indices[t % season]
      end
      model[:intercept], model[:slope] = least_squares_line(adjusted)
      model[:seasonal] = indices
      errors = values.each_with_index.map { |value, t| value - decomposition_prediction(model, t) }
    when 'ar'
      model.merge!(fit_ar(values, settings))
      errors = model[:residuals]
    else
      best_score = nil
      parameter_grid(SMOOTHING_PARAMETERS.fetch(name), settings) do |parameters|
        residuals, states = Smoothing.recurse(name, values, season, parameters)
        score = total(residuals.map { |error| error * error })
        next unless best_score.nil? || score < best_score

        best_score = score
        model[:parameters] = parameters
        model[:states] = states
        errors = residuals
      end
    end
    model[:residuals] = errors
    model
  end

  def combination_model(members, values, season)
    { name: 'combo', members:, series: values, season: }
  end

  def forecast(model, origin, steps)
    name = model[:name]
    values = model[:series]
    season = model[:season]
    case name
    when 'combo'
      predictions = model[:members].map { |member| forecast(member, origin, steps) }
      Array.new(steps) { |i| total(predictions.map { |row| row[i] }) / predictions.length }
    when 'naive'
      Array.new(steps, values[origin - 1])
    when 'snaive'
      Array.new(steps) { |i| values[origin - season + i % season] }
    when 'drift'
      slope = (values[origin - 1] - values.first) / (origin - 1)
      (1..steps).map { |step| values[origin - 1] + step * slope }
    when 'decomp_add', 'decomp_mult'
      Array.new(steps) { |i| decomposition_prediction(model, origin + i) }
    when 'ar'
      Autoregression.forecast(model, origin, steps)
    else
      Smoothing.forecast(name, model[:states][origin], model[:parameters], origin, steps, season)
    end
  end

  # Parameters stay fixed at their fitted values; smoothing uses its saved state
  # at each origin, rather than selecting parameters again for every prefix.
  def cross_validate(model, settings)
    values = model[:series]
    horizon = settings[:horizon]
    counts = Array.new(horizon, 0)
    squared = Array.new(horizon, 0.0)
    absolute = Array.new(horizon, 0.0)
    (settings[:cv_start]...values.length).each do |origin|
      predictions = forecast(model, origin, [horizon, values.length - origin].min)
      predictions.each_with_index do |prediction, i|
        error = values[origin + i] - prediction
        counts[i] += 1
        squared[i] += error * error
        absolute[i] += error.abs
      end
    end
    sigma = squared.each_with_index.map { |value, i| Math.sqrt(value / counts[i]) }
    mae = absolute.each_with_index.map { |value, i| value / counts[i] }
    holdout = settings[:holdout]
    cv_rmse = Math.sqrt(total(squared.first(holdout)) / total(counts.first(holdout)))
    { counts:, sigma:, mae:, cv_rmse: }
  end

  def interval_rows(predicted, sigma, coefficients, multipliers = nil)
    multipliers ||= Array.new(predicted.length, 1.0)
    low_factor, high_factor = coefficients
    predicted.each_with_index.map do |value, i|
      error = sigma[i]
      multiplier = multipliers[i]
      {
        forecast: value * multiplier,
        lo80: (value - low_factor * error) * multiplier,
        hi80: (value + low_factor * error) * multiplier,
        lo95: (value - high_factor * error) * multiplier,
        hi95: (value + high_factor * error) * multiplier
      }
    end
  end

  def evaluate_holdout(models, cvs, actual, training, settings)
    scale = Evaluation.seasonal_scale(training, settings[:season])
    metrics = {}
    intervals = {}
    MODELS.each do |name|
      predicted = forecast(models[name], training.length, actual.length)
      rows = interval_rows(predicted, cvs[name][:sigma], settings[:interval])
      intervals[name] = rows
      measures = Evaluation.accuracy(actual, predicted, scale)
      measures[:cv_rmse] = cvs[name][:cv_rmse]
      measures[:cover80] = rows.zip(actual).count { |row, value| row[:lo80] <= value && value <= row[:hi80] }
      measures[:cover95] = rows.zip(actual).count { |row, value| row[:lo95] <= value && value <= row[:hi95] }
      measures[:winkler80] = total(rows.zip(actual).map do |row, value|
        Evaluation.winkler(value, row[:lo80], row[:hi80], 10)
      end) / actual.length
      measures[:winkler95] = total(rows.zip(actual).map do |row, value|
        Evaluation.winkler(value, row[:lo95], row[:hi95], 40)
      end) / actual.length
      metrics[name] = measures
    end
    naive_mae = metrics['naive'][:mae]
    metrics.each_value { |measures| measures[:fva] = 100 * (naive_mae - measures[:mae]) / naive_mae }
    ranking = Evaluation.rank_models(MODELS, metrics)
    ranking.each_with_index { |name, i| metrics[name][:rank] = i + 1 }
    [metrics, intervals, ranking.first]
  end

  def inventory_plan(model, demands, policy, settings)
    lead = policy[:lead_time]
    review = policy[:review]
    protection = lead + review
    values = model[:series]
    errors = (settings[:cv_start]..(values.length - protection)).map do |origin|
      predictions = forecast(model, origin, protection)
      total(predictions.each_with_index.map { |prediction, i| values[origin + i] - prediction })
    end
    safety = policy[:service] * rmse(errors)
    reviews = (1..(demands.length - protection + 1)).step(review).to_a
    last_step = reviews.last - 1 + protection
    on_hand = policy[:on_hand].to_f
    outstanding = 0
    receipts = {}
    rows = []
    orders = 0
    ordered = 0
    (1..last_step).each do |step|
      receipt = receipts.delete(step) || 0
      on_hand += receipt
      outstanding -= receipt
      row = { step:, receipt:, demand: demands[step - 1] }
      if reviews.include?(step)
        position = on_hand + outstanding
        target = total(demands[step - 1, protection]) + safety
        quantity = [0, (target - position).ceil].max
        row[:review] = { position:, target:, order: quantity }
        if quantity.positive?
          orders += 1
          ordered += quantity
          outstanding += quantity
          receipts[step + lead] = quantity
        end
      end
      on_hand -= demands[step - 1]
      row[:on_hand] = on_hand
      row[:status] = if on_hand < 0
                       'short'
                     elsif on_hand < safety
                       'low'
                     else
                       'ok'
                     end
      rows << row
    end
    stocks = rows.map { |row| row[:on_hand] }
    {
      safety:, rows:, orders:, ordered:, short_periods: rows.count { |row| row[:status] == 'short' },
      lowest: stocks.min, average: mean(stocks)
    }
  end

  def yearly_totals(periods, actual, future, demands)
    years = Hash.new do |hash, year|
      hash[year] = { actual_months: 0, actual: 0.0, forecast_months: 0, forecast: 0.0 }
    end
    periods.zip(actual).each do |period, value|
      row = years[period[0, 4]]
      row[:actual_months] += 1
      row[:actual] += value
    end
    future.zip(demands).each do |period, value|
      row = years[period[0, 4]]
      row[:forecast_months] += 1
      row[:forecast] += value
    end
    previous = nil
    years.keys.sort.map do |year|
      row = years[year]
      row[:year] = year
      row[:total] = row[:actual] + row[:forecast]
      complete = row[:actual_months] + row[:forecast_months] == 12
      row[:growth] = nil
      if complete && previous && previous[:actual_months] + previous[:forecast_months] == 12
        row[:growth] = 100 * (row[:total] - previous[:total]) / previous[:total]
      end
      previous = row
      row
    end
  end

  def residual_diagnostics(errors, lags)
    count = errors.length
    average = mean(errors)
    centered = errors.map { |error| error - average }
    squared = total(centered.map { |value| value * value })
    m2 = squared / count
    m3 = total(centered.map { |value| value * value * value }) / count
    m4 = total(centered.map { |value| value * value * value * value }) / count
    sd = Math.sqrt(squared / (count - 1))
    dw = total((1...count).map { |i| (errors[i] - errors[i - 1]) * (errors[i] - errors[i - 1]) }) /
         total(errors.map { |value| value * value })
    skewness = m3 / (m2 * Math.sqrt(m2))
    kurtosis = m4 / (m2 * m2) - 3
    jb = count / 6.0 * (skewness * skewness + kurtosis * kurtosis / 4)
    { count:, mean: average, sd:, dw:, skewness:, kurtosis:, jb:,
      ljung_box: Autoregression.ljung_box(errors, lags) }
  end

  def analyze(record, events, policy, settings)
    data = prepare_series(record, events, settings)
    training_count = data[:values].length - settings[:holdout]
    training = data[:corrected].first(training_count)
    actual = data[:values].drop(training_count)
    models = METHODS.to_h { |name| [name, fit_method(name, training, settings)] }
    cvs = METHODS.to_h { |name| [name, cross_validate(models[name], settings)] }
    selected = METHODS.each_with_index.sort_by { |name, i| [cvs[name][:cv_rmse], i] }
                      .first(settings[:combo]).map(&:first)
    members = METHODS.select { |name| selected.include?(name) }
    models['combo'] = combination_model(members.map { |name| models[name] }, training, settings[:season])
    cvs['combo'] = cross_validate(models['combo'], settings)
    metrics, intervals, best = evaluate_holdout(models, cvs, actual, training, settings)
    final_names = best == 'combo' ? members : [best]
    final_fits = final_names.to_h { |name| [name, fit_method(name, data[:corrected], settings)] }
    final = if best == 'combo'
              combination_model(final_fits.values, data[:corrected], settings[:season])
            else
              final_fits[best]
            end
    final_cv = cross_validate(final, settings)
    future = forecast(final, data[:values].length, settings[:horizon])
    multipliers = data[:future_periods].map do |period|
      events.key?(period) ? data[:lifts][events[period]][:lift] : 1.0
    end
    future_rows = interval_rows(future, final_cv[:sigma], settings[:interval], multipliers)
    demands = future_rows.map { |row| row[:forecast] }
    data.merge(
      training_count:, models:, cv: cvs, members:, metrics:, intervals:, best:, final_fits:, future_rows:, policy:,
      plan: inventory_plan(final, demands, policy, settings),
      years: yearly_totals(data[:periods], data[:values], data[:future_periods], demands),
      residual_diagnostics: METHODS.to_h do |name|
        [name, residual_diagnostics(models[name][:residuals], settings[:ljung_box])]
      end
    )
  end

  def model_lines(model)
    name = model[:name]
    residuals = model[:residuals]
    common = "rmse #{real(rmse(residuals))} residuals #{residuals.length}"
    case name
    when 'naive', 'snaive'
      ["#{name} #{common}"]
    when 'drift'
      ["drift slope #{real(model[:slope])} #{common}"]
    when 'decomp_add', 'decomp_mult'
      ["#{name} intercept #{real(model[:intercept])} slope #{real(model[:slope])} #{common}",
       "#{name} seasonal " + model[:seasonal].map { |value| real(value) }.join(' ')]
    when 'ar'
      variance = Autoregression::KINDS.zip(model[:variances]).map do |kind, value|
        "#{kind} #{real(value)}"
      end.join(' ')
      coefficients = model[:coefficients].empty? ? 'none' : model[:coefficients].map { |value| real(value) }.join(' ')
      ["ar variance #{variance}",
       "ar difference #{model[:kind]} n #{model[:differenced].length} mean #{real(model[:mean])} " \
       "order #{model[:order]} sigma2 #{real(model[:sigma2])} #{common}",
       'ar aic ' + model[:aic].map { |value| real(value) }.join(' '),
       "ar coefficients #{coefficients}"]
    else
      parameters = SMOOTHING_PARAMETERS[name].map do |key|
        "#{key} #{real(model[:parameters][key])}"
      end.join(' ')
      level, slope, seasonal = model[:states].last
      first = "#{name} #{parameters} #{common} level #{real(level)}"
      first += " slope #{real(slope)}" unless name == 'ses'
      lines = [first]
      if seasonal
        origin = model[:series].length
        rotated = Array.new(model[:season]) { |i| seasonal[(origin + i) % model[:season]] }
        lines << "#{name} seasonal " + rotated.map { |value| real(value) }.join(' ')
      end
      lines
    end
  end

  def decomposition_lines(analyses, settings)
    lines = ['series,period,value,cleaned,trend,seasonal_add,residual_add,seasonal_mult,residual_mult,flag']
    season = settings[:season]
    analyses.each do |name, data|
      decomposition = data[:decomposition]
      data[:periods].each_with_index do |period, t|
        flag = if data[:past].key?(t)
                 data[:past][t]
               elsif data[:missing].include?(t)
                 'missing'
               elsif data[:outliers].key?(t)
                 'outlier'
               else
                 'ok'
               end
        values = [data[:values][t], data[:corrected][t], decomposition[:trend][t],
                  decomposition[:additive][t % season], decomposition[:residual_add][t],
                  decomposition[:multiplicative][t % season], decomposition[:residual_mult][t]]
        lines << ([name, period] + values.map { |value| real(value) } + [flag]).join(',')
      end
    end
    lines
  end

  def fitted_model_lines(analyses, settings)
    lines = []
    analyses.each do |name, data|
      lines << "series #{name}"
      lines << "data observations #{data[:values].length} train #{data[:training_count]} " \
               "holdout #{settings[:holdout]} missing #{data[:missing].length} " \
               "outliers #{data[:outliers].length} events #{data[:past].length}"
      data[:lifts].each do |kind, lift|
        lines << "event #{kind} occurrences #{lift[:occurrences]} lift #{real(lift[:lift])}"
      end
      data[:outliers].each do |t, score|
        lines << "outlier #{data[:periods][t]} value #{real(data[:values][t])} " \
                 "expected #{real(data[:corrected][t])} score #{real(score)}"
      end
      lines << "strength trend #{real(data[:strength_trend])} seasonal #{real(data[:strength_seasonal])}"
      METHODS.each { |method| lines.concat(model_lines(data[:models][method])) }
      lines << 'combo members ' + data[:members].join(' ')
      lines << "best #{data[:best]} rmse #{real(data[:metrics][data[:best]][:rmse])}"
      data[:final_fits].each_value do |model|
        lines.concat(model_lines(model).map { |line| 'final ' + line })
      end
    end
    lines
  end

  def forecast_lines(analyses)
    lines = ['series,stage,method,period,actual,forecast,lo80,hi80,lo95,hi95']
    analyses.each do |name, data|
      start = data[:training_count]
      MODELS.each do |method|
        data[:intervals][method].each_with_index do |row, i|
          prefix = [name, 'holdout', method, data[:periods][start + i], data[:raw][start + i]]
          lines << (prefix + INTERVAL_FIELDS.map { |key| real(row[key]) }).join(',')
        end
      end
      data[:future_periods].zip(data[:future_rows]).each do |period, row|
        prefix = [name, 'future', data[:best], period, 'NA']
        lines << (prefix + INTERVAL_FIELDS.map { |key| real(row[key]) }).join(',')
      end
    end
    lines
  end

  def accuracy_lines(analyses)
    lines = ['series,method,' + ACCURACY_FIELDS.join(',')]
    analyses.each do |name, data|
      MODELS.each do |method|
        values = data[:metrics][method]
        fields = ACCURACY_FIELDS.map do |key|
          %i[cover80 cover95 rank].include?(key) ? values[key].to_s : real(values[key])
        end
        lines << ([name, method] + fields).join(',')
      end
    end
    lines
  end

  def cross_validation_lines(analyses)
    lines = ['series,method,step,origins,mae,rmse']
    analyses.each do |name, data|
      MODELS.each do |method|
        cv = data[:cv][method]
        cv[:counts].each_with_index do |count, i|
          lines << [name, method, i + 1, count, real(cv[:mae][i]), real(cv[:sigma][i])].join(',')
        end
      end
    end
    lines
  end

  def correlation_bar(value, band)
    width = (value.abs * 20 + 0.5).floor
    threshold = (band * 20 + 0.5).floor
    cells = Array.new(41, ' ')
    cells[20 - threshold] = ':'
    cells[20 + threshold] = ':'
    cells[20] = '|'
    if value > 0
      (21...(21 + width)).each { |index| cells[index] = '#' }
    elsif value < 0
      ((20 - width)...20).each { |index| cells[index] = '#' }
    end
    cells.join
  end

  def correlogram_lines(analyses)
    lines = []
    analyses.each do |name, data|
      ar = data[:models]['ar']
      count = ar[:differenced].length
      band = 2 / Math.sqrt(count)
      lines << "series #{name} difference #{ar[:kind]} n #{count} band #{real(band)}"
      [['acf', ar[:correlations]], ['pacf', ar[:partial]]].each do |label, sequence|
        (1...sequence.length).each do |lag|
          value = sequence[lag]
          line = format('%s %2d %7s [%s]', label, lag, real(value), correlation_bar(value, band))
          lines << line + (value.abs > band ? ' *' : '')
        end
      end
      METHODS.each do |method|
        stats = data[:residual_diagnostics][method]
        lines << "residuals #{method} n #{stats[:count]} mean #{real(stats[:mean])} " \
                 "sd #{real(stats[:sd])} dw #{real(stats[:dw])} skewness #{real(stats[:skewness])} " \
                 "kurtosis #{real(stats[:kurtosis])} jb #{real(stats[:jb])}"
        tests = stats[:ljung_box].map do |lag, q, p|
          "lag #{lag} q #{real(q)} p #{real(p)}"
        end
        lines << "ljung_box #{method} " + tests.join(' ')
      end
    end
    lines
  end

  def chart_rows(data)
    start = data[:training_count]
    rows = data[:intervals][data[:best]].each_with_index.map do |row, i|
      row.merge(period: data[:periods][start + i], actual: data[:values][start + i])
    end
    future = data[:future_periods].zip(data[:future_rows]).map do |period, row|
      row.merge(period:, actual: nil)
    end
    rows + future
  end

  def forecast_chart(row, low, high)
    column = ->(value) { ((value - low) / (high - low) * 60 + 0.5).floor }
    cells = Array.new(61, ' ')
    [[:lo95, :hi95, '-'], [:lo80, :hi80, '=']].each do |start, stop, symbol|
      (column.call(row[start])..column.call(row[stop])).each { |index| cells[index] = symbol }
    end
    cells[column.call(row[:forecast])] = 'o'
    cells[column.call(row[:actual])] = '*' unless row[:actual].nil?
    cells.join
  end

  def seasonal_profile(value, peak)
    width = ((value - 1).abs / peak * 30 + 0.5).floor
    cells = Array.new(61, ' ')
    cells[30] = '|'
    if value > 1
      (31...(31 + width)).each { |index| cells[index] = '#' }
    elsif value < 1
      ((30 - width)...30).each { |index| cells[index] = '#' }
    end
    cells.join
  end

  def chart_lines(analyses)
    lines = []
    analyses.each do |name, data|
      rows = chart_rows(data)
      actual = rows.map { |row| row[:actual] }.compact
      low = (rows.map { |row| row[:lo95] } + actual).min
      high = (rows.map { |row| row[:hi95] } + actual).max
      lines << "chart #{name} method #{data[:best]}"
      lines << "scale low #{real(low)} high #{real(high)}"
      rows.each { |row| lines << "#{row[:period]} |#{forecast_chart(row, low, high)}|" }
      seasonal = data[:decomposition][:multiplicative]
      peak = seasonal.map { |value| (value - 1).abs }.max
      lines << "profile peak #{real(peak)}"
      seasonal.each_with_index do |value, i|
        lines << format('season %2d %s [%s]', i + 1, real(value), seasonal_profile(value, peak))
      end
    end
    lines
  end

  def plan_lines(analyses)
    lines = []
    analyses.each do |name, data|
      policy = data[:policy]
      plan = data[:plan]
      lines << "series #{name} method #{data[:best]}"
      lines << "policy on_hand #{policy[:on_hand]} lead_time #{policy[:lead_time]} " \
               "review #{policy[:review]} service #{real(policy[:service])} safety_stock #{real(plan[:safety])}"
      plan[:rows].each do |row|
        period = data[:future_periods][row[:step] - 1]
        if row[:review]
          review = row[:review]
          lines << "review #{period} position #{real(review[:position])} " \
                   "target #{real(review[:target])} order #{review[:order]}"
        end
        lines << "period #{period} demand #{real(row[:demand])} receipt #{row[:receipt]} " \
                 "on_hand #{real(row[:on_hand])} status #{row[:status]}"
      end
      lines << "summary orders #{plan[:orders]} ordered #{plan[:ordered]} short_periods #{plan[:short_periods]} " \
               "lowest #{real(plan[:lowest])} average #{real(plan[:average])}"
      data[:years].each do |year|
        lines << "year #{year[:year]} actual_months #{year[:actual_months]} actual #{real(year[:actual])} " \
                 "forecast_months #{year[:forecast_months]} forecast #{real(year[:forecast])} " \
                 "total #{real(year[:total])} growth #{real(year[:growth])}"
      end
    end
    lines
  end

  def main
    series, events, policies, settings = read_inputs
    analyses = series.to_h do |name, record|
      [name, analyze(record, events[name], policies[name], settings)]
    end
    write_lines('decomposition.csv', decomposition_lines(analyses, settings))
    write_lines('models.txt', fitted_model_lines(analyses, settings))
    write_lines('forecasts.csv', forecast_lines(analyses))
    write_lines('accuracy.csv', accuracy_lines(analyses))
    write_lines('cv.csv', cross_validation_lines(analyses))
    write_lines('correlogram.txt', correlogram_lines(analyses))
    write_lines('chart.txt', chart_lines(analyses))
    write_lines('plan.txt', plan_lines(analyses))
  end
end

TimeSeriesForecasting.main if $PROGRAM_NAME == __FILE__
