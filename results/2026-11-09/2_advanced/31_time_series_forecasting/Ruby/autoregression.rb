require_relative 'decomposition'

module Autoregression
  extend self

  KINDS = %w[none first seasonal both].freeze

  def difference(values, season, kind)
    case kind
    when 'none'
      [values.dup, 0]
    when 'first'
      [(1...values.length).map { |t| values[t] - values[t - 1] }, 1]
    when 'seasonal'
      [(season...values.length).map { |t| values[t] - values[t - season] }, season]
    when 'both'
      transformed = ((season + 1)...values.length).map do |t|
        (values[t] - values[t - 1]) - (values[t - season] - values[t - season - 1])
      end
      [transformed, season + 1]
    end
  end

  def autocorrelation(values, max_lag)
    average = Decomposition.mean(values)
    centered = values.map { |value| value - average }
    count = values.length
    variance = Decomposition.total(centered.map { |value| value * value }) / count
    correlations = [1.0]
    (1..max_lag).each do |lag|
      numerator = Decomposition.total((0...(count - lag)).map { |i| centered[i] * centered[i + lag] })
      correlations << numerator / count / variance
    end
    [average, variance, correlations]
  end

  def durbin_levinson(correlations)
    coefficients = [[]]
    partial = [0.0]
    variances = [1.0]
    (1...correlations.length).each do |order|
      previous = coefficients.last
      correction = Decomposition.total((1...order).map { |j| previous[j - 1] * correlations[order - j] })
      theta = (correlations[order] - correction) / variances.last
      current = (1...order).map { |j| previous[j - 1] - theta * previous[order - j - 1] }
      coefficients << current + [theta]
      partial << theta
      variances << variances.last * (1 - theta * theta)
    end
    [coefficients, partial, variances]
  end

  def residuals(values, average, coefficients)
    order = coefficients.length
    (order...values.length).map do |i|
      correction = Decomposition.total((1..order).map { |j| coefficients[j - 1] * (values[i - j] - average) })
      values[i] - average - correction
    end
  end

  def forecast(model, origin, steps)
    transformed = model[:differenced].first(origin - model[:offset])
    extended = model[:series].first(origin)
    average = model[:mean]
    season = model[:season]
    Array.new(steps) do
      correction = Decomposition.total(model[:coefficients].each_with_index.map do |coefficient, j|
        coefficient * (transformed[-j - 1] - average)
      end)
      predicted = average + correction
      transformed << predicted
      predicted = case model[:kind]
                  when 'first' then predicted + extended[-1]
                  when 'seasonal' then predicted + extended[-season]
                  when 'both' then predicted + extended[-1] + extended[-season] - extended[-season - 1]
                  else predicted
                  end
      extended << predicted
      predicted
    end
  end

  def ljung_box(errors, lags)
    count = errors.length
    _, _, correlations = autocorrelation(errors, lags.max)
    lags.map do |lag|
      sum = Decomposition.total((1..lag).map { |k| correlations[k] * correlations[k] / (count - k) })
      q = count * (count + 2) * sum
      x = q / 2
      term = 1.0
      terms = [term]
      (1...(lag / 2)).each do |i|
        term = term * x / i
        terms << term
      end
      [lag, q, Math.exp(-x) * Decomposition.total(terms)]
    end
  end
end
