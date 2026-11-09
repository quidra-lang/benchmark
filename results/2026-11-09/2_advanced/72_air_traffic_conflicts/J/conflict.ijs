loss_interval =: 3 : 0
 'p w t1 t2' =. y
 'px py pz' =. p
 'wx wy wz' =. w
 qa =. (wx*wx)+wy*wy
 qb =. 2*((px*wx)+py*wy)
 qc =. ((px*px)+py*py)-Dh*Dh
 lo =. t1
 hi =. t2
 if. qa<1e_12 do.
  if. qc>:0 do. i.0 return. end.
 else.
  disc =. (qb*qb)-4*qa*qc
  if. disc<:0 do. i.0 return. end.
  root =. %:disc
  lo =. lo>.t1+((-qb)-root)%(2*qa)
  hi =. hi<.t1+((-qb)+root)%(2*qa)
 end.
 if. wz=0 do.
  if. (|pz)>:Dv do. i.0 return. end.
 else.
  r1 =. ((-Dv)-pz)%wz
  r2 =. (Dv-pz)%wz
  lo =. lo>.t1+r1<.r2
  hi =. hi<.t1+r1>.r2
 end.
 if. (hi-lo)<:1e_6 do. i.0 return. end.
 tc =. t1
 if. qa>:1e_12 do. tc =. t1+(-qb)%(2*qa) end.
 tc =. hi<.lo>.tc
 tau =. tc-t1
 ex =. px+wx*tau
 ey =. py+wy*tau
 lo,hi,tc,(%:(ex*ex)+ey*ey),|pz+wz*tau
)
pair_conflicts =: 4 : 0
 pieces =. 0 7$0.0
 for_a. i.#x do.
  sa =. a{x
  for_b. i.#y do.
   sb =. b{y
   t1 =. (3{sa)>.3{sb
   t2 =. (4{sa)<.4{sb
   if. t1<t2 do.
    result =. loss_interval ((sa position t1)-sb position t1);((8 9 10{sa)-8 9 10{sb);t1;t2
    if. #result do. pieces =. pieces,a,b,result end.
   end.
  end.
 end.
 pieces =. (/:2{"1 pieces){pieces
 conflicts =. 0$a:
 for_piece. pieces do.
  if. 0=#conflicts do. new =. 1
  else. last =. >{:conflicts
  new =. ((2{piece)-1{::last)>1e_6 end.
  if. new do. conflicts =. conflicts,< (2{piece);(3{piece);(,:piece);piece
  else.
   last =. (<3{piece)1}last
   last =. (<(2{::last),piece)2}last
   if. (5{piece)<(_1e_9+5{3{::last) do. last =. (<piece)3}last end.
   conflicts =. (<last)((#conflicts)-1)}conflicts
  end.
 end.
 conflicts
)
all_conflicts =: 3 : 0
 out =. 0$a:
 keys =. 0 3$0.0
 for_a. i.NF do.
  for_b. (a+1)+i.(NF-a)-1 do.
   for_c. (a{::y)pair_conflicts b{::y do.
    c =. >c
    out =. out,<a;b;(0{::c);(1{::c);(2{::c);3{::c
    keys =. keys,(0{::c),a,b
   end.
  end.
 end.
 (/:keys){out
)
