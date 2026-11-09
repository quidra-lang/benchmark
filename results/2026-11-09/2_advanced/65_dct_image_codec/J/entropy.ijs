category=:3 :0
 n=.0
 magnitude=.|y
 while. magnitude>:2^n do. n=.n+1 end.
 n
)
extra_value=:3 :0
 n=.category y
 if. y<0 do. y+(2^n)-1 else. y end.
)
receive_extend=:4 :0
 if. x=0 do. 0 elseif. y<2^x-1 do. y-(2^x)+1 else. y end.
)
huffman_table=:3 :0
 'counts values'=.y
 t=.cocreate''
 counts__t=:counts
 values__t=:values
 codes__t=:256$0
 lengths__t=:256$0
 code=.0
 p=.0
 for_l. 1+i.16 do.
  for_j. i.(l-1){counts do.
   value=.p{values
   codes__t=:code value}codes__t
   lengths__t=:l value}lengths__t
   code=.code+1
   p=.p+1
  end.
  code=.2*code
 end.
 t
)
optimized_table=:3 :0
 freq=.y,1
 sizes=.257$0
 others=.257$_1
 while. 1 do.
  live=.I.freq>0
  if. 1=#live do. break. end.
  order=.\:live
  order=.( /:order{live{freq){order
  c1=.({.order){live
  c2=.(1{order){live
  freq=.((c1{freq)+c2{freq)c1}freq
  freq=.0 c2}freq
  p=.c1
  while. 1 do.
   sizes=.(1+p{sizes)p}sizes
   if. _1=p{others do. break. end.
   p=.p{others
  end.
  others=.c2 p}others
  p=.c2
  while. 1 do.
   sizes=.(1+p{sizes)p}sizes
   if. _1=p{others do. break. end.
   p=.p{others
  end.
 end.
 counts=.258$0
 for_s. sizes#~sizes>0 do. counts=.(1+s{counts)s}counts end.
 for_l. |.17+i.0>.({:I.counts>0)-16 do.
  while. (l{counts)>0 do.
   j=.l-2
   while. 0=j{counts do. j=.j-1 end.
   counts=.(_2+l{counts)l}counts
   counts=.(1+(l-1){counts)(l-1)}counts
   counts=.(2+(j+1){counts)(j+1)}counts
   counts=.(_1+j{counts)j}counts
  end.
 end.
 l=.{:I.(17{.counts)>0
 counts=.(_1+l{counts)l}counts
 values=.I.(256{.sizes)>0
 values=.( /:values{sizes){values
 huffman_table (1}.17{.counts);values
)
