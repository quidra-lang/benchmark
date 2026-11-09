require_relative 'linalg'

module Evaluation
  extend self

  def reduced_fraction(numerator, denominator)
    denominator.zero? ? nil : Rational(numerator, denominator)
  end

  def sum_fractions(values)
    values.reduce(Rational(0)) { |sum, value| sum + value }
  end

  def confusion_matrix(actual, predictions, class_count)
    matrix = Array.new(class_count) { Array.new(class_count, 0) }
    actual.zip(predictions).each { |expected, predicted| matrix[expected][predicted] += 1 }
    matrix
  end

  def measures(actual, predictions, class_count)
    matrix = confusion_matrix(actual, predictions, class_count)
    support = matrix.map(&:sum)
    predicted_counts = Array.new(class_count) { |k| matrix.sum { |row| row[k] } }
    correct = class_count.times.sum { |k| matrix[k][k] }
    count = actual.length
    recall = Array.new(class_count) { |k| reduced_fraction(matrix[k][k], support[k]) }
    precision = Array.new(class_count) { |k| reduced_fraction(matrix[k][k], predicted_counts[k]) }
    f1 = Array.new(class_count) { |k| reduced_fraction(2 * matrix[k][k], support[k] + predicted_counts[k]) }
    expected = class_count.times.sum { |k| support[k] * predicted_counts[k] }
    macro_f1 = Linalg.total(Array.new(class_count) do |k|
      (2 * matrix[k][k]).fdiv(support[k] + predicted_counts[k])
    end) / class_count
    {
      matrix:, support:, correct:, accuracy: reduced_fraction(correct, count),
      balanced_accuracy: sum_fractions(recall) / class_count,
      kappa: reduced_fraction(count * correct - expected, count * count - expected),
      recall:, precision:, f1:, macro_f1:
    }
  end

  def mcnemar(actual, predictions_a, predictions_b)
    b01 = 0
    b10 = 0
    actual.zip(predictions_a, predictions_b).each do |expected, a, b|
      b01 += 1 if a == expected && b != expected
      b10 += 1 if a != expected && b == expected
    end
    difference = (b01 - b10).abs - 1
    chi2 = b01 == b10 ? 0.0 : (difference * difference).fdiv(b01 + b10)
    [b01, b10, chi2, chi2 > 3.841]
  end

  class RandomGenerator
    def initialize(seed)
      @state = seed
    end

    def draw
      @state = 48_271 * @state % 2_147_483_647
    end
  end
end
