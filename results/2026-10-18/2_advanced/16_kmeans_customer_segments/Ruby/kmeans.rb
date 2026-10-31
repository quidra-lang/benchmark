# frozen_string_literal: true

module KMeans
  def self.squared_distance(first, last)
    first.each_index.reduce(0.0) do |sum, index|
      delta = first[index] - last[index]
      sum + delta * delta
    end
  end

  def self.mean(points)
    points.first.each_index.map do |feature|
      points.reduce(0.0) { |sum, point| sum + point[feature] } / points.length
    end
  end

  def self.groups(assignment, count)
    groups = Array.new(count) { [] }
    assignment.each_with_index { |group, index| groups[group] << index }
    groups
  end

  def self.centers(points, assignment, count)
    groups(assignment, count).map { |indices| mean(indices.map { |index| points[index] }) }
  end

  def self.assign(points, centers)
    assignments = []
    errors = []
    points.each do |point|
      distances = centers.map { |center| squared_distance(point, center) }
      chosen = distances.each_index.min_by { |index| [distances[index], index] }
      assignments << chosen
      errors << distances[chosen]
    end
    [assignments, errors]
  end

  def self.refill(assignment, errors, count)
    sizes = Array.new(count, 0)
    assignment.each { |group| sizes[group] += 1 }
    reseeds = 0
    count.times do |group|
      next unless sizes[group].zero?

      eligible = assignment.each_index.select { |index| sizes[assignment[index]] >= 2 }
      chosen = eligible.min_by { |index| [-errors[index], index] }
      sizes[assignment[chosen]] -= 1
      assignment[chosen] = group
      sizes[group] += 1
      errors[chosen] = 0.0
      reseeds += 1
    end
    reseeds
  end

  def self.sse(points, assignment, centers)
    points.each_index.reduce(0.0) { |sum, index| sum + squared_distance(points[index], centers[assignment[index]]) }
  end

  def self.lloyd(points, initial, limit)
    count = initial.length
    assignment, errors = assign(points, initial)
    iterations = reseeds = 0
    converged = false
    while iterations < limit
      reseeds += refill(assignment, errors, count)
      centers = self.centers(points, assignment, count)
      iterations += 1
      updated, errors = assign(points, centers)
      converged = updated == assignment
      assignment = updated
      break if converged
    end
    reseeds += refill(assignment, errors, count)
    centers = self.centers(points, assignment, count)
    { assignment: assignment, centers: centers, iterations: iterations, reseeds: reseeds,
      converged: converged, sse: sse(points, assignment, centers) }
  end
end
