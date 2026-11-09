module Analysis
  def self.points(domains, index = 0, values = {}, &block)
    if index == domains.length
      yield values
    else
      name, candidates = domains[index]
      candidates.each do |value|
        values[name] = value
        points(domains, index + 1, values, &block)
      end
    end
  end

  def self.day_notation(days)
    days.sort.chunk_while { |a, b| b == a + 1 }.map { |run| "#{run.first}-#{run.last}" }.join(',')
  end

  def self.blocker(rule, standalone)
    rule.parent.children.each do |earlier|
      break if earlier.equal?(rule)
      return earlier.id unless standalone[earlier.id] == Combining::NA
    end
    nil
  end

  def self.conflict_winner(policy, earlier, later)
    return earlier.id if policy.behavior == 'first-applicable'
    effect = %w[deny-overrides permit-unless-deny].include?(policy.behavior) ? 'DENY' : 'PERMIT'
    earlier.behavior == effect ? earlier.id : later.id
  end
end
