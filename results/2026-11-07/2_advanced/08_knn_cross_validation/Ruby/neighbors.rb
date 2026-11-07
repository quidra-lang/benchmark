# frozen_string_literal: true

module Neighbors
  Prediction = Struct.new(:label, :share, :runner, :runner_share, :estimate, :neighbors, keyword_init: true)

  def self.distance(left, right, metric)
    total = 0.0
    if metric == 'cosine'
      dot = left_norm = right_norm = 0.0
      left.each_index do |index|
        dot += left[index] * right[index]
        left_norm += left[index] * left[index]
        right_norm += right[index] * right[index]
      end
      left_norm = Math.sqrt(left_norm)
      right_norm = Math.sqrt(right_norm)
      return 1.0 if left_norm.zero? || right_norm.zero?

      return 1.0 - dot / (left_norm * right_norm)
    end
    left.each_index do |index|
      difference = left[index] - right[index]
      case metric
      when 'squared_euclidean' then total += difference * difference
      when 'manhattan' then total += difference.abs
      when 'chebyshev' then total = [total, difference.abs].max
      end
    end
    total
  end

  def self.order(query_vector, rows, vectors, metric)
    rows.map { |row| [row, distance(query_vector, vectors.fetch(row.id), metric)] }
        .sort_by { |row, value| [value, row.id] }
  end

  def self.vote(ordered, k, weighting)
    nearest = ordered.first(k)
    totals = {}
    weight_total = target_total = weighted_target = 0.0
    nearest.each do |row, distance|
      weight = 1.0 / (distance + 0.000000001)
      tally = (totals[row.label] ||= { count: 0, distance: 0.0, weight: 0.0 })
      tally[:count] += 1
      tally[:distance] += distance
      tally[:weight] += weight
      weight_total += weight
      target_total += row.target
      weighted_target += weight * row.target
    end
    labels = totals.keys.sort_by do |label|
      tally = totals[label]
      [weighting == 'uniform' ? -tally[:count] : -tally[:weight], tally[:distance], label]
    end
    shares = labels.map do |label|
      weighting == 'uniform' ? totals[label][:count].to_f / nearest.length.to_f : totals[label][:weight] / weight_total
    end
    estimate = weighting == 'uniform' ? target_total / nearest.length.to_f : weighted_target / weight_total
    Prediction.new(label: labels.first, share: shares.first, runner: labels[1], runner_share: shares[1] || 0.0,
                   estimate: estimate, neighbors: nearest)
  end
end
