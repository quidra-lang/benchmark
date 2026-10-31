LF=:10{a.
say=:3 : '1!:2&2 y,LF'
num=:3 : ',''0'' 8!:2 y'
trimleft=:3 : '(+/ *./\ y='' '')}.y'
trimright=:3 : '|.trimleft |.y'
syntax=:3 : 0
 throw.
)
letters=:'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
digits=:'0123456789'
words=:3 : '(<;._1 '' '',y)-.<'''''
Functions=:words 'ABS SGN INT SQR RND LEN ASC VAL CHR$ STR$ LEFT$ RIGHT$ MID$ INSTR'
variable=:3 : 0
 s=.y
 if. 0=#s do. 0 return. end.
 if. '$'={:s do. s=.}:s end.
 if. -. (#s)e.1 2 do. 0 return. end.
 if. -.({.s)e.letters do. 0 return. end.
 if. 2=#s do. ({:s)e.digits else. 1 end.
)
tokenize=:3 : 0
 ts=.0$a:
 i=.0
 while. i<#y do.
  ch=.i{y
  if. ch=' ' do. i=.>:i continue. end.
  if. ch='"' do.
   j=.>:i
   while. j<#y do. if. '"'=j{y do. break. end.
    j=.>:j
   end.
   if. j=#y do. syntax 0 end.
   ts=.ts,<1;((>:i)}.j{.y)
   i=.>:j
  elseif. ch e.digits do.
   j=.i
   while. j<#y do. if. -.(j{y)e.digits do. break. end.
    j=.>:j
   end.
   v=.0".i}.j{.y
   if. v>32767 do. syntax 0 end.
   ts=.ts,<0;v
   i=.j
  elseif. ch e.letters do.
   if. 'REM'-:3{.i}.y do. ts=.ts,<2;'REM' break. end.
   j=.i
   while. j<#y do. if. -.(j{y)e.letters,digits do. break. end.
    j=.>:j
   end.
   if. j<#y do. if. '$'=j{y do. j=.>:j end. end.
   ts=.ts,<2;(i}.j{.y)
   i=.j
  else.
   two=.2{.i}.y
   if. (<two)e.'<>';'<=';'>=' do.
    ts=.ts,<2;two
    i=.i+2
   else.
    if. -.ch e.'+-*/^=<>() ,;:' do. syntax 0 end.
    ts=.ts,<2;,ch
    i=.>:i
   end.
  end.
 end.
 ts
)
peek=:3 : 0
 if. Pos=#Tokens do. '' return. end.
 'kind val'=.Pos{::Tokens
 if. kind=0 do. '#number' elseif. kind=1 do. '#string' else. val end.
)
consume=:3 : 0
 t=.Pos{::Tokens
 Pos=:>:Pos
 t
)
expect=:3 : 0
 if. -.y-:peek 0 do. syntax 0 end.
 Pos=:>:Pos
)
constant=:3 : 0
 if. Pos=#Tokens do. syntax 0 end.
 'kind value'=.consume 0
 if. kind~:0 do. syntax 0 end.
 value
)
node=:3 : 0
 'typ tag args'=.y
 typ;tag;<args
)
needint=:3 : 0
 if. 0~:0{::y do. syntax 0 end.
 y
)
readargs=:3 : 0
 expect '('
 args=.,<expression 0
 while. ','-:peek 0 do.
  expect ','
  args=.args,<expression 0
 end.
 expect ')'
 args
)
reference=:3 : 0
 name=.peek 0
 if. -.variable name do. syntax 0 end.
 Pos=:>:Pos
 typ=.'$'={:name
 if. '('-:peek 0 do.
  args=.readargs 0
  if. -. (#args)e.1 2 do. syntax 0 end.
  for_e. args do. needint >e end.
  typ;'ARRAY';<(name;<args)
 else.
  typ;'VAR';<,<name
 end.
)
primary=:3 : 0
 t=.peek 0
 if. '#number'-:t do.
  v=.1{::consume 0
  0;'NUM';<,<v return.
 elseif. '#string'-:t do.
  v=.1{::consume 0
  1;'STR';<,<v return.
 elseif. '('-:t do.
  expect '('
  r=.expression 0
  expect ')'
  r return.
 elseif. (<t)e.'ERR';'ERL' do.
  Pos=:>:Pos
  0;t;<0$a: return.
 elseif. variable t do. reference 0 return.
 elseif. (<t)e.Functions do.
  Pos=:>:Pos
  args=.readargs 0
  types=.i.0
  for_e. args do. types=.types,0{::>e end.
  fn=.Functions i.<t
  valid=.0
  select. fn
  case. 0;1;2;3;4;8;9 do. valid=.types-:,0
  case. 5;6;7 do. valid=.types-:,1
  case. 10;11 do. valid=.types-:1 0
  case. 12 do. valid=.(types-:1 0)+.types-:1 0 0
  case. 13 do. valid=.types-:1 1
  end.
  if. -.valid do. syntax 0 end.
  (fn e.8 9 10 11 12);'CALL';<(t;<args) return.
 end.
 syntax 0
)
unary=:3 : 0
 if. '-'-:peek 0 do.
  expect '-'
  a=.needint unary 0
  0;'UNARY';<('-';<a) return.
 end.
 a=.primary 0
 if. '^'-:peek 0 do.
  expect '^'
  b=.needint unary 0
  needint a
  0;'BINARY';<('^';a;<b)
 else. a end.
)
product=:3 : 0
 a=.unary 0
 while. (<peek 0)e.'*';'/';'MOD' do.
  op=.peek 0
  Pos=:>:Pos
  b=.needint unary 0
  needint a
  a=.0;'BINARY';<(op;a;<b)
 end.
 a
)
sumexpr=:3 : 0
 a=.product 0
 while. (<peek 0)e.'+';'-' do.
  op=.peek 0
  Pos=:>:Pos
  b=.product 0
  if. (0{::a)~:0{::b do. syntax 0 end.
  if. '-'-:op do. needint a end.
  a=.(0{::a);'BINARY';<(op;a;<b)
 end.
 a
)
comparison=:3 : 0
 a=.sumexpr 0
 while. (<peek 0)e.'=';'<>';'<' ;'>';'<=';'>=' do.
  op=.peek 0
  Pos=:>:Pos
  b=.sumexpr 0
  if. (0{::a)~:0{::b do. syntax 0 end.
  a=.0;'BINARY';<(op;a;<b)
 end.
 a
)
negation=:3 : 0
 if. 'NOT'-:peek 0 do.
  expect 'NOT'
  a=.needint negation 0
  0;'UNARY';<('NOT';<a)
 else. comparison 0 end.
)
conjunction=:3 : 0
 a=.negation 0
 while. 'AND'-:peek 0 do.
  expect 'AND'
  b=.needint negation 0
  needint a
  a=.0;'BINARY';<('AND';a;<b)
 end.
 a
)
expression=:3 : 0
 a=.conjunction 0
 while. 'OR'-:peek 0 do.
  expect 'OR'
  b=.needint conjunction 0
  needint a
  a=.0;'BINARY';<('OR';a;<b)
 end.
 a
)
stmt=:4 : 'x;y;LineNumber'
clause=:3 : 0
 if. '#number'-:peek 0 do.
  n=.constant 0
  if. -. (<peek 0)e.'';'ELSE' do. syntax 0 end.
  1;n return.
 end.
 list=.,<1 statement 0
 while. ':'-:peek 0 do.
  expect ':'
  list=.list,<1 statement 0
 end.
 2;<list
)
statement=:4 : 0
 inclause=.x
 tag=.peek 0
 if. inclause*.(<tag)e.'IF';'FOR';'NEXT';'WHILE';'WEND';'DATA' do. syntax 0 end.
 if. variable tag do. tag=.'LET' else. Pos=:>:Pos end.
 args=.0$a:
 select. tag
 case. 'REM';'RETURN';'WEND';'END';'STOP' do.
 case. 'LET' do.
  target=.reference 0
  expect '='
  value=.expression 0
  if. (0{::target)~:0{::value do. syntax 0 end.
  args=.target;<value
 case. 'PRINT' do.
  adjacent=.0
  while. -. (<peek 0)e.'';':';'ELSE' do.
   token=.peek 0
   if. (<token)e.';';',' do.
    Pos=:>:Pos
    args=.args,<token;<0$a:
    adjacent=.0
   elseif. (<token)e.'TAB';'SPC' do.
    Pos=:>:Pos
    expect '('
    value=.needint expression 0
    expect ')'
    args=.args,<token;<value
    adjacent=.0
   else.
    if. adjacent do. syntax 0 end.
    value=.expression 0
    args=.args,<'VALUE';<value
    adjacent=.1
   end.
  end.
 case. 'INPUT';'READ' do.
  args=.,<reference 0
  while. ','-:peek 0 do.
   expect ','
   args=.args,<reference 0
  end.
 case. 'DATA' do.
  while. 1 do.
   sign=.1
   if. '-'-:peek 0 do. expect '-' [ sign=._1 end.
   token=.peek 0
   if. '#number'-:token do. item=.<sign*constant 0
   elseif. (sign=1)*.'#string'-:token do. item=.<1{::consume 0
   else. syntax 0 end.
   args=.args,item
   if. -.','-:peek 0 do. break. end.
   expect ','
  end.
 case. 'IF' do.
  cond=.needint expression 0
  expect 'THEN'
  yes=.clause 0
  no=.0;0
  if. 'ELSE'-:peek 0 do.
   expect 'ELSE'
   no=.clause 0
  end.
  if. #peek 0 do. syntax 0 end.
  args=.cond;yes;<no
 case. 'GOTO';'GOSUB' do. args=.,<constant 0
 case. 'ON' do.
  if. 'ERROR'-:peek 0 do.
   expect 'ERROR'
   expect 'GOTO'
   tag=.'HANDLER'
   args=.,<constant 0
  else.
   cond=.needint expression 0
   which=.peek 0
   if. -.(<which)e.'GOTO';'GOSUB' do. syntax 0 end.
   Pos=:>:Pos
   targets=.,constant 0
   while. ','-:peek 0 do.
    expect ','
    targets=.targets,constant 0
   end.
   args=.cond;which;targets
  end.
 case. 'RESUME' do.
  mode=.0
  target=.0
  if. 'NEXT'-:peek 0 do. expect 'NEXT' [ mode=.1
  elseif. '#number'-:peek 0 do. target=.constant 0 [ mode=.2 end.
  args=.mode;target
 case. 'FOR' do.
  name=.peek 0
  if. -.variable name do. syntax 0 end.
  if. '$'={:name do. syntax 0 end.
  Pos=:>:Pos
  expect '='
  first=.needint expression 0
  expect 'TO'
  last=.needint expression 0
  step=.0;'NUM';<,<1
  if. 'STEP'-:peek 0 do.
   expect 'STEP'
   step=.needint expression 0
  end.
  args=.name;first;last;<step
 case. 'NEXT' do.
  name=.''
  if. variable peek 0 do.
   name=.peek 0
   if. '$'={:name do. syntax 0 end.
   Pos=:>:Pos
  end.
  args=.,<name
 case. 'WHILE';'RANDOMIZE' do. args=.,<needint expression 0
 case. 'DIM' do.
  while. 1 do.
   ref=.reference 0
   if. -.'ARRAY'-:1{::ref do. syntax 0 end.
   args=.args,<ref
   if. -.','-:peek 0 do. break. end.
   expect ','
  end.
 case. 'RESTORE' do.
  if. '#number'-:peek 0 do. args=.,<constant 0 end.
 case. do. syntax 0
 end.
 if. -. (<peek 0)e.'';':';'ELSE' do. syntax 0 end.
 tag stmt args
)
parse=:3 : 0
 Tokens=:tokenize y
 Pos=:0
 result=.,<0 statement 0
 while. ':'-:peek 0 do.
  expect ':'
  result=.result,<0 statement 0
 end.
 if. Pos~:#Tokens do. syntax 0 end.
 result
)
compilelist=:4 : 0
 continuation=.x
 for_s. |.y do. continuation=.continuation compile >s end.
 continuation
)
compile=:4 : 0
 'tag args line'=.y
 id=.#Nodes
 Nodes=:Nodes,<y
 Next=:Next,x
 if. 'IF'-:tag do.
  'cond yes no'=.args
  if. 2=0{::yes do. yes=.2;x compilelist 1{::yes end.
  if. 2=0{::no do. no=.2;x compilelist 1{::no end.
  Nodes=.(<tag;(cond;yes;<no);line)id}Nodes
 end.
 id
)
ErrorCodes=:1 3 4 5 6 7 8 9 10 11 13 15 20 26 29 30 62
ErrorMessages=:'NEXT WITHOUT FOR';'RETURN WITHOUT GOSUB';'OUT OF DATA';'ILLEGAL FUNCTION CALL';'OVERFLOW';'OUT OF MEMORY';'UNDEFINED LINE NUMBER';'SUBSCRIPT OUT OF RANGE';'DUPLICATE DEFINITION';'DIVISION BY ZERO';'TYPE MISMATCH';'STRING TOO LONG';'RESUME WITHOUT ERROR';'FOR WITHOUT NEXT';'WHILE WITHOUT WEND';'WEND WITHOUT WHILE';'INPUT PAST END'
error=:3 : 0
 Error=:y
 throw.
)
checked=:3 : 0
 if. (y<_32768)+.y>32767 do. error 6 end.
 y
)
endline=:3 : 0
 say trimright Output
 Output=:''
)
message=:3 : 0
 if. #Output do. endline 0 end.
 say y
)
varindex=:3 : 0
 i=.VariableNames i.<y
 if. i=#VariableNames do.
  VariableNames=:VariableNames,<y
  default=.0
  if. '$'={:y do. default=.'' end.
  VariableValues=:VariableValues,<default
 end.
 i
)
newarray=:4 : 0
 name=.x
 bounds=.y
 default=.0
 if. '$'={:name do. default=.'' end.
 ArrayNames=:ArrayNames,<name
 ArrayBounds=:ArrayBounds,<bounds
 ArrayValues=:ArrayValues,<(*/>:bounds)#<default
)
location=:3 : 0
 'typ tag args'=.y
 name=.0{::args
 if. 'VAR'-:tag do. 0;(varindex name);0 return. end.
 subs=.i.0
 for_e. 1{::args do. subs=.subs,evaluate >e end.
 index=.ArrayNames i.<name
 if. index=#ArrayNames do. name newarray (#subs)#10 end.
 bounds=.index{::ArrayBounds
 if. (#subs)~:#bounds do. error 9 end.
 if. (+./subs<0)+.+./subs>bounds do. error 9 end.
 offset=.{.subs
 if. 2=#subs do. offset=.({:subs)+({.subs)*>:1{bounds end.
 1;index;offset
)
readlocation=:3 : 0
 'array index offset'=.y
 if. array do. offset{::index{::ArrayValues else. index{::VariableValues end.
)
assign=:4 : 0
 'array index offset'=.x
 if. array do.
  values=.index{::ArrayValues
  values=.(<y)offset}values
  ArrayValues=:(<values)index}ArrayValues
 else. VariableValues=:(<y)index}VariableValues end.
)
lexcompare=:4 : 0
 if. x-:y do. 0 return. end.
 if. 0={./:x;y do. _1 else. 1 end.
)
function=:4 : 0
 fn=.Functions i.<x
 a=.0{::y
 select. fn
 case. 0 do. checked |a
 case. 1 do. *a
 case. 2 do. a
 case. 3 do. if. a<0 do. error 5 end.
  <.%:a
 case. 4 do.
  if. a<1 do. error 5 end.
  Random=:2147483647|48271*Random
  1+a|Random
 case. 5 do. #a
 case. 6 do. if. 0=#a do. error 5 end.
  a.i.{.a
 case. 7 do.
  s=.trimleft a
  sign=.1
  if. #s do.
   if. ({.s)e.'+-' do.
    if. '-'={.s do. sign=._1 end.
    s=.}.s
   end.
  end.
  n=.+/ *./\ s e.digits
  if. n=0 do. 0 else. checked sign*0".n{.s end.
 case. 8 do. if. (a<32)+.a>126 do. error 5 end.
  ,a{a.
 case. 9 do. num a
 case. 10;11 do.
  n=.1{::y
  if. n<0 do. error 5 end.
  n=.n<.#a
  if. fn=10 do. n{.a else. (-n){.a end.
 case. 12 do.
  p=.1{::y
  if. p<1 do. error 5 end.
  s=.(p-1)}.a
  if. 3=#y do.
   n=.2{::y
   if. n<0 do. error 5 end.
   s=.(n<.#s){.s
  end.
  s
 case. 13 do.
  needle=.1{::y
  if. 0=#needle do. 1 return. end.
  matches=.I.needle E.a
  if. #matches do. >:{.matches else. 0 end.
 end.
)
evaluate=:3 : 0
 'typ tag args'=.y
 select. tag
 case. 'NUM';'STR' do. 0{::args
 case. 'VAR';'ARRAY' do. readlocation location y
 case. 'ERR' do. Err
 case. 'ERL' do. Erl
 case. 'CALL' do.
  vals=.0$a:
  for_a. 1{::args do. vals=.vals,<evaluate >a end.
  (0{::args)function vals
 case. 'UNARY' do.
  a=.evaluate 1{::args
  if. '-'-:0{::args do. checked -a else. _1-a end.
 case. 'BINARY' do.
  'op left right'=.args
  a=.evaluate left
  b=.evaluate right
  if. (<op)e.'=';'<>';'<' ;'>';'<=';'>=' do.
   if. 0=0{::left do. cmp=.*a-b else. cmp=.a lexcompare b end.
   select. op
   case. '=' do. -(cmp=0)
   case. '<>' do. -(cmp~:0)
   case. '<' do. -(cmp<0)
   case. '>' do. -(cmp>0)
   case. '<=' do. -(cmp<:0)
   case. '>=' do. -(cmp>:0)
   end.
  elseif. typ=1 do.
   r=.a,b
   if. 255<#r do. error 15 end.
   r
  else.
   select. op
   case. '+' do. checked a+b
   case. '-' do. checked a-b
   case. '*' do. checked a*b
   case. '/';'MOD' do.
    if. b=0 do. error 11 end.
    q=.(*a*b)*<.(|a)%|b
    if. '/'-:op do. checked q else. a-b*q end.
   case. '^' do.
    if. b<0 do. error 5 end.
    if. b=0 do. 1 elseif. a=0 do. 0 elseif. a=1 do. 1 elseif. a=_1 do. 1-2*2|b
    else.
     if. b>15 do. error 6 end.
     checked a^b
    end.
   case. 'AND';'OR' do.
    ab=.(16#2)#:65536|a
    bb=.(16#2)#:65536|b
    if. 'AND'-:op do. r=.#.ab*.bb else. r=.#.ab+.bb end.
    r-65536*r>:32768
   end.
  end.
 end.
)
lineposition=:3 : 0
 i=.LineNumbers i.y
 if. i=#LineNumbers do. error 8 end.
 i{FirstPositions
)
push=:3 : 0
 if. 100=#Stack do. error 7 end.
 Stack=:Stack,<y
)
stackfind=:4 : 0
 tag=.x
 name=.y
 for_i. |.i.#Stack do.
  frame=.i{::Stack
  kind=.0{::frame
  if. tag-:kind do.
   if. 'FOR'-:tag do.
    if. #name do. if. -.name-:1{::frame do. continue. end. end.
   end.
   i return.
  end.
  if. ('GOSUB'-:kind)*.-.'GOSUB'-:tag do. break. end.
 end.
 _1
)
matching=:4 : 0
 'opening closing'=.x
 at=.Sequence i.y
 depth=.0
 for_id. (>:at)}.Sequence do.
  tag=.0{::id{::Nodes
  if. opening-:tag do. depth=.>:depth
  elseif. closing-:tag do.
   if. depth=0 do. id return. end.
   depth=.<:depth
  end.
 end.
 _1
)
execute=:3 : 0
 id=.y
 'tag args line'=.id{::Nodes
 following=.id{Next
 Pc=:following
 select. tag
 case. 'REM';'DATA' do.
 case. 'LET' do.
  loc=.location 0{::args
  value=.evaluate 1{::args
  loc assign value
 case. 'PRINT' do.
  last=.''
  for_item. args do.
   'kind value'=.>item
   last=.kind
   select. kind
   case. ';' do.
   case. ',' do. Output=:Output,(10-10|#Output)#' '
   case. 'TAB';'SPC' do.
    n=.evaluate value
    if. n<0 do. error 5 end.
    if. 'TAB'-:kind do. n=.0>.n-#Output end.
    Output=:Output,n#' '
   case. 'VALUE' do.
    v=.evaluate value
    if. 0=0{::value do. v=.num v end.
    Output=:Output,v
   end.
  end.
  if. -.(<last)e.';';',' do. endline 0 end.
 case. 'INPUT';'READ' do.
  for_target. args do.
   target=.>target
   typ=.0{::target
   loc=.location target
   if. 'READ'-:tag do.
    if. ReadAt=#DataValues do. error 4 end.
    value=.ReadAt{::DataValues
    ReadAt=:>:ReadAt
    if. typ~:2=3!:0 value do. error 13 end.
   else.
    while. 1 do.
     if. InputAt=#InputLines do. error 62 end.
     value=.InputAt{::InputLines
     InputAt=:>:InputAt
     if. typ=1 do. break. end.
     s=.value
     sign=.1
     if. #s do. if. '-'={.s do. sign=._1 [ s=.}.s end. end.
     valid=.(0<#s)*.*./s e.digits
     if. valid do.
      v=.sign*0".s
      valid=.(v>:_32768)*.v<:32767
     end.
     if. valid do. value=.v break. end.
     message '?REDO FROM START'
    end.
   end.
   loc assign value
  end.
 case. 'IF' do.
  value=.evaluate 0{::args
  chosen=.(1+value=0){::args
  'kind payload'=.chosen
  if. kind=1 do. Pc=:lineposition payload elseif. kind=2 do. Pc=:payload end.
 case. 'GOTO';'GOSUB' do.
  dest=.lineposition 0{::args
  if. 'GOSUB'-:tag do. push 'GOSUB';following end.
  Pc=:dest
 case. 'ON' do.
  'cond mode targets'=.args
  index=.evaluate cond
  if. index<0 do. error 5 end.
  if. (index>0)*.index<:#targets do.
   dest=.lineposition (index-1){targets
   if. 'GOSUB'-:mode do. push 'GOSUB';following end.
   Pc=:dest
  end.
 case. 'RETURN' do.
  i=.'GOSUB'stackfind ''
  if. i<0 do. error 3 end.
  Pc=:1{::i{::Stack
  Stack=:i{.Stack
 case. 'FOR' do.
  'name first last increment'=.args
  a=.evaluate first
  b=.evaluate last
  step=.evaluate increment
  if. step=0 do. error 5 end.
  i=.'FOR'stackfind name
  if. i>:0 do. Stack=:i{.Stack end.
  vi=.varindex name
  VariableValues=:(<a)vi}VariableValues
  if. ((step>0)*.a>b)+.((step<0)*.a<b) do.
   next=.('FOR';'NEXT')matching id
   if. next<0 do. error 26 end.
   Pc=:next{Next
  else. push 'FOR';name;b;step;following end.
 case. 'NEXT' do.
  i=.'FOR'stackfind 0{::args
  if. i<0 do. error 1 end.
  Stack=:(>:i){.Stack
  'kind name last step start'=.i{::Stack
  vi=.varindex name
  value=.checked step+vi{::VariableValues
  VariableValues=:(<value)vi}VariableValues
  if. ((step>0)*.value>last)+.((step<0)*.value<last) do. Stack=:}:Stack else. Pc=:start end.
 case. 'WHILE' do.
  value=.evaluate 0{::args
  if. value do. push 'WHILE';id else.
   next=.('WHILE';'WEND')matching id
   if. next<0 do. error 29 end.
   Pc=:next{Next
  end.
 case. 'WEND' do.
  i=.'WHILE'stackfind ''
  if. i<0 do. error 30 end.
  Pc=:1{::i{::Stack
  Stack=:i{.Stack
 case. 'DIM' do.
  for_ref. args do.
   'typ kind values'=.>ref
   'name exprs'=.values
   bounds=.i.0
   for_e. exprs do. bounds=.bounds,evaluate >e end.
   if. (<name)e.ArrayNames do. error 10 end.
   if. +./bounds<0 do. error 5 end.
   if. 10000<*/>:bounds do. error 7 end.
   name newarray bounds
  end.
 case. 'RESTORE' do.
  if. 0=#args do. ReadAt=:0 else.
   n=.0{::args
   lineposition n
   ReadAt=:+/DataLines<n
  end.
 case. 'RANDOMIZE' do.
  n=.evaluate 0{::args
  if. n<1 do. error 5 end.
  Random=:n
 case. 'HANDLER' do.
  n=.0{::args
  if. n do. lineposition n end.
  Handler=:n
 case. 'RESUME' do.
  if. -.Handling do. error 20 end.
  'mode target'=.args
  select. mode
  case. 0 do. dest=.ErrorPosition
  case. 1 do. dest=.ErrorPosition{Next
  case. 2 do. dest=.lineposition target
  end.
  Handling=:0
  Pc=:dest
 case. 'END' do. Pc=:_1
 case. 'STOP' do. message 'BREAK IN LINE ',num line [ Pc=:_1
 end.
)
runprogram=:3 : 0
 Output=:''
 top=.0$a:
 for_i. i.#LineNumbers do.
  LineNumber=:i{LineNumbers
  try. parsed=.parse i{::Source
  catcht.
   message 'ERROR IN LINE ',(num LineNumber),': SYNTAX ERROR'
   say 'READY'
   return.
  end.
  top=.top,parsed
 end.
 Nodes=:0$a:
 Next=:Sequence=:i.0
 continuation=._1
 for_s. |.top do.
  continuation=.continuation compile >s
  Sequence=:continuation,Sequence
 end.
 FirstPositions=:i.0
 for_line. LineNumbers do.
  for_id. Sequence do.
   if. line=2{::id{::Nodes do. FirstPositions=:FirstPositions,id break. end.
  end.
 end.
 VariableNames=:VariableValues=:ArrayNames=:ArrayBounds=:ArrayValues=:Stack=:0$a:
 DataValues=:0$a:
 DataLines=:i.0
 for_s. top do.
  'tag args line'=.>s
  if. 'DATA'-:tag do.
   DataValues=:DataValues,args
   DataLines=:DataLines,(#args)#line
  end.
 end.
 ReadAt=:InputAt=:Handler=:Handling=:Err=:Erl=:0
 Random=:1
 Pc=:continuation
 while. Pc>:0 do.
  id=.Pc
  try. execute id
  catcht.
   line=.2{::id{::Nodes
   if. (Handler~:0)*.-.Handling do.
    Err=:Error
    Erl=:line
    Handling=:1
    ErrorPosition=:id
    Pc=:lineposition Handler
   else.
    message 'ERROR IN LINE ',(num line),': ',(ErrorCodes i.Error){::ErrorMessages
    Pc=:_1
   end.
  end.
 end.
 if. #Output do. endline 0 end.
 say 'READY'
)
main=:3 : 0
 lines=.<;._2 (1!:1&3''),LF
 programs=.0".0{::lines
 cursor=.1
 for_program. i.programs do.
  LineNumbers=:i.0
  Source=:0$a:
  while. -.'RUN'-:cursor{::lines do.
   line=.cursor{::lines
   cursor=.>:cursor
   cut=.line i.' '
   n=.0".cut{.line
   index=.LineNumbers i.n
   if. cut=#line do.
    if. index<#LineNumbers do.
     LineNumbers=:((i.#LineNumbers)-.index){LineNumbers
     Source=:((i.#Source)-.index){Source
    end.
   else.
    text=.trimleft cut}.line
    if. index=#LineNumbers do. LineNumbers=:LineNumbers,n [ Source=:Source,<text
    else. Source=:(<text)index}Source end.
   end.
  end.
  order=./:LineNumbers
  LineNumbers=:order{LineNumbers
  Source=:order{Source
  cursor=.>:cursor
  InputLines=:0$a:
  while. -.'END'-:cursor{::lines do.
   InputLines=:InputLines,cursor{lines
   cursor=.>:cursor
  end.
  cursor=.>:cursor
  runprogram 0
 end.
)
main''
