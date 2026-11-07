build_index =: 3 : 0
 'sa classes' =. suffix_array y
 n =. #y
 bwt =. (n|sa-1){y
 counts =. +/"1 Symbols=/y
 c =. }:0,+/\counts
 interval =. pn 'OCC_INTERVAL'
 checkpoints =. 0 6$0
 for_q. i.1+<.n%interval do. checkpoints =. checkpoints,+/"1 Symbols=/(q*interval){.bwt end.
 sample =. n$_1
 ids =. I.0=(pn 'SA_SAMPLE_INTERVAL')|sa
 sample =. (ids{sa)ids}sample
 y;sa;classes;bwt;c;checkpoints;sample
)
occ =: 4 : 0
 'symbol pos' =. y
 bwt =. 3{::x
 interval =. pn 'OCC_INTERVAL'
 q =. <.pos%interval
 ((<q,Symbols i.symbol){5{::x)++/symbol=(q*interval)}.pos{.bwt
)
extend =: 4 : 0
 'symbol lo hi' =. y
 if. symbol='N' do. 0 0 return. end.
 c =. (Symbols i.symbol){4{::x
 (c+x occ symbol;lo),c+x occ symbol;hi
)
lf =: 4 : 0
 ch =. y{3{::x
 ((Symbols i.ch){4{::x)+x occ ch;y
)
locate =: 4 : 0
 row =. y
 steps =. 0
 sample =. 6{::x
 while. (row{sample)<0 do. row =. x lf row
 steps =. steps+1 end.
 ((row{sample)+steps),steps
)
inverse =: 3 : 0
 n =. #0{::y
 out =. n#'$'
 j =. 0
 for_p. |.i.n-1 do.
  out =. (j{3{::y)p}out
  j =. y lf j
 end.
 out
)
backward =: 4 : 0
 interval =. 0,#0{::x
 for_ch. |.y do.
  interval =. x extend ch;({.interval);{:interval
  if. ({.interval)>:{:interval do. break. end.
 end.
 interval
)
