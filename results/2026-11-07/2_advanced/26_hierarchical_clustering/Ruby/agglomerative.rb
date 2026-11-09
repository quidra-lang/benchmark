# frozen_string_literal: true

module Agglomerative
  SQUARED = %w[centroid median ward].freeze

  def self.coefficients(method, a, b, k)
    case method
    when 'single' then [0.5, 0.5, 0.0, -0.5]
    when 'complete' then [0.5, 0.5, 0.0, 0.5]
    when 'weighted' then [0.5, 0.5, 0.0, 0.0]
    when 'median' then [0.5, 0.5, -0.25, 0.0]
    when 'average' then [a.to_f / (a + b), b.to_f / (a + b), 0.0, 0.0]
    when 'centroid'
      [a.to_f / (a + b), b.to_f / (a + b), -(a * b).to_f / ((a + b) * (a + b)), 0.0]
    when 'ward'
      total = a + b + k
      [(a + k).to_f / total, (b + k).to_f / total, -k.to_f / total, 0.0]
    end
  end

  def self.cluster(matrix, method)
    count = matrix.length
    squared = SQUARED.include?(method)
    values = Array.new(2 * count - 1) { Array.new(2 * count - 1, 0.0) }
    count.times do |i|
      (i + 1...count).each do |j|
        value = squared ? matrix[i][j] * matrix[i][j] : matrix[i][j]
        values[i][j] = values[j][i] = value
      end
    end
    sizes = Array.new(2 * count - 1, 1)
    active = (0...count).to_a
    merges = []
    (count - 1).times do |step|
      best = nil
      active.each_with_index do |a, index|
        active.drop(index + 1).each do |b|
          candidate = values[a][b]
          best = [a, b, candidate] if best.nil? || candidate < best[2]
        end
      end
      a, b, value = best
      node = count + step
      sizes[node] = sizes[a] + sizes[b]
      merges << [a, b, squared ? Math.sqrt(value) : value, sizes[node]]
      active.each do |k|
        next if k == a || k == b

        alpha_a, alpha_b, beta, gamma = coefficients(method, sizes[a], sizes[b], sizes[k])
        updated = alpha_a * values[a][k] + alpha_b * values[b][k] +
                  beta * value + gamma * (values[a][k] - values[b][k]).abs
        values[k][node] = values[node][k] = updated
      end
      active.delete(a)
      active.delete(b)
      active << node
    end
    merges
  end

  def self.prim(matrix)
    count = matrix.length
    present = Array.new(count, false)
    present[0] = true
    keys = matrix[0].dup
    parents = Array.new(count, 0)
    edges = []
    (count - 1).times do
      chosen = nil
      count.times do |vertex|
        next if present[vertex]

        chosen = vertex if chosen.nil? || keys[vertex] < keys[chosen]
      end
      present[chosen] = true
      edges << [parents[chosen], chosen, keys[chosen]]
      count.times do |vertex|
        next if present[vertex] || matrix[chosen][vertex] >= keys[vertex]

        keys[vertex] = matrix[chosen][vertex]
        parents[vertex] = chosen
      end
    end
    edges
  end
end
