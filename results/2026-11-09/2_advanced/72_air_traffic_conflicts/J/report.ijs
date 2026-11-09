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
 for_i. i.#y do. if. i do. t =. t,x end.
 t =. t,str i{::y end.
 t
)
emit =: 3 : ''' ''join y'
fmt =: 4 : 0
 n =. <.0.5+(10^x)*|y
 t =. (str <.n%10^x),'.',(-x){.(x#'0'),str (10^x)|n
 if. (y<0)*.n do. '-',t else. t end.
)
fixed =: 3 : '3 fmt y'
render =: 4 : 0
 parts =. <;._1 '|',x
 t =. 0{::parts
 for_i. i.#y do. t =. t,(str i{::y),(i+1){::parts end.
 t
)
write =: 4 : 0
 (;(,&LF)&.>y)1!:2 <'output/',x
 i.0 0
)
chart =: 3 : 0
 border =. '+',(({:$y)#'-'),'+'
 out =. <border
 for_r. y do. out =. out,<'|',r,'|' end.
 out,<border
)
pair_name =: 3 : '((0{y){::Callsigns),''-'',(1{y){::Callsigns'
sector_name =: 3 : 0
 if. y<0 do. '-' else. y{::SectorNames end.
)
sum =: 3 : 0
 total =. 0.0
 for_v. y do. total =. total+v end.
 total
)
