main =: 3 : 0
  sales =. 120 135 98 143 160 152 171 149 188 176
  window =. 3
  for_index. (window-1)+i.(#sales)-window-1 do.
    total =. +/ ((index-window-1)+i.window){sales
    smoutput 'day ', (":>:index), ': ', , '2' 8!:2 total%window
  end.
)
main ''
