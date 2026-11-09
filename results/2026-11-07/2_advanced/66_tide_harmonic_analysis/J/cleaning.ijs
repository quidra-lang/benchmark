median =: 3 : 0
 a =. /:~y
 n =. #a
 if. 2|n do. (<.n%2){a else. ((sum ((<.n%2)+_1 0){a)%2) end.
)
flat_runs =: 3 : 0
 'times values good' =. y
 reason =. (#times)$0
 runs =. 0 3$0
 i =. 0
 while. i<#times do.
  j =. i+1
  if. i{good do.
   while. j<#times do.
    if. (-.j{good)+.((j{times)~:1+(j-1){times)+.(j{values)~:i{values do. break. end.
    j =. j+1
   end.
   if. (j-i)>:pn 'flat_run' do.
    reason =. 1 (i+1+i.(j-i)-1)}reason
    runs =. runs,(i{times),((j-1){times),i{values
   end.
  end.
  i =. j
 end.
 reason;runs
)
spike_test =: 3 : 0
 'times residuals values' =. y
 'w c ks d' =. num&>pv 'spike'
 flagged =. (#times)$0
 details =. 0 6$0.0
 tested =. 0
 for_i. i.#times do.
  window =. (w>:|times-i{times)#residuals
  if. (#window)<c do. continue. end.
  tested =. tested+1
  me =. median window
  mad =. median |window-me
  limit =. d>.(ks*1.4826)*mad
  if. (|(i{residuals)-me)>limit do.
   flagged =. 1 i}flagged
   details =. details,(i{times),(i{values),(i{residuals),me,mad,limit
  end.
 end.
 flagged;details;tested
)
gaps =: 3 : 0
 out =. 0 3$0
 i =. 0
 while. i<#y do.
  if. (i{y)=0 do. i =. i+1
  continue. end.
  j =. i+1
  while. j<#y do. if. (j{y)=0 do. break. end.
  j =. j+1 end.
  kinds =. ~.(i+i.j-i){y
  cause =. 5
  if. 1=#kinds do. cause =. {.kinds end.
  out =. out,i,(j-1),cause
  i =. j
 end.
 out
)
