key=:3 :0
 'n a'=.indicator y
 n,'/',decimal a
)
ControlKeys=:(<;._1 ' ',',/2 !/0 ;/2 ->/2 \+/1 call/1 call/2 call/3 call/4 call/5 call/6 call/7 call/8 catch/3')
BuiltinKeys=:(<;._1 ' ','findall/3 throw/1 between/3 length/2 true/0 fail/0 false/0 =/2 \=/2 ==/2 \==/2 var/1 nonvar/1 atom/1 number/1 integer/1 atomic/1 compound/1 callable/1 is_list/1 is/2 =:=/2 =\=/2 </2 >/2 =</2 >=/2 functor/3 arg/3 =../2 copy_term/2 atom_length/2 atom_chars/2 write/1 writeq/1 nl/0')
find_predicate=:3 :0
 i=.DatabaseKeys i.<y
  if. i=#DatabaseKeys  do. a: else. i{Database  end.
)
goal_convert=:3 :0
 t=.deref y
  if. kind__t=0  do. 'call' compound ,t
  elseif. kind__t=1  do. ConversionFailed=:1
  t
  elseif. (kind__t=3)*.(2=#args__t)*.(<value__t)e.',';';';'->' do.
  es=.0$a:
   for_a. args__t  do. es=.es,goal_convert a  end.
  value__t compound es
  else. t  end.
)
same_kind=:4 :0
 a=.deref x
  b=.deref y
  if. (kind__a=0)+.kind__b=0  do. 1  return.  end.
 (kind__a=kind__b)*.(value__a-:value__b)*.(#args__a)=#args__b
)
candidates=:4 :0
 goal=.x
  predicate=.y
  cs=.0$a:
  for_c. clauses__predicate  do.
   if. 0=#args__goal  do. cs=.cs,c
   else. h=.head__c
   if. (0{args__goal)same_kind 0{args__h  do. cs=.cs,c  end.  end.
  end.
 cs
)
copy_clause=:3 :0
 c=.y
 es=.,head__c
  if. -.body__c-:a: do. es=.es,body__c  end.
 t=.copy_term 'clause' compound es
 args__t
)
