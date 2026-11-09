require 'set'
require_relative 'predicates'

class Triangulation
  include Predicates

  attr_reader :directed, :initial

  def initialize(points)
    @points = points
    @directed = {}
    @initial = orient(points[1], points[2], points[3]).positive? ? [1, 2, 3] : [1, 3, 2]
    add(*@initial)
  end

  def canonical(a, b, c)
    [[a, b, c], [b, c, a], [c, a, b]].min
  end

  def triangles
    @directed.map { |(a, b), c| canonical(a, b, c) }.uniq.sort
  end

  def hull_edges
    @directed.keys.select { |u, v| !@directed.key?([v, u]) }.sort
  end

  def insert(site)
    containing = triangles.find do |a, b, c|
      [[a, b], [b, c], [c, a]].all? do |u, v|
        orient(@points[u], @points[v], @points[site]).positive?
      end
    end
    visible = 0
    if containing
      a, b, c = containing
      remove(a, b, c)
      check = Set[[a, b], [b, c], [c, a]]
      kind = 'inside'
    else
      check = hull_edges.filter_map do |u, v|
        [v, u] if orient(@points[u], @points[v], @points[site]).negative?
      end.to_set
      visible = check.size
      kind = 'outside'
    end
    check.each { |a, b| add(a, b, site) }

    flips = 0
    until check.empty?
      a, b = check.first
      check.delete([a, b])
      q = @directed[[b, a]]
      next unless q && incircle(@points[a], @points[b], @points[site], @points[q]).positive?

      remove(a, b, site)
      remove(b, a, q)
      add(a, q, site)
      add(q, b, site)
      check.add([a, q])
      check.add([q, b])
      flips += 1
    end
    { kind: kind, containing: containing, visible: visible, flips: flips,
      triangle_count: @directed.size / 3, hull_count: hull_edges.size }
  end

  def visibility_walk(query, triangles, edge_triangles)
    path = [1]
    loop do
      a, b, c = triangles[path.last]
      crossed = [[a, b], [b, c], [c, a]].find do |u, v|
        orient(@points[u], @points[v], query).negative?
      end
      return [path, nil] unless crossed

      u, v = crossed
      following = edge_triangles[[v, u]]
      return [path, [u, v].sort] unless following

      path << following
    end
  end

  private

  def add(a, b, c)
    @directed[[a, b]] = c
    @directed[[b, c]] = a
    @directed[[c, a]] = b
  end

  def remove(a, b, c)
    @directed.delete([a, b])
    @directed.delete([b, c])
    @directed.delete([c, a])
  end
end
