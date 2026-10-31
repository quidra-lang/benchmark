main =: 3 : 0
  state =. 12345
  counts =. 13$0
  for_trial. i.1000 do.
    state =. 2147483647 | 48271*state
    first =. 1+6|state
    state =. 2147483647 | 48271*state
    second =. 1+6|state
    sum =. first+second
    counts =. (>:sum{counts) sum}counts
  end.
  for_sum. 2+i.11 do. smoutput (":sum),': ',":sum{counts end.
  frequencies =. 2}.counts
  smoutput 'most frequent: ',":2+frequencies i. >./frequencies
)
main ''
