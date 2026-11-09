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
list =: 3 : 0
 if. #y do. ','join y else. '-' end.
)
frac =: 3 : 0
 pair =. 2 x:x:y
 a =. {.pair
 b =. {:pair
 neg =. a<0
 a =. |a
 t =. <.(10000x*a)%b
 dec =. (str <.t%10000),'.',_4{.'0000',str 10000|t
 if. neg do.
  prefix =. '-'
  if. t>0 do. dec =. '-',dec end.
 else. prefix =. '' end.
 prefix,(str a),'/',(str b),'=',dec
)
ratio =: 4 : 'frac (x:x)%x:y'
percent =: 4 : 0
 t =. <.(10000x*x)%y
 (str <.t%100),'.',(_2{.'00',str 100|t),'%'
)
mean =: 3 : '(+/x:y)%#y'
write =: 4 : 0
 (;(,&LF)&.>y)1!:2 <'output/',x
 i.0 0
)
