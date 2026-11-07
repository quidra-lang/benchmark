lower_bound =: 3 : 0
 z =. 0
 interval =. 0,#Text
 ds =. i.0
 for_ch. y do.
  interval =. Reverse extend ch;({.interval);{:interval
  if. ({.interval)>:{:interval do. z =. z+1
  interval =. 0,#Text end.
  ds =. ds,z
 end.
 ds
)
backtrack =: 4 : 0
 ds =. 0,lower_bound y
 stack =. ,:((#y)-1),x,0,#Text
 nodes =. leaves =. positions =. 0
 hits =. 0 2$0
 while. #stack do.
  'i z lo hi' =. {:stack
  stack =. }:stack
  nodes =. nodes+1
  if. z<(i+1){ds do. continue. end.
  if. i=_1 do.
   leaves =. leaves+1
   positions =. positions+hi-lo
   for_row. lo+i.hi-lo do. hits =. hits,({.Forward locate row),x-z end.
  else.
   for_ch. 'TGCA' do.
    'a b' =. Forward extend ch;lo;hi
    zz =. z-ch~:i{y
    if. (a<b)*.zz>:0 do. stack =. stack,(i-1),zz,a,b end.
   end.
  end.
 end.
 SearchTotals =: SearchTotals+1,nodes,leaves,positions
 hits
)
