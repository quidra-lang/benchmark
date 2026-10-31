require_relative 'decomposition'

module Evaluation
  extend self

  def seasonal_scale(values, season)
    Decomposition.total((season...values.length).map { |t| (values[t] - values[t - season]).abs }) /
      (values.length - season)
  end

  def accuracy(actual, predicted, scale)
    count = actual.length
    errors = actual.zip(predicted).map { |observed, forecast| observed - forecast }
    mae = Decomposition.total(errors.map(&:abs)) / count
    {
      me: Decomposition.total(errors) / count, mae:,
      rmse: Math.sqrt(Decomposition.total(errors.map { |error| error * error }) / count),
      mape: 100 * Decomposition.total(errors.zip(actual).map { |error, value| error.abs / value }) / count,
      smape: 100 * Decomposition.total(errors.zip(actual, predicted).map do |error, a, f|
        2 * error.abs / (a.abs + f.abs)
      end) / count,
      mase: mae / scale
    }
  end

  def winkler(actual, low, high, multiplier)
    return high - low + multiplier * (low - actual) if actual < low
    return high - low + multiplier * (actual - high) if actual > high

    high - low
  end

  def rank_models(names, metrics)
    names.each_with_index.sort_by { |name, i| [metrics[name][:rmse], i] }.map(&:first)
  end
end
