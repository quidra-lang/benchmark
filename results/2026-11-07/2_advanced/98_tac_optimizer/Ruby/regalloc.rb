require_relative 'dataflow'

module TAC
  class Allocation
    attr_reader :graph, :cost, :order, :potential, :colors
    def initialize(function, cfg, flow, k)
      @graph, @cost, @order, @potential, @colors = {}, Hash.new(0), [], [], {}
      nodes = (function.params + cfg.reachable.flat_map { |b| b.instructions.flat_map { |s| [s.x, *s.uses].compact } }).uniq.sort
      nodes.each { |v| graph[v] = Set.new }
      edge = lambda do |a, b|
        return if a == b
        graph[a] << b
        graph[b] << a
      end
      cfg.reachable.each do |b|
        live = flow.output[:live][b.id].dup
        b.instructions.reverse_each do |s|
          if s.x
            live.each { |v| edge.call(s.x, v) unless s.kind == :copy && s.a == v }
          end
          live.delete(s.x)
          live.merge(s.uses)
          [s.x, *s.uses].compact.each { |v| cost[v] += 10**b.depth }
        end
      end
      function.params.each do |p|
        cost[p] += 1
        (flow.input[:live][1] | function.params.to_set).each { |v| edge.call(p, v) }
      end
      remaining = nodes.to_set
      until remaining.empty?
        degree = remaining.to_h { |v| [v, (graph[v] & remaining).size] }
        small = remaining.select { |v| degree[v] < k }
        if small.empty?
          v = remaining.min { |a, b| (cost[a] * degree[b] <=> cost[b] * degree[a]).nonzero? || (a <=> b) }
          potential << [v, cost[v], degree[v]]
        else
          v = small.min_by { |n| [degree[n], n] }
        end
        order << v
        remaining.delete(v)
      end
      partners = Hash.new { |h, v| h[v] = Set.new }
      function.instructions.each do |s|
        next unless s.kind == :copy && s.a.is_a?(String) && s.x != s.a
        partners[s.x] << s.a
        partners[s.a] << s.x
      end
      order.reverse_each do |v|
        free = (0...k).to_a - graph[v].filter_map { |n| colors[n] }
        preferred = partners[v].filter_map { |n| colors[n] } & free
        colors[v] = preferred.min || free.min
      end
    end
  end
end
