str =: 3 : 0
 if. 2=3!:0 y do. y return. end.
 n =. <.|y
 text =. ''
 while. n>0 do.
  text =. ((10|n){'0123456789'),text
  n =. <.n%10
 end.
 if. 0=#text do. text =. '0' end.
 if. y<0 do. '-',text else. text end.
)
join =: 4 : 0
 t =. ''
 for_i. i.#y do.
  if. i do. t =. t,x end.
  t =. t,str i{::y
 end.
 t
)
fmt =: 4 : 0
 n =. <.0.5+(10^x)*|y
 s =. str n
 if. x do. s =. ((-x-1){.(x#'0'),s)
 s =. (str <.n%10^x),'.',(-x){.(x#'0'),str (10^x)|n end.
 if. (y<0)*.n>0 do. '-',s else. s end.
)
render =: 4 : 0
 p =. <;._1 '|',x
 t =. 0{::p
 for_i. i.#y do. t =. t,(str i{::y),(i+1){::p end.
 t
)
write_lines =: 4 : 0
 (;(,&LF)&.>y)1!:2 <'output/',x
 i.0 0
)
sum =: 3 : 0
 s =. 0.0
 for_v. y do. s =. s+v end.
 s
)
mean =: 3 : '(sum y)%#y'
plot_lines =: 3 : 0
 'model ex' =. y
 'wp zt zb zs' =. PlotValues
 nr =. 1+<.(zt-zb)%zs
 cells =. (nr,wp)$' '
 qz =. <.0.5+(zt-100*0{::model)%zs
 if. (qz>:0)*.qz<nr do. cells =. (wp#'-')qz}cells end.
 marks =. wp#'*'
 for_e. ex do.
  'mu z high' =. e
  c =. <.((mu-60*Ts)+30)%60
  if. (c>:0)*.c<wp do. marks =. (high{'LH')c}marks end.
 end.
 for_c. i.wp do.
  q =. <.0.5+(zt-100*model predict Ts+c)%zs
  ch =. c{marks
  if. q<0 do. q =. 0
  ch =. '^' elseif. q>:nr do. q =. nr-1
  ch =. 'v' end.
  cells =. ch(<q,c)}cells
 end.
 labels =. 0$a:
 for_q. i.nr do. labels =. labels,<2 fmt (zt-q*zs)%100 end.
 width =. >./#&>labels
 lines =. 0$a:
 for_q. i.nr do. lines =. lines,<((-width){.(width#' '),q{::labels),' |',(q{cells),'|' end.
 axis =. wp#'-'
 axis =. '+'(I.0=6|i.wp)}axis
 lines,<(width#' '),' +',axis,'+'
)
