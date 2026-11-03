module Analysis
  def self.graph(events, copies)
    edges = events.to_h { |event| [event[:number], []] }
    events.each do |event|
      following = event[:process_events][event[:local]]
      edges[event[:number]] << following[:number] if following
    end
    copies.each do |copy|
      edges[copy[:send_event][:number]] << copy[:recv_event][:number] if copy[:recv_event]
    end
    edges
  end

  def self.path(source, target, edges)
    queue = [source]
    parents = { source => nil }
    cursor = 0
    while cursor < queue.size && !parents.key?(target)
      current = queue[cursor]
      cursor += 1
      edges[current].each do |following|
        next if parents.key?(following)
        parents[following] = current
        queue << following
      end
    end
    return unless parents.key?(target)
    result = []
    while target
      result << target
      target = parents[target]
    end
    result.reverse
  end

  def self.concurrency(events, indices)
    result = { pairs: events.size * (events.size - 1) / 2, ordered: 0,
               concurrent: 0, same_lamport: 0, inversions: 0, by_pair: Hash.new(0) }
    events.combination(2) do |a, b|
      if Clocks.relation(a[:vector], b[:vector]) == '||'
        result[:concurrent] += 1
        result[:same_lamport] += 1 if a[:lamport] == b[:lamport]
        pair = [a[:process], b[:process]].sort_by { |name| indices[name] }
        result[:by_pair][pair] += 1 if pair[0] != pair[1]
      else
        result[:ordered] += 1
      end
      result[:inversions] += 1 if (a[:time] - b[:time]) * (a[:lamport] - b[:lamport]) < 0
    end
    result
  end

  def self.races_and_violations(names, processes)
    races = []
    violations = []
    names.each do |name|
      delivered = processes[name][:delivered]
      delivered.each_cons(2) do |a, b|
        races << [name, a, b] if Clocks.relation(a[:send_event][:vector], b[:send_event][:vector]) == '||'
      end
      delivered.combination(2) do |a, b|
        violations << [name, a, b] if Clocks.before?(b[:send_event][:vector], a[:send_event][:vector])
      end
    end
    [races, violations]
  end

  def self.consistent?(cut, names, processes)
    names.each_with_index.all? do |name, i|
      cut[i].zero? || processes[name][:events][cut[i] - 1][:vector].each_with_index.all? { |value, j| value <= cut[j] }
    end
  end

  def self.enumerate(names, processes, time, thresholds)
    limits = names.map { |name| processes[name][:events].count { |event| event[:time] <= time } }
    initial = names.sum { |name| processes[name][:initial] }
    consistent = {}
    levels = Array.new(limits.sum + 1, 0)
    visit = lambda do |prefix|
      if prefix.size == names.size
        if consistent?(prefix, names, processes)
          balances = names.each_with_index.sum { |name, i| Processes.balance_at(processes[name], prefix[i]) }
          consistent[prefix] = initial - balances
          levels[prefix.sum] += 1
        end
      else
        (0..limits[prefix.size]).each { |value| visit.call(prefix + [value]) }
      end
    end
    visit.call([])
    predicates = thresholds.uniq.to_h do |threshold|
      count = consistent.count { |_, transit| transit >= threshold }
      zero = Array.new(names.size, 0)
      queue = [zero]
      seen = { zero => true }
      cursor = 0
      avoids = false
      while cursor < queue.size
        cut = queue[cursor]
        cursor += 1
        next if consistent.fetch(cut) >= threshold
        if cut == limits
          avoids = true
          break
        end
        names.each_index do |i|
          next if cut[i] == limits[i]
          following = cut.dup
          following[i] += 1
          next unless consistent.key?(following) && !seen.key?(following)
          seen[following] = true
          queue << following
        end
      end
      [threshold, { cuts: count, possibly: count.positive?, definitely: !avoids }]
    end
    { limits: limits, product: limits.reduce(1) { |a, n| a * (n + 1) },
      consistent: consistent.size, levels: levels, predicates: predicates }
  end
end
