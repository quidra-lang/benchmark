fixed =: 4 : 0
  scale =. 10 ^ x
  rounded =. (*y) * <. 0.5 + scale * |y
  , (":x) 8!:2 rounded % scale
)

main =: 3 : 0
  values =. 72 85 64 90 85 58 77 85 69 93 71
  mean =. (+/values)%#values
  ordered =. /:~values
  candidates =. ~.ordered
  counts =. +/"1 candidates =/ values
  mode =. (counts i. >./counts){candidates
  squares =. 0.0
  for_value. values do.
    difference =. value-mean
    squares =. squares+difference*difference
  end.
  deviation =. %:squares%#values
  smoutput 'mean: ',3 fixed mean
  smoutput 'median: ',":5{ordered
  smoutput 'mode: ',":mode
  smoutput 'range: ',":({:ordered)-{.ordered
  smoutput 'stdev: ',3 fixed deviation
)
main ''
