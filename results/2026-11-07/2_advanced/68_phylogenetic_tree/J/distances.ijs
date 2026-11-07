pair_counts =: 4 : 0
 'i j' =. x
 n =. s =. v =. 0
 for_c. i.L do.
  a =. (<i,c){Alignment
  b =. (<j,c){Alignment
  if. (a e.'ACGT')*.b e.'ACGT' do.
   weight =. c{y
   n =. n+weight
   if. a~:b do.
    transition =. ((a e.'AG')*.b e.'AG')+.((a e.'CT')*.b e.'CT')
    if. transition do. s =. s+weight else. v =. v+weight end.
   end.
  end.
 end.
 n,s,v
)
correct_distance =: 4 : 0
 'n s v' =. y
 saturated =. n=0
 if. x=1 do. saturated =. saturated+.(4*(s+v))>:3*n
 elseif. x=2 do. saturated =. saturated+.((2*s)+v)>:n
 saturated =. saturated+.(2*v)>:n end.
 if. saturated do. (pn 'saturation_distance');1 return. end.
 select. x
 case. 0 do. d =. (s+v)%n
 case. 1 do. d =. _0.75*^.1-(4*(s+v))%(3*n)
 case. 2 do.
  first =. (1-((2*s)%n))-v%n
  second =. 1-(2*v)%n
  d =. (_0.5*^.first)-0.25*^.second
 end.
 d;0
)
distance_matrix =: 4 : 0
 matrix =. (N,N)$0.0
 saturated =. 0 3$0
 pairs =. 0 5$0
 for_i. i.N do.
  for_j. (i+1)+i.(N-i)-1 do.
   counts =. (i,j)pair_counts y
   pairs =. pairs,i,j,counts
   'd sat' =. x correct_distance counts
   matrix =. d(<i,j)}matrix
   matrix =. d(<j,i)}matrix
   if. sat do. saturated =. saturated,i,j,{.counts end.
  end.
 end.
 matrix;saturated;pairs
)
