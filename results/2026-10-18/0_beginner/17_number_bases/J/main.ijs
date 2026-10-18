base =: 4 : 0
  if. y=0 do. '0' return. end.
  digits =. (x&#.^:_1) y
  digits { '0123456789ABCDEF'
)
main =: 3 : 0
  for_n. 0 10 255 1000 43981 65535 do.
    smoutput (":n), ': bin=', (2 base n), ' oct=', (8 base n), ' hex=', 16 base n
  end.
)
main ''
