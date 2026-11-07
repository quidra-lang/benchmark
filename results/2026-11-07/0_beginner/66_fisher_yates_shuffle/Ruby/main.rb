ranks = 'A23456789TJQK'
deck = 'SHDC'.chars.flat_map { |suit| ranks.chars.map { |rank| rank + suit } }
state = 2026
(deck.length - 1).downto(1) do |i|
  state = state * 48271 % 2147483647
  j = state % (i + 1)
  deck[i], deck[j] = deck[j], deck[i]
end
deck.each_slice(13) { |cards| puts cards.join(' ') }
