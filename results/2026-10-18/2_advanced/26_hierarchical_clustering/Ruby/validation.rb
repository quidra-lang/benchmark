# frozen_string_literal: true

module Validation
  def self.correlation(left, right)
    left_sum = right_sum = 0.0
    left.each_index do |index|
      left_sum += left[index]
      right_sum += right[index]
    end
    left_mean = left_sum / left.length
    right_mean = right_sum / right.length
    cross = left_square = right_square = 0.0
    left.each_index do |index|
      a = left[index] - left_mean
      b = right[index] - right_mean
      cross += a * b
      left_square += a * a
      right_square += b * b
    end
    cross / Math.sqrt(left_square * right_square)
  end

  def self.contingency(left, right, rows = left.max + 1, columns = right.max + 1)
    table = Array.new(rows) { Array.new(columns, 0) }
    left.each_index { |index| table[left[index]][right[index]] += 1 }
    table
  end

  def self.choose_two(value)
    value * (value - 1) / 2
  end

  def self.ari(left, right)
    table = contingency(left, right)
    row_sums = table.map(&:sum)
    column_sums = Array.new(table.first.length, 0)
    cells = 0
    table.each do |row|
      row.each_with_index do |value, column|
        cells += choose_two(value)
        column_sums[column] += value
      end
    end
    rows = row_sums.sum { |value| choose_two(value) }
    columns = column_sums.sum { |value| choose_two(value) }
    pairs = choose_two(left.length)
    numerator = 2 * (pairs * cells - rows * columns)
    denominator = pairs * (rows + columns) - 2 * rows * columns
    denominator.zero? ? Rational(1, 1) : Rational(numerator, denominator)
  end

  def self.silhouettes(partition, matrix)
    groups = Array.new(partition.max) { [] }
    partition.each_with_index { |group, index| groups[group - 1] << index }
    return nil if groups.length == 1

    partition.each_with_index.map do |group, i|
      own = groups[group - 1]
      next 0.0 if own.length == 1

      within = 0.0
      own.each { |j| within += matrix[i][j] unless i == j }
      within /= own.length - 1
      nearest = nil
      groups.each_with_index do |members, index|
        next if index == group - 1

        total = 0.0
        members.each { |j| total += matrix[i][j] }
        mean = total / members.length
        nearest = mean if nearest.nil? || mean < nearest
      end
      (nearest - within) / [within, nearest].max
    end
  end
end
