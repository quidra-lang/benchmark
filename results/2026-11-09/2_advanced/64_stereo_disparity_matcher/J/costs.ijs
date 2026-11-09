inside =: 3 : '((0<:{.y)*.({.y)<W)*.(0<:{:y)*.({:y)<H'
index =: 3 : '({.y)+W*{:y'
xy =: 3 : '(W|y),<.y%W'
clamped =: 3 : 'index (0>.(_1+W)<.{.y),0>.(_1+H)<.{:y'
box_sum =: 4 : 0
 h =. <.x%2
 ew =. W+2*h
 eh =. H+2*h
 padded =. (eh,ew)$0x
 for_yy. i.eh do.
  for_xx. i.ew do. padded =. ((clamped (xx-h),yy-h){y)(<yy,xx)}padded end.
 end.
 a =. +/\"1 +/\padded
 a =. ((1,ew)$0x),a
 a =. (((eh+1),1)$0x),.a
 out =. N$0x
 for_p. i.N do.
  'xx yy' =. xy p
  x1 =. xx+x
  y1 =. yy+x
  z =. (((<y1,x1){a)+(<yy,xx){a)-(((<yy,x1){a)+(<y1,xx){a)
  out =. z p}out
 end.
 out
)
census =: 3 : 0
 out =. N$0x
 for_p. i.N do.
  'xx yy' =. xy p
  v =. 0x
  for_dy. _2+i.5 do.
   for_dx. _2+i.5 do.
    if. (dx~:0)+.dy~:0 do. v =. (2*v)+((clamped (xx+dx),yy+dy){y)<p{y end.
   end.
  end.
  out =. v p}out
 end.
 out
)
texture =: 3 : 0
 g =. N$0
 for_p. i.N do.
  'xx yy' =. xy p
  g =. (|((clamped (xx+1),yy){IL)-(clamped (xx-1),yy){IL)p}g
 end.
 (pn 'texture_window')box_sum g
)
cost_volume =: 3 : 0
 'kind window' =. y
 c =. (N,#Ds)$0x
 for_j. i.#Ds do.
  d =. j{Ds
  a =. N$0
  for_p. i.N do.
   'xx yy' =. xy p
   q =. index (0>.xx-d),yy
   select. kind
   case. 'sad' do. v =. |(p{IL)-q{IR
   case. 'ssd' do. v =. *:(p{IL)-q{IR
   case. 'census' do. v =. +/(24#2)#: (p{CL)(22 b.)q{CR
   end.
   a =. v p}a
  end.
  c =. (window box_sum a)(<a:;j)}c
 end.
 c
)
neighbours =: 4 : 0
 pos =. xy y
 q =. 0 2$0
 for_d. x do.
  v =. pos+d
  if. inside v do. q =. q,v end.
 end.
 index"1 q
)
