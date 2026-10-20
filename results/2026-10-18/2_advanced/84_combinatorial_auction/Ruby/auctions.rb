module Auctions
  Candidate = Struct.new(:number, :bundle, :value)
  module_function

  def candidates(bids, xor)
    (1...(1 << bids.size)).filter_map do |number|
      next if xor && (number & (number - 1)) != 0
      bundle, value, feasible = Set.new, 0, true
      bids.each_with_index do |bid, index|
        next if (number & (1 << index)).zero?
        if bundle.intersect?(bid.bundle)
          feasible = false
          break
        end
        bundle.merge(bid.bundle)
        value += bid.amount
      end
      Candidate.new(number, bundle, value) if feasible
    end
  end

  def value_of(candidates, items)
    candidates.select { |candidate| candidate.bundle.subset?(items) }.map(&:value).max || 0
  end

  def english(participants, reserve, increment)
    price, steps = reserve, 0
    remaining = participants.each_index.select { |index| participants[index].value >= price }
    winner = nil
    paid = 0
    while remaining.size >= 2
      previous = remaining
      price += increment
      steps += 1
      remaining = participants.each_index.select { |index| participants[index].value >= price }
      if remaining.empty?
        winner, paid = previous.first, price - increment
        break
      end
    end
    unless remaining.empty?
      winner, paid = remaining.first, price
    end
    drops = participants.map do |participant|
      drop = participant.value < reserve ? reserve : reserve + ((participant.value - reserve) / increment + 1) * increment
      drop if drop <= price
    end
    OpenStruct.new(winner: winner, price: paid, steps: steps, drops: drops)
  end

  def dutch(participants, reserve, start, decrement)
    price, steps = start, 0
    while price >= reserve
      eligible = participants.each_index.select { |index| participants[index].bid >= price }
      unless eligible.empty?
        winner = eligible.min_by { |index| [-participants[index].bid, index] }
        return OpenStruct.new(winner: winner, price: price, steps: steps)
      end
      price -= decrement
      steps += 1
    end
    OpenStruct.new(winner: nil, price: 0, steps: steps)
  end
end
