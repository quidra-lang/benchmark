words=:3 : '(<;._1 '' '',y)-.<'''''
LF=:10{a.
SQ=:39{a.
Letters=:'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
Digits=:'0123456789'
Reserved=:words 'SELECT DISTINCT FROM AS JOIN INNER LEFT OUTER ON WHERE GROUP BY HAVING ORDER ASC DESC LIMIT OFFSET INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE DROP PRIMARY KEY NOT NULL INT TEXT AND OR IS IN BETWEEN LIKE COUNT SUM MIN MAX AVG EXIT'
Aggregates=:words 'COUNT SUM MIN MAX AVG'
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
Null=:2;''
kind=:3 : '0{::y'
val=:3 : '1{::y'
written=:3 : 0
 if. 0=kind y do. num val y elseif. 1=kind y do. val y else. 'NULL' end.
)
truth=:3 : 'if. 2=kind y do. _1 else. 0~:val y end.'
compare=:4 : 0
 a=.kind x
 b=.kind y
 if. (a=2)+.b=2 do. (a~:2)-(b~:2) return. end.
 if. a=0 do. *(val x)-val y
 else.
  s=.val x
  t=.val y
  if. s-:t do. 0 elseif. (<s)-:{./:~s;t do. _1 else. 1 end.
 end.
)
lex=:3 : 0
 ts=.0$a:
 i=.0
 while. i<#y do.
  c=.i{y
  if. c e.' ',LF do. i=.i+1 continue. end.
  if. '--'-:2{.i}.y do.
   while. i<#y do. if. LF=i{y do. break. end. i=.i+1 end.
   continue.
  end.
  start=.i
  if. c=SQ do.
   i=.i+1
   while. SQ~:i{y do. i=.i+1 end.
   i=.i+1
   raw=.(i-start){.start}.y
   t=.1;(}.}:raw);raw
  elseif. c e.Digits do.
   i=.i+1
   while. i<#y do. if. -. (i{y)e.Digits do. break. end. i=.i+1 end.
   raw=.(i-start){.start}.y
   t=.0;(0".raw);raw
  elseif. c e.Letters,'_' do.
   i=.i+1
   while. i<#y do. if. -. (i{y)e.Letters,Digits,'_' do. break. end. i=.i+1 end.
   raw=.(i-start){.start}.y
   canonical=.toupper raw
   if. (<canonical)e.Reserved do. t=.3;canonical;raw else. t=.2;raw;raw end.
  else.
   raw=.2{.i}.y
   if. (<raw)e.words '<> != <= >= ||' do. i=.i+2
   elseif. c e.'(),.;*/%+-=<>' do. raw=.,c
    i=.i+1
   else. fail 'unexpected character ',SQ,c,SQ end.
   t=.4;raw;raw
  end.
  ts=.ts,<t
 end.
 ts
)
peek=:3 : 'Pos{::Tokens'
key=:3 : 0
 t=.peek''
 if. (kind t)e.3 4 do. val t else. '' end.
)
syntax=:3 : 'fail ''syntax error at '',SQ,(2{::peek''''),SQ'
accept=:3 : 0
 if. y-:key'' do. Pos=:Pos+1
  1
 else. 0 end.
)
expect=:3 : 'if. -.accept y do. syntax'''' end.'
name=:3 : 0
 t=.peek''
 if. 2~:kind t do. syntax'' end.
 Pos=:Pos+1
 val t
)
column=:3 : 0
 c=.name''
 q=.''
 if. accept '.' do. q=.c
  c=.name''
 end.
 w=.c
 if. #q do. w=.q,'.',c end.
 3;q;c;w
)
primary=:3 : 0
 t=.peek''
 k=.kind t
 if. k e.0 1 do. Pos=:Pos+1
  2{.t return.
 end.
 if. k=2 do. column'' return. end.
 if. accept 'NULL' do. Null return. end.
 if. accept '(' do.
  a=.expression''
  expect ')'
  11;<a return.
 end.
 f=.key''
 if. (<f)e.Aggregates do.
  Pos=:Pos+1
  expect '('
  distinct=.0
  star=.0
  if. f-:'COUNT' do. star=.accept '*' end.
  if. star do. a=.Null
  else.
   distinct=.accept 'DISTINCT'
   a=.expression''
  end.
  expect ')'
  10;f;distinct;star;<a return.
 end.
 syntax''
)
unary=:3 : 'if. accept ''-'' do. 5;''-'';<unary'''' else. primary'''' end.'
multiplicative=:3 : 0
 a=.unary''
 while. (<key'')e.words '* / %' do.
  op=.key''
  Pos=:Pos+1
  b=.unary''
  a=.6;op;a;<b
 end.
 a
)
additive=:3 : 0
 a=.multiplicative''
 while. (<key'')e.words '+ - ||' do.
  op=.key''
  Pos=:Pos+1
  b=.multiplicative''
  a=.6;op;a;<b
 end.
 a
)
comparison=:3 : 0
 a=.additive''
 op=.key''
 if. (<op)e.words '= <> != < <= > >=' do.
  Pos=:Pos+1
  b=.additive''
  6;op;a;<b return.
 end.
 if. accept 'IS' do.
  neg=.accept 'NOT'
  expect 'NULL'
  7;neg;<a return.
 end.
 neg=.accept 'NOT'
 if. accept 'IN' do.
  expect '('
  fs=.,<expression''
  while. accept ',' do. fs=.fs,<expression'' end.
  expect ')'
  8;neg;a;<fs return.
 elseif. accept 'BETWEEN' do.
  lo=.additive''
  expect 'AND'
  hi=.additive''
  9;neg;a;lo;<hi return.
 elseif. accept 'LIKE' do.
  b=.additive''
  a=.6;'LIKE';a;<b
  if. neg do. 5;'NOT';<a else. a end.
  return.
 end.
 if. neg do. syntax'' end.
 a
)
notexpr=:3 : 'if. accept ''NOT'' do. 5;''NOT'';<notexpr'''' else. comparison'''' end.'
andexpr=:3 : 0
 a=.notexpr''
 while. accept 'AND' do. b=.notexpr''
  a=.6;'AND';a;<b
 end.
 a
)
expression=:3 : 0
 a=.andexpr''
 while. accept 'OR' do. b=.andexpr''
  a=.6;'OR';a;<b
 end.
 a
)
heading=:3 : 0
 r=.''
 previous=.4
 for_t. y do.
  k=.kind >t
  if. (#r)*.(k~:4)*.previous~:4 do. r=.r,' ' end.
  r=.r,2{::>t
  previous=.k
 end.
 r
)
tableref=:3 : 0
 t=.name''
 alias=.t
 if. accept 'AS' do. alias=.name''
 elseif. 2=kind peek'' do. alias=.name'' end.
 t;alias
)
selectparse=:3 : 0
 distinct=.accept 'DISTINCT'
 items=.0$a:
 star=.accept '*'
 if. -.star do.
  while. 1 do.
   start=.Pos
   expr=.expression''
   text=.heading (Pos-start){.start}.Tokens
   if. 3=kind expr do. text=.2{::expr end.
   alias=.''
   if. accept 'AS' do. alias=.name''
   elseif. 2=kind peek'' do. alias=.name'' end.
   if. #alias do. text=.alias end.
   items=.items,<expr;alias;text
   if. -.accept ',' do. break. end.
  end.
 end.
 expect 'FROM'
 tables=.,<tableref''
 joins=.0$a:
 while. (<key'')e.words 'JOIN INNER LEFT' do.
  left=.accept 'LEFT'
  if. left do. accept 'OUTER' else. accept 'INNER' end.
  expect 'JOIN'
  tables=.tables,<tableref''
  expect 'ON'
  e=.expression''
  joins=.joins,<left;<e
 end.
 where=.a:
 if. accept 'WHERE' do. where=.<expression'' end.
 groups=.0$a:
 hasgroup=.accept 'GROUP'
 if. hasgroup do.
  expect 'BY'
  groups=.,<column''
  while. accept ',' do. groups=.groups,<column'' end.
 end.
 having=.a:
 if. accept 'HAVING' do. having=.<expression'' end.
 orders=.0$a:
 if. accept 'ORDER' do.
  expect 'BY'
  while. 1 do.
   e=.expression''
   desc=.accept 'DESC'
   if. -.desc do. accept 'ASC' end.
   orders=.orders,<e;desc
   if. -.accept ',' do. break. end.
  end.
 end.
 limit=._1
 offset=.0
 if. accept 'LIMIT' do.
  if. 0~:kind peek'' do. syntax'' end.
  limit=.val peek''
  Pos=:Pos+1
  if. accept 'OFFSET' do.
   if. 0~:kind peek'' do. syntax'' end.
   offset=.val peek''
   Pos=:Pos+1
  end.
 end.
 'SELECT';distinct;star;items;tables;joins;where;hasgroup;groups;having;orders;limit;offset
)
parse=:3 : 0
 Tokens=:lex y
 Pos=:0
 if. accept ';' do. ,<'EMPTY' return. end.
 if. accept 'EXIT' do. result=.,<'EXIT'
 elseif. accept 'CREATE' do.
  expect 'TABLE'
  t=.name''
  expect '('
  defs=.0$a:
  while. 1 do.
   c=.name''
   type=.key''
   if. -. (<type)e.words 'INT TEXT' do. syntax'' end.
   Pos=:Pos+1
   pk=.0
   nn=.0
   while. (<key'')e.words 'PRIMARY NOT' do.
    if. accept 'PRIMARY' do. expect 'KEY'
     pk=.pk+1
    else. expect 'NOT'
     expect 'NULL'
     nn=.1
    end.
   end.
   defs=.defs,<c;(type-:'TEXT');nn;pk
   if. -.accept ',' do. break. end.
  end.
  expect ')'
  result=.'CREATE';t;<defs
 elseif. accept 'DROP' do. expect 'TABLE'
  result=.'DROP';name''
 elseif. accept 'INSERT' do.
  expect 'INTO'
  t=.name''
  cols=.0$a:
  if. accept '(' do. cols=.,<name''
   while. accept ',' do. cols=.cols,<name'' end.
   expect ')'
  end.
  expect 'VALUES'
  tuples=.0$a:
  while. 1 do.
   expect '('
   fs=.,<expression''
   while. accept ',' do. fs=.fs,<expression'' end.
   expect ')'
   tuples=.tuples,<fs
   if. -.accept ',' do. break. end.
  end.
  result=.'INSERT';t;cols;<tuples
 elseif. accept 'UPDATE' do.
  t=.name''
  expect 'SET'
  assignments=.0$a:
  while. 1 do.
   c=.name''
   expect '='
   a=.expression''
   assignments=.assignments,<c;<a
   if. -.accept ',' do. break. end.
  end.
  where=.a:
  if. accept 'WHERE' do. where=.<expression'' end.
  result=.'UPDATE';t;assignments;<where
 elseif. accept 'DELETE' do.
  expect 'FROM'
  t=.name''
  where=.a:
  if. accept 'WHERE' do. where=.<expression'' end.
  result=.'DELETE';t;<where
 elseif. accept 'SELECT' do. result=.selectparse''
 else. syntax'' end.
 expect ';'
 result
)
DbNames=:0$a:
DbTables=:0$a:
findtable=:3 : 0
 i=.DbNames i.<y
 if. i=#DbNames do. fail 'unknown table ',y end.
 i
)
clearscope=:3 : 0
 ScopeNames=:0$a:
 ScopeCols=:0$a:
 ScopeQual=:0$a:
 ScopeTypes=:i.0
)
addscope=:3 : 0
 'alias table'=.y
 'cols types nn pk rows'=.table
 ScopeNames=:ScopeNames,<alias
 ScopeCols=:ScopeCols,cols
 ScopeQual=:ScopeQual,(#cols)$<alias
 ScopeTypes=:ScopeTypes,types
)
resolve=:3 : 0
 'tag qualifier col text'=.y
 matches=.I.ScopeCols=<col
 if. #qualifier do.
  if. -. (<qualifier)e.ScopeNames do. fail 'unknown table ',qualifier end.
  matches=.matches#~(matches{ScopeQual)=<qualifier
 end.
 if. 0=#matches do. fail 'unknown column ',text end.
 if. 1<#matches do. fail 'ambiguous column ',col end.
 {.matches
)
compatible=:4 : '(x=y)+.2 e.x,y'
mismatch=:3 : 'fail ''type mismatch for '',y'
check=:3 : 0
 k=.kind y
 if. k e.0 1 2 do. Type=:k
  y return.
 end.
 if. k=3 do.
  i=.resolve y
  if. Grouping*.-.InsideAgg do.
   if. -.i e.GroupCols do. fail 'column ',(3{::y),' is not grouped' end.
  end.
  Type=:i{ScopeTypes
  4;i;Type;3{::y return.
 end.
 if. k=4 do. Type=:2{::y
  y return.
 end.
 if. k=11 do. a=.check val y
  11;<a return.
 end.
 if. k=10 do.
  'tag f distinct star arg'=.y
  if. (-.AllowAgg)+.InsideAgg do. fail 'misuse of aggregate ',f end.
  if. star do. Type=:0
   y return.
  end.
  InsideAgg=:1
  a=.check arg
  InsideAgg=:0
  if. (<f)e.words 'SUM AVG' do. if. -.0 compatible Type do. mismatch f end. end.
  if. (<f)e.words 'COUNT SUM AVG' do. Type=:0 end.
  10;f;distinct;star;<a return.
 end.
 if. k=5 do.
  op=.val y
  a=.check 2{::y
  if. -.0 compatible Type do. mismatch op end.
  Type=:0
  5;op;<a return.
 end.
 if. k=7 do. a=.check 2{::y
  Type=:0
  7;(val y);<a return.
 end.
 if. k=6 do.
  op=.val y
  a=.check 2{::y
  ta=.Type
  b=.check 3{::y
  tb=.Type
  if. (<op)e.words '+ - * / % AND OR' do.
   if. (-.0 compatible ta)+.-.0 compatible tb do. mismatch op end.
   Type=:0
  elseif. (<op)e.words '|| LIKE' do.
   if. (-.1 compatible ta)+.-.1 compatible tb do. mismatch op end.
   Type=:op-:'||'
  else.
   if. -.ta compatible tb do. mismatch op end.
   Type=:0
  end.
  6;op;a;<b return.
 end.
 a=.check 2{::y
 ta=.Type
 fs=.0$a:
 types=.i.0
 if. k=8 do. source=.3{::y else. source=.3}.y end.
 for_f. source do.
  fs=.fs,<check >f
  types=.types,Type
 end.
 op=.k{::'';'';'';'';'';'';'';'';'IN';'BETWEEN'
 for_t. types do. if. -.ta compatible t do. mismatch op end. end.
 Type=:0
 if. k=8 do. 8;(val y);a;<fs else. 9;(val y);a;fs end.
)
condition=:4 : 0
 a=.check y
 if. -.0 compatible Type do. mismatch x end.
 a
)
containsagg=:3 : 0
 k=.kind y
 if. k=10 do. 1 return. end.
 if. k e.0 1 2 3 4 do. 0 return. end.
 if. k=11 do. fs=.,<val y
 elseif. k e.5 7 do. fs=.,<2{::y
 elseif. k=8 do. fs=.(2{y),3{::y
 else. fs=.2}.y end.
 for_f. fs do. if. containsagg >f do. 1 return. end. end.
 0
)
like=:4 : 0
 text=.x
 pattern=.y
 dp=.(1),(#text)$0
 for_c. pattern do.
  next=.(1+#text)$0
  if. c='%' do.
   next=.({.dp)0}next
   for_i. 1+i.#text do. next=.((i{dp)+.(i-1){next)i}next end.
  else.
   for_i. i.#text do.
    next=.((i{dp)*.(c='_')+.c=i{text)(i+1)}next
   end.
  end.
  dp=.next
 end.
 {:dp
)
boolean=:4 : 0
 'a b'=.y
 u=.truth a
 v=.truth b
 if. x-:'AND' do.
  if. 0 e.u,v do. I 0 elseif. _1 e.u,v do. Null else. I 1 end.
 else.
  if. 1 e.u,v do. I 1 elseif. _1 e.u,v do. Null else. I 0 end.
 end.
)
relation=:4 : 0
 'a b'=.y
 if. 2 e.(kind a),kind b do. Null return. end.
 c=.a compare b
 select. x
 case. '=' do. I c=0
 case. '<>'; '!=' do. I c~:0
 case. '<' do. I c<0
 case. '<=' do. I c<:0
 case. '>' do. I c>0
 case. '>=' do. I c>:0
 end.
)
negate=:3 : 'if. 2=kind y do. Null else. I 0=val y end.'
evaluate=:4 : 0
 row=.x
 k=.kind y
 if. k e.0 1 2 do. y return. end.
 if. k=4 do. (val y){::row return. end.
 if. k=11 do. row evaluate val y return. end.
 if. k=10 do.
  'tag f distinct star arg'=.y
  if. star do. I #EvalGroup return. end.
  vals=.0$a:
  for_r. EvalGroup do.
   a=.(>r)evaluate arg
   if. 2~:kind a do. vals=.vals,<a end.
  end.
  if. distinct do. vals=.~.vals end.
  if. f-:'COUNT' do. I #vals return. end.
  if. 0=#vals do. Null return. end.
  if. (<f)e.words 'MIN MAX' do.
   best=.>{.vals
   for_a. }.vals do.
    c=.(>a)compare best
    if. ((f-:'MIN')*.c<0)+.((f-:'MAX')*.c>0) do. best=.>a end.
   end.
   best
  else.
   sum=.0
   for_a. vals do. sum=.sum+val >a end.
   if. f-:'AVG' do. q=.sum%#vals
    sum=.(*q)*<.|q
   end.
   I sum
  end.
  return.
 end.
 if. k=5 do.
  a=.row evaluate 2{::y
  if. (val y)-:'NOT' do. negate a
  elseif. 2=kind a do. Null else. I -val a end.
  return.
 end.
 if. k=7 do.
  a=.row evaluate 2{::y
  I (val y)~:2=kind a return.
 end.
 a=.row evaluate 2{::y
 if. k=8 do.
  seenNull=.2=kind a
  found=.0
  for_f. 3{::y do.
   b=.row evaluate >f
   if. 2=kind b do. seenNull=.1 elseif. a-:b do. found=.1 end.
  end.
  if. found do. r=.I 1 elseif. seenNull do. r=.Null else. r=.I 0 end.
  if. val y do. negate r else. r end.
  return.
 end.
 b=.row evaluate 3{::y
 if. k=9 do.
  c=.row evaluate 4{::y
  p=.'>='relation a;<b
  q=.'<='relation a;<c
  r=.'AND'boolean p;<q
  if. val y do. negate r else. r end.
  return.
 end.
 op=.val y
 if. (<op)e.words 'AND OR' do. op boolean a;<b return. end.
 if. 2 e.(kind a),kind b do. Null return. end.
 u=.val a
 v=.val b
 select. op
 case. '+' do. I u+v
 case. '-' do. I u-v
 case. '*' do. I u*v
 case. '/';'%' do.
  if. v=0 do. Null
  else. q=.u%v
   q=.(*q)*<.|q
   if. op-:'/' do. I q else. I u-v*q end.
  end.
 case. '||' do. S u,v
 case. 'LIKE' do. I u like v
 case. do. op relation a;<b
 end.
)
constraint=:4 : 0
 'cols types nn pk rows'=.x
 for_i. y do.
  row=.i{::rows
  for_j. i.#cols do.
   if. (j{nn)*.2=kind j{::row do. fail 'NULL value in column ',j{::cols end.
  end.
  if. pk>:0 do.
   v=.pk{::row
   for_j. (i.#rows)-.i do.
    if. v-:pk{::j{::rows do. fail 'duplicate primary key ',written v end.
   end.
  end.
 end.
)
countline=:4 : '(num y),'' row'',((y~:1)#''s''),'' '',x,''.'''
settings=:3 : 0
 AllowAgg=:0
 Grouping=:0
 InsideAgg=:0
 GroupCols=:i.0
 EvalGroup=:0$a:
)
resulttable=:3 : 0
 'heads types rows'=.y
 widths=.#&>heads
 strings=.0$a:
 for_row. rows do.
  ss=.0$a:
  for_v. >row do. ss=.ss,<written >v end.
  widths=.widths>.#&>ss
  strings=.strings,<ss
 end.
 sep=.'+'
 line=.'|'
 for_i. i.#heads do.
  w=.i{widths
  s=.i{::heads
  sep=.sep,((w+2)$'-'),'+'
  line=.line,' ',s,((w-#s)$' '),' |'
 end.
 out=.sep;line;sep
 for_row. strings do.
  line=.'|'
  for_i. i.#heads do.
   s=.i{::>row
   padding=.((i{widths)-#s)$' '
   if. 0=i{types do. s=.padding,s else. s=.s,padding end.
   line=.line,' ',s,' |'
  end.
  out=.out,<line
 end.
 out,sep;('(',(num #rows),' row',((1~:#rows)#'s'),')')
)
keyless=:4 : 0
 a=.x
 b=.y
 for_i. i.#OrderDesc do.
  c=.(i{::a)compare i{::b
  if. c do.
   if. i{OrderDesc do. c>0 else. c<0 end.
   return.
  end.
 end.
 0
)
query=:3 : 0
 'tag distinct star items tables joins where hasgroup groups having orders limit offset'=.y
 clearscope''
 settings''
 resolvedtables=.i.0
 checkedjoins=.0$a:
 for_i. i.#tables do.
  't alias'=.i{::tables
  ti=.findtable t
  if. (<alias)e.ScopeNames do. fail 'duplicate table name ',alias end.
  addscope alias;<ti{::DbTables
  resolvedtables=.resolvedtables,ti
  if. i do.
   'left on'=.(i-1){::joins
   on=.'ON'condition on
   checkedjoins=.checkedjoins,<left;<on
  end.
 end.
 if. -.where-:a: do. where=.<'WHERE'condition >where end.
 GroupCols=:i.0
 for_g. groups do. GroupCols=:GroupCols,resolve >g end.
 aggregate=.hasgroup+.-.having-:a:
 for_item. items do. aggregate=.aggregate+.containsagg 0{::>item end.
 for_order. orders do. aggregate=.aggregate+.containsagg 0{::>order end.
 AllowAgg=:1
 Grouping=:aggregate
 if. star do.
  items=.0$a:
  for_i. i.#ScopeCols do.
   expr=.3;(i{::ScopeQual);(i{::ScopeCols);i{::ScopeCols
   items=.items,<expr;'';i{::ScopeCols
  end.
 end.
 expressions=.0$a:
 heads=.0$a:
 aliases=.0$a:
 types=.i.0
 for_item. items do.
  'expr alias head'=.>item
  expressions=.expressions,<check expr
  types=.types,Type
  heads=.heads,<head
  aliases=.aliases,<alias
 end.
 if. -.having-:a: do. having=.<'HAVING'condition >having end.
 keys=.0$a:
 OrderDesc=:i.0
 for_order. orders do.
  'expr desc'=.>order
  index=._1
  if. 0=kind expr do.
   k=.val expr
   if. (k<1)+.k>#expressions do. fail 'ORDER BY position ',(num k),' is out of range' end.
   index=.k-1
  elseif. 3=kind expr do.
   if. 0=#val expr do.
    j=.aliases i.<2{::expr
    if. j<#aliases do. index=.j end.
   end.
  end.
  if. index<0 do. expr=.check expr end.
  keys=.keys,<index;<expr
  OrderDesc=:OrderDesc,desc
 end.
 first=.({.resolvedtables){::DbTables
 rows=.4{::first
 for_j. i.#checkedjoins do.
  'left on'=.j{::checkedjoins
  table=.((j+1){resolvedtables){::DbTables
  right=.4{::table
  fresh=.0$a:
  for_l. rows do.
   found=.0
   for_r. right do.
    row=.(>l),>r
    if. 1=truth row evaluate on do. fresh=.fresh,<row
     found=.1
    end.
   end.
   if. left*.-.found do. fresh=.fresh,<(>l),(#0{::table)$<Null end.
  end.
  rows=.fresh
 end.
 if. -.where-:a: do.
  fresh=.0$a:
  for_row. rows do. if. 1=truth (>row)evaluate >where do. fresh=.fresh,row end. end.
  rows=.fresh
 end.
 batches=.0$a:
 if. aggregate do.
  if. hasgroup do.
   seen=.0$a:
   for_row. rows do.
    gkey=.GroupCols{>row
    i=.seen i.<gkey
    if. i=#seen do. seen=.seen,<gkey
     batches=.batches,<,row
    else. batches=.(<(i{::batches),row)i}batches end.
   end.
  else. batches=.,<rows end.
 else.
  for_row. rows do. batches=.batches,<,row end.
 end.
 outputs=.0$a:
 sortkeys=.0$a:
 for_batch. batches do.
  EvalGroup=:>batch
  if. #EvalGroup do. row=.>{.EvalGroup else. row=.(#ScopeCols)$<Null end.
  if. -.having-:a: do. if. 1~:truth row evaluate >having do. continue. end. end.
  vals=.0$a:
  for_expr. expressions do. vals=.vals,<row evaluate >expr end.
  kv=.0$a:
  for_key. keys do.
   'index expr'=.>key
   if. index>:0 do. v=.index{::vals else. v=.row evaluate expr end.
   kv=.kv,<v
  end.
  outputs=.outputs,<vals
  sortkeys=.sortkeys,<kv
 end.
 order=.i.0
 for_i. i.#outputs do.
  j=.0
  while. j<#order do.
   if. (i{::sortkeys)keyless (j{order){::sortkeys do. break. end.
   j=.j+1
  end.
  order=.(j{.order),i,j}.order
 end.
 outputs=.order{outputs
 if. distinct do. outputs=.~.outputs end.
 outputs=.offset}.outputs
 if. limit>:0 do. outputs=.(limit<.#outputs){.outputs end.
 resulttable heads;types;<outputs
)
execute=:3 : 0
 cmd=.0{::y
 if. (<cmd)e.words 'EMPTY EXIT' do. 0$a: return. end.
 if. cmd-:'SELECT' do. query y return. end.
 t=.1{::y
 if. cmd-:'CREATE' do.
  if. (<t)e.DbNames do. fail 'table ',t,' already exists' end.
  defs=.2{::y
  cols=.0$a:
  types=.i.0
  nn=.i.0
  pk=._1
  count=.0
  for_def. defs do.
   'c type forbidden primary'=.>def
   if. (<c)e.cols do. fail 'duplicate column ',c end.
   count=.count+primary
   if. count>1 do. fail 'multiple primary keys' end.
   if. primary do. pk=.#cols end.
   cols=.cols,<c
   types=.types,type
   nn=.nn,forbidden+.primary>0
  end.
  table=.cols;types;nn;pk;<0$a:
  DbNames=:DbNames,<t
  DbTables=:DbTables,<table
  ,<'Table ',t,' created.' return.
 end.
 ti=.findtable t
 if. cmd-:'DROP' do.
  keep=.(i.#DbNames)-.ti
  DbNames=:keep{DbNames
  DbTables=:keep{DbTables
  ,<'Table ',t,' dropped.' return.
 end.
 table=.ti{::DbTables
 'cols types nn pk rows'=.table
 clearscope''
 settings''
 if. cmd-:'INSERT' do.
  targets=.2{::y
  if. 0=#targets do. targets=.cols end.
  indexes=.i.0
  for_c. targets do.
   i=.cols i.c
   if. i=#cols do. fail 'unknown column ',>c end.
   if. i e.indexes do. fail 'duplicate column ',>c end.
   indexes=.indexes,i
  end.
  checked=.0$a:
  for_tuple. 3{::y do.
   fs=.>tuple
   if. (#fs)~:#indexes do. fail 'expected ',(num #indexes),' values, got ',num #fs end.
   result=.0$a:
   for_j. i.#fs do.
    e=.check j{::fs
    i=.j{indexes
    if. -.Type compatible i{types do. fail 'type mismatch for column ',i{::cols end.
    result=.result,<e
   end.
   checked=.checked,<result
  end.
  fresh=.rows
  for_tuple. checked do.
   row=.(#cols)$<Null
   fs=.>tuple
   for_j. i.#fs do. value=.(0$a:)evaluate j{::fs
    row=.(<value)(j{indexes)}row
   end.
   fresh=.fresh,<row
  end.
  modified=.cols;types;nn;pk;<fresh
  modified constraint (#rows)+i.#checked
  DbTables=:(<modified)ti}DbTables
  ,<'inserted'countline #checked return.
 end.
 addscope t;<table
 if. cmd-:'UPDATE' do.
  assigns=.2{::y
  where=.3{::y
  indexes=.i.0
  for_assignment. assigns do.
   c=.0{::>assignment
   i=.cols i.<c
   if. i=#cols do. fail 'unknown column ',c end.
   if. i e.indexes do. fail 'duplicate column ',c end.
   indexes=.indexes,i
  end.
  checked=.0$a:
  for_j. i.#assigns do.
   e=.check 1{::j{::assigns
   i=.j{indexes
   if. -.Type compatible i{types do. fail 'type mismatch for column ',i{::cols end.
   checked=.checked,<e
  end.
 else. where=.2{::y end.
 if. -.where-:a: do. where=.<'WHERE'condition >where end.
 target=.i.0
 for_i. i.#rows do.
  take=.1
  if. -.where-:a: do. take=.1=truth (i{::rows)evaluate >where end.
  if. take do. target=.target,i end.
 end.
 if. cmd-:'DELETE' do.
  fresh=.((i.#rows)-.target){rows
  modified=.cols;types;nn;pk;<fresh
  DbTables=:(<modified)ti}DbTables
  ,<'deleted'countline #target
 else.
  fresh=.rows
  for_i. target do.
   old=.i{::rows
   row=.old
   for_j. i.#indexes do.
    v=.old evaluate j{::checked
    row=.(<v)(j{indexes)}row
   end.
   fresh=.(<row)i}fresh
  end.
  modified=.cols;types;nn;pk;<fresh
  modified constraint target
  DbTables=:(<modified)ti}DbTables
  ,<'updated'countline #target
 end.
)
main=:3 : 0
 input=.1!:1&3''
 statement=.''
 quoted=.0
 comment=.0
 i=.0
 while. i<#input do.
  c=.i{input
  if. comment do.
   if. c=LF do. comment=.0
    statement=.statement,LF
   end.
   i=.i+1
   continue.
  end.
  if. -.quoted do.
   if. '--'-:2{.i}.input do. comment=.1
    i=.i+2
    continue.
   end.
  end.
  statement=.statement,c
  if. c=SQ do. quoted=.-.quoted end.
  if. (c=';')*.-.quoted do.
   try. ast=.parse statement
    out=.execute ast
   catcht. out=.,<'ERROR: ',Error end.
   for_s. out do. 1!:2&2 (>s),LF end.
   statement=.''
  end.
  i=.i+1
 end.
)
main''
