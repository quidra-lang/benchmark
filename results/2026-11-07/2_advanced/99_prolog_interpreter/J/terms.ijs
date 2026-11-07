LF=:10{a.
letters=:'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
digits=:'0123456789'
alnum=:letters,digits,'_'
symbols=:'+-*/\^<>=~:.?@#&$'
decimal=:3 : '(":y) rplc ''_'';''-'''
readlines=:3 : '<;._2 (1!:1 <y)'
join=:4 :0
  if. 0=#y  do. '' else. (#x)}.;(x&,)&.>y  end.
)
write_lines=:4 : '(;(,&LF)&.>y) 1!:2 <x'
term=:4 :0
 t=.cocreate''
 kind__t=:x
 value__t=:y
 args__t=:0$a:
 binding__t=:a:
 t
)
fresh=:3 : '0 term 0'
integer=:3 : '1 term y'
atom=:3 : '2 term y'
compound=:4 :0
 t=.3 term x
 args__t=:y
 t
)
deref=:3 :0
 t=.y
  while. kind__t=0  do.
   if. binding__t-:a:  do.  break.  end.
  t=.binding__t
  end.
 t
)
indicator=:3 :0
 t=.deref y
 value__t;#args__t
)
indicator_term=:3 :0
 'name arity'=.y
 '/' compound (atom name),integer arity
)
make_list=:4 :0
 tail=.y
  for_t. |.x  do. tail=. '.' compound t,tail  end.
 tail
)
proper_list=:3 : 'y make_list atom ''[]'''
unlist=:3 :0
 t=.deref y
 es=.0$a:
  while. (kind__t=3)*.(value__t-:'.')*.2=#args__t  do.
  es=.es,0{args__t
  t=.deref 1{args__t
  end.
 es;t
)
variables=:3 :0
 result=.0$a:
 pending=.,y
  while. #pending  do.
  t=.deref {.pending
  pending=.}.pending
   if. kind__t=0  do. result=.result,t
   elseif. kind__t=3  do. pending=.args__t,pending  end.
  end.
 result
)
copy_walk=:3 :0
 t=.deref y
  if. kind__t=0  do.
  i=.CopyOld i.t
   if. i=#CopyOld  do. CopyOld=:CopyOld,t
  CopyNew=:CopyNew,fresh'' end.
  i{CopyNew
  elseif. kind__t=3  do.
  es=.0$a:
   for_e. args__t  do. es=.es,copy_walk e  end.
  value__t compound es
  else. t  end.
)
copy_term=:3 :0
 CopyOld=:CopyNew=:0$a:
 copy_walk y
)
error_term=:4 : 'x compound y'
type_error=:4 : '''type_error'' compound (atom x),y'
domain_error=:4 : '''domain_error'' compound (atom x),y'
exception=:4 : '''error'' compound y,indicator_term x'
