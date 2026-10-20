# frozen_string_literal: true

require_relative 'kmeans'

module Validation
  def self.distance_table(points)
    table = Array.new(points.length) { Array.new(points.length, 0.0) }
    points.each_index do |first|
      (first + 1...points.length).each do |last|
        table[first][last] = table[last][first] = Math.sqrt(KMeans.squared_distance(points[first], points[last]))
      end
    end
    table
  end

  def self.indices(points, assignment, centers, sse, distances)
    count = centers.length
    groups = KMeans.groups(assignment, count)
    silhouettes = points.each_index.map do |index|
      own = assignment[index]
      members = groups[own]
      next 0.0 if members.length == 1

      a = members.reduce(0.0) { |sum, other| other == index ? sum : sum + distances[index][other] } / (members.length - 1)
      b = groups.each_index.reject { |group| group == own }.map do |group|
        groups[group].reduce(0.0) { |sum, other| sum + distances[index][other] } / groups[group].length
      end.min
      maximum = [a, b].max
      maximum.zero? ? 0.0 : (b - a) / maximum
    end
    global = KMeans.mean(points)
    between = groups.each_index.reduce(0.0) do |sum, group|
      sum + groups[group].length * KMeans.squared_distance(centers[group], global)
    end
    ch = (between / (count - 1)) / (sse / (points.length - count))
    scatter = groups.each_with_index.map do |members, group|
      members.reduce(0.0) { |sum, index| sum + Math.sqrt(KMeans.squared_distance(points[index], centers[group])) } / members.length
    end
    maxima = groups.each_index.map do |group|
      groups.each_index.reject { |other| other == group }.map do |other|
        (scatter[group] + scatter[other]) / Math.sqrt(KMeans.squared_distance(centers[group], centers[other]))
      end.max
    end
    { silhouettes: silhouettes, silhouette: silhouettes.reduce(0.0, :+) / points.length,
      calinski_harabasz: ch, davies_bouldin: maxima.reduce(0.0, :+) / count }
  end

  def self.elbow(k, minimum, maximum, sse, first_sse, last_sse)
    x = (k - minimum).fdiv(maximum - minimum)
    y = (sse - last_sse) / (first_sse - last_sse)
    ((1 - x) - y) / Math.sqrt(2)
  end

  def self.hartigan(sse, next_sse, size, k)
    (sse / next_sse - 1) * (size - k - 1)
  end

  def self.pairs(count)
    count * (count - 1) / 2
  end

  def self.ari(first, last)
    joint = Hash.new(0)
    first.each_index { |index| joint[[first[index], last[index]]] += 1 }
    z = pairs(first.length)
    xy = joint.values.sum { |count| pairs(count) }
    x = first.tally.values.sum { |count| pairs(count) }
    y = last.tally.values.sum { |count| pairs(count) }
    numerator = 2 * (z * xy - x * y)
    denominator = z * (x + y) - 2 * x * y
    denominator.zero? ? 1.0 : numerator.fdiv(denominator)
  end
end
