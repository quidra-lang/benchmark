split =: 4 : 0
  <;._1 x,y
)

score =: 3 : 0
  cards =. ' ' split y
  counts =. 15$0
  suits =. ''
  for_box. cards do.
    card =. >box
    rank =. 2+'23456789TJQKA'i.{.card
    counts =. (>:rank{counts) rank}counts
    suits =. suits,{:card
  end.
  flush =. *./suits={.suits
  distinct =. I.counts>0
  wheel =. distinct-:2 3 4 5 14
  straight =. (5=#distinct)*.((4=({:distinct)-{.distinct)+.wheel)
  largest =. >./counts
  pairs =. +/counts=2
  category =. 0
  if. straight*.flush do. category =. 8
  elseif. largest=4 do. category =. 7
  elseif. (largest=3)*.pairs=1 do. category =. 6
  elseif. flush do. category =. 5
  elseif. straight do. category =. 4
  elseif. largest=3 do. category =. 3
  elseif. pairs=2 do. category =. 2
  elseif. pairs=1 do. category =. 1
  end.
  sequence =. i.0
  if. straight*.wheel do. sequence =. 5 4 3 2 1
  else.
    sequence =. |.distinct
    sequence =. sequence {~ \:sequence{counts
  end.
  category,5{.sequence
)
main =: 3 : 0
  hands =. '9C 9D 5H QH 2C';'4D AH 3C 5S 2H';'KS 8S 2S JS 6S';'7H 7D KC 7S KD';'3H 6C 4S 2D 5C';'JD TC 4H 8C AS';'QC 6D QS 3S 6H';'9H KH 9S 8H 3D'
  categories =. 'high card';'one pair';'two pair';'three of a kind';'straight';'flush';'full house';'four of a kind';'straight flush'
  keys =. 0 6$0
  for_hand. hands do. keys =. keys,score >hand end.
  order =. \:keys
  for_position. i.8 do.
    i =. position{order
    category =. (<i,0){keys
    smoutput (":>:position),'. ',(>i{hands),': ',>category{categories
  end.
)
main ''
