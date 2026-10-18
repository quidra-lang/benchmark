fixed =: 4 : 0
  scale =. 10 ^ x
  rounded =. (*y) * <. 0.5 + scale * |y
  , (":x) 8!:2 rounded % scale
)

main =: 3 : 0
  names =. ;:'Tanaka Suzuki Yamada Ito Kato Mori'
  scores =. 6 3$78 85 94 88 74 82 65 90 71 80 79 85 92 88 95 70 62 78
  totals =. +/"1 scores
  alpha =. /:names
  order =. alpha {~ \:alpha{totals
  previous =. _1
  rank =. 0
  for_position. i.6 do.
    i =. position{order
    total =. i{totals
    if. total~:previous do. rank =. >:position end.
    previous =. total
    smoutput (":rank),'. ',(>i{names),' total=',(":total),' average=',2 fixed total%3
  end.
)
main ''
