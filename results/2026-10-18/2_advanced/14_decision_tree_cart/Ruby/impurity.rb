# frozen_string_literal: true

module Impurity
  Statistics = Struct.new(:size, :counts, :squares, :majority, :errors, keyword_init: true)

  module_function

  def statistics(rows, class_count)
    counts = Array.new(class_count, 0)
    rows.each { |row| counts[row.klass] += 1 }
    largest = counts.max
    Statistics.new(size: rows.length, counts: counts, squares: counts.sum { |count| count * count },
                   majority: counts.index(largest), errors: rows.length - largest)
  end

  def quality(left, right)
    Rational(left.squares * right.size + right.squares * left.size, left.size * right.size)
  end

  def improves?(quality, parent)
    quality.numerator * parent.size > parent.squares * quality.denominator
  end

  def decrease(parent, left, right)
    left_value = left.squares.to_f / left.size
    right_value = right.squares.to_f / right.size
    parent_value = parent.squares.to_f / parent.size
    (left_value + right_value) - parent_value
  end
end
