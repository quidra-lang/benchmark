# frozen_string_literal: true

module HITS
  def self.compute(count, nodes, edges, iterations)
    nodes = nodes.sort
    incoming = Array.new(count) { [] }
    outgoing = Array.new(count) { [] }
    edges.each do |source, destination|
      incoming[destination] << source
      outgoing[source] << destination
    end
    incoming.each(&:sort!)
    outgoing.each(&:sort!)
    authorities = Array.new(count, 0.0)
    hubs = Array.new(count, 0.0)
    nodes.each { |vertex| authorities[vertex] = hubs[vertex] = 1.0 }
    iterations.times do
      raw_authorities = Array.new(count, 0.0)
      raw_hubs = Array.new(count, 0.0)
      nodes.each do |vertex|
        incoming[vertex].each { |source| raw_authorities[vertex] += hubs[source] }
      end
      nodes.each do |vertex|
        outgoing[vertex].each { |destination| raw_hubs[vertex] += raw_authorities[destination] }
      end
      authority_norm = 0.0
      hub_norm = 0.0
      nodes.each do |vertex|
        authority_norm += raw_authorities[vertex] * raw_authorities[vertex]
        hub_norm += raw_hubs[vertex] * raw_hubs[vertex]
      end
      authority_norm = Math.sqrt(authority_norm)
      hub_norm = Math.sqrt(hub_norm)
      nodes.each do |vertex|
        authorities[vertex] = raw_authorities[vertex] / authority_norm
        hubs[vertex] = raw_hubs[vertex] / hub_norm
      end
    end
    { authority: authorities, hub: hubs }
  end
end
