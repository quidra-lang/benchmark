module AcyclicLayering
  def self.neighbors(count, edges)
    upper, lower = Array.new(count) { [] }, Array.new(count) { [] }
    edges.each { |a, b| lower[a] << b; upper[b] << a }
    [upper, lower]
  end

  def self.acyclic_order(count, edges)
    upper, lower = neighbors(count, edges)
    remaining = (0...count).to_a
    head, tail = [], []
    until remaining.empty?
      indegree = remaining.to_h { |v| [v, upper[v].count { |u| remaining.include?(u) }] }
      outdegree = remaining.to_h { |v| [v, lower[v].count { |u| remaining.include?(u) }] }
      sink = remaining.find { |v| outdegree[v].zero? }
      source = remaining.find { |v| indegree[v].zero? }
      if sink
        chosen = sink
        tail.unshift(chosen)
      else
        chosen = source || remaining.min_by { |v| [indegree[v] - outdegree[v], v] }
        head << chosen
      end
      remaining.delete(chosen)
    end
    head + tail
  end

  def self.heights(count, edges, settings)
    upper, lower = neighbors(count, edges)
    height = Array.new(count)
    labels = nil
    if settings['layering'] == 'coffman'
      labels = Array.new(count)
      (1..count).each do |label|
        candidates = (0...count).select { |v| labels[v].nil? && upper[v].all? { |u| labels[u] } }
        chosen = candidates.min_by { |v| [upper[v].map { |u| labels[u] }.sort.reverse, v] }
        labels[chosen] = label
      end
      current = occupied = 0
      count.times do
        chosen = (0...count).select { |v| height[v].nil? && lower[v].all? { |w| height[w] } }.max_by { |v| labels[v] }
        if occupied == settings['width'] || lower[chosen].any? { |w| height[w] == current }
          current += 1
          occupied = 0
        end
        height[chosen] = current
        occupied += 1
      end
    else
      count.times do
        v = (0...count).find { |u| height[u].nil? && lower[u].all? { |w| height[w] } }
        height[v] = lower[v].map { |w| height[w] + 1 }.max || 0
      end
    end
    before = edges.sum { |a, b| height[a] - height[b] - 1 }
    rounds = 0
    record = []
    promote = lambda do |v|
      diff = 0
      upper[v].each { |u| diff += promote.call(u) if height[u] == height[v] + 1 }
      height[v] += 1
      diff + lower[v].size - upper[v].size
    end
    if settings['promotion'] == 'on'
      loop do
        rounds += 1
        accepted = 0
        count.times do |v|
          next if upper[v].empty?
          saved = height.dup
          diff = promote.call(v)
          if diff.negative?
            record << [rounds, v, diff]
            accepted += 1
          else
            height.replace(saved)
          end
        end
        break if accepted.zero?
      end
    end
    [height, labels, before, rounds, record]
  end
end
