follows =: 3 : 0
 counts =. (NA,NA)$0
 for_item. y do.
  'trace weight' =. >item
  for_i. i.(#trace)-1 do.
   key =. (i{trace),(i+1){trace
   counts =. (weight+(<key){counts)(<key)}counts
  end.
 end.
 counts
)
relation =: 3 : 0
 (y>0)+2*0<|:y
)
RelationSymbols =: '#';'->';'<-';'||'
table =: 4 : 0
 n =. #y
 header =. '    '
 for_i. 1+i.n do. header =. header,(-x){.(x#' '),str i end.
 out =. <header
 for_i. i.n do.
  text =. _4{.'    ',str i+1
  for_v. i{y do. text =. text,(-x){.(x#' '),str >v end.
  out =. out,<text
 end.
 out
)
footprint =: 4 : 0
 out =. 0$a:
 for_i. i.#x do. out =. out,<emit 'ACTIVITY';(i+1);(i{x){::AllNames end.
 symbols =. RelationSymbols{~(<x;x){y
 out,4 table symbols
)
