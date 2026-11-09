module Logistic
  def self.score(weights, row)
    total = 0.0
    weights.each_index { |index| total += weights[index] * row[index] }
    total
  end

  def self.probability(score)
    return 1.0 / (1.0 + Math.exp(-score)) if score >= 0.0

    exponential = Math.exp(score)
    exponential / (1.0 + exponential)
  end

  def self.loss(score, target)
    [score, 0.0].max - target * score + Math.log(1.0 + Math.exp(-score.abs))
  end

  def self.probabilities(weights, rows)
    rows.map { |row| probability(score(weights, row)) }
  end

  def self.average_loss(weights, rows, targets)
    total = 0.0
    rows.each_with_index { |row, index| total += loss(score(weights, row), targets[index]) }
    total / rows.length.to_f
  end

  def self.objective(weights, rows, targets, lambda)
    penalty = 0.0
    (1...weights.length).each { |index| penalty += weights[index] * weights[index] }
    average_loss(weights, rows, targets) + lambda * penalty / 2.0
  end

  def self.gradient(weights, rows, targets, lambda)
    errors = rows.each_with_index.map do |row, index|
      probability(score(weights, row)) - targets[index]
    end
    weights.each_index.map do |feature|
      total = 0.0
      rows.each_with_index { |row, index| total += errors[index] * row[feature] }
      value = total / rows.length.to_f
      feature.zero? ? value : value + lambda * weights[feature]
    end
  end

  def self.hessian(weights, rows, lambda)
    variances = probabilities(weights, rows).map { |value| value * (1.0 - value) }
    matrix = Array.new(weights.length) { Array.new(weights.length, 0.0) }
    weights.each_index do |first|
      (0..first).each do |second|
        total = 0.0
        rows.each_with_index do |row, index|
          total += variances[index] * row[first] * row[second]
        end
        value = total / rows.length.to_f
        value += lambda if first == second && first.positive?
        matrix[first][second] = value
        matrix[second][first] = value
      end
    end
    matrix
  end
end
