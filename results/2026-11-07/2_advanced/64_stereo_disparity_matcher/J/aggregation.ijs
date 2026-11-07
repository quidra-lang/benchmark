path_cost =: 4 : 0
 'rx ry' =. x
 l =. ($y)$0x
 rows =. i.H
 cols =. i.W
 if. ry<0 do. rows =. |.rows end.
 if. rx<0 do. cols =. |.cols end.
 p1 =. pn 'p1'
 for_yy. rows do.
  for_xx. cols do.
   p =. index xx,yy
   qxy =. (xx-rx),yy-ry
   v =. p{y
   if. inside qxy do.
    q =. index qxy
    previous =. q{l
    m =. <./previous
    gamma =. pn 'p2_gamma'
    p2 =. p1>.<.((pn 'p2')*gamma)%(gamma+|(p{IL)-q{IL)
    for_j. i.#Ds do.
     opts =. (j{previous),m+p2
     if. j>0 do. opts =. opts,p1+(j-1){previous end.
     if. j<(_1+#Ds) do. opts =. opts,p1+(j+1){previous end.
     v =. ((j{v)+(<./opts)-m)j}v
    end.
   end.
   l =. v p}l
  end.
 end.
 l
)
aggregate =: 3 : 0
 s =. ($y)$0x
 stages =. 0$a:
 for_r. (pn 'sgm_paths'){.Directions do.
  s =. s+r path_cost y
  stages =. stages,<s
 end.
 stages
)
