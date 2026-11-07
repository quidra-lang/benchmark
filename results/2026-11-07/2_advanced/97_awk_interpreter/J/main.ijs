ScriptPath=: >{:4!:3''
SourceDirectory=: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'lexer.ijs'
load SourceDirectory,'parser.ijs'
load SourceDirectory,'values_fields.ijs'
load SourceDirectory,'builtins.ijs'
load SourceDirectory,'streams.ijs'
write_lines=:4 : '(;(,&LF)&.>y) 1!:2 <x'
param_names=:3 :0
 result=.0$a:
  for_n. params__y  do. result=.result,<value__n  end.
 result
)
canonical=:4 :0
 scope=.x
  name=.y
  if. scope-:'' do. 'g:',name  return.  end.
  if. (<name)e.param_names scope  do. (>scope),':',name  else. 'g:',name  end.
)
all_nodes=:3 :0
 result=.0$a:
  pending=.,y
  while. #pending  do.
  n=.{.pending
  pending=.}.pending
   if. n-:a: do.  continue.  end.
  result=.result,n
  pending=.children__n,pending
   if. -.redirect__n-:a: do. pending=.redirect__n,pending  end.
   if. kind__n-:'getline' do.
    if. -.target__n-:a: do. pending=.target__n,pending  end.
    if. -.source__n-:a: do. pending=.source__n,pending  end.
   end.
  end.
 result
)
static_error=:4 :0
 'priority message'=.y
  n=.x
 StaticErrors=:StaticErrors,<((line__n*10000)+column__n);priority;(line__n,column__n);message
)
static_checks=:3 :0
 FunctionNames=:0$a:
  nodes=.0$a:
  StaticErrors=:0$a:
  ArrayKeys=:0$a:
  GlobalNames=:(<;._1 ' ','FILENAME FNR FS NF NR OFS ORS SUBSEP')
  for_f. Functions  do.
   if. (<name__f)e.FunctionNames  do. f static_error 0;'function ',name__f,' redefined' end.
  FunctionNames=:FunctionNames,<name__f
  seen=.0$a:
   for_p. params__f  do.
    if. (<value__p)e.seen  do. p static_error 1;'duplicate parameter ',value__p  end.
   seen=.seen,<value__p
   end.
  nodes=.nodes,all_nodes body__f
  end.
  for_r. Rules  do.
   for_p. patterns__r  do. nodes=.nodes,all_nodes p  end.
   if. -.body__r-:a: do. nodes=.nodes,all_nodes body__r  end.
  end.
  for_f. Functions  do.  for_p. params__f  do.  if. (<value__p)e.FunctionNames  do. p static_error 2;'function ',value__p,' used as variable' end.  end.  end.
 links=.0$a:
  for_n. nodes  do.
  kind=.kind__n
  name=.value__n
   if. (<kind)e.'var';'array';'in' do.
    if. (<name)e.FunctionNames  do. n static_error 2;'function ',name,' used as variable' end.
   key=.scope__n canonical name
    if. 'g:'-:2{.key  do. GlobalNames=:~.GlobalNames,<name  end.
    if. (<kind)e.'array';'in' do. ArrayKeys=:~.ArrayKeys,<key  end.
   elseif. kind-:'delete' do. a=.{.children__n
  ArrayKeys=:~.ArrayKeys,<scope__a canonical value__a
   elseif. kind-:'forin' do. a=.1{children__n
  ArrayKeys=:~.ArrayKeys,<scope__a canonical value__a
   elseif. (kind-:'builtin')*.name-:'split' do. a=.1{children__n
  ArrayKeys=:~.ArrayKeys,<scope__a canonical value__a
   elseif. kind-:'call' do.
   i=.FunctionNames i.<name
    if. i=#FunctionNames  do. n static_error 3;'undefined function ',name
    else.
    f=.i{Functions
  ps=.param_names f
     if. (#children__n)>#ps  do. n static_error 4;'too many arguments to ',name  end.
     for_i. i.(#children__n)<.#ps  do.
     a=.i{children__n
      if. kind__a-:'var' do. links=.links,<((scope__a canonical value__a);f canonical i{::ps) end.
     end.
    end.
   end.
  end.
  if. #StaticErrors  do.
  scores=.i.0
   for_e. StaticErrors  do. 'pos priority place message'=.>e
  scores=.scores,10*pos+priority  end.
  'pos priority place message'=.({./:scores){::StaticErrors
  Status=:'status: error at ',(dec 0{place),':',(dec 1{place),': ',message
  0 return.
  end.
 changed=.1
  while. changed  do.
  changed=.0
   for_link. links  do. 'a b'=.>link
    if. (<a)e.ArrayKeys  do.  if. -.(<b)e.ArrayKeys  do. ArrayKeys=:ArrayKeys,<b
  changed=.1 end.
    elseif. (<b)e.ArrayKeys  do. ArrayKeys=:ArrayKeys,<a
  changed=.1 end.
   end.
  end.
 1
)
new_cell=:3 :0
 c=.cocreate''
 array__c=:y
  value__c=:uninitialized''
  keys__c=:values__c=:0$a:
 c
)
global_cell=:3 :0
 i=.GlobalKeys i.<y
  if. i=#GlobalKeys  do. GlobalKeys=:GlobalKeys,<y
  GlobalCells=:GlobalCells,new_cell (< 'g:',y)e.ArrayKeys  end.
 i{GlobalCells
)
resolve_cell=:3 :0
  if. -.CurrentFunction-:a: do.
  ps=.param_names CurrentFunction
  i=.ps i.<y
   if. i<#ps  do. i{LocalCells  return.  end.
  end.
 global_cell y
)
scalar_global=:3 :0
  if. y-:'NF' do. number #Fields  else. c=.global_cell y
  value__c  end.
)
subscript=:3 :0
 parts=.0$a:
  for_n. y  do. parts=.parts,<to_string evaluate n  end.
 (to_string scalar_global 'SUBSEP')join parts
)
location=:3 :0
 n=.y
  if. kind__n-:'field' do.
  k=.to_number evaluate {.children__n
  ErrorPosition=:line__n,column__n
   if. k<0 do. runtime_error 'negative field index' end.
  1;a:;k
  else.
  cell=.resolve_cell value__n
   if. kind__n-:'array' do. 0;cell;subscript children__n
   else. 0;cell;a: end.
  end.
)
location_value=:3 :0
 'field c key'=.y
  if. field  do. field_value key
  elseif. key-:a: do.
   if. (c-:global_cell 'NF') do. number #Fields  else. value__c  end.
  else.
  i=.keys__c i.<key
   if. i=#keys__c  do. keys__c=:keys__c,<key
  values__c=:values__c,<uninitialized'' end.
  i{::values__c
  end.
)
store=:4 :0
 'field c key'=.x
  v=.y
  if. field  do. key set_field v
  elseif. key-:a: do.
   if. c-:global_cell 'NF' do. set_nf v  else. value__c=:v
  v  end.
  else.
  i=.keys__c i.<key
   if. i=#keys__c  do. keys__c=:keys__c,<key
  values__c=:values__c,<v  else. values__c=:(<v)i}values__c  end.
  v
  end.
)
assign_global=:4 :0
 cell=.global_cell x
 value__cell=:y
 GlobalNames=:~.GlobalNames,<x
)
calculate=:4 :0
 'a b'=.y
  a=.to_number a
  b=.to_number b
  if. ((<x)e.'/';'%')*.b=0 do. runtime_error 'division by zero' end.
  if. (x-:'^')*.b<0 do. runtime_error 'negative exponent' end.
  select. x
  case. '+' do. r=.a+b
  case. '-' do. r=.a-b
  case. '*' do. r=.a*b
  case. '/' do. r=.(*a%b)*<.|a%b
  case. '%' do. r=.a-b*(*a%b)*<.|a%b
  case. '^' do. r=.a^b
  end.
 number r
)
next_main=:3 :0
  if. InEnd  do. 0;'' return.  end.
  while. 1 do.
   if. MainPosition<#MainLines  do.
   line=.MainPosition{::MainLines
  MainPosition=:MainPosition+1
   InputStats=:(1+MainFile{InputStats)MainFile}InputStats
   'NR'assign_global number 1+to_number scalar_global 'NR'
   'FNR'assign_global number 1+to_number scalar_global 'FNR'
   1;line  return.
   end.
   if. OperandPosition=#Operands  do. 0;'' return.  end.
  'file name val'=.OperandPosition{::Operands
  OperandPosition=:OperandPosition+1
   if. -.file  do. name assign_global input_value val
   else. MainFile=:val
  MainLines=:readlines 'input/',name
  MainPosition=:0
  'FILENAME'assign_global string name
  'FNR'assign_global number 0 end.
  end.
)
user_call=:3 :0
 n=.y
  f=.(FunctionNames i.<value__n){Functions
  ps=.param_names f
  cells=.0$a:
  for_i. i.#ps  do.
  array=.(<f canonical i{::ps)e.ArrayKeys
  c=.new_cell array
   if. i<#children__n  do.
   arg=.i{children__n
    if. array  do. c=.resolve_cell value__arg  else. value__c=:evaluate arg
    if. #Flow do. uninitialized'' return. end.
   end.
   end.
  cells=.cells,c
  end.
 savedfunc=.CurrentFunction
  savedlocals=.LocalCells
  savedflow=.Flow
  savedreturn=.ReturnValue
 CurrentFunction=:f
  LocalCells=:cells
  Flow=:''
  ReturnValue=:uninitialized''
 calls__f=:calls__f+1
  active__f=:active__f+1
  depth__f=:depth__f>.active__f
 execute body__f
 result=.ReturnValue
 active__f=:active__f-1
 functionflow=.Flow
 CurrentFunction=:savedfunc
  LocalCells=:savedlocals
  ReturnValue=:savedreturn
  if. (<functionflow)e.'next';'exit' do. Flow=:functionflow  else. Flow=:savedflow  end.
 result
)
builtin_call=:3 :0
 n=.y
  name=.value__n
  es=.children__n
  if. name-:'length' do.
   if. 0=#es  do. number #to_string Record  return.  end.
  a=.{.es
   if. kind__a-:'var' do. c=.resolve_cell value__a
   if. array__c  do. number #keys__c  return.  end.  end.
  elseif. name-:'split' do.
  s=.to_string evaluate 0{es
  arr=.1{es
   if. 3=#es  do. sep=.to_string evaluate 2{es  else. sep=.to_string scalar_global 'FS' end.
  pieces=.sep split_string s
  c=.resolve_cell value__arr
  keys__c=:values__c=:0$a:
   for_i. i.#pieces  do. keys__c=:keys__c,<dec i+1
  values__c=:values__c,<input_value i{::pieces  end.
  number #pieces  return.
  elseif. name-:'close' do. number close_stream to_string evaluate {.es  return.  end.
 values=.0$a:
  for_a. es do.
   values=.values,<evaluate a
   if. #Flow do. uninitialized'' return. end.
  end.
 ErrorPosition=:line__n,column__n
 name scalar_builtin values
)
evaluate=:3 :0
 n=.y
 ErrorPosition=:line__n,column__n
  select. kind__n
  case. 'number' do. number value__n
  case. 'string' do. string value__n
  case. 'var';'array';'field' do. location_value location n
  case. 'paren' do. evaluate {.children__n
  case. 'call' do. user_call n
  case. 'builtin' do. builtin_call n
  case. 'assign' do.
  loc=.location 0{children__n
  if. #Flow do. uninitialized'' return. end.
  v=.evaluate 1{children__n
  if. #Flow do. uninitialized'' return. end.
  ErrorPosition=:line__n,column__n
   if. -.value__n-:'=' do. v=.(}:value__n)calculate (location_value loc);v  end.
  loc store v
  case. 'preinc';'postinc' do.
  loc=.location {.children__n
  old=.to_number location_value loc
  delta=.1
   if. value__n-:'--' do. delta=._1 end.
  ErrorPosition=:line__n,column__n
  loc store number old+delta
   if. kind__n-:'preinc' do. number old+delta  else. number old  end.
  case. 'unary' do.
  v=.evaluate {.children__n
   select. value__n
   case. '!' do. number -.truth v
   case. '-' do. number -to_number v
   case. '+' do. number to_number v
   end.
  case. 'conditional' do.
  c=.truth evaluate 0{children__n
   if. c  do. evaluate 1{children__n  else. evaluate 2{children__n  end.
  case. 'in' do.
  key=.subscript children__n
  c=.resolve_cell value__n
  number (<key)e.keys__c
  case. 'binary' do.
  a=.evaluate 0{children__n
  if. #Flow do. uninitialized'' return. end.
  op=.value__n
   if. (op-:'&&')*.-.truth a  do. number 0 return.  end.
   if. (op-:'||')*.truth a  do. number 1 return.  end.
  b=.evaluate 1{children__n
  if. #Flow do. uninitialized'' return. end.
  ErrorPosition=:line__n,column__n
   select. op
   case. 'concat' do. string (to_string a),to_string b
   case. '&&';'||' do. number truth b
   case. '<';'<=';'==';'!=';'>=';'>' do.
   cmp=.a compare b
    select. op
    case. '<' do. number cmp<0
    case. '<=' do. number cmp<:0
    case. '==' do. number cmp=0
    case. '!=' do. number cmp~:0
    case. '>=' do. number cmp>:0
    case. '>' do. number cmp>0
    end.
   case.  do. op calculate a;b
   end.
  case. 'getline' do.
   if. source__n-:a: do. 'ok line'=.next_main'' else. 'ok line'=.getline_stream to_string evaluate source__n  end.
   if. ok=1 do.
    if. target__n-:a: do. set_record line
    else. loc=.location target__n
  ErrorPosition=:line__n,column__n
  loc store input_value line  end.
   end.
  number ok
  end.
)
output_text=:4 :0
 n=.x
  text=.y
  if. redirect__n-:a: do. Stdout=:Stdout,text
  StdoutWrites=:StdoutWrites+1
  else.
  name=.to_string evaluate redirect__n
  ErrorPosition=:redirpos__n
  (name;(redirop__n-:'>>'))stream_output text
  end.
)
execute=:3 :0
 n=.y
  if. #Flow  do.  return.  end.
 kind=.kind__n
  if. kind-:'block' do.  for_s. children__n  do. execute s
   if. #Flow  do.  break.  end.  end.
   return.  end.
  if. kind-:'empty' do.  return.  end.
 i=.StatementLines i.line__n
  LineCounts=:(1+i{LineCounts)i}LineCounts
 es=.children__n
  select. kind
  case. 'expr' do. evaluate {.es
  case. 'if' do.
   if. truth evaluate 0{es  do. execute 1{es  elseif. 3=#es  do. execute 2{es  end.
  case. 'while';'do';'for' do.
   if. kind-:'for' do.  if. -.(0{es)-:a: do. evaluate 0{es  end.
  condition=.1{es
  step=.2{es
  body=.3{es
   elseif. kind-:'while' do. condition=.0{es
  step=.a:
  body=.1{es
   else. condition=.1{es
  step=.a:
  body=.0{es  end.
  first=.1
   while. 1 do.
    if. -.(kind-:'do')*.first  do.  if. -.condition-:a: do.  if. -.truth evaluate condition  do.  break.  end.  end.  end.
   first=.0
   execute body
    if. Flow-:'break' do. Flow=:''
   break.  end.
    if. Flow-:'continue' do. Flow=:'' end.
    if. #Flow  do.  break.  end.
    if. -.step-:a: do. evaluate step  end.
    if. kind-:'do' do.  if. -.truth evaluate condition  do.  break.  end.  end.
   end.
  case. 'forin' do.
  v=.0{es
  arr=.1{es
  c=.resolve_cell value__arr
  keys=.key_order keys__c
   for_key. keys  do.
   ErrorPosition=:line__v,column__v
   (location v)store input_value >key
   execute 2{es
    if. Flow-:'break' do. Flow=:''
   break.  end.
    if. Flow-:'continue' do. Flow=:'' end.
    if. #Flow  do.  break.  end.
   end.
  case. 'delete' do.
  a=.{.es
  c=.resolve_cell value__a
   if. kind__a-:'var' do. keys__c=:values__c=:0$a:
   else. key=.subscript children__a
  i=.keys__c i.<key
   if. i<#keys__c  do. keep=.(i.#keys__c)-.i
  keys__c=:keep{keys__c
  values__c=:keep{values__c  end.  end.
  case. 'print';'printf' do.
  values=.0$a:
   for_e. es do.
   values=.values,<evaluate e
   if. #Flow do. return. end.
  end.
   if. kind-:'print' do.
    if. 0=#values  do. values=.,<Record  end.
   text=.(to_string scalar_global 'OFS')join to_string&.>values
   text=.text,to_string scalar_global 'ORS'
   else. ErrorPosition=:line__n,column__n
  text=.format_values values  end.
  n output_text text
  case. 'return' do.
  ReturnValue=:uninitialized''
   if. #es  do. ReturnValue=:evaluate {.es  end.
  if. 0=#Flow do. Flow=:'return' end.
  case. 'exit' do.
   if. #es  do. ExitStatus=:to_number evaluate {.es  end.
  Flow=:'exit'
  case. 'next' do.
   if. (<Phase)e.'BEGIN';'END' do. ErrorPosition=:line__n,column__n
  runtime_error 'next used in BEGIN or END' end.
  Flow=:'next'
  case. 'break';'continue' do. Flow=:kind
  end.
 0
)
execute_rules=:3 :0
  for_r. Rules  do.
   if. (<kind__r)e.'BEGIN';'END' do.  continue.  end.
  match=.1
   if. kind__r-:'pattern' do. match=.truth evaluate 0{patterns__r
   elseif. kind__r-:'range' do.
    if. -.range__r  do. range__r=:truth evaluate 0{patterns__r  end.
   match=.range__r
    if. match  do.  if. truth evaluate 1{patterns__r  do. range__r=:0 end.  end.
   end.
   if. #Flow do. break. end.
  if. match  do.
   count__r=:count__r+1
    if. body__r-:a: do. Stdout=:Stdout,(to_string Record),to_string scalar_global 'ORS'
  StdoutWrites=:StdoutWrites+1
    else. execute body__r  end.
   end.
   if. #Flow  do.  break.  end.
  end.
)
statistics=:3 :0
 result=.,<Status
 result=.result,<'[inputs]'
  for_i. i.#InputNames  do. result=.result,<(i{::InputNames),' records=',dec i{InputStats  end.
 result=.result,<'[getline]'
  for_i. i.#GetNames  do.
   if. i{GetExists  do. line=.(i{::GetNames),' reads=',dec i{GetCounts  else. line=.(i{::GetNames),' missing' end.
  result=.result,<line
  end.
 result=.result,<'[rules]'
  for_r. Rules  do. result=.result,<(dec line__r),':',(dec column__r),' ',kind__r,' count=',dec count__r  end.
 result=.result,<'[functions]'
  for_f. Functions  do. result=.result,<name__f,' calls=',(dec calls__f),' depth=',dec depth__f  end.
 result=.result,(<'[outputs]'),<'stdout.txt writes=',(dec StdoutWrites),' bytes=',dec #Stdout
  for_i. i.#OutputNames  do. result=.result,<(i{::OutputNames),' writes=',(dec i{OutputCounts),' bytes=',dec #i{::OutputContents  end.
 result=.result,<'[lines]'
  for_i. /:StatementLines  do. result=.result,<(dec i{StatementLines),' count=',dec i{LineCounts  end.
 result=.result,<'[globals]'
  for_name. /:~~.GlobalNames  do.
  name=.>name
  c=.global_cell name
   if. array__c  do. val=.'array (',(dec #keys__c),')' else. val=.value_text scalar_global name  end.
  result=.result,<name,' = ',val
  end.
 result
)
main=:3 :0
 Stdout=:''
  try.
  ts=.lex 1!:1 <'input/program.awk'
  parse_program ts
  catch.
  Status=:'status: syntax error at ',(dec 0{SyntaxPosition),':',dec 1{SyntaxPosition
  ''1!:2 <'output/stdout.txt'
  'output/stats.txt'write_lines ,<Status
  0 return.
  end.
  if. -.static_checks'' do.
  ''1!:2 <'output/stdout.txt'
  'output/stats.txt'write_lines ,<Status
  0 return.
  end.
 parse_arguments readlines 'input/args.txt'
 GlobalKeys=:GlobalCells=:0$a:
 CurrentFunction=:a:
  LocalCells=:0$a:
  Fields=:0$a:
  Record=:string''
  for_name. GlobalNames  do. global_cell >name  end.
 'FS'assign_global string ' '
 'OFS'assign_global string ' '
 'ORS'assign_global string LF
 'SUBSEP'assign_global string 28{a.
 'NR'assign_global number 0
 'FNR'assign_global number 0
 'FILENAME'assign_global string''
 OutputNames=:OutputContents=:GetNames=:GetLines=:0$a:
 OutputOpen=:OutputCounts=:GetOpen=:GetPositions=:GetCounts=:GetExists=:i.0
 OperandPosition=:MainPosition=:0
  MainFile=:_1
  MainLines=:0$a:
 InEnd=:0
  ExitStatus=:0
  Flow=:''
  ReturnValue=:uninitialized''
 StdoutWrites=:0
  LineCounts=:(#StatementLines)$0
  for_f. Functions  do. calls__f=:active__f=:depth__f=:0 end.
  try.
   for_option. Options  do. 'name val'=.>option
  name assign_global input_value val  end.
  Phase=:'BEGIN'
   for_r. Rules  do.  if. kind__r-:'BEGIN' do. count__r=:1
  execute body__r
   if. Flow-:'exit' do.  break.  end.  end.  end.
  readmain=.0
   for_r. Rules  do.  if. -.kind__r-:'BEGIN' do. readmain=.1 end.  end.
  Phase=:'record'
   if. readmain*.-.Flow-:'exit' do.
    while. 1 do.
    Flow=:''
    'ok line'=.next_main''
     if. -.ok  do.  break.  end.
    set_record line
    execute_rules''
     if. Flow-:'exit' do.  break.  end.
    end.
   end.
  InEnd=:1
  Phase=:'END'
  Flow=:''
   for_r. Rules  do.  if. kind__r-:'END' do. count__r=:1
  execute body__r
   if. Flow-:'exit' do.  break.  end.  end.  end.
  Status=:'status: exit ',dec ExitStatus
  catch.
  Status=:'status: runtime error at ',(dec 0{RuntimePosition),':',(dec 1{RuntimePosition),': ',RuntimeMessage
  end.
 Stdout 1!:2 <'output/stdout.txt'
  for_i. i.#OutputNames  do. (i{::OutputContents)1!:2 <'output/',i{::OutputNames  end.
 'output/stats.txt'write_lines statistics''
 0
)
main''
