module Search
  def self.lower_bounds(sequence, reverse_index)
    lower, upper, mismatches = 0, reverse_index.size, 0
    sequence.chars.map do |base|
      lower, upper = reverse_index.extend_interval(lower, upper, base)
      if lower >= upper
        mismatches += 1
        lower, upper = 0, reverse_index.size
      end
      mismatches
    end
  end

  def self.backtrack(sequence, maximum, forward_index, reverse_index)
    bounds = lower_bounds(sequence, reverse_index)
    stack = [[sequence.size - 1, maximum, 0, forward_index.size]]
    nodes, leaves = 0, []
    until stack.empty?
      position, remaining, lower, upper = stack.pop
      nodes += 1
      next if remaining < (position >= 0 ? bounds[position] : 0)
      if position == -1
        leaves << [lower, upper, maximum - remaining]
        next
      end
      'TGCA'.each_char do |base|
        first, last = forward_index.extend_interval(lower, upper, base)
        next if first >= last
        mismatch = base == sequence[position] ? 0 : 1
        stack << [position - 1, remaining - mismatch, first, last] if mismatch.zero? || remaining >= 1
      end
    end
    [nodes, leaves, leaves.sum { |lower, upper, _| upper - lower }]
  end
end
