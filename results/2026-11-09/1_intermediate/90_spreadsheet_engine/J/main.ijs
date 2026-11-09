words=:3 : '(<;._1 '' '',y)-.<'''''
LF=:10{a.
DQ=:34{a.
Letters=:'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
Digits=:'0123456789'
num=:3 : ',''0'' 8!:2 y'
join=:4 : 0
 r=.''
 for_i. i.#y do. if. i do. r=.r,x end. r=.r,i{::y end.
 r
)
fail=:3 : 0
 Error=:y
 throw.
)
I=:3 : '0;y'
S=:3 : '1;y'
E=:3 : '2;y'
Empty=:3;''
kind=:3 : '0{::y'
val=:3 : '1{::y'
address=:3 : 0
 if. -. (#y)e.2 3 do. _1 return. end.
 if. -. ({.y)e.Letters do. _1 return. end.
 s=.}.y
 if. ('0'={.s)+.-.*./s e.Digits do. _1 return. end.
 r=.0".s
 if. (r<1)+.r>99 do. _1 return. end.
 (Letters i.{.y)+26*r-1
)
addr=:3 : '((26|y){Letters),num 1+<.y%26'
coord=:3 : '(26|y),<.y%26'
inside=:3 : '(*./y>:0)*.*./y<26 99'
refread=:3 : 0
 s=.y
 ac=.0
 ar=.0
 if. #s do. if. '$'={.s do. ac=.1
 s=.}.s end. end.
 if. 0=#s do. i.0 return. end.
 c=.Letters i.{.s
 if. c=26 do. i.0 return. end.
 s=.}.s
 if. #s do. if. '$'={.s do. ar=.1
 s=.}.s end. end.
 if. (0=#s)+.(2<#s) do. i.0 return. end.
 if. ('0'={.s)+.-.*./s e.Digits do. i.0 return. end.
 r=.0".s
 if. (r<1)+.r>99 do. i.0 return. end.
 c,(r-1),ac,ar
)
normalize=:3 : 0
 'a b'=.y
 if. (0{a)>0{b do.
  t=.0 2{a
  a=.(0 2{b)0 2}a
  b=.t 0 2}b
 end.
 if. (1{a)>1{b do.
  t=.1 3{a
  a=.(1 3{b)1 3}a
  b=.t 1 3}b
 end.
 a;b
)
range=:3 : 0
 ps=.<;._1 ':',y
 if. -. (#ps)e.1 2 do. fail 'bad address' end.
 a=.address 0{::ps
 b=.address _1{::ps
 if. (a<0)+.b<0 do. fail 'bad address' end.
 ca=.coord a
 cb=.coord b
 (ca<.cb),ca>.cb
)
cells=:3 : 0
 'c r d s'=.y
 ,(26*r+i.1+s-r)+/c+i.1+d-c
)
refstr=:3 : 0
 'c r ac ar'=.y
 (ac#'$'),(c{Letters),(ar#'$'),num r+1
)
syntax=:3 : 'fail ''syntax error at '',num y'
lex=:3 : 0
 ts=.0$a:
 i=.1
 while. i<#y do.
  c=.i{y
  if. c=' ' do. i=.i+1 continue. end.
  start=.i
  if. c e.Digits do.
   i=.i+1
   while. i<#y do. if. -. (i{y)e.Digits do. break. end. i=.i+1 end.
   if. 9<i-start do. syntax start+1 end.
   t=.0;(0".(i-start){.start}.y);start+1
  elseif. c=DQ do.
   tail=.(i+1)}.y
   j=.tail i.DQ
   if. j=#tail do. syntax start+1 end.
   t=.1;(j{.tail);start+1
   i=.i+j+2
  elseif. c e.Letters,(tolower Letters),'$' do.
   i=.i+1
   while. i<#y do. if. -. (i{y)e.Letters,(tolower Letters),Digits,'$' do. break. end. i=.i+1 end.
   s=.toupper (i-start){.start}.y
   ref=.refread s
   if. #ref do. t=.4;ref;start+1
   else.
    if. (-.({.s)e.Letters)+.-.*./s e.Letters,Digits do. syntax start+1 end.
    j=.i
    while. j<#y do. if. ' '~:j{y do. break. end. j=.j+1 end.
    k=.6
    if. j<#y do. if. '('=j{y do. k=.7 end. end.
    t=.k;s;start+1
   end.
  elseif. c e.'+-*/&(),:=<>' do.
   s=.,c
   if. (i+1)<#y do.
    p=.2{.i}.y
    if. (<p)e.words '<> <= >=' do. s=.p end.
   end.
   t=.9;s;start+1
   i=.i+#s
  else. syntax i+1 end.
  ts=.ts,<t
 end.
 ts,<10;'';1+#y
)
peek=:3 : 'Pos{::Tokens'
accept=:3 : 0
 if. y-:val peek'' do. Pos=:Pos+1
 1 else. 0 end.
)
expect=:3 : 'if. -.accept y do. syntax 2{::peek'''' end.'
primary=:3 : 0
 t=.peek''
 k=.kind peek''
 if. k e.0 1 6 do. Pos=:Pos+1
 2{.t return. end.
 if. k=4 do.
  Pos=:Pos+1
  a=.val t
  if. accept ':' do.
   t=.peek''
   if. 4~:kind t do. syntax 2{::t end.
   Pos=:Pos+1
   5;<normalize a;val t
  else. 4;a end.
  return.
 end.
 if. k=7 do.
  Pos=:Pos+1
  expect '('
  fs=.0$a:
  if. -.accept ')' do.
   fs=.,<0 expression''
   while. accept ',' do. fs=.fs,<0 expression'' end.
   expect ')'
  end.
  7;(val t);<fs return.
 end.
 if. accept '(' do. r=.0 expression''
 expect ')'
 r return. end.
 syntax 2{::t
)
unary=:3 : 0
 if. accept '-' do. 8;<unary'' else. primary'' end.
)
Levels=:(words '= <> < <= > >=');(,<'&');(words '+ -');<words '* /'
expression=:4 : 0
 if. x=4 do. unary'' return. end.
 r=.(x+1)expression''
 while. (<val peek'')e.x{::Levels do.
  op=.val peek''
  Pos=:Pos+1
  b=.(x+1)expression''
  r=.9;op;r;<b
 end.
 r
)
parse=:3 : 0
 Tokens=:lex y
 Pos=:0
 r=.0 expression''
 if. 10~:kind peek'' do. syntax 2{::peek'' end.
 r
)
precedence=:3 : 0
 op=.val y
 if. (<op)e.words '* /' do. 4 elseif. (<op)e.words '+ -' do. 3 elseif. op-:'&' do. 2 else. 1 end.
)
canonical=:3 : 0
 k=.kind y
 select. k
 case. 0 do. num val y
 case. 1 do. DQ,(val y),DQ
 case. 4 do. refstr val y
 case. 5 do. refs=.val y
  (refstr 0{::refs),':',refstr 1{::refs
 case. 6 do. val y
 case. 7 do.
  ss=.0$a:
  for_a. 2{::y do. ss=.ss,<canonical >a end.
  (val y),'(',(','join ss),')'
 case. 8 do.
  a=.val y
 s=.canonical val y
  if. 9=kind a do. s=.'(',s,')' end.
  '-',s
 case. 9 do.
  a=.2{::y
 b=.3{::y
  s=.canonical a
 t=.canonical b
 p=.precedence y
  if. 9=kind a do. if. p>precedence a do. s=.'(',s,')' end. end.
  if. 9=kind b do. if. p>:precedence b do. t=.'(',t,')' end. end.
  s,(val y),t
 case. 11 do. '#REF!'
 end.
)
notation=:3 : 0
 select. kind y
 case. 0 do. num val y
 case. 1 do. DQ,(val y),DQ
 case. 2 do. val y
 case. 3 do. '(empty)'
 case. 12 do. '=',canonical val y
 end.
)
display=:3 : 0
 if. 0=kind y do. num val y elseif. 3=kind y do. '' else. val y end.
)
getrefs=:3 : 0
 k=.kind y
 if. k=4 do. 'c r'=.2{.val y
  c+26*r return.
 end.
 if. k=5 do. 'a b'=.val y
  cells (2{.a),2{.b return.
 end.
 if. k=7 do. fs=.2{::y
 elseif. k=8 do. fs=.,<val y
 elseif. k=9 do. fs=.2}.y
 else. i.0 return. end.
 r=.i.0
 for_a. fs do. r=.r,getrefs >a end.
 /:~~.r
)
number=:3 : 0
 select. kind y
 case. 0;2 do. y
 case. 3 do. I 0
 case. do. E '#VALUE!'
 end.
)
string=:3 : 0
 select. kind y
 case. 0 do. S num val y
 case. 1;2 do. y
 case. 3 do. S ''
 case. do. E '#VALUE!'
 end.
)
compare=:4 : 0
 k=.kind x
 l=.kind y
 if. (k=1)*.l=0 do. 1 return. end.
 if. (k=0)*.l=1 do. _1 return. end.
 if. 1 e.k,l do.
  a=.val string x
 b=.val string y
  if. a-:b do. 0 elseif. (<a)-:{./:~a;b do. _1 else. 1 end.
 else. *(val number x)-val number y end.
)
Functions=:words 'SUM MIN MAX COUNT AVERAGE AND OR CONCAT IF ABS NOT LEN'
call=:3 : 0
 f=.val y
 fs=.2{::y
 if. -. (<f)e.Functions do. E '#NAME?' return. end.
 n=.#fs
 if. f-:'IF' do. good=.n e.2 3
 elseif. (<f)e.words 'ABS NOT LEN' do. good=.n=1
 else. good=.n>:1 end.
 if. -.good do. E '#VALUE!' return. end.
 if. f-:'IF' do.
  c=.number evaluate 0{::fs
  if. 2=kind c do. c return. end.
  if. 0~:val c do. evaluate 1{::fs elseif. n=3 do. evaluate 2{::fs else. I 0 end.
  return.
 end.
 if. (<f)e.words 'ABS NOT LEN' do.
  a=.evaluate 0{::fs
  if. f-:'LEN' do. a=.string a else. a=.number a end.
  if. 2=kind a do. a return. end.
  if. f-:'LEN' do. I #val a elseif. f-:'ABS' do. I |val a else. I 0=val a end.
  return.
 end.
 items=.0$a:
 for_a. fs do.
  v=.evaluate >a
  if. 4=kind v do.
   for_i. val v do. items=.items,<cellvalue i end.
  else. items=.items,<v end.
 end.
 ns=.i.0
 for_a. items do. if. 0=kind >a do. ns=.ns,val >a end. end.
 if. f-:'COUNT' do. I #ns return. end.
 for_a. items do. if. 2=kind >a do. >a return. end. end.
 select. f
 case. 'SUM' do. I +/ns
 case. 'MIN' do. if. #ns do. I <./ns else. I 0 end.
 case. 'MAX' do. if. #ns do. I >./ns else. I 0 end.
 case. 'AVERAGE' do. if. #ns do. q=.(+/ns)%#ns
 I (*q)*<.|q else. E '#DIV/0!' end.
 case. 'AND';'OR' do.
  if. 0=#ns do. E '#VALUE!'
  elseif. f-:'AND' do. I *./ns~:0 else. I +./ns~:0 end.
 case. 'CONCAT' do.
  s=.''
  for_a. items do. s=.s,val string >a end.
  S s
 end.
)
evaluate=:3 : 0
 k=.kind y
 select. k
 case. 0;1 do. y
 case. 4 do. 'c r'=.2{.val y
 cellvalue c+26*r
 case. 5 do. 'a b'=.val y
 4;cells (2{.a),2{.b
 case. 6 do. E '#NAME?'
 case. 11 do. E '#REF!'
 case. 7 do. call y
 case. 8 do.
  a=.number evaluate val y
  if. 2=kind a do. a else. I -val a end.
 case. 9 do.
  a=.evaluate 2{::y
  b=.evaluate 3{::y
  if. 2=kind a do. a return. end.
  if. 2=kind b do. b return. end.
  op=.val y
  if. (<op)e.words '+ - * / &' do.
   if. op-:'&' do. a=.string a
 b=.string b else. a=.number a
 b=.number b end.
   if. 2=kind a do. a return. end.
   if. 2=kind b do. b return. end.
   u=.val a
 v=.val b
   select. op
   case. '+' do. I u+v
   case. '-' do. I u-v
   case. '*' do. I u*v
   case. '/' do. if. v=0 do. E '#DIV/0!' else. q=.u%v
 I (*q)*<.|q end.
   case. '&' do. S u,v
   end.
  else.
   if. 4 e.(kind a),kind b do. E '#VALUE!' return. end.
   c=.a compare b
   select. op
   case. '=' do. I c=0
   case. '<>' do. I c~:0
   case. '<' do. I c<0
   case. '<=' do. I c<:0
   case. '>' do. I c>0
   case. '>=' do. I c>:0
   end.
  end.
 end.
)
visit=:3 : 0
 Indices=:Counter y}Indices
 Low=:Counter y}Low
 Counter=:Counter+1
 Stack=:Stack,y
 OnStack=:1 y}OnStack
 for_q. y{::Refs do.
  if. 12~:kind q{::Sheet do. continue. end.
  if. (q{Indices)<0 do.
   visit q
   Low=:((y{Low)<.q{Low)y}Low
  elseif. q{OnStack do.
   Low=:((y{Low)<.q{Indices)y}Low
  end.
 end.
 if. (y{Low)=y{Indices do.
  component=.i.0
  while. 1 do.
   q=.{:Stack
   Stack=:}:Stack
   OnStack=:0 q}OnStack
   component=.component,q
   if. q=y do. break. end.
  end.
  if. (1<#component)+.y e.y{::Refs do.
   Cyclic=:1 component}Cyclic
  end.
 end.
)
cellvalue=:3 : 0
 if. y{Known do. y{::Values return. end.
 if. y{Cyclic do. v=.E '#CYCLE!'
 else.
  content=.y{::Sheet
  if. 12=kind content do.
   v=.evaluate val content
   if. 3=kind v do. v=.I 0 elseif. 4=kind v do. v=.E '#VALUE!' end.
  else. v=.content end.
 end.
 Values=:(<v)y}Values
 Known=:1 y}Known
 v
)
recalc=:3 : 0
 Refs=:2574$<i.0
 for_i. i.2574 do.
  c=.i{::Sheet
  if. 12=kind c do. Refs=:(<getrefs val c)i}Refs end.
 end.
 Indices=:2574$_1
 Low=:2574$_1
 OnStack=:2574$0
 Cyclic=:2574$0
 Counter=:0
 Stack=:i.0
 for_i. i.2574 do.
  if. (12=kind i{::Sheet)*.(i{Indices)<0 do. visit i end.
 end.
 Values=:2574$<Empty
 Known=:2574$0
 for_i. i.2574 do. cellvalue i end.
)
rewriteRef=:3 : 0
 r=.y
 p=.2{.r
 select. Rewrite
 case. 'COPY' do. p=.p+Delta*(1-2}.r)
 case. 'MOVE' do.
  i=.(0{p)+26*1{p
  if. i e.Source do. p=.p+Delta elseif. i e.Dest do. i.0 return. end.
 case. 'INSERT' do. a=.Axis{p
  if. a>:At do. p=.(a+1)Axis}p end.
 case. 'DELETE' do. a=.Axis{p
  if. a=At do. i.0 return. elseif. a>At do. p=.(a-1)Axis}p end.
 end.
 if. -.inside p do. i.0 else. p,2}.r end.
)
rewrite=:3 : 0
 k=.kind y
 if. k=4 do.
  r=.rewriteRef val y
  if. #r do. 4;r else. 11;'' end.
  return.
 end.
 if. k=5 do.
  'a b'=.val y
  if. Rewrite-:'MOVE' do.
   ai=.(0{a)+26*1{a
 bi=.(0{b)+26*1{b
   if. -. (ai e.Source)*.bi e.Source do. y return. end.
   a=.(Delta+2{.a),2}.a
 b=.(Delta+2{.b),2}.b
  elseif. Rewrite-:'DELETE' do.
   u=.Axis{a
 v=.Axis{b
   if. (u=At)*.v=At do. 11;'' return. end.
   a=.(u-(u>At))Axis}a
   b=.(v-(v>:At))Axis}b
  else. a=.rewriteRef a
 b=.rewriteRef b end.
  if. (0=#a)+.0=#b do. 11;'' else. 5;<normalize a;b end.
  return.
 end.
 if. k=7 do.
  fs=.0$a:
  for_a. 2{::y do. fs=.fs,<rewrite >a end.
  7;(val y);<fs
 elseif. k=8 do. 8;<rewrite val y
 elseif. k=9 do.
  a=.rewrite 2{::y
  b=.rewrite 3{::y
  9;(val y);a;<b
 else. y end.
)
rewriteAll=:3 : 0
 for_i. i.2574 do.
  c=.i{::Sheet
  if. 12=kind c do. Sheet=:(<12;<rewrite val c)i}Sheet end.
 end.
)
content=:3 : 0
 if. '='={.y do. 12;<parse y return. end.
 if. 2<:#y do.
  if. (DQ={.y)*.DQ={:y do.
   s=.}.}:y
   if. -.DQ e.s do. S s return. end.
  end.
 end.
 if. y-:'0' do. I 0 return. end.
 s=.y
 sign=.1
 if. '-'={.s do. sign=._1
 s=.}.s end.
 if. (#s)e.1+i.9 do.
  if. ({.s)e.'123456789' do. if. *./s e.Digits do. I sign*0".s return. end. end.
 end.
 fail 'bad value'
)
show=:3 : '(addr y),'': '',(notation y{::Sheet),'' -> '',notation y{::Values'
refnames=:3 : 0
 if. 0=#y do. 'none' return. end.
 ss=.0$a:
 for_i. y do. ss=.ss,<addr i end.
 ','join ss
)
table=:3 : 0
 'c r d s'=.y
 cols=.c+i.1+d-c
 rows=.r+i.1+s-r
 rw=.#num s+1
 widths=.i.0
 for_col. cols do.
  w=.1
  for_row. rows do. w=.w>.#display (col+26*row){::Values end.
  widths=.widths,w
 end.
 sep=.'+',(rw$'-'),'+'
 header=.'|',(rw$' '),'|'
 for_j. i.#cols do.
  w=.j{widths
  sep=.sep,(w$'-'),'+'
  header=.header,((j{cols){Letters),((w-1)$' '),'|'
 end.
 out=.sep;header;<sep
 for_row. rows do.
  st=.num row+1
  line=.'|',((rw-#st)$' '),st,'|'
  for_j. i.#cols do.
   v=.((j{cols)+26*row){::Values
   st=.display v
 w=.j{widths
   if. 0=kind v do. st=.((w-#st)$' '),st else. st=.st,((w-#st)$' ') end.
   line=.line,st,'|'
  end.
  out=.out,<line
 end.
 out,<sep
)
Commands=:words 'SET CLEAR COPY MOVE INSERTROW DELETEROW INSERTCOL DELETECOL PRINT SHOW DEPS LIST UNDO'
command=:3 : 0
 p=.y i.' '
 cmd=.p{.y
 arg=.(p+1)}.y
 if. -. (<cmd)e.Commands do. fail 'unknown command' end.
 if. cmd-:'LIST' do.
  out=.0$a:
  for_i. i.2574 do. if. 3~:kind i{::Sheet do. out=.out,<show i end. end.
  if. #out do. out else. ,<'(no cells)' end.
  return.
 end.
 if. (<cmd)e.words 'SHOW DEPS' do.
  i=.address arg
  if. i<0 do. fail 'bad address' end.
  if. cmd-:'SHOW' do. ,<show i return. end.
  deps=.i.0
  for_j. i.2574 do. if. i e.j{::Refs do. deps=.deps,j end. end.
  ,<arg,': precedents=',(refnames i{::Refs),' dependents=',refnames deps return.
 end.
 if. cmd-:'PRINT' do. table range arg return. end.
 before=.Values
 old=.Sheet
 if. cmd-:'UNDO' do.
  if. 0=#History do. fail 'nothing to undo' end.
  'name Sheet'=:>{:History
  History=:}:History
  recalc''
  ,<'UNDO ',name,' changed=',num +/-.before-:&>Values return.
 end.
 if. cmd-:'SET' do.
  p=.arg i.' '
  a=.p{.arg
  i=.address a
  if. i<0 do. fail 'bad address' end.
  c=.content (p+1)}.arg
  Sheet=:(<c)i}Sheet
 elseif. cmd-:'CLEAR' do.
  Source=:cells range arg
  Sheet=:(<Empty)Source}Sheet
 elseif. (<cmd)e.words 'COPY MOVE' do.
  ps=.words arg
  bounds=.range 0{::ps
  target=.address 1{::ps
  if. target<0 do. fail 'bad address' end.
  Delta=:(coord target)-2{.bounds
  hi=.(2}.bounds)+Delta
  if. -.inside hi do. fail 'out of grid' end.
  Source=:cells bounds
  Dest=:Source+(0{Delta)+26*1{Delta
  Rewrite=:cmd
  if. cmd-:'MOVE' do. rewriteAll'' end.
  copied=.Source{Sheet
  if. cmd-:'MOVE' do. Sheet=:(<Empty)Source}Sheet
  else.
   for_j. i.#copied do.
    c=.j{::copied
    if. 12=kind c do. copied=:(<12;<rewrite val c)j}copied end.
   end.
  end.
  Sheet=:copied Dest}Sheet
 else.
  Axis=:('ROW'-:_3{.cmd)
  if. Axis do.
   valid=.((#arg)e.1 2)*.*./arg e.Digits
   if. valid do. valid=.('0'~:{.arg)*.(0".arg)e.1+i.99 end.
   if. -.valid do. fail 'bad address' end.
   At=:(_1+0".arg)
  else.
   if. (1~:#arg)+.-.arg e.Letters do. fail 'bad address' end.
   At=:Letters i.{.arg
  end.
  inserting=.'INSERT'-:6{.cmd
  Rewrite=:inserting{::'DELETE';'INSERT'
  if. inserting do.
   for_i. i.2574 do.
    p=.coord i
    if. (Axis{p)=Axis{25 98 do.
     if. 3~:kind i{::Sheet do.
      if. Axis do. fail 'last row not empty' else. fail 'last column not empty' end.
     end.
    end.
   end.
  end.
  fresh=.2574$<Empty
  for_i. i.2574 do.
   p=.coord i
   a=.Axis{p
   if. inserting do.
    if. a>:At do. p=.(a+1)Axis}p end.
   else.
    if. a=At do. continue. end.
    if. a>At do. p=.(a-1)Axis}p end.
   end.
   if. inside p do. j=.(0{p)+26*1{p
 fresh=.(i{Sheet)j}fresh end.
  end.
  Sheet=:fresh
  rewriteAll''
 end.
 History=:History,<cmd;<old
 recalc''
 count=.+/-.before-:&>Values
 if. cmd-:'SET' do. ,<'SET ',a,'=',(notation i{::Values),' changed=',num count
 else. ,<cmd,' changed=',num count end.
)
Sheet=:2574$<Empty
History=:0$a:
recalc''
main=:3 : 0
 lines=.<;._2 (1!:1&3''),LF
 n=.0".>{.lines
 for_line. n{.}.lines do.
  try. out=.command >line
  catcht. out=.,<'ERROR ',Error end.
  for_s. out do. 1!:2&2 (>s),LF end.
 end.
)
main''
