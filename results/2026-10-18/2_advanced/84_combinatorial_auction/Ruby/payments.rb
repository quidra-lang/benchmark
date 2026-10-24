module Payments
  module_function

  def vcg(items, reserves, bids, optimal, bidders)
    bidders.each_with_object({}) do |name, results|
      winning = optimal.winning.select { |bid| bid.bidder == name }
      next if winning.empty?
      alternative = WDPSolver.solve(items, reserves, bids.reject { |bid| bid.bidder == name })
      payment = alternative.welfare - (optimal.welfare - winning.sum(&:amount))
      results[name] = [payment, alternative]
    end
  end

  def critical(order, winning, reserves)
    winning.to_h do |bid|
      selected = WDPSolver.greedy_select(order.reject { |other| other.number == bid.number })
      rival = selected.find do |other|
        bid.bundle.intersect?(other.bundle) || (bid.xor && bid.bidder == other.bidder)
      end
      payment = bid.bundle.sum { |item| reserves[item] }
      if rival
        threshold = rival.amount**2 * bid.bundle.size
        earlier = lambda do |amount|
          score = amount**2 * rival.bundle.size
          score > threshold || (score == threshold && bid.number < rival.number)
        end
        low = high = 1
        high *= 2 until earlier.call(high)
        while low < high
          middle = (low + high) / 2
          earlier.call(middle) ? high = middle : low = middle + 1
        end
        payment = [payment, low].max
      end
      [bid.number, [payment, rival]]
    end
  end

  def coalitions(items, reserves, bids, bidders)
    result = []
    (0..bidders.size).each do |size|
      (0...bidders.size).to_a.combination(size) do |positions|
        members = positions.map { |position| bidders[position] }
        allocation = WDPSolver.solve(items, reserves, bids.select { |bid| members.include?(bid.bidder) })
        result << OpenStruct.new(members: members, mask: positions.sum { |position| 1 << position },
                                 welfare: allocation.welfare, numbers: allocation.numbers)
      end
    end
    result
  end

  def blocking(coalitions, seller, utilities)
    blocked, minimal = [], []
    coalitions.each do |coalition|
      payoff = seller + coalition.members.sum { |name| utilities[name] }
      next unless coalition.welfare > payoff
      record = OpenStruct.new(coalition: coalition, payoff: payoff, deficit: coalition.welfare - payoff)
      minimal << record unless blocked.any? { |other| (other.coalition.mask & coalition.mask) == other.coalition.mask }
      blocked << record
    end
    [blocked, minimal]
  end

  def gsp_price(ranking, rank)
    ranking[rank + 1]&.bid || 0
  end

  def slot_vcg(ranking, rates, rank)
    ((rank + 1)...[ranking.size, rates.size + 1].min).sum do |following|
      ranking[following].value * (rates[following - 1] - (rates[following] || 0))
    end
  end
end
