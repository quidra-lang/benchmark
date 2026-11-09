require_relative 'alignment'

module Distances
  MODELS = %w[P JC K2P].freeze
  def self.pair_counts(first, second, weights)
    sites = transitions = transversions = 0
    weights.each_with_index do |weight, column|
      a, b = first[column], second[column]
      next unless Alignment::BASES.include?(a) && Alignment::BASES.include?(b)
      sites += weight
      next if a == b
      if %w[AG GA CT TC].include?(a + b)
        transitions += weight
      else
        transversions += weight
      end
    end
    [sites, transitions, transversions]
  end

  def self.all_pairs(sequences, weights)
    (0...sequences.size).to_a.combination(2).map do |i, j|
      [i, j, *pair_counts(sequences[i], sequences[j], weights)]
    end
  end

  def self.corrected(model, n, s, v, replacement)
    saturated = n.zero? || (model == 'JC' && 4 * (s + v) >= 3 * n) ||
                (model == 'K2P' && (2 * s + v >= n || 2 * v >= n))
    return [replacement, true] if saturated
    value = case model
            when 'P' then (s + v).fdiv(n)
            when 'JC' then -0.75 * Math.log(1 - (4 * (s + v)).fdiv(3 * n))
            else -0.5 * Math.log(1 - (2 * s).fdiv(n) - v.fdiv(n)) -
                 0.25 * Math.log(1 - (2 * v).fdiv(n))
            end
    [value, false]
  end

  def self.build_matrix(pairs, count, model, replacement)
    matrix = Array.new(count) { Array.new(count, 0.0) }
    saturated = []
    pairs.each do |i, j, n, s, v|
      value, replaced = corrected(model, n, s, v, replacement)
      matrix[i][j] = matrix[j][i] = value
      saturated << [i, j, n] if replaced
    end
    [matrix, saturated]
  end
end
