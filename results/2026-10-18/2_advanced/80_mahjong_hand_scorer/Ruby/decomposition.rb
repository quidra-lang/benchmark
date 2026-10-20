require_relative 'tiles'

module Decomposition
  def self.standard(counts, meld_count = 0)
    needed = 4 - meld_count
    return [] unless counts.sum == needed * 3 + 2

    remaining = counts.dup
    found = []
    visit = lambda do |pair, sets|
      first = remaining.index { |n| n.positive? }
      if sets.size == needed
        found << [pair, sets.sort_by { |b| [b.first, b.first == b.last ? 0 : 1] }] unless first
        next
      end
      next unless first

      if remaining[first] >= 3
        remaining[first] -= 3
        visit.call(pair, sets + [[first] * 3])
        remaining[first] += 3
      end
      if first < 27 && first % 9 <= 6 && remaining[first + 1].positive? && remaining[first + 2].positive?
        block = [first, first + 1, first + 2]
        block.each { |k| remaining[k] -= 1 }
        visit.call(pair, sets + [block])
        block.each { |k| remaining[k] += 1 }
      end
    end
    34.times do |pair|
      next if remaining[pair] < 2

      remaining[pair] -= 2
      visit.call(pair, [])
      remaining[pair] += 2
    end
    found.uniq
  end

  def self.seven_pairs?(counts)
    counts.count(2) == 7 && counts.all? { |n| n == 0 || n == 2 }
  end

  def self.thirteen_orphans?(counts)
    counts.sum == 14 && Tiles::YAOCHUU.all? { |k| counts[k].positive? } &&
      counts.each_index.all? { |k| counts[k].zero? || Tiles::YAOCHUU.include?(k) }
  end

  def self.winning?(counts, meld_count = 0)
    !standard(counts, meld_count).empty? ||
      (meld_count.zero? && (seven_pairs?(counts) || thirteen_orphans?(counts)))
  end

  def self.waiting_tiles(hand, melds, meld_count)
    counts = hand.dup
    (0...34).select do |kind|
      next false if hand[kind] + melds[kind] >= 4

      counts[kind] += 1
      winning = winning?(counts, meld_count)
      counts[kind] -= 1
      winning
    end
  end

  def self.wait_shape(form, block, win, hand)
    return 'tanki' if form == 'chiitoitsu'
    return Tiles::YAOCHUU.all? { |k| hand[k] == 1 } ? 'thirteen' : 'single' if form == 'kokushi'
    return 'tanki' if block.size == 2
    return 'shanpon' if block.first == block.last
    return 'kanchan' if win == block.first + 1
    return 'penchan' if (block.first % 9 == 0 && win == block.last) ||
                        (block.first % 9 == 6 && win == block.first)

    'ryanmen'
  end
end
