permutations =: 3 : 0
  'prefix used count' =. y
  if. 4=#prefix do.
    count =. >:count
    smoutput (":count),': ',prefix
    count return.
  end.
  for_i. i.4 do.
    if. -.i{used do.
      used =. 1 i}used
      count =. permutations (prefix,i{'ABCD');used;count
      used =. 0 i}used
    end.
  end.
  count
)
count =: permutations '';(4$0);0
