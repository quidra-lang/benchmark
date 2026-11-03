module Boosting
  Stump = Data.define(:feature, :thresholds, :values) do
    def call(features)
      values[thresholds.count { |threshold| features[feature] > threshold }]
    end
  end

  class SearchSpace
    attr_reader :rows, :orders, :groups, :thresholds

    def initialize(rows)
      @rows = rows
      @orders = []
      @groups = []
      @thresholds = []
      rows[0].values.length.times do |feature|
        order = rows.each_index.sort_by { |index| [rows[index].values[feature], index] }
        groups = []
        distinct = []
        order.each do |index|
          value = rows[index].values[feature]
          if distinct.empty? || value != distinct[-1]
            distinct << value
            groups << []
          end
          groups[-1] << index
        end
        thresholds = [distinct[0] - 1.0]
        distinct.each_cons(2) { |left, right| thresholds << (left + right) / 2.0 }
        @orders << order
        @groups << groups
        @thresholds << thresholds
      end
    end
  end

  module_function

  # Array#sum compensates floating-point error; the specification requires this order.
  def ordered_sum(values)
    total = 0.0
    values.each { |value| total += value }
    total
  end

  def left_cumulative(groups, values)
    total = 0.0
    sums = [total]
    groups[0...-1].each do |group|
      group.each { |index| total += values[index] }
      sums << total
    end
    sums
  end

  def choose(candidates)
    minimum = candidates.map(&:first).min
    candidates.find { |candidate| candidate[0] <= minimum + 1e-9 }
  end

  def discrete_search(space, labels, weights)
    positives = labels.each_index.map { |i| labels[i] == 1 ? weights[i] : 0.0 }
    negatives = labels.each_index.map { |i| labels[i] == -1 ? weights[i] : 0.0 }
    positive_total = ordered_sum(positives)
    negative_total = ordered_sum(negatives)
    candidates = []
    space.thresholds.each_with_index do |thresholds, feature|
      left_positive = left_cumulative(space.groups[feature], positives)
      left_negative = left_cumulative(space.groups[feature], negatives)
      thresholds.each_with_index do |threshold, index|
        positive = left_positive[index]
        negative = left_negative[index]
        candidates << [positive + (negative_total - negative), feature, threshold, 1]
        candidates << [negative + (positive_total - positive), feature, threshold, -1]
      end
    end
    choose(candidates)
  end

  def regression_search(space, targets, weights)
    total_weight = ordered_sum(weights)
    products = weights.each_index.map { |i| weights[i] * targets[i] }
    total_target = ordered_sum(products)
    total_square = ordered_sum(weights.each_index.map { |i| weights[i] * targets[i] * targets[i] })
    candidates = []
    space.thresholds.each_with_index do |thresholds, feature|
      left_weights = left_cumulative(space.groups[feature], weights)
      left_targets = left_cumulative(space.groups[feature], products)
      thresholds.each_with_index do |threshold, position|
        left_weight = left_weights[position]
        left_target = left_targets[position]
        right_weight = total_weight - left_weight
        right_target = total_target - left_target
        right_value = right_target / right_weight
        if position.zero?
          left_value = 0.0
          gain = right_target * right_target / right_weight
        else
          left_value = left_target / left_weight
          gain = left_target * left_target / left_weight + right_target * right_target / right_weight
        end
        candidates << [total_square - gain, feature, threshold, left_value, right_value]
      end
    end
    error, feature, threshold, left, right = choose(candidates)
    [Stump.new(feature, [threshold], [left, right]), error]
  end

  def multiclass_search(space, labels, weights, classes)
    total_weight = ordered_sum(weights)
    totals = Array.new(classes, 0.0)
    labels.each_index { |i| totals[labels[i] - 1] += weights[i] }
    candidates = []
    space.thresholds.each_with_index do |thresholds, feature|
      left = Array.new(classes, 0.0)
      thresholds.each_with_index do |threshold, position|
        unless position.zero?
          space.groups[feature][position - 1].each { |i| left[labels[i] - 1] += weights[i] }
        end
        right = totals.each_index.map { |i| totals[i] - left[i] }
        left_class = left.index(left.max)
        right_class = right.index(right.max)
        error = total_weight - (left[left_class] + right[right_class])
        candidates << [error, feature, threshold, left_class + 1, right_class + 1]
      end
    end
    error, feature, threshold, left, right = choose(candidates)
    [Stump.new(feature, [threshold], [left, right]), error]
  end

  def real_geometry(space, bins)
    count = space.rows.length
    cuts = []
    assignments = []
    space.orders.each_with_index do |order, feature|
      values = order.map { |i| space.rows[i].values[feature] }
      feature_cuts = (1...bins).map do |bin|
        rank = bin * count / bins
        (values[rank - 1] + values[rank]) / 2.0
      end
      cuts << feature_cuts
      assignments << space.rows.map { |row| feature_cuts.count { |cut| cut < row.values[feature] } }
    end
    [cuts, assignments]
  end

  def real_search(assignments, labels, weights, bins)
    candidates = assignments.each_with_index.map do |memberships, feature|
      positives = Array.new(bins, 0.0)
      negatives = Array.new(bins, 0.0)
      labels.each_index do |i|
        destination = labels[i] == 1 ? positives : negatives
        destination[memberships[i]] += weights[i]
      end
      z = 2.0 * ordered_sum(positives.each_index.map { |i| Math.sqrt(positives[i] * negatives[i]) })
      [z, feature, positives, negatives]
    end
    choose(candidates)
  end
end
