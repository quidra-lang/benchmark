module Crossing
  def self.positions(orders)
    orders.each_with_object({}) { |layer, result| layer.each_with_index { |v, p| result[v] = p } }
  end

  def self.accumulator(segments, position, size)
    capacity = 1
    capacity *= 2 while capacity < size
    tree = Array.new(2 * capacity - 1, 0)
    count = 0
    segments.map { |p, q, _| [position[p], position[q]] }.sort.each do |_, q|
      k = q + capacity - 1
      tree[k] += 1
      while k.positive?
        count += tree[k + 1] if k.odd?
        k = (k - 1) / 2
        tree[k] += 1
      end
    end
    count
  end

  def self.cross?(a, b, position)
    (position[a[0]] - position[b[0]]) * (position[a[1]] - position[b[1]]) < 0
  end

  def self.brute_force(segments, position)
    segments.combination(2).count { |a, b| cross?(a, b, position) }
  end

  def self.gap_counts(gaps, orders)
    position = positions(orders)
    gaps.each_with_index.map { |segments, i| accumulator(segments, position, orders[i + 1].size) }
  end

  def self.total(gaps, orders)
    gap_counts(gaps, orders).sum
  end

  def self.local(gaps, orders, layer)
    position = positions(orders)
    [layer - 1, layer].select { |i| i >= 0 && i < gaps.size }.sum do |i|
      accumulator(gaps[i], position, orders[i + 1].size)
    end
  end

  def self.adjacent(v, w, upper, lower, position)
    [upper, lower].sum { |neighbors| neighbors[v].sum { |a| neighbors[w].count { |b| position[a] > position[b] } } }
  end
end
