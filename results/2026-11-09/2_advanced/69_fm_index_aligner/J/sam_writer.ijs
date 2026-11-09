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
emit =: 3 : ''' ''join y'
ratio =: 4 : 0
 if. y=0 do. '-' return. end.
 n =. <.((20000x*x)+y)%(2*y)
 (str <.n%10000),'.',_4{.'0000',str 10000|n
)
write =: 4 : 0
 (;(,&LF)&.>y)1!:2 <'output/',x
 i.0 0
)
sam_header =: 3 : 0
 ls =. <TAB join '@HD';'VN:1.6';'SO:unsorted'
 for_r. i.#Refs do. ls =. ls,<TAB join '@SQ';('SN:',r{::RefNames);'LN:',str r{RefLengths end.
 ls,<TAB join '@PG';'ID:fm_index_aligner';'PN:fm_index_aligner';'VN:1.0'
)
