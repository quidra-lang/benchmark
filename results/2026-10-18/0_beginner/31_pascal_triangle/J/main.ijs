main =: 3 : 0
  row =. ,1
  for_n. i.12 do.
    smoutput ":row
    row =. (0,row)+(row,0)
  end.
)
main ''
