hands = [
  '9C 9D 5H QH 2C', '4D AH 3C 5S 2H', 'KS 8S 2S JS 6S', '7H 7D KC 7S KD',
  '3H 6C 4S 2D 5C', 'JD TC 4H 8C AS', 'QC 6D QS 3S 6H', '9H KH 9S 8H 3D'
]
categories = [
  'high card', 'one pair', 'two pair', 'three of a kind', 'straight',
  'flush', 'full house', 'four of a kind', 'straight flush'
]
ranked = hands.map do |hand|
  cards = hand.split
  counts = cards.map { |card| '23456789TJQKA'.index(card[0]) + 2 }.tally
  ranks = counts.keys.sort
  wheel = ranks == [2, 3, 4, 5, 14]
  straight = ranks.length == 5 && (ranks[-1] - ranks[0] == 4 || wheel)
  flush = cards.map { |card| card[1] }.uniq.length == 1
  pattern = counts.values.sort.reverse
  strength = if straight && flush
               8
             elsif pattern[0] == 4
               7
             elsif pattern == [3, 2]
               6
             elsif flush
               5
             elsif straight
               4
             elsif pattern[0] == 3
               3
             elsif pattern == [2, 2, 1]
               2
             elsif pattern[0] == 2
               1
             else
               0
             end
  sequence = counts.keys.sort_by { |rank| [-counts[rank], -rank] }
  sequence = [5, 4, 3, 2, 1] if wheel && straight
  [strength, sequence, hand]
end
ranked.sort_by! { |strength, sequence, _| [-strength, *sequence.map { |rank| -rank }] }
ranked.each_with_index do |(strength, _, hand), i|
  puts "#{i + 1}. #{hand}: #{categories[strength]}"
end
