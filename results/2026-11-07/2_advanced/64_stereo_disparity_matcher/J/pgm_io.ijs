words =: 3 : '<;._1 '' '',y'
read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
num =: 3 : '0".''_''(I.y=''-'')}y'
str =: 3 : 0
 if. 2=3!:0 y do. y else. '-' (I.'_'=":y)}":y end.
)
join =: 4 : 0
 t =. ''
 for_i. i.#y do.
  if. i do. t =. t,x end.
  t =. t,str i{::y
 end.
 t
)
emit =: 3 : ''' '' join y'
write_lines =: 4 : 0
 (;(,&LF)&.>y)1!:2 <'output/',x
 i.0 0
)
read_pgm =: 3 : 0
 l =. read_lines y
 'W H' =: num 1{::l
 ,>num&.>3}.l
)
write_pgm =: 4 : 0
 l =. (<'P2'),(<emit W;H),<'255'
 for_r. (H,W)$y do. l =. l,<emit <"0 r end.
 x write_lines l
)
read_input =: 3 : 0
 IL =: read_pgm 'left.pgm'
 IR =: read_pgm 'right.pgm'
 G =: read_pgm 'ground_truth.pgm'
 N =: W*H
 Names =: Values =: 0$a:
 Samples =: 0 2$0
 for_line. read_lines 'params.txt' do.
  f =. words >line
  if. 'sample'-:0{::f do. Samples =: Samples,num&>}.f
  else. Names =: Names,{.f
  Values =: Values,<}.f end.
 end.
 Dmin =: pn 'disparity_min'
 Dmax =: pn 'disparity_max'
 Ds =: Dmin+i.1+Dmax-Dmin
 Directions =: 8 2$1 0 _1 0 0 1 0 _1 1 1 _1 _1 _1 1 1 _1
 i.0 0
)
pv =: 3 : '(Names i.<y){::Values'
pn =: 3 : 'num 0{::pv y'
