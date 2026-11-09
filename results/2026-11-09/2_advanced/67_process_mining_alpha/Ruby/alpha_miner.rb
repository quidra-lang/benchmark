require_relative 'dfg'

module AlphaMiner
  module_function

  def extend_pair(pair, activity, side, relation)
    own = pair[side]
    return nil if own.include?(activity) || relation.call(activity, activity) != '#'
    return nil if own.any? { |other| relation.call(activity, other) != '#' }
    return nil if side == :a && pair[:b].any? { |other| relation.call(activity, other) != '->' }
    return nil if side == :b && pair[:a].any? { |other| relation.call(other, activity) != '->' }
    {a: side == :a ? (pair[:a] + [activity]).sort : pair[:a],
     b: side == :b ? (pair[:b] + [activity]).sort : pair[:b]}
  end

  def compare_pairs(first, second)
    [first[:a], first[:b]] <=> [second[:a], second[:b]]
  end

  def triangle_counts(log)
    counts = Hash.new(0)
    log.each do |entry|
      entry[:trace].each_cons(3) { |a, b, c| counts[[a, b]] += entry[:weight] if a != b && a == c }
    end
    counts
  end

  def alpha_plus_relation(counts, triangles)
    causal = lambda do |a, b|
      Dfg.count(counts, a, b).positive? && (Dfg.count(counts, b, a).zero? ||
        (a != b && Dfg.count(triangles, a, b).positive? && Dfg.count(triangles, b, a).positive?))
    end
    lambda do |a, b|
      if causal.call(a, b)
        '->'
      elsif causal.call(b, a)
        '<-'
      elsif Dfg.count(counts, a, b).positive? && Dfg.count(counts, b, a).positive?
        '||'
      else
        '#'
      end
    end
  end
end
