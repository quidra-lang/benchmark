sum =: 3 : 0
 s =. 0.0
 for_v. y do. s =. s+v end.
 s
)
assignments =: 3 : 0
 if. 0=#y do. 1 0$0 return. end.
 |:(y{K)#:i.*/y{K
)
row_number =: 4 : 0
 if. 0=#x do. 0 else. (x{K)#.x{y end.
)
family =: 4 : 0
 v =. x
 pars =. y
 nr =. */pars{K
 counts =. (nr,v{K)$0
 for_row. Data do.
  r =. pars row_number row
  s =. v{row
  counts =. (1+(<r,s){counts)(<r,s)}counts
 end.
 probs =. (0,v{K)$0.0
 for_r. i.nr do.
  a =. Alpha+r{counts
  probs =. probs,a%sum a
 end.
 ll =. 0.0
 for_r. i.nr do.
  for_s. i.v{K do.
   c =. (<r,s){counts
   if. c do. ll =. ll+c*^. (<r,s){probs end.
  end.
 end.
 d =. nr*((v{K)-1)
 counts;probs;ll;d;(ll-(d*^.NS)%2)
)
learn =: 3 : 0
 CPTs =: Counts =: Learned =: 0$a:
 LLs =: Dimensions =: BICs =: i.0
 for_v. i.NV do.
  'counts probs ll d bic' =. v family v{::Parents
  Counts =: Counts,<counts
  Learned =: Learned,<probs
  if. 'GIVEN'-:v{::Source do. probs =. v{::Given end.
  CPTs =: CPTs,<probs
  ll =. 0.0
  for_r. i.#counts do.
   for_s. i.v{K do.
    c =. (<r,s){counts
    if. c do. ll =. ll+c*^.(<r,s){probs end.
   end.
  end.
  LLs =: LLs,ll
  Dimensions =: Dimensions,d
  BICs =: BICs,ll-(d*^.NS)%2
 end.
 i.0 0
)
probability =: 4 : 0
 r =. (x{::Parents)row_number y
 (<r,x{y){x{::CPTs
)
