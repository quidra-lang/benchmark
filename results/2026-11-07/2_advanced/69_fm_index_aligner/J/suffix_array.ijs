Symbols =: '$#ACGT'
counting_sort =: 4 : 0
 'keys classes' =. x
 counts =. classes$0
 for_i. y do. k =. i{keys
 counts =. (1+k{counts)k}counts end.
 starts =. }:0,+/\counts
 out =. (#y)$0
 for_i. y do.
  k =. i{keys
  pos =. k{starts
  out =. i pos}out
  starts =. (pos+1)k}starts
 end.
 out
)
suffix_array =: 3 : 0
 n =. #y
 ranks =. Symbols i.y
 order =. (ranks;6)counting_sort i.n
 nr =. n$0
 c =. 0
 previous =. _1
 for_i. order do.
  if. (i{ranks)~:previous do. previous =. i{ranks
  c =. c+1 end.
  nr =. (c-1)i}nr
 end.
 ranks =. nr
 classes =. ,c
 h =. 1
 while. c<n do.
  key2 =. n$0
  ids =. i.0>.n-h
  key2 =. (1+(ids+h){ranks)ids}key2
  order =. (key2;c+1)counting_sort i.n
  order =. (ranks;c)counting_sort order
  nr =. n$0
  c2 =. 0
  previous =. _1 _1
  for_i. order do.
   pair =. (i{ranks),i{key2
   if. -.pair-:previous do. c2 =. c2+1
   previous =. pair end.
   nr =. (c2-1)i}nr
  end.
  c =. c2
  ranks =. nr
  classes =. classes,c
  h =. 2*h
 end.
 order;classes
)
check_sa =: 4 : 0
 lcp =. i.0
 ordered =. 0
 for_i. 1+i.(#y)-1 do.
  a =. (i-1){y
  b =. i{y
  l =. 0
  while. (a+l)<#x do.
   if. (a+l){x~:(b+l){x do. break. end.
   l =. l+1
  end.
  ordered =. ordered+((Symbols i.(a+l){x)<Symbols i.(b+l){x)
  lcp =. lcp,l
 end.
 ordered;lcp
)
direct_sort =: 3 : 0
 suffixes =. 0$a:
 for_i. i.#y do. suffixes =. suffixes,<i}.y end.
 /:suffixes
)
