require_relative 'logistic'

module Softmax
  def self.row_values(weights, row)
    scores = weights.map { |vector| Logistic.score(vector, row) }
    maximum = scores.max
    shifted = scores.map { |value| value - maximum }
    exponentials = shifted.map { |value| Math.exp(value) }
    total = 0.0
    exponentials.each { |value| total += value }
    [exponentials.map { |value| value / total }, shifted, total]
  end

  def self.probabilities(weights, row)
    row_values(weights, row)[0]
  end

  def self.predict(probabilities)
    probabilities.each_index.max_by { |index| [probabilities[index], -index] }
  end

  def self.average_loss(weights, rows, labels)
    total = 0.0
    rows.each_with_index do |row, index|
      _probabilities, shifted, sum = row_values(weights, row)
      total += Math.log(sum) - shifted[labels[index]]
    end
    total / rows.length.to_f
  end

  def self.objective(weights, rows, labels, lambda)
    penalty = 0.0
    weights.each do |vector|
      (1...vector.length).each { |index| penalty += vector[index] * vector[index] }
    end
    average_loss(weights, rows, labels) + lambda * penalty / 2.0
  end

  def self.gradient(weights, rows, labels, lambda)
    probabilities = rows.map { |row| self.probabilities(weights, row) }
    weights.each_index.map do |klass|
      weights[klass].each_index.map do |feature|
        total = 0.0
        rows.each_with_index do |row, index|
          residual = probabilities[index][klass] - (labels[index] == klass ? 1.0 : 0.0)
          total += residual * row[feature]
        end
        value = total / rows.length.to_f
        feature.zero? ? value : value + lambda * weights[klass][feature]
      end
    end
  end

  def self.train(rows, labels, classes, rate, iterations, lambda)
    weights = Array.new(classes) { Array.new(rows[0].length, 0.0) }
    checkpoints = [[0, weights.map(&:dup)]]
    (1..iterations).each do |iteration|
      gradients = gradient(weights, rows, labels, lambda)
      weights = weights.each_index.map do |klass|
        weights[klass].each_index.map do |index|
          weights[klass][index] - rate * gradients[klass][index]
        end
      end
      checkpoints << [iteration, weights.map(&:dup)] if (iteration % 100).zero?
    end
    checkpoints
  end
end
