words=:3 : '(<;._1 '' '',y)-.<'''''
LF=:10{a.
SQ=:39{a.
num=:3 : ',''0'' 8!:2 y'
trim=:3 : 0
 s=.y
 while. #s do. if. ' '~:{.s do. break. end. s=.}.s end.
 while. #s do. if. ' '~:{:s do. break. end. s=.}:s end.
 s
)
join=:4 : 0
 r=.''
 for_i. i.#y do. if. i do. r=.r,x end. r=.r,i{::y end.
 r
)
fail=:3 : 0
 Error=:y
 throw.
)
N=:3 : '5;x:y'
V=:3 : '0;y'
kind=:3 : '0{::y'
value=:3 : '1{::y'
isnum=:3 : '5=kind y'
iszero=:3 : 'y-:N 0'
isone=:3 : 'y-:N 1'
integer=:3 : 0
 if. -.isnum y do. 0 return. end.
 q=.value y
 q=<.q
)
base=:3 : 'if. 3=kind y do. 1{::y else. y end.'
exponent=:3 : 'if. 3=kind y do. 2{::y else. N 1 end.'
parts=:3 : 0
 if. isnum y do. (value y);<0$a: return. end.
 if. 2=kind y do.
  f=.value y
  if. isnum >{.f do. (value >{.f);<}.f else. 1;<f end.
 else. 1;<,<y end.
)
cmp=:4 : 0
 a=.kind x
 b=.kind y
 if. a~:b do. *a-b return. end.
 if. a=5 do. *(value x)-value y return. end.
 if. a=0 do.
  s=.value x
  t=.value y
  if. s-:t do. 0 else. if. (<s)-:{./:~s;t do. _1 else. 1 end. end.
  return.
 end.
 if. a e.1 2 do. s=.value x
 t=.value y
 elseif. a=3 do. s=.}.x
 t=.}.y
 else.
  s=.value x
 t=.value y
  if. -.s-:t do.
   if. (<s)-:{./:~s;t do. _1 else. 1 end.
   return.
  end.
  s=.,<2{::x
 t=.,<2{::y
 end.
 for_i. i.(#s)<.#t do.
  c=.(i{::s)cmp i{::t
  if. c do. c return. end.
 end.
 *(#s)-#t
)
sortE=:3 : 0
 r=.0$a:
 for_a. y do.
  j=.0
  while. j<#r do. if. (>a)cmp j{::r do. if. 0>(>a)cmp j{::r do. break. end. end. j=.j+1 end.
  r=.(j{.r),a,j}.r
 end.
 r
)
expcmp=:4 : 0
 if. (isnum x)*.isnum y do. *(value x)-value y
 elseif. isnum x do. _1
 elseif. isnum y do. 1
 else. x cmp y end.
)
termcmp=:4 : 0
 'c s'=.parts x
 'd t'=.parts y
 bs=.0$a:
 for_f. s,t do. bs=.bs,<base >f end.
 bs=.sortE ~.bs
 for_b. bs do.
  p=.N 0
 q=.N 0
  for_f. s do. if. (>b)-:base >f do. p=.exponent >f end. end.
  for_f. t do. if. (>b)-:base >f do. q=.exponent >f end. end.
  k=.p expcmp q
  if. k do. -k return. end.
 end.
 0
)
sortTerms=:3 : 0
 r=.0$a:
 for_a. y do.
  j=.0
  while. j<#r do. if. 0>(>a)termcmp j{::r do. break. end. j=.j+1 end.
  r=.(j{.r),a,j}.r
 end.
 r
)
product=:3 : 0
 'c fs'=.y
 if. 0=#fs do. N c return. end.
 if. c~:1 do. fs=.(<N c),fs end.
 if. 1=#fs do. >{.fs else. 2;<fs end.
)
add=:3 : 0
 ts=.0$a:
 for_a. y do.
  f=.>a
  if. 1=kind f do. ts=.ts,value f
  elseif. 2=kind f do.
   fs=.value f
   if. 2=#fs do.
    if. (isnum 0{::fs)*.1=kind 1{::fs do.
     for_t. value 1{::fs do. ts=.ts,<mul (0{fs),t end.
    else. ts=.ts,a end.
   else. ts=.ts,a end.
  else. ts=.ts,a end.
 end.
 ms=.0$a:
 cs=.0$0x
 for_t. ts do.
  'c m'=.parts >t
  i=.ms i.<m
  if. i=#ms do. ms=.ms,<m
 cs=.cs,c
  else. cs=.(c+i{cs)i}cs end.
 end.
 r=.0$a:
 for_i. i.#ms do. if. 0~:i{cs do. r=.r,<product (i{cs);<i{::ms end. end.
 r=.sortTerms r
 if. 0=#r do. N 0 elseif. 1=#r do. >{.r else. 1;<r end.
)
mul=:3 : 0
 fs=.0$a:
 for_a. y do. if. 2=kind >a do. fs=.fs,value >a else. fs=.fs,a end. end.
 c=.1x
 bs=.0$a:
 es=.0$a:
 originals=.0$a:
 for_f. fs do.
  a=.>f
  if. isnum a do. c=.c*value a
  else.
   b=.base a
 e=.exponent a
   i=.bs i.<b
   if. i=#bs do. bs=.bs,<b
 es=.es,<,<e
 originals=.originals,f
   else. es=.(<(i{::es),<e)i}es end.
  end.
 end.
 if. c=0 do. N 0 return. end.
 gs=.0$a:
 for_i. i.#bs do.
  xs=.i{::es
  if. 1=#xs do. g=.i{::originals else. g=.(i{::bs)pow add xs end.
  gs=.gs,<g
 end.
 again=.0
 seen=.0$a:
 for_g. gs do.
  if. (kind >g)e.2 5 do. again=.1 end.
  b=.base >g
  if. (<b)e.seen do. again=.1 end.
  seen=.seen,<b
 end.
 if. again do. mul (<N c),gs return. end.
 order=.i.0
 for_i. i.#gs do.
  j=.0
  while. j<#order do. if. 0>(base i{::gs)cmp base (j{order){::gs do. break. end. j=.j+1 end.
  order=.(j{.order),i,j}.order
 end.
 product c;<order{gs
)
rootInt=:4 : 0
 if. y<2 do. y return. end.
 bits=.0
 remaining=.y
 while. remaining>0 do.
  bits=.bits+1
  remaining=.<.remaining%2
 end.
 if. x>:bits do. 1x return. end.
 lo=.0x
 hi=.1x+y
 while. hi>lo+1 do.
  mid=.<.(lo+hi)%2
  if. (mid^x)>y do. hi=.mid else. lo=.mid end.
 end.
 lo
)
pow=:4 : 0
 b=.x
 e=.y
 if. iszero e do. N 1 return. end.
 if. isone e do. b return. end.
 if. isnum b do.
  q=.value b
  if. q=1 do. N 1 return. end.
  if. isnum e do.
   z=.value e
   if. q=0 do. if. z<0 do. fail 'division by zero' else. N 0 return. end. end.
   if. integer e do. N q^z return. end.
   if. q>0 do.
    'u w'=.2 x:q
    'p d'=.2 x:z
    s=.d rootInt u
 t=.d rootInt w
    if. (u=s^d)*.w=t^d do. N (s%t)^p return. end.
   end.
  end.
 elseif. integer e do.
  if. 3=kind b do. (base b)pow mul (exponent b);<e return. end.
  if. 2=kind b do.
   r=.0$a:
   for_f. value b do. r=.r,< (>f)pow e end.
   mul r return.
  end.
 end.
 3;b;<e
)
fn=:4 : 0
 f=.x
 a=.y
 if. f-:'sqrt' do. a pow N 1r2 return. end.
 if. (iszero a)*.(<f)e.words 'sin tan cos exp' do. N (<f)e.words 'cos exp' return. end.
 if. (f-:'ln')*.isone a do. N 0 return. end.
 'c m'=.parts a
 if. (c<0)*.(<f)e.words 'sin cos tan' do.
  b=.f fn mul (N _1);<a
  if. f-:'cos' do. b else. mul (N _1);<b end.
  return.
 end.
 if. 4=kind a do.
  if. ((f-:'exp')*.('ln'-:value a))+.((f-:'ln')*.('exp'-:value a)) do. 2{::a return. end.
 end.
 4;f;<a
)
variables=:3 : 0
 k=.kind y
 if. k=5 do. 0$a: return. end.
 if. k=0 do. ,<value y return. end.
 if. k e.1 2 do. fs=.value y elseif. k=3 do. fs=.}.y else. fs=.,<2{::y end.
 r=.0$a:
 for_f. fs do. r=.r,variables >f end.
 /:~~.r
)
derivative=:4 : 0
 v=.x
 f=.y
 k=.kind y
 select. k
 case. 5 do. N 0
 case. 0 do. N v-:value f
 case. 1 do.
  r=.0$a:
  for_t. value f do. r=.r,<v derivative >t end.
  add r
 case. 2 do.
  fs=.value f
 r=.0$a:
  for_i. i.#fs do. r=.r,<mul (<v derivative i{::fs)i}fs end.
  add r
 case. 3 do.
  b=.base f
 e=.exponent f
  if. -. (<v)e.variables e do.
   db=.v derivative b
   mul e;(b pow add e;<N _1);<db
  elseif. -. (<v)e.variables b do.
   de=.v derivative e
   mul f;('ln'fn b);<de
  else.
   de=.v derivative e
 db=.v derivative b
   a=.mul de;<'ln'fn b
   z=.mul e;db;<b pow N _1
   mul f;<add a;<z
  end.
 case. 4 do.
  g=.value f
 a=.2{::f
  select. g
  case. 'sin' do. h=.'cos'fn a
  case. 'cos' do. h=.mul (N _1);<'sin'fn a
  case. 'tan' do. h=.('cos'fn a)pow N _2
  case. 'exp' do. h=.f
  case. 'ln' do. h=.a pow N _1
  end.
  mul h;<v derivative a
 end.
)
subst=:4 : 0
 'names vals'=.x
 k=.kind y
 if. k=5 do. y return. end.
 if. k=0 do.
  i=.names i.<value y
  if. i<#names do. i{::vals else. y end.
  return.
 end.
 if. k e.1 2 do.
  fs=.0$a:
  for_f. value y do. fs=.fs,<x subst >f end.
  if. k=1 do. add fs else. mul fs end.
 elseif. k=3 do.
  b=.x subst base y
  e=.x subst exponent y
  b pow e
 else. (value y)fn x subst 2{::y end.
)
distribute=:4 : 0
 if. 1=kind x do. s=.value x else. s=.,<x end.
 if. 1=kind y do. t=.value y else. t=.,<y end.
 r=.0$a:
 for_a. s do. for_b. t do. r=.r,<mul a,b end. end.
 add r
)
expand=:3 : 0
 k=.kind y
 if. k e.0 5 do. y return. end.
 if. k=4 do. (value y)fn expand 2{::y return. end.
 if. k e.1 2 do.
  fs=.0$a:
  for_f. value y do. fs=.fs,<expand >f end.
  if. k=1 do. add fs else.
   r=.>{.fs
   for_f. }.fs do. r=.r distribute >f end.
   r
  end.
  return.
 end.
 b=.expand base y
 e=.expand exponent y
 if. (1=kind b)*.integer e do.
  n=.value e
  if. n>0 do. r=.b
   for_i. i.n-1 do. r=.r distribute b end.
   r return.
  end.
 end.
 b pow e
)
ratstr=:3 : 0
 'p q'=.2 x:y
 r=.num p
 if. q~:1 do. r=.r,'/',num q end.
 r
)
atomic=:3 : 0
 k=.kind y
 if. k e.0 4 do. 1 return. end.
 if. k=5 do. (integer y)*.0<:value y return. end.
 if. k=3 do. (exponent y)-:N 1r2 else. 0 end.
)
A=:3 : 'if. atomic y do. P y else. ''('',(P y),'')'' end.'
W=:4 : 0
 if. y-:N 1r2 do. 'sqrt(',(P x),')' else. (A x),'^',A y end.
)
G=:3 : 0
 if. 1=kind y do. '(',(P y),')'
 elseif. 3=kind y do. (base y)W exponent y
 else. P y end.
)
Q=:3 : 0
 'c fs'=.y
 'p q'=.2 x:|c
 ns=.0$a:
 ds=.0$a:
 if. p~:1 do. ns=.ns,<num p end.
 if. q~:1 do. ds=.ds,<num q end.
 for_f. fs do.
  g=.>f
 negative=.0
  if. 3=kind g do. e=.exponent g
   if. isnum e do. negative=.0>value e end.
  end.
  if. negative do.
   b=.base g
 r=.-value e
   if. r=1 do. ds=.ds,<G b else. ds=.ds,<b W N r end.
  else. ns=.ns,<G g end.
 end.
 if. #ns do. r=.'*'join ns else. r=.'1' end.
 if. 1=#ds do. r=.r,'/',>{.ds elseif. 1<#ds do. r=.r,'/(',('*'join ds),')' end.
 if. c<0 do. r=.'-',r end.
 r
)
P=:3 : 0
 k=.kind y
 select. k
 case. 5 do. ratstr value y
 case. 0 do. value y
 case. 4 do. (value y),'(',(P 2{::y),')'
 case. 1 do.
  fs=.value y
  r=.P >{.fs
  for_f. }.fs do.
   s=.P >f
   if. '-'={.s do. r=.r,' - ',}.s else. r=.r,' + ',s end.
  end.
  r
 case. 2 do. Q parts y
 case. 3 do.
  e=.exponent y
  if. isnum e do.
   if. 0>value e do. Q 1;<,<y return. end.
  end.
  (base y)W e
 end.
)
numeric=:3 : 0
 k=.kind y
 if. k=5 do. 0.0+value y return. end.
 if. k e.1 2 do.
  r=.k-1.0
  for_f. value y do. a=.numeric >f
   if. k=1 do. r=.r+a else. r=.r*a end.
  end.
  r return.
 end.
 if. k=3 do.
  u=.numeric base y
 e=.exponent y
  z=.numeric e
  if. (u<0)*.z~:<.z do. fail 'domain error' end.
  if. e-:N 1r2 do. %:u else. u^z end.
  return.
 end.
 a=.numeric 2{::y
 select. value y
 case. 'sin' do. 1 o.a
 case. 'cos' do. 2 o.a
 case. 'tan' do. 3 o.a
 case. 'exp' do. ^a
 case. 'ln' do. if. a<:0 do. fail 'domain error' end. ^.a
 end.
)
Functions=:words 'sin cos tan exp ln sqrt'
Lower=:'abcdefghijklmnopqrstuvwxyz'
Upper=:'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
Digits=:'0123456789'
validvar=:3 : 0
 if. 0=#y do. 0 return. end.
 (({.y)e.Lower)*.(*./y e.Lower,Digits)*.-.(<y)e.Functions
)
validname=:3 : 0
 if. 0=#y do. 0 return. end.
 (({.y)e.Upper)*.*./y e.Upper,Digits
)
tokenize=:3 : 0
 r=.0$a:
 i=.0
 while. i<#y do.
  c=.i{y
  if. c=' ' do. i=.i+1 continue. end.
  if. c e.'+-*/^()' do. r=.r,<,c
 i=.i+1 continue. end.
  if. c e.Digits do. chars=.Digits
  elseif. c e.Lower do. chars=.Lower,Digits
  elseif. c e.Upper do. chars=.Upper,Digits
  else. fail 'invalid character ',SQ,c,SQ end.
  j=.i+1
  while. j<#y do. if. -. (j{y)e.chars do. break. end. j=.j+1 end.
  r=.r,<(j-i){.i}.y
  i=.j
 end.
 r
)
peek=:3 : 'if. Pos<#Tokens do. Pos{::Tokens else. '''' end.'
unexpected=:3 : 0
 t=.peek''
 if. #t do. fail 'unexpected ',SQ,t,SQ else. fail 'unexpected end of expression' end.
)
atom=:3 : 0
 t=.peek''
 if. 0=#t do. unexpected'' end.
 Pos=:Pos+1
 if. t-:'(' do.
  r=.expression''
  if. -.')'-:peek'' do. unexpected'' end.
  Pos=:Pos+1
  r return.
 end.
 if. (<t)e.Functions do.
  if. -.'('-:peek'' do. unexpected'' end.
  Pos=:Pos+1
  r=.expression''
  if. -.')'-:peek'' do. unexpected'' end.
  Pos=:Pos+1
  14;t;<r return.
 end.
 if. ({.t)e.Digits do. N 0x ".t return. end.
 if. validvar t do. V t return. end.
 if. validname t do.
  i=.Names i.<t
  if. i=#Names do. fail 'undefined name ',SQ,t,SQ end.
  i{::Definitions return.
 end.
 Pos=:Pos-1
 unexpected''
)
unary=:3 : 0
 if. '-'-:peek'' do.
  Pos=:Pos+1
  12;(N _1);<unary''
 else.
  b=.atom''
  if. '^'-:peek'' do.
   Pos=:Pos+1
   b=.13;b;<unary''
  end.
  b
 end.
)
term=:3 : 0
 r=.unary''
 while. (<peek'')e.words '* /' do.
  op=.peek''
  Pos=:Pos+1
  t=.unary''
  if. op-:'/' do. t=.13;t;<N _1 end.
  r=.12;r;<t
 end.
 r
)
expression=:3 : 0
 r=.term''
 while. (<peek'')e.words '+ -' do.
  op=.peek''
  Pos=:Pos+1
  t=.term''
  if. op-:'-' do. t=.12;(N _1);<t end.
  r=.11;r;<t
 end.
 r
)
calculate=:3 : 0
 k=.kind y
 if. k<10 do. y return. end.
 if. k=14 do. (value y)fn calculate 2{::y return. end.
 a=.calculate 1{::y
 b=.calculate 2{::y
 select. k
 case. 11 do. add a;<b
 case. 12 do. mul a;<b
 case. 13 do. a pow b
 end.
)
parse=:3 : 0
 Tokens=:tokenize y
 Pos=:0
 ast=.expression''
 if. Pos<#Tokens do. unexpected'' end.
 calculate ast
)
ratvalid=:3 : 0
 s=.y
 if. #s do. if. '-'={.s do. s=.}.s end. end.
 ps=.<;._1 '/',s
 if. -. (#ps)e.1 2 do. 0 return. end.
 for_p. ps do. if. (0=#>p)+.-.*./(>p)e.Digits do. 0 return. end. end.
 1
)
ratread=:3 : 0
 s=.y
 sign=.1
 if. '-'={.s do. sign=._1
 s=.}.s end.
 ps=.<;._1 '/',s
 p=.0x ".0{::ps
 q=.1x
 if. 2=#ps do. q=.0x ".1{::ps end.
 if. q=0 do. fail 'division by zero' end.
 sign*p%q
)
fixed=:3 : 0
 h=.<.0.5+1000000*|y
 s=.num 1000000|h
 s=.((6-#s)$'0'),s
 r=.(num <.h%1000000),'.',s
 if. y<0 do. r=.'-',r end.
 r
)
Commands=:words 'LET SIMPLIFY EXPAND DIFF DIFFN GRAD HESSIAN IMPLICIT SUBST EVAL TANGENT LIMIT TAYLOR'
command=:3 : 0
 p=.y i.' '
 cmd=.p{.y
 arg=.(p+1)}.y
 if. -. (<cmd)e.Commands do. fail 'unknown command ',cmd end.
 if. cmd-:'LET' do.
  at=.arg i.'='
  if. at=#arg do. fail 'wrong number of arguments' end.
  name=.trim at{.arg
  if. -.validname name do. fail 'invalid name ',SQ,name,SQ end.
  f=.parse trim (at+1)}.arg
  i=.Names i.<name
  if. i=#Names do. Names=:Names,<name
 Definitions=:Definitions,<f
  else. Definitions=:(<f)i}Definitions end.
  ,<name,' = ',P f return.
 end.
 fields=.0$a:
 if. p<#y do. fields=.trim each <;._1 ';',arg end.
 n=.#fields
 i=.Commands i.<cmd
 expected=.0 1 1 2 3 1 1 3 3 1 3 3 4
 if. cmd-:'EVAL' do. good=.n e.1 2 else. good=.n=i{expected end.
 if. -.good do. fail 'wrong number of arguments' end.
 f=.parse 0{::fields
 if. (<cmd)e.words 'DIFF DIFFN IMPLICIT SUBST TANGENT LIMIT TAYLOR' do.
  v=.1{::fields
  if. -.validvar v do. fail 'invalid variable ',SQ,v,SQ end.
 end.
 if. cmd-:'IMPLICIT' do.
  w=.2{::fields
  if. -.validvar w do. fail 'invalid variable ',SQ,w,SQ end.
 end.
 if. cmd-:'SUBST' do. g=.parse 2{::fields end.
 if. (<cmd)e.words 'TANGENT LIMIT TAYLOR' do.
  point=.2{::fields
  if. -.ratvalid point do. fail 'invalid number ',SQ,point,SQ end.
  c=.ratread point
  sigma=.(,<v);<,<N c
 end.
 if. (<cmd)e.words 'DIFFN TAYLOR' do.
  o=.{:fields
  if. -.o e.words '1 2 3 4 5 6 7 8' do. fail 'invalid order ',SQ,(>o),SQ end.
  order=.0".>o
 end.
 out=.0$a:
 select. cmd
 case. 'SIMPLIFY' do. out=.,<'simplified: ',P f
 case. 'EXPAND' do. out=.,<'expanded: ',P expand f
 case. 'DIFF' do. out=.,<'d/d',v,' = ',P v derivative f
 case. 'DIFFN' do.
  for_k. 1+i.order do. f=.v derivative f
   out=.out,<'d^',(num k),'/d',v,'^',(num k),' = ',P f
  end.
 case. 'GRAD';'HESSIAN' do.
  vs=.variables f
  if. 0=#vs do. out=.,<'no variables'
  else.
   for_i. i.#vs do.
    v=.i{::vs
    d=.v derivative f
    if. cmd-:'GRAD' do. out=.out,<'d/d',v,' = ',P d
    else. for_w. i}.vs do. out=.out,<'d2/d',v,'d',(>w),' = ',P (>w)derivative d end.
    end.
   end.
  end.
 case. 'IMPLICIT' do.
  if. v-:w do. fail 'same variable' end.
  a=.v derivative f
 b=.w derivative f
  out=.,<'d',w,'/d',v,' = ',P mul (N _1);a;<b pow N _1
 case. 'SUBST' do. out=.,<'substituted: ',P ((,<v);<,<g)subst f
 case. 'EVAL' do.
  ns=.0$a:
 vals=.0$a:
  if. n=2 do.
   for_a. words 1{::fields do.
    s=.>a
    eq=.s i.'='
    v=.eq{.s
 literal=.(eq+1)}.s
    if. (-.validvar v)+.-.ratvalid literal do. fail 'invalid assignment ',SQ,s,SQ end.
    q=.ratread literal
    if. (<v)e.ns do. fail 'duplicate variable ',v end.
    ns=.ns,<v
 vals=.vals,<N q
   end.
  end.
  for_v. variables f do. if. -.v e.ns do. fail 'no value for ',>v end. end.
  r=.(ns;<vals)subst f
  if. isnum r do. out=.,<'exact: ',P r else. out=.,<'approx: ',fixed numeric r end.
 case. 'TANGENT' do.
  m=.sigma subst v derivative f
  y0=.sigma subst f
  t=.add (mul m;<V v);y0;<mul (N -c);<m
  out=.,<'tangent: y = ',P t
  if. iszero m do. out=.out,<'normal: ',v,' = ',ratstr c
  else.
   k=.m pow N _1
   t=.add (mul (N _1);k;<V v);y0;<mul (N c);<k
   out=.out,<'normal: y = ',P t
  end.
 case. 'LIMIT' do.
  if. 2=kind f do. fs=.value f else. fs=.,<f end.
  ns=.0$a:
 ds=.0$a:
  for_a. fs do.
   g=.>a
 negative=.0
   if. 3=kind g do. e=.exponent g
    if. isnum e do. negative=.0>value e end.
   end.
   if. negative do. ds=.ds,<(base g)pow N -value e else. ns=.ns,a end.
  end.
  g=.mul ns
 h=.mul ds
  for_k. i.6 do.
   a=.sigma subst g
 b=.sigma subst h
   if. -.iszero b do. out=.,<'limit: ',P mul a;<b pow N _1 break. end.
   if. -.iszero a do. out=.,<'limit: unbounded' break. end.
   if. k=5 do. out=.,<'limit: unknown' break. end.
   g=.v derivative g
 h=.v derivative h
  end.
 case. 'TAYLOR' do.
  ts=.0$a:
 fac=.1x
  for_k. i.order+1 do.
   if. k do. f=.v derivative f
 fac=.fac*k end.
   ck=.mul (sigma subst f);<N %fac
   pk=.mul ck;<(add (V v);<N -c)pow N k
   ts=.ts,<pk
  end.
  out=.,<'taylor: ',P expand add ts
 end.
 out
)
Names=:0$a:
Definitions=:0$a:
main=:3 : 0
 lines=.<;._2 (1!:1&3''),LF
 n=.0".>{.lines
 for_line. n{.}.lines do.
  try. out=.command >line
  catcht. out=.,<'error: ',Error
  end.
  for_s. out do. 1!:2&2 (>s),LF end.
 end.
)
main''
