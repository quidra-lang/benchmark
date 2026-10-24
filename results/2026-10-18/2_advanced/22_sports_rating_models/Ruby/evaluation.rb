# frozen_string_literal: true

module Evaluation
  def self.sigma(value)
    1.0 / (1.0 + Math.exp(-value))
  end

  def self.fit_link(features, results, iterations)
    alpha = 0.0
    beta = 0.0
    iterations.times do
      g0 = 0.0
      g1 = 0.0
      h00 = 0.0
      h01 = 0.0
      h11 = 0.0
      features.each_with_index do |feature, index|
        probability = sigma(alpha + beta * feature)
        weight = probability * (1.0 - probability)
        residual = results[index].to_f - probability
        g0 += residual
        g1 += residual * feature
        h00 += weight
        h01 += weight * feature
        h11 += weight * feature * feature
      end
      determinant = h00 * h11 - h01 * h01
      alpha += (h11 * g0 - h01 * g1) / determinant
      beta += (h00 * g1 - h01 * g0) / determinant
    end
    [alpha, beta]
  end

  def self.log_loss(probability, result)
    return -Math.log(probability) if result == 1
    return -Math.log(1.0 - probability) if result.zero?

    -(Math.log(probability) / 2.0 + Math.log(1.0 - probability) / 2.0)
  end

  def self.brier(probability, result)
    difference = probability - result.to_f
    difference * difference
  end

  def self.correctness(probability, result)
    return Rational(1, 2) if result == Rational(1, 2)

    correct = (probability > 0.5 && result == 1) || (probability < 0.5 && result.zero?)
    Rational(correct ? 1 : 0)
  end

  def self.average_ranks(values)
    values.map do |value|
      greater = values.count { |other| other > value }
      equal = values.count { |other| other == value }
      Rational(2 * greater + equal + 1, 2)
    end
  end

  def self.kendall(first, second)
    total = 0
    first.length.times do |team|
      (team + 1...first.length).each do |other|
        total += (first[team] <=> first[other]) * (second[team] <=> second[other])
      end
    end
    Rational(total, first.length * (first.length - 1) / 2)
  end

  def self.spearman(first, second)
    first_ranks = average_ranks(first)
    second_ranks = average_ranks(second)
    total = Rational(0)
    first.length.times do |team|
      difference = first_ranks[team] - second_ranks[team]
      total += difference * difference
    end
    1 - Rational(6, first.length * (first.length * first.length - 1)) * total
  end
end
