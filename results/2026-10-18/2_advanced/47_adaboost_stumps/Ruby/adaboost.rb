require_relative 'stumps'

module Boosting
  Round = Struct.new(:stump, :weights, :error, :alpha, :polarity, :z, :bound, :loss, keyword_init: true)
  Model = Struct.new(:rounds, :stop, :cuts, keyword_init: true)

  module_function

  def train_discrete(rows, max_rounds, weights: nil, shrinkage: 1.0, space: nil)
    space ||= SearchSpace.new(rows)
    labels = rows.map(&:label)
    weights = weights ? weights.dup : Array.new(rows.length, 1.0 / rows.length)
    rounds = []
    bound = 1.0
    stop = 'completed'
    max_rounds.times do
      error, feature, threshold, polarity = discrete_search(space, labels, weights)
      if error >= 0.5
        stop = 'weak'
        break
      end
      alpha = error <= 1e-10 ? 1.0 : shrinkage * (0.5 * Math.log((1.0 - error) / error))
      stump = Stump.new(feature, [threshold], [-polarity * alpha, polarity * alpha])
      before = weights.dup
      updated = rows.each_index.map do |i|
        decision = rows[i].values[feature] > threshold ? polarity : -polarity
        factor = decision == labels[i] ? Math.exp(-alpha) : Math.exp(alpha)
        weights[i].zero? ? 0.0 : weights[i] * factor
      end
      z = ordered_sum(updated)
      weights = updated.map { |weight| weight / z }
      bound *= z
      rounds << Round.new(stump: stump, weights: before, error: error, alpha: alpha,
                          polarity: polarity, z: z, bound: bound)
      if error <= 1e-10
        stop = 'perfect'
        break
      end
    end
    Model.new(rounds: rounds, stop: stop)
  end

  def train_samme(rows, max_rounds, classes)
    space = SearchSpace.new(rows)
    labels = rows.map(&:label)
    weights = Array.new(rows.length, 1.0 / rows.length)
    rounds = []
    stop = 'completed'
    max_rounds.times do
      stump, error = multiclass_search(space, labels, weights, classes)
      if error >= (classes - 1).to_f / classes
        stop = 'weak'
        break
      end
      alpha = error <= 1e-10 ? 1.0 : Math.log((1.0 - error) / error) + Math.log(classes - 1)
      updated = rows.each_index.map do |i|
        stump.call(rows[i].values) != labels[i] ? weights[i] * Math.exp(alpha) : weights[i]
      end
      z = ordered_sum(updated)
      weights = updated.map { |weight| weight / z }
      rounds << Round.new(stump: stump, error: error, alpha: alpha)
      if error <= 1e-10
        stop = 'perfect'
        break
      end
    end
    Model.new(rounds: rounds, stop: stop)
  end
end
