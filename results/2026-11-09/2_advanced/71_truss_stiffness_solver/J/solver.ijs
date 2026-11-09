cholesky =: 3 : 0
 n =. #y
 g =. (n,n)$0.0
 for_i. i.n do.
  for_j. i.i+1 do.
   w =. (<i,j){y
   for_h. i.j do. w =. w-((<i,h){g)*(<j,h){g end.
   if. i=j do.
    if. w<:1e_9*(<i,i){y do. i;g return. end.
    v =. %:w
   else. v =. w%(<j,j){g end.
   g =. v(<i,j)}g
  end.
 end.
 _1;g
)
solve =: 4 : 0
 n =. #y
 z =. n$0.0
 for_i. i.n do.
  w =. i{y
  for_h. i.i do. w =. w-((<i,h){x)*h{z end.
  z =. (w%(<i,i){x)i}z
 end.
 answer =. n$0.0
 for_i. |.i.n do.
  w =. i{z
  for_h. (i+1)+i.(n-i)-1 do. w =. w-((<h,i){x)*h{answer end.
  answer =. (w%(<i,i){x)i}answer
 end.
 answer
)
matvec =: 4 : 0
 answer =. i.0
 for_row. x do.
  total =. 0.0
  for_j. i.#y do. total =. total+(j{row)*j{y end.
  answer =. answer,total
 end.
 answer
)
