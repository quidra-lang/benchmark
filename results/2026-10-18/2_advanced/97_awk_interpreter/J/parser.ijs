node=:4 :0
 t=.cocreate''
 kind__t=:x
  children__t=:y
  value__t=:''
  line__t=:line__LastToken
  column__t=:column__LastToken
 scope__t=:Scope
  lvalue__t=:0
  redirect__t=:a:
  redirop__t=:''
 t
)
peek=:3 :0
 t=.Position{Tokens
 if. kind__t-:'string' do. 'STRING' elseif. kind__t-:'number' do. 'NUMBER' else. value__t end.
)
current=:3 : 'Position{Tokens'
consume=:3 :0
 t=.current''
 LastToken=:t
  Position=:Position+1
 t
)
fail=:3 :0
 t=.y
 syntax_error line__t,column__t
)
expect=:3 :0
 t=.consume''
  if. ((<kind__t)e.'string';'number')+.-.value__t-:y do. fail t end.
 t
)
skipnl=:3 : 'while.''NL''-:peek''''do.consume''''end.'
parse_args=:3 :0
 result=.0$a:
  if. ')'-:peek'' do. result  return.  end.
  while. 1 do.
  result=.result,parse_expr''
   if. -.','-:peek'' do.  break.  end.
  consume''
  skipnl''
  end.
 result
)
parse_name=:3 :0
 t=.consume''
  if. -.kind__t-:'name' do. fail t  end.
 n=.'var'node 0$a:
 value__n=:value__t
  lvalue__n=:1
 n
)
parse_atom=:3 :0
 t=.consume''
  pos=.t
  value=.value__t
  select. kind__t
  case. 'number' do. n=.'number'node 0$a:
  value__n=:0".value
  case. 'string' do. n=.'string'node 0$a:
  value__n=:value
  case. 'name' do.
  n=.'var'node 0$a:
  value__n=:value
  lvalue__n=:1
   if. '['-:peek'' do.
   consume''
  ExprDepth=:ExprDepth+1
   es=.parse_args''
   expect ']'
  ExprDepth=:ExprDepth-1
   kind__n=:'array'
  children__n=:es
   end.
  case. 'function';'builtin' do.
  args=.0$a:
   if. '('-:peek'' do. consume''
  ExprDepth=:ExprDepth+1
  args=.parse_args''
  expect ')'
  ExprDepth=:ExprDepth-1
   elseif. -.(kind__t-:'builtin')*.value-:'length' do. fail current'' end.
  n=.'call'node args
  value__n=:value
   if. kind__t-:'builtin' do.
   kind__n=:'builtin'
   count=.#args
    select. value
    case. 'length' do. valid=.count e.0 1
    case. 'substr';'split' do. valid=.count e.2 3
    case. 'index' do. valid=.count=2
    case. 'sprintf' do. valid=.count>:1
    case.  do. valid=.count=1
    end.
    if. (value-:'split')*.valid  do. a=.1{args
  valid=.(kind__a-:'var')*.lvalue__a  end.
    if. -.valid  do. fail pos  end.
   end.
  case.  do.
   select. value
   case. '(' do.
   ExprDepth=:ExprDepth+1
  es=.parse_args''
  expect ')'
  ExprDepth=:ExprDepth-1
    if. 1=#es  do. n=.'paren'node es
    elseif. 1<#es  do. expect 'in'
  a=.parse_name''
  n=.'in'node es
  value__n=:value__a
    else. fail current'' end.
   case. '$' do.
    if. (<peek'')e.'++';'--' do. e=.parse_postfix'' else. e=.parse_atom'' end.
   n=.'field'node ,e
  lvalue__n=:1
   case. 'getline' do.
   target=.a:
  source=.a:
  next=.current''
    if. (kind__next-:'name')+.value__next-:'$' do. target=.parse_atom'' end.
    if. '<'-:peek'' do. consume''
  source=.parse_atom'' end.
   n=.'getline'node 0$a:
  target__n=:target
  source__n=:source
   case.  do. fail t
   end.
  end.
 line__n=:line__pos
  column__n=:column__pos
 n
)
parse_postfix=:3 :0
  if. (<peek'')e.'++';'--' do.
  t=.consume''
  n=.parse_atom''
   if. -.lvalue__n  do. fail current'' end.
  r=.'preinc'node ,n
  value__r=:value__t
  line__r=:line__t
  column__r=:column__t
  r
  else.
  n=.parse_atom''
   if. lvalue__n*.(<peek'')e.'++';'--' do. t=.consume''
  r=.'postinc'node ,n
  value__r=:value__t
  n=.r  end.
  n
  end.
)
parse_unary=:3 :0
  if. (<peek'')e.'!';'-';'+' do.
  t=.consume''
  op=.value__t
  pos=.t
  n=.'unary'node ,parse_unary''
  value__n=:op
  line__n=:line__pos
  column__n=:column__pos
  n
  else.
  n=.parse_postfix''
   if. '^'-:peek'' do. t=.consume''
  pos=.t
  r=.'binary'node n,parse_unary''
  value__r=:'^'
  line__r=:line__pos
  column__r=:column__pos
  n=.r  end.
  n
  end.
)
BinaryLevels=:('||';'&&';'in'),(<(<;._1 ' ','< <= == != >= >')),(<'concat'),(<(<;._1 ' ','+ -')),<(<;._1 ' ','* / %')
concat_starts=:3 :0
 t=.current''
 ((<kind__t)e.(<;._1 ' ','number string name function builtin'))+.(<value__t)e.'$';'(';'++';'--'
)
parse_level=:3 :0
 level=.y
  if. level=7 do. parse_unary'' return.  end.
 left=.parse_level level+1
 ops=.level{::BinaryLevels
  if. 2=3!:0 ops  do. ops=.,<ops  end.
  while. 1 do.
  op=.peek''
   if. level=4 do.
    if. -.concat_starts'' do.  break.  end.
   pos=.current''
  right=.parse_level level+1
  op=.'concat'
   else.
    if. -.(<op)e.ops  do.  break.  end.
    if. (op-:'>')*.OutputMode*.ExprDepth=0 do.  break.  end.
   pos=.consume''
    if. (<op)e.'||';'&&' do. skipnl'' end.
    if. op-:'in' do.
    name=.parse_name''
    n=.'in'node ,left
  value__n=:value__name
  left=.n
   continue.
    end.
   right=.parse_level level+1
   end.
  n=.'binary'node left,right
  value__n=:op
  line__n=:line__pos
  column__n=:column__pos
  left=.n
  end.
 left
)
parse_cond=:3 :0
 n=.parse_level 0
  if. '?'-:peek'' do. consume''
  a=.parse_cond''
  expect ':'
  b=.parse_cond''
  n=.'conditional'node n,a,b  end.
 n
)
parse_expr=:3 :0
 n=.parse_cond''
  if. lvalue__n*.(<peek'')e.(<;._1 ' ','= += -= *= /= %= ^=') do.
  t=.consume''
  op=.value__t
  pos=.t
  r=.'assign'node n,parse_expr''
  value__r=:op
  line__r=:line__pos
  column__r=:column__pos
  n=.r
  end.
 n
)
terminator=:3 :0
  if. (<peek'')e.';';'NL' do. consume'' elseif. -.'}'-:peek'' do. fail current'' end.
)
parse_block=:3 :0
 pos=.expect '{'
  statements=.0$a:
  while. -.'}'-:peek'' do.
   if. (<peek'')e.'NL';';' do. consume'' else. statements=.statements,parse_statement'' end.
  end.
 expect '}'
 n=.'block'node statements
  line__n=:line__pos
  column__n=:column__pos
 n
)
parse_statement=:3 :0
 first=.current''
  keyword=.peek''
  if. keyword-:'{' do. parse_block'' return.  end.
  if. keyword-:';' do. consume''
  'empty'node 0$a: return.  end.
 consume''
  select. keyword
  case. 'if' do.
  expect '('
  c=.parse_expr''
  expect ')'
  skipnl''
  a=.parse_statement''
  skipnl''
  es=.c,a
   if. 'else'-:peek'' do. consume''
  skipnl''
  es=.es,parse_statement'' end.
  n=.'if'node es
  case. 'while' do.
  expect '('
  c=.parse_expr''
  expect ')'
  skipnl''
  LoopDepth=:LoopDepth+1
  body=.parse_statement''
  LoopDepth=:LoopDepth-1
  n=.'while'node c,body
  case. 'do' do.
  skipnl''
  LoopDepth=:LoopDepth+1
  body=.parse_statement''
  LoopDepth=:LoopDepth-1
  skipnl''
  expect 'while'
  expect '('
  c=.parse_expr''
  expect ')'
  terminator''
  n=.'do'node body,c
  case. 'for' do.
  expect '('
  p=.Position
  pattern=.0
   if. p+3<#Tokens  do. t0=.p{Tokens
  t1=.(p+1){Tokens
  t2=.(p+2){Tokens
  t3=.(p+3){Tokens
   pattern=.(kind__t0-:'name')*.(value__t1-:'in')*.(kind__t2-:'name')*.value__t3-:')'
   end.
   if. pattern  do. v=.parse_name''
  expect 'in'
  arr=.parse_name''
  expect ')'
  skipnl''
  es=.v,arr
  kind=.'forin'
   else.
   es=.0$a:
    for_delimiter. ';';';';')' do.
    d=.>delimiter
  e=.a:
     if. -.d-:peek'' do. e=.parse_expr'' end.
    expect d
  skipnl''
  es=.es,e
    end.
   kind=.'for'
   end.
  LoopDepth=:LoopDepth+1
  body=.parse_statement''
  LoopDepth=:LoopDepth-1
  n=.kind node es,body
  case. 'break';'continue';'next';'return';'exit' do.
   if. ((<keyword)e.'break';'continue')*.LoopDepth=0 do. fail first  end.
   if. (keyword-:'return')*.-.InFunction  do. fail first  end.
   if. (keyword-:'next')*.(<ActionKind)e.'BEGIN';'END' do.  if. -.InFunction  do. fail first  end.  end.
  es=.0$a:
   if. (<keyword)e.'return';'exit' do.  if. -.(<peek'')e.';';'NL';'}' do. es=.,parse_expr'' end.  end.
  n=.keyword node es
  terminator''
  case. 'delete' do.
  e=.parse_atom''
   if. -.(<kind__e)e.'var';'array' do. fail current'' end.
  n=.'delete'node ,e
  terminator''
  case. 'print';'printf' do.
  es=.0$a:
  parenthesized=.0
   if. '('-:peek'' do.
   p=.Position
  depth=.0
    while. p<#Tokens  do. t=.p{Tokens
     if. kind__t-:'symbol' do.
     if. value__t-:'(' do. depth=.depth+1 elseif. value__t-:')' do. depth=.depth-1 end.
    end.
     if. depth=0 do. p=.p+1
   break.  end.
  p=.p+1
    end.
    if. p<#Tokens  do. t=.p{Tokens
  parenthesized=.(<value__t)e.';';'NL';'}';'>'; '>>';'EOF' end.
   end.
  OutputMode=:1
   if. parenthesized  do. consume''
  ExprDepth=:ExprDepth+1
  es=.parse_args''
  expect ')'
  ExprDepth=:ExprDepth-1
   elseif. -.(<peek'')e.';';'NL';'}';'>'; '>>' do. es=.parse_args'' end.
  OutputMode=:0
   if. (keyword-:'printf')*.0=#es  do. fail current'' end.
  n=.keyword node es
   if. (<peek'')e.'>'; '>>' do. t=.consume''
  redirop__n=:value__t
  redirpos__n=:line__t,column__t
  redirect__n=:parse_level 4 end.
  terminator''
  case.  do.
  Position=:Position-1
  n=.'expr'node ,parse_expr''
  terminator''
  end.
 line__n=:line__first
  column__n=:column__first
 StatementLines=:~.StatementLines,line__first
 n
)
parse_program=:3 :0
 Tokens=:y
  Position=:0
  LastToken=:{.Tokens
  Scope=:''
  InFunction=:0
  LoopDepth=:0
  ExprDepth=:0
  OutputMode=:0
  ActionKind=:''
 Functions=:Rules=:0$a:
  StatementLines=:i.0
  while. -.'EOF'-:peek'' do.
   if. (<peek'')e.'NL';';' do. consume''
   continue.  end.
  first=.current''
  keyword=.peek''
   if. keyword-:'function' do.
   consume''
  name=.consume''
    if. -.(<kind__name)e.'name';'function' do. fail name  end.
   expect '('
  params=.0$a:
    if. -.')'-:peek'' do.  while. 1 do. params=.params,parse_name''
   if. -.','-:peek'' do.  break.  end.
  consume''
  skipnl'' end.  end.
   expect ')'
  skipnl''
   f=.cocreate''
   name__f=:value__name
  line__f=:line__name
  column__f=:column__name
  params__f=:params
   Scope=:f
  InFunction=:1
  ActionKind=:''
   body__f=:parse_block''
   Scope=:''
  InFunction=:0
   Functions=:Functions,f
   else.
   kind=.'all'
  es=.0$a:
  body=.a:
    if. (<keyword)e.'BEGIN';'END' do. consume''
  kind=.keyword
  ActionKind=:kind
  body=.parse_block''
    elseif. keyword-:'{' do. body=.parse_block''
    else.
    es=.,parse_expr''
  kind=.'pattern'
     if. ','-:peek'' do. consume''
  skipnl''
  es=.es,parse_expr''
  kind=.'range' end.
     if. '{'-:peek'' do. body=.parse_block'' elseif. -.(<peek'')e.'NL';';';'EOF' do. fail current'' end.
    end.
   r=.cocreate''
   kind__r=:kind
  patterns__r=:es
  body__r=:body
  line__r=:line__first
  column__r=:column__first
  count__r=:0
  range__r=:0
   Rules=:Rules,r
  ActionKind=:''
   end.
  end.
)
