fixed =: 4 : 0
  scale =. 10 ^ x
  rounded =. (*y) * <. 0.5 + scale * |y
  , (":x) 8!:2 rounded % scale
)

main =: 3 : 0
  sales =. 120 135 98 143 160 152 171 149 188 176
  for_index. 2+i.8 do.
    total =. +/ ((index-2)+i.3){sales
    smoutput 'day ', (":>:index), ': ', 2 fixed total%3
  end.
)
main ''
