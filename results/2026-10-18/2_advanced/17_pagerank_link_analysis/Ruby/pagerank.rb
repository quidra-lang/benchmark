# frozen_string_literal: true

module PageRank
  Result = Struct.new(:values, :changes, :converged, keyword_init: true)

  def self.compute(count, edges, seeds, damping, iterations, tolerance)
    weights = Array.new(count, 0)
    incoming = Array.new(count) { [] }
    edges.each do |source, destination, weight|
      weights[source] += weight
      incoming[destination] << [source, weight]
    end
    incoming.each { |list| list.sort_by!(&:first) }
    teleport = Array.new(count, false)
    seeds.each { |vertex| teleport[vertex] = true }
    size = seeds.length
    values = Array.new(count) { |vertex| teleport[vertex] ? 1.0 / size : 0.0 }
    changes = []
    converged = nil
    1.upto(iterations) do |iteration|
      dangling = 0.0
      count.times { |vertex| dangling += values[vertex] if weights[vertex].zero? }
      base = ((1.0 - damping) + damping * dangling) / size
      updated = Array.new(count, 0.0)
      count.times do |vertex|
        inflow = 0.0
        incoming[vertex].each { |source, weight| inflow += (values[source] * weight) / weights[source] }
        updated[vertex] = damping * inflow
        updated[vertex] += base if teleport[vertex]
      end
      change = 0.0
      count.times { |vertex| change += (updated[vertex] - values[vertex]).abs }
      changes << change
      converged ||= iteration if change < tolerance
      values = updated
    end
    Result.new(values: values, changes: changes, converged: converged)
  end
end
