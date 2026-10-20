require_relative 'adaboost'

module Boosting
  module_function

  def update_weights(rows, weights, stump)
    updated = rows.each_index.map { |i| weights[i] * Math.exp(-rows[i].label * stump.call(rows[i].values)) }
    z = ordered_sum(updated)
    updated.map { |weight| weight / z }
  end

  def train_real(rows, max_rounds, bins, smoothing, convergence)
    space = SearchSpace.new(rows)
    cuts, assignments = real_geometry(space, bins)
    labels = rows.map(&:label)
    weights = Array.new(rows.length, 1.0 / rows.length)
    rounds = []
    bound = 1.0
    stop = 'completed'
    max_rounds.times do
      z, feature, positives, negatives = real_search(assignments, labels, weights, bins)
      if z >= 1.0 - convergence
        stop = 'converged'
        break
      end
      values = positives.each_index.map { |i| 0.5 * Math.log((positives[i] + smoothing) / (negatives[i] + smoothing)) }
      stump = Stump.new(feature, cuts[feature], values)
      bound *= z
      rounds << Round.new(stump: stump, weights: weights.dup, z: z, bound: bound)
      weights = update_weights(rows, weights, stump)
    end
    Model.new(rounds: rounds, stop: stop, cuts: cuts)
  end

  def train_gentle(rows, max_rounds)
    space = SearchSpace.new(rows)
    targets = rows.map(&:label)
    weights = Array.new(rows.length, 1.0 / rows.length)
    rounds = []
    max_rounds.times do
      stump, error = regression_search(space, targets, weights)
      rounds << Round.new(stump: stump, weights: weights.dup, error: error)
      weights = update_weights(rows, weights, stump)
    end
    Model.new(rounds: rounds, stop: 'completed')
  end

  def train_logit(rows, max_rounds, clip)
    space = SearchSpace.new(rows)
    targets = rows.map { |row| row.label == 1 ? 1.0 : 0.0 }
    scores = Array.new(rows.length, 0.0)
    probabilities = Array.new(rows.length, 0.5)
    rounds = []
    max_rounds.times do
      working_weights = []
      responses = []
      probabilities.each_with_index do |probability, i|
        weight = probability * (1.0 - probability)
        response = (targets[i] - probability) / weight
        response = clip if response > clip
        response = -clip if response < -clip
        working_weights << weight
        responses << response
      end
      z = ordered_sum(working_weights)
      weights = working_weights.map { |weight| weight / z }
      fitted, error = regression_search(space, responses, weights)
      stump = Stump.new(fitted.feature, fitted.thresholds, fitted.values.map { |value| value / 2.0 })
      rows.each_with_index do |row, i|
        scores[i] += stump.call(row.values)
        probabilities[i] = 1.0 / (1.0 + Math.exp(-2.0 * scores[i]))
      end
      loss = ordered_sum(rows.each_index.map { |i| Math.log(1.0 + Math.exp(-2.0 * rows[i].label * scores[i])) }) / rows.length
      rounds << Round.new(stump: stump, weights: weights, error: error, loss: loss)
    end
    Model.new(rounds: rounds, stop: 'completed')
  end
end
