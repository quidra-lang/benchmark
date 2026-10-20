# frozen_string_literal: true

module Distances
  def self.statistics(values)
    count = values.length
    means = []
    deviations = []
    values.first.length.times do |feature|
      total = 0.0
      values.each { |row| total += row[feature] }
      mean = total / count
      variance = 0.0
      values.each do |row|
        difference = row[feature] - mean
        variance += difference * difference
      end
      means << mean
      deviations << Math.sqrt(variance / (count - 1))
    end
    [means, deviations]
  end

  def self.standardize(values, means, deviations, enabled)
    values.map do |row|
      row.each_with_index.map do |value, feature|
        enabled ? (value - means[feature]) / deviations[feature] : value
      end
    end
  end

  def self.squared(left, right)
    total = 0.0
    left.each_index do |feature|
      difference = left[feature] - right[feature]
      total += difference * difference
    end
    total
  end

  def self.distance(left, right, type)
    return Math.sqrt(squared(left, right)) if type == 'euclidean'

    if type == 'manhattan'
      total = 0.0
      left.each_index { |feature| total += (left[feature] - right[feature]).abs }
      return total
    end
    left_total = right_total = 0.0
    left.each_index do |feature|
      left_total += left[feature]
      right_total += right[feature]
    end
    left_mean = left_total / left.length
    right_mean = right_total / right.length
    cross = left_square = right_square = 0.0
    left.each_index do |feature|
      a = left[feature] - left_mean
      b = right[feature] - right_mean
      cross += a * b
      left_square += a * a
      right_square += b * b
    end
    1.0 - cross / Math.sqrt(left_square * right_square)
  end

  def self.matrix(vectors, type)
    count = vectors.length
    matrix = Array.new(count) { Array.new(count, 0.0) }
    count.times do |i|
      (i + 1...count).each do |j|
        value = distance(vectors[i], vectors[j], type)
        matrix[i][j] = matrix[j][i] = value
      end
    end
    matrix
  end
end
