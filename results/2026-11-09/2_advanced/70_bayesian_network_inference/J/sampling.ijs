random =: 3 : 0
 RNG =: 2147483647|48271x*RNG
 (0.0+RNG)%2147483647
)
weighted_sample =: 3 : 0
 'ev es' =. y
 row =. NV$0
 weight =. 1.0
 for_v. Topological do.
  r =. (v{::Parents)row_number row
  probs =. r{v{::CPTs
  i =. ev i.v
  if. i<#ev do. s =. i{es
  weight =. weight*s{probs
  else.
   u =. random ''
   total =. 0.0
   s =. (v{K)-1
   for_j. i.v{K do.
    total =. total+j{probs
    if. u<total do. s =. j
    break. end.
   end.
  end.
  row =. s v}row
 end.
 row;weight
)
