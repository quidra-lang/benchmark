predict =: 4 : 0
 'z chosen coef amp phase ainv' =. x
 h =. z
 for_k. i.#chosen do.
  th =. ((k{chosen){Speeds)angle y
  h =. h+(((1+2*k){coef)*2 o.th)+((2+2*k){coef)*1 o.th
 end.
 h
)
find_extrema =: 4 : 0
 g =. pn 'grid_minutes'
 mins =. (60*Ts)+g*i.1+<.(60*P)%g
 values =. x predict"_ 0 mins%60
 ex =. 0 3$0.0
 for_j. 1+i.(#values)-2 do.
  'a b c' =. (j+_1 0 1){values
  high =. (a<b)*.b>c
  low =. (a>b)*.b<c
  if. high+.low do.
   delta =. (a-c)%(2*((a-2*b)+c))
   ex =. ex,((j{mins)+delta*g),(b-((a-c)*delta)%4),high
  end.
 end.
 raw =. #ex
 while. 1<#ex do.
  diff =. |(}.1{"1 ex)-}:1{"1 ex
  i =. diff i.<./diff
  if. (i{diff)>:pn 'min_range' do. break. end.
  ex =. ex#~-. (i.#ex)e.i,i+1
 end.
 ex =. (<.0.5+0{"1 ex)(<a:;0)}ex
 ex;raw
)
