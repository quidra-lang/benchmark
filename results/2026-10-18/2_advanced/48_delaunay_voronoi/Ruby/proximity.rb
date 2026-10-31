require_relative 'predicates'

module Proximity
  extend self
  include Predicates

  class DisjointSets
    attr_reader :count

    def initialize(size)
      @parent = (0..size).to_a
      @size = Array.new(size + 1, 1)
      @count = size
    end

    def find(site)
      until @parent[site] == site
        @parent[site] = @parent[@parent[site]]
        site = @parent[site]
      end
      site
    end

    def union(first, second)
      first, second = find(first), find(second)
      return false if first == second

      first, second = second, first if @size[first] < @size[second]
      @parent[second] = first
      @size[first] += @size[second]
      @count -= 1
      true
    end
  end

  def nearest_neighbors(points, neighbors)
    points.each_index.map do |site|
      neighbors[site].min_by { |other| [d2(points[site], points[other]), other] } if site.positive?
    end
  end

  def nearest_components(nearest)
    sets = DisjointSets.new(nearest.size - 1)
    (1...nearest.size).each { |site| sets.union(site, nearest[site]) }
    (1...nearest.size).group_by { |site| sets.find(site) }.values.sort_by(&:first)
  end

  def kruskal(points, edges)
    sets = DisjointSets.new(points.size - 1)
    edges.sort_by { |i, j| [d2(points[i], points[j]), i, j] }.select do |i, j|
      sets.union(i, j)
    end
  end

  def gabriel_edge?(points, edge, directed)
    i, j = edge
    [edge, [j, i]].all? do |direction|
      opposite = directed[direction]
      !opposite || dot(points[opposite], points[i], points[j]).positive?
    end
  end

  def relative_neighbor_edge?(points, edge)
    i, j = edge
    length2 = d2(points[i], points[j])
    points.drop(1).none? { |p| d2(points[i], p) < length2 && d2(points[j], p) < length2 }
  end

  def greedy_route(points, neighbors, start, target)
    route = [start]
    length = 0.0
    current = start
    until current == target
      following = neighbors[current].min_by { |site| [d2(points[site], points[target]), site] }
      length += Math.sqrt(d2(points[current], points[following]))
      route << following
      current = following
    end
    [route, length]
  end

  def dijkstra(points, neighbors, start)
    distances = Array.new(points.size, Float::INFINITY)
    previous = Array.new(points.size)
    distances[start] = 0.0
    remaining = (1...points.size).to_a
    until remaining.empty?
      site = remaining.min_by { |vertex| distances[vertex] }
      remaining.delete(site)
      neighbors[site].each do |other|
        candidate = distances[site] + Math.sqrt(d2(points[site], points[other]))
        next unless candidate < distances[other]

        distances[other] = candidate
        previous[other] = site
      end
    end
    [distances, previous]
  end
end
