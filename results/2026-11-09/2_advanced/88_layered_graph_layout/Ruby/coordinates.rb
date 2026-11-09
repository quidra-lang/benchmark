require 'set'
require_relative 'crossing'

module Coordinates
  VARIANTS = %w[ul ur dl dr].freeze
  Result = Struct.new(:x, :left, :right, :aligned, :blocks, :widths, :smallest, :conflicts)

  def self.assign(orders, upper, lower, widths, nodes, settings)
    count = widths.size
    vertical = %w[TB BT].include?(settings['direction'])
    left = widths.map { |w| vertical ? (w - 1) / 2 : 0 }
    right = widths.each_with_index.map { |w, v| vertical ? w - 1 - left[v] : 0 }
    pos = Crossing.positions(orders)
    marked = Set.new
    orders.each_cons(2) do |above, below|
      k0 = start = 0
      below.each_with_index do |v, last|
        inner = v >= nodes && upper[v][0] >= nodes
        next unless inner || last == below.size - 1
        k1 = inner ? pos[upper[v][0]] : above.size - 1
        below[start..last].each do |w|
          upper[w].each { |u| marked << [u, w] if pos[u] < k0 || pos[u] > k1 }
        end
        start, k0 = last + 1, k1
      end
    end
    layouts, blocks, bounds, spans = {}, {}, {}, {}
    VARIANTS.each do |variant|
      leftward = variant[1] == 'l'
      upward = variant[0] == 'u'
      scan = orders.map { |layer| leftward ? layer.dup : layer.reverse }
      rank = Crossing.positions(scan)
      root = (0...count).to_a
      align = root.dup
      layers = (0...orders.size).to_a
      layers.reverse! unless upward
      reference = upward ? upper : lower
      layers.drop(1).each do |i|
        rho = -1
        scan[i].each do |v|
          neighbors = reference[v].sort_by { |u| rank[u] }
          next if neighbors.empty?
          [(neighbors.size - 1) / 2, neighbors.size / 2].each do |m|
            u = neighbors[m]
            segment = upward ? [u, v] : [v, u]
            next unless align[v] == v && !marked.include?(segment) && rho < rank[u]
            align[u] = v
            root[v] = root[u]
            align[v] = root[v]
            rho = rank[u]
          end
        end
      end
      representatives = root.uniq.sort
      incoming = representatives.to_h { |v| [v, {}] }
      outgoing = representatives.to_h { |v| [v, {}] }
      scan.each do |layer|
        layer.each_cons(2) do |first, second|
          a, b = leftward ? [first, second] : [second, first]
          gap = settings[a < nodes && b < nodes ? 'node_sep' : 'dummy_sep']
          distance = right[a] + left[b] + 1 + gap
          origin, target = root[first], root[second]
          distance = [distance, outgoing[origin].fetch(target, distance)].max
          outgoing[origin][target] = incoming[target][origin] = distance
        end
      end
      pending = incoming.transform_values(&:size)
      ready = representatives.select { |v| pending[v].zero? }
      ordered, y1, y2 = [], {}, {}
      until ready.empty?
        v = ready.pop
        ordered << v
        y1[v] = incoming[v].map { |u, d| y1[u] + d }.max || 0
        outgoing[v].each_key do |w|
          pending[w] -= 1
          ready << w if pending[w].zero?
        end
      end
      ordered.reverse_each do |v|
        y2[v] = y1[v]
        y2[v] = [y1[v], outgoing[v].map { |w, d| y2[w] - d }.min].max unless outgoing[v].empty?
      end
      coordinates = root.map { |v| leftward ? y2[v] : -y2[v] }
      low = count.times.map { |v| coordinates[v] - left[v] }.min
      high = count.times.map { |v| coordinates[v] + right[v] }.max
      layouts[variant], blocks[variant] = coordinates, representatives.size
      bounds[variant], spans[variant] = [low, high], high - low + 1
    end
    smallest = VARIANTS.min_by { |v| spans[v] }
    aligned = VARIANTS.to_h do |v|
      side = v[1] == 'l' ? 0 : 1
      shift = bounds[smallest][side] - bounds[v][side]
      [v, layouts[v].map { |x| x + shift }]
    end
    x = count.times.map do |v|
      values = VARIANTS.map { |k| aligned[k][v] }.sort
      (values[1] + values[2]) / 2
    end
    low = count.times.map { |v| x[v] - left[v] }.min
    Result.new(x.map { |value| value - low }, left, right, aligned, blocks, spans, smallest, marked)
  end
end
