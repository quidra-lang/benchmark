ScriptPath=: >{:4!:3''
SourceDirectory=: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'lexer.ijs'
load SourceDirectory,'definitions.ijs'
load SourceDirectory,'expression.ijs'
load SourceDirectory,'expander.ijs'
load SourceDirectory,'include_manager.ijs'
diagnostic=:3 :0
 'file line kind message'=.y
 Diagnostics=:Diagnostics,<file,':',(dec line),': ',kind,': ',message
  if. kind-:'error' do. ErrorCount=:ErrorCount+1 else. WarningCount=:WarningCount+1 end.
)
error=:3 : 'diagnostic display__Current;(At+offset__Current);''error'';y'
warning=:3 : 'diagnostic display__Current;(At+offset__Current);''warning'';y'
history=:3 : 'History=:History,<display__Current,'':'',(dec At+offset__Current),'': '',y'
unused=:3 :0
 m=.y
  if. main__m*.(expanded__m=0)*.tested__m=0 do. diagnostic file__m;line__m;'warning';'macro "',name__m,'" is not used' end.
)
install_definition=:3 :0
  try. m=.parse_definition y  catch.  return.  end.
 file__m=:display__Current
  line__m=:At+offset__Current
  main__m=:depth__Current=0
 i=.MacroNames i.<name__m
  if. i=#MacroNames  do. MacroNames=:MacroNames,<name__m
  Macros=:Macros,m
  history 'define ',signature m
  else.
  old=.i{Macros
   if. old identical_definition m  do. history 'identical ',signature m
   else.
   unused old
   warning '"',name__m,'" redefined (previous definition at ',file__old,':',(dec line__old),')'
   Macros=:m i}Macros
   history 'redefine ',signature m
   end.
  end.
 EverDefined=:~.EverDefined,<name__m
)
undefine=:3 :0
 message=.'undef'name_error y
  if. #message  do. error message
   return.  end.
  if. 1<#y  do. warning 'extra tokens at end of #undef directive' end.
 t=.{.y
  name=.spell__t
  i=.MacroNames i.<name
  if. i<#MacroNames  do. unused i{Macros
  MacroNames=:((i.#MacroNames)-.i){MacroNames
  Macros=:((i.#Macros)-.i){Macros
  history 'undef ',name
  else. history 'undef ',name,' (not defined)' end.
)
poison_check=:3 :0
 saved=.At
  for_t. y  do.  if. (kind__t-:'identifier')*.(<spell__t)e.Poisoned  do. At=:line__t
  error 'attempt to use poisoned "',spell__t,'"' end.  end.
 At=:saved
)
mark_line=:3 :0
 'file line suffix'=.y
 Preprocessed=:Preprocessed,<'# ',(dec line),' "',file,'"',suffix
 PreviousFile=:file
  PreviousLine=:line-1
)
output_line=:3 :0
 'line text'=.y
 file=.display__Current
  if. (PreviousFile-:file)*.(line>PreviousLine)*.line<:PreviousLine+8 do.
  Preprocessed=:Preprocessed,((line-PreviousLine-1)$<'')
  else. mark_line file;line;'' end.
 Preprocessed=:Preprocessed,<text
 PreviousFile=:file
  PreviousLine=:line
 f=.file__Current
  output__f=:output__f+1
)
flush_segment=:3 :0
 ts=.segment__Current
  segment__Current=:0$a:
  if. 0=#ts  do.  return.  end.
 poison_check ts
 ts=.expand ts
  while. #ts  do.
  first=.{.ts
  n=.line__first
  count=.0
   for_t. ts  do.  if. line__t~:n  do.  break.  end.
  count=.count+1 end.
  output_line (n+offset__Current);output_render count{.ts
  ts=.count}.ts
  end.
)
is_defined=:3 :0
 m=.find_macro y
  if. -.m-:a: do. tested__m=:tested__m+1
  1
  else. (<y)e.Builtins,<'__has_include' end.
)
replace_operators=:3 :0
 ts=.y
  p=.0
  out=.0$a:
  while. p<#ts  do.
  t=.p{ts
  p=.p+1
  name=.spell__t
   if. (kind__t-:'identifier')*.name-:'defined' do.
   paren=.0
    if. p<#ts  do. n=.p{ts
   if. spell__n-:'(' do. paren=.1
  p=.p+1 end.  end.
    if. p=#ts  do. expression_error 'operator "defined" requires an identifier' end.
   n=.p{ts
  p=.p+1
    if. -.kind__n-:'identifier' do. expression_error 'operator "defined" requires an identifier' end.
   value=.is_defined spell__n
    if. paren  do.
     if. p=#ts  do. expression_error 'missing '')'' after "defined"' end.
    n=.p{ts
  p=.p+1
     if. -.spell__n-:')' do. expression_error 'missing '')'' after "defined"' end.
    end.
   out=.out,token 'number';(dec value);line__t;space__t
   elseif. (kind__t-:'identifier')*.name-:'__has_include' do.
    if. p=#ts  do. expression_error 'missing ''('' after "__has_include"' end.
   n=.p{ts
  p=.p+1
    if. -.spell__n-:'(' do. expression_error 'missing ''('' after "__has_include"' end.
   'header rendering count quoted'=.read_header p}.ts
    if. 0=#header  do. expression_error 'operator "__has_include" requires a header-name' end.
   p=.p+count
    if. p=#ts  do. expression_error 'missing '')'' after "__has_include" operand' end.
   n=.p{ts
  p=.p+1
    if. -.spell__n-:')' do. expression_error 'missing '')'' after "__has_include" operand' end.
   out=.out,token 'number';(dec 0<#search_header header;quoted);line__t;space__t
   else. out=.out,t  end.
  end.
 out
)
test_condition=:4 :0
 directive=.x
  ts=.y
  value=.0
  good=.1
  expanded=.0
  result=.0$a:
  try.
  poison_check ts
   if. (<directive)e.'if';'elif' do.
   replaced=.replace_operators ts
   result=.expand replaced
  expanded=.1
    if. 0=#result  do. expression_error '#',directive,' with no expression' end.
   ETokens=:result
  EPos=:0
   root=.expr_conditional''
    if. EPos<#ETokens  do. t=.EPos{ETokens
  expression_error 'missing binary operator before "',spell__t,'"' end.
   value=.evaluate_expr root
   else.
    if. 0=#ts  do. expression_error 'no macro name given in #',directive,' directive' end.
   t=.{.ts
    if. -.kind__t-:'identifier' do. expression_error 'macro names must be identifiers' end.
    if. 1<#ts  do. warning 'extra tokens at end of #',directive,' directive' end.
   value=.is_defined spell__t
    if. (<directive)e.'ifndef';'elifndef' do. value=.-.value  end.
   end.
  catch. good=.0 end.
  if. -.good  do. text=.'not taken (error)'
  elseif. value~:0 do. text=.'taken' else. text=.'not taken' end.
  if. good*.(<directive)e.'if';'elif' do. text=.text,' (value ',(dec value),')' end.
  if. expanded  do. text=.text,' [',(output_render result),']' end.
 (good*.value~:0);text
)
close_region=:4 :0
 b=.x
  ending=.y
  if. skip__b~:_1 do.
  start=.skip__b
   if. ending>:start  do.
   SkippedRegions=:SkippedRegions,<display__Current,':',(dec start+offset__Current),'-',(dec ending+offset__Current),' lines=',dec 1+ending-start
   f=.file__Current
  skippedlines__f=:skippedlines__f+1+ending-start
   end.
  skip__b=:_1
  end.
)
conditional=:3 :0
 'directive operands logical'=.y
 stack=.conditions__Current
  level=.#stack
  if. (<directive)e.(<;._1 ' ','if ifdef ifndef') do.
  b=.cocreate''
  kind__b=:directive
  display__b=:display__Current
  line__b=:At+offset__Current
  parent__b=:1
  active__b=:chosen__b=:else__b=:0
  skip__b=:_1
   if. #stack  do. top=.{:stack
  parent__b=:active__top  end.
   if. parent__b  do. 'ok result'=.directive test_condition operands
  active__b=:chosen__b=:ok
   if. -.ok  do. skip__b=:end__logical+1 end.
   else. result=.'skipped' end.
  conditions__Current=:stack,b
  else.
   if. 0=#stack  do. error '#',directive,' without #if'
   return.  end.
  b=.{:stack
  level=.level-1
  b close_region start__logical-1
   if. directive-:'endif' do.
    if. parent__b*.#operands  do. warning 'extra tokens at end of #endif directive' end.
   result=.'closes #',kind__b,' at line ',dec line__b
   conditions__Current=:}:stack
   else.
    if. else__b  do. error '#',directive,' after #else' end.
    if. directive-:'else' do.
     if. parent__b*.#operands  do. warning 'extra tokens at end of #else directive' end.
    else__b=:1
     if. parent__b  do. active__b=: -.chosen__b
  chosen__b=:1
  result=.('not taken';'taken'){::~active__b  else. result=.'skipped' end.
    elseif. -.parent__b  do. active__b=:0
  result=.'skipped'
    elseif. chosen__b  do. active__b=:0
  result=.'not evaluated'
    else. 'ok result'=.directive test_condition operands
  active__b=:ok
  chosen__b=:chosen__b+.ok  end.
    if. parent__b*.-.active__b  do. skip__b=:end__logical+1 end.
   end.
  end.
 rendering=.'#',directive
  if. #operands  do. rendering=.rendering,' ',render operands  end.
 ConditionRecords=:ConditionRecords,<display__Current,':',(dec At+offset__Current),': ',((2*level)$' '),rendering,' => ',result
 results=.('taken';'not taken';'skipped';'not evaluated';'closes')
  for_i. i.5 do. prefix=.i{::results
   if. prefix-:(#prefix){.result  do. ConditionCounts=:(1+i{ConditionCounts)i}ConditionCounts
   break.  end.  end.
)
include_directive=:3 :0
 'operands logical'=.y
  try.
  'name rendering count quoted'=.read_header operands
   if. (count=0)*.#operands  do. operands=.expand operands
  'name rendering count quoted'=.read_header operands  end.
   if. count=0 do. error '#include expects "FILENAME" or <FILENAME>'
   return.  end.
   if. count<#operands  do. warning 'extra tokens at end of #include directive' end.
   if. 0=#name  do. error 'empty filename in #include'
   return.  end.
  catch.  return.  end.
 prefix=.((2*depth__Current+1)$' '),(dec At),': '
 path=.search_header name;quoted
  if. 0=#path  do. IncludeTree=:IncludeTree,<prefix,rendering,' [not found]'
  error 'cannot find include file ',rendering
   return.  end.
 i=.FileNames i.<path
  if. i<#FileNames  do.
  f=.i{Files
  reason=.''
   if. once__f  do. reason=.'pragma once'
   elseif. #guard__f  do.  if. -.(find_macro guard__f)-:a: do. reason=.'guard ',guard__f  end.  end.
   if. #reason  do. IncludeTree=:IncludeTree,<prefix,path,' [skipped: ',reason,']'
  skipped__f=:skipped__f+1
   return.  end.
  end.
  if. depth__Current+1>8 do. IncludeTree=:IncludeTree,<prefix,path,' [too deep]'
  error '#include nested too deeply'
   return.  end.
 IncludeTree=:IncludeTree,<prefix,path
 saved=.Current
  nextline=.1+end__logical+offset__Current
 mark_line path;1;' 1'
 process_file path;depth__Current+1
 Current=:saved
 mark_line display__Current;nextline;' 2'
)
pragma=:3 :0
 ts=.y
  names=.spellings ts
 first=.''
  if. #ts  do. first=.0{::names  end.
  select. first
  case. 'once' do.
   if. 1<#ts  do. warning 'extra tokens at end of #pragma once directive' end.
   if. depth__Current=0 do. warning '#pragma once in main file' end.
  f=.file__Current
  once__f=:1
  case. 'GCC' do.
   if. ('GCC';'poison')-:2{.names  do.
    for_t. 2}.ts  do.  if. -.kind__t-:'identifier' do. error 'invalid #pragma GCC poison directive'
   return.  end.  end.
    for_t. 2}.ts  do.
     if. -.(find_macro spell__t)-:a: do. warning 'poisoning existing macro "',spell__t,'"' end.
    Poisoned=:~.Poisoned,<spell__t
    end.
   else. output_line (At+offset__Current);'#pragma ',render ts  end.
  case. 'push_macro';'pop_macro' do.
  valid=.4=#ts
   if. valid  do. t=.2{ts
  valid=.('('-:1{::names)*.(')'-:3{::names)*.kind__t-:'string' end.
   if. -.valid  do. error 'invalid #pragma ',first,' directive'
   return.  end.
  name=.}.}:2{::names
  i=.SaveNames i.<name
   if. i=#SaveNames  do. SaveNames=:SaveNames,<name
  Saves=:Saves,<0$a: end.
  stack=.i{::Saves
   if. first-:'push_macro' do. stack=.stack,find_macro name
  history 'push ',name
   elseif. 0=#stack  do. warning 'no matching push_macro for "',name,'"'
   else.
   m=.{:stack
  stack=.}:stack
  j=.MacroNames i.<name
    if. m-:a: do.
     if. j<#MacroNames  do. MacroNames=:((i.#MacroNames)-.j){MacroNames
  Macros=:((i.#Macros)-.j){Macros  end.
    history 'pop ',name,' (undefined)'
    else.
     if. j=#MacroNames  do. MacroNames=:MacroNames,<name
  Macros=:Macros,m  else. Macros=:m j}Macros  end.
    history 'pop ',name
    end.
   end.
  Saves=:(<stack)i}Saves
  case.  do.
  text=.'#pragma'
   if. #ts  do. text=.text,' ',render ts  end.
  output_line (At+offset__Current);text
  end.
)
other_directive=:3 :0
 'directive operands logical'=.y
 poison=.1
  if. directive-:'pragma' do.  if. ('GCC';'poison')-:2{.spellings operands  do. poison=.0 end.  end.
  if. poison  do. poison_check operands  end.
  select. directive
  case. 'define' do. install_definition operands
  case. 'undef' do. undefine operands
  case. 'include' do. include_directive operands;logical
  case. 'error';'warning' do.
  text=.'#',directive
   if. #operands  do. text=.text,' ',render operands  end.
   if. directive-:'error' do. error text  else. warning text  end.
  case. 'pragma' do. pragma operands
  case. 'line' do.
  ts=.operands
  plain=.0
   if. #ts  do. t=.{.ts
  plain=.(kind__t-:'number')*.*./spell__t e.digits  end.
   if. -.plain  do. ts=.expand ts  end.
  valid=.(#ts)e.1 2
   if. valid  do. t=.{.ts
  valid=.(kind__t-:'number')*.(*./spell__t e.digits)
    if. 2=#ts  do. s=.1{ts
  valid=.valid*.kind__s-:'string' end.
   end.
   if. -.valid  do. error 'invalid #line directive'
   else. n=.0".spell__t
    if. (n<1)+.n>2147483647 do. error 'line number out of range'
    else. offset__Current=:n-1+end__logical
   if. 2=#ts  do. display__Current=:}.}:spell__s  end.  end.
   end.
  case.  do. error 'invalid preprocessing directive #',directive
  end.
)
process_file=:3 :0
 'path depth'=.y
 f=.get_file path
 entered__f=:entered__f+1
 ctx=.cocreate''
 file__ctx=:f
  depth__ctx=:depth
  display__ctx=:path
  offset__ctx=:0
  conditions__ctx=:segment__ctx=:0$a:
 Current=:ctx
  for_l. lines__f  do.
  ts=.tokens__l
  directive=.''
   if. #ts  do. t=.{.ts
    if. spell__t-:'#' do.
     if. 1<#ts  do. t=.1{ts
  directive=.spell__t  end.
    flush_segment''
    t=.{.ts
  At=:line__t
     if. (<directive)e.(<;._1 ' ','if ifdef ifndef elif elifdef elifndef else endif') do. conditional directive;(2}.ts);l
   continue.  end.
    skipping=.0
     if. #conditions__Current  do. b=.{:conditions__Current
  skipping=.-.active__b  end.
     if. skipping  do.  continue.  end.
     if. 1<#ts  do. other_directive directive;(2}.ts);l  end.
     continue.
    end.
   end.
  skipping=.0
   if. #conditions__Current  do. b=.{:conditions__Current
  skipping=.-.active__b  end.
   if. -.skipping  do. segment__Current=:segment__Current,ts  end.
  end.
 flush_segment''
  for_b. conditions__Current  do. b close_region physical__f
  diagnostic display__b;line__b;'error';'unterminated #',kind__b  end.
)
macro_refs=:3 :0
 m=.y
  refs=.0$a:
  for_t. replacement__m  do.  if. (kind__t-:'identifier')*.(<spell__t)e.MacroNames  do.  if. -.(<spell__t)e.params__m  do. refs=.refs,<spell__t  end.  end.  end.
 /:~~.refs
)
is_recursive=:3 :0
 name=.y
  pending=.macro_refs find_macro name
  seen=.0$a:
  while. #pending  do. n=.{.pending
  pending=.}.pending
   if. n-:<name  do. 1 return.  end.
   if. n e.seen  do.  continue.  end.
  seen=.seen,n
  pending=.pending,macro_refs find_macro >n
  end.
 0
)
write_reports=:3 :0
 includes=.IncludeTree,('';'== files ==')
  for_path. /:FileNames  do. f=.path{Files
  guard=.guard__f
   if. 0=#guard  do. guard=.'-' end.
  includes=.includes,<path__f,' entered=',(dec entered__f),' skipped=',(dec skipped__f),' lines=',(dec physical__f),' output_lines=',(dec output__f),' skipped_lines=',(dec skippedlines__f),' guard=',guard,' once=',('no';'yes'){::~once__f
  end.
 includes=.includes,<''
  dependency=.'main.o:'
  haspath=.0
  for_path. FileNames  do. path=.>path
   if. haspath*.(#dependency)+1+#path>76 do. includes=.includes,<dependency,' \'
  dependency=.' ' end.
  dependency=.dependency,' ',path
  haspath=.1
  end.
 includes=.includes,<dependency
 macros=.(<'== history =='),History,('';'== table ==')
  functioncount=.0
  for_n. /:MacroNames  do. m=.n{Macros
  sig=.signature m
  replacement=.render replacement__m
  first=.'#define ',sig
   if. #replacement  do. first=.first,' ',replacement  end.
  refs=.macro_refs m
  recursive=.( 'no';'yes'){::~is_recursive name__m
  macros=.macros,(<first),(<'  at ',file__m,':',(dec line__m),' expanded=',(dec expanded__m),' tested=',(dec tested__m),' recursive=',recursive),<'  refs:',;(' '&,)&.>refs
  functioncount=.functioncount+function__m
  end.
 macros=.macros,(<''),(<'macros=',(dec #Macros),' object_like=',(dec (#Macros)-functioncount),' function_like=',dec functioncount),(<'undefined:',;(' '&,)&.>/:~EverDefined-.MacroNames),<'builtins: __COUNTER__=',(dec 0{BuiltinCounts),' __FILE__=',(dec 1{BuiltinCounts),' __LINE__=',dec 2{BuiltinCounts
 'a b c d e'=.ConditionCounts
 conditions=.ConditionRecords,('';'== skipped regions =='),SkippedRegions,(<''),<'directives=',(dec #ConditionRecords),' taken=',(dec a),' not_taken=',(dec b),' skipped=',(dec c),' not_evaluated=',(dec d),' endif=',(dec e),' regions=',dec #SkippedRegions
 Diagnostics=:Diagnostics,<'errors=',(dec ErrorCount),' warnings=',dec WarningCount
 'output/preprocessed.txt'write_lines Preprocessed
 'output/includes.txt'write_lines includes
 'output/macros.txt'write_lines macros
 'output/conditionals.txt'write_lines conditions
 'output/diagnostics.txt'write_lines Diagnostics
)
main=:3 :0
 MacroNames=:Macros=:EverDefined=:Files=:FileNames=:Poisoned=:SaveNames=:Saves=:0$a:
 History=:Diagnostics=:ConditionRecords=:SkippedRegions=:Preprocessed=:0$a:
 IncludeTree=:,<'main.c'
  ErrorCount=:WarningCount=:Counter=:0
  BuiltinCounts=:3$0
  ConditionCounts=:5$0
 Current=:cocreate''
 display__Current=:'defines.txt'
  offset__Current=:0
  depth__Current=:_1
 defs=.readlines 'input/defines.txt'
  for_i. i.#defs  do.
  line=.i{::defs
   if. 0=#line  do.  continue.  end.
  at=.line i.'='
   if. at<#line  do. line=.' 'at}line  else. line=.line,' 1' end.
  At=:i+1
  install_definition lex_line line
  end.
 mark_line 'main.c';1;''
 process_file 'main.c';0
  for_i. /:MacroNames  do. unused i{Macros  end.
 write_reports''
 0
)
main''
