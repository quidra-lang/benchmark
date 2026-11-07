select_constituents =: 3 : 0
 chosen =. i.0
 status =. 0$a:
 for_i. i.#Speeds do.
  state =. 'fitted'
  if. ((i{Speeds)*y)<360*pn 'rayleigh' do. state =. 'short'
  else.
   for_j. chosen do.
    if. ((|(i{Speeds)-j{Speeds)*y)<360*pn 'rayleigh' do. state =. 'conflict:',j{::CNames
    break. end.
   end.
  end.
  if. state-:'fitted' do. chosen =. chosen,i end.
  status =. status,<state
 end.
 chosen;status
)
angle =: 4 : 0
 d =. x*y
 ((d-360*<.d%360)*3.141592653589793)%180
)
regressors =: 4 : 0
 r =. ,1.0
 for_i. x do.
  th =. (i{Speeds)angle y
  r =. r,(2 o.th),1 o.th
 end.
 r
)
fit =: 3 : 0
 'chosen times values' =. y
 p =. 1+2*#chosen
 a =. (p,p)$0.0
 rhs =. p$0.0
 for_i. i.#times do.
  r =. chosen regressors i{times
  a =. a+r*/r
  rhs =. rhs+r*i{values
 end.
 m =. a,.rhs,.=i.p
 for_j. i.p do.
  pivot =. j+{.\:|j}.j{"1 m
  if. pivot~:j do. old =. j{m
  m =. (pivot{m)j}m
  m =. old pivot}m end.
  for_i. (j+1)+i.(p-j)-1 do.
   f =. (<i,j){m
   f =. f%(<j,j){m
   for_c. j+i.(1+2*p)-j do. m =. (((<i,c){m)-f*(<j,c){m)(<i,c)}m end.
  end.
 end.
 sol =. (p,p+1)$0.0
 for_c. i.p+1 do.
  for_i. |.i.p do.
   s =. (<i,p+c){m
   for_j. (i+1)+i.(p-i)-1 do. s =. s-((<i,j){m)*(<j,c){sol end.
   sol =. (s%(<i,i){m)(<i,c)}sol
  end.
 end.
 coef =. 0{"1 sol
 amp =. phase =. i.0
 for_i. i.#chosen do.
  aa =. (1+2*i){coef
  bb =. (2+2*i){coef
  amp =. amp,%:(aa*aa)+bb*bb
  phase =. phase,360|((12 o.aa j.bb)*180)%3.141592653589793
 end.
 (0{coef);chosen;coef;amp;phase;(1}."1 sol)
)
