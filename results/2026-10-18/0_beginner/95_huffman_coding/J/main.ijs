smallest =: 3 : 0
  best =. {.y
  for_node. }.y do.
    if. ((node{weights)<best{weights)+.((node{weights)=best{weights)*.(node{minima)<best{minima do.
      best =. node
    end.
  end.
  best
)
assign =: 4 : 0
  node =. x
  prefix =. y
  symbol =. node{symbols
  if. symbol>:0 do.
    codes =: (<prefix) symbol}codes
  else.
    (node{left) assign prefix,'0'
    (node{right) assign prefix,'1'
  end.
  i.0 0
)
main =: 3 : 0
  text =. 'she sells sea shells by the sea shore'
  alphabet =. ' abcdefghijklmnopqrstuvwxyz'
  frequencies =. +/"1 alphabet =/text
  weights =: minima =: left =: right =: symbols =: i.0
  active =. i.0
  for_i. I.frequencies>0 do.
    active =. active,#weights
    weights =: weights,i{frequencies
    minima =: minima,i
    left =: left,_1
    right =: right,_1
    symbols =: symbols,i
  end.
  while. (#active)>1 do.
    first =. smallest active
    active =. active-.first
    second =. smallest active
    active =. active-.second
    node =. #weights
    weights =: weights,(first{weights)+second{weights
    minima =: minima,(first{minima)<.second{minima
    left =: left,first
    right =: right,second
    symbols =: symbols,_1
    active =. active,node
  end.
  codes =: 27$<''
  ({.active) assign ''
  bits =. 0
  quote =. 39{a.
  for_i. I.frequencies>0 do.
    code =. >i{codes
    frequency =. i{frequencies
    bits =. bits+frequency*#code
    smoutput quote,(i{alphabet),quote,' freq=',(":frequency),' code=',code
  end.
  smoutput 'encoded bits: ',":bits
  smoutput 'fixed 8-bit: ',":8*#text
)
main ''
