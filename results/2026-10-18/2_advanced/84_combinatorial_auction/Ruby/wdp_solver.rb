module WDPSolver
  module_function

  def shares(items, reserves, bids)
    items.map do |item|
      share, source = Rational(reserves[item]), nil
      bids.each do |bid|
        next unless bid.bundle.include?(item)
        candidate = Rational(bid.amount, bid.bundle.size)
        share, source = candidate, bid.number if candidate > share
      end
      [item, share, source]
    end
  end

  def solve(items, reserves, bids)
    bids = bids.sort_by(&:number)
    root = shares(items, reserves, bids)
    result = OpenStruct.new(welfare: nil, numbers: [], nodes: 0, pruned: 0, leaves: 0,
                            improvements: [], shares: root, bound: root.sum { |_, share, _| share })
    visit = lambda do |decided, used, welfare, chosen|
      result.nodes += 1
      if decided.size == items.size
        result.leaves += 1
        numbers = chosen.map(&:number).sort
        if result.welfare.nil? || welfare > result.welfare ||
           (welfare == result.welfare && (numbers <=> result.numbers).negative?)
          result.welfare, result.numbers = welfare, numbers
          result.improvements << [result.nodes, welfare, numbers]
        end
        next
      end
      usable = bids.reject { |bid| bid.bundle.intersect?(decided) || (bid.xor && used.include?(bid.bidder)) }
      remaining = items.reject { |item| decided.include?(item) }
      bound = welfare + shares(remaining, reserves, usable).sum { |_, share, _| share }
      if !result.welfare.nil? && bound < result.welfare
        result.pruned += 1
        next
      end
      first = remaining.first
      usable.each do |bid|
        next unless bid.bundle.include?(first)
        visit.call(decided | bid.bundle, bid.xor ? used | [bid.bidder] : used,
                   welfare + bid.amount, chosen + [bid])
      end
      visit.call(decided | [first], used, welfare + reserves[first], chosen)
    end
    visit.call(Set.new, Set.new, 0, [])
    by_number = bids.to_h { |bid| [bid.number, bid] }
    result.winning = result.numbers.map { |number| by_number[number] }
    result
  end

  def greedy_order(bids)
    bids.sort do |a, b|
      comparison = (b.amount**2 * a.bundle.size) <=> (a.amount**2 * b.bundle.size)
      comparison.zero? ? a.number <=> b.number : comparison
    end
  end

  def greedy_select(bids)
    occupied, used, chosen = Set.new, Set.new, []
    bids.each do |bid|
      next if bid.bundle.intersect?(occupied) || (bid.xor && used.include?(bid.bidder))
      chosen << bid
      occupied.merge(bid.bundle)
      used.add(bid.bidder) if bid.xor
    end
    chosen
  end
end
