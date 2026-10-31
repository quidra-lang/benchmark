main =: 3 : 0
  n =. 5
  for_row. >:i.<:2*n do.
    i =. row <. (2*n)-row
    smoutput ((n-i)$' '), ((2*i)-1)$'*'
  end.
)
main ''
