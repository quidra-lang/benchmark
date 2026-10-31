main =: 3 : 0
  days =. ;:'Mon Tue Wed Thu Fri Sat Sun'
  counts =. 7 12 4 15 9 18 11
  for_i. i.7 do.
    n =. i{counts
    smoutput (>i{days), ' | ', (n$'*'), ' ', ":n
  end.
)
main ''
