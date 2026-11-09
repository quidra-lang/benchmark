ScriptPath=: >{:4!:3''
SourceDirectory=: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'charset.ijs'
load SourceDirectory,'formatter.ijs'
load SourceDirectory,'backtrack_vm.ijs'
load SourceDirectory,'pike_vm.ijs'
read_lines=:3 : '<;._2 (1!:1 <y)'
node=:3 :0
 n=.cocreate''
 kind__n=:y
 children__n=:0$a:
 value__n=:''
 lower__n=:0
 upper__n=:0
 mode__n=:'greedy'
 n
)
parse_error=:3 :0
 'Error Column'=:y
 13!:8]3
)
peek=:3 : 'Position{Pattern'
advance=:3 : 'Position=:Position+1'
read_name=:3 :0
 start=.Position
  if. (peek'')e.LETTERS,'_'  do.
  advance''
   while. (peek'')e.WORD  do. advance'' end.
  end.
 name=.(Position-start){.start}.Pattern
  if. (0=#name)+.'>'~:peek''  do. parse_error 'invalid group name';Position+1  end.
 advance''
 name
)
class_item=:3 :0
 c=.peek''
 advance''
  if. c~:'\'  do. ,a.i.c  return.  end.
 at=.Position
 c=.peek''
  if. c=0{a.  do. parse_error 'trailing backslash';at  end.
 advance''
  if. c e.'dDwWsS'  do. escape_set c
  elseif. c='n'  do. ,10
  elseif. c='t'  do. ,9
  elseif. c e.LETTERS,DIGITS  do. parse_error 'invalid escape';at
  else. ,a.i.c  end.
)
parse_element=:3 :0
 start=.Position+1
 c=.peek''
 advance''
  select. c
  case. '('  do.
  mode=.'group'
  num=.0
   if. '?'=peek''  do.
   advance''
   t=.peek''
   advance''
    select. t
    case. ':'  do. mode=.'plain'
    case. '='  do. mode=.'ahead'
    case. '!'  do. mode=.'not'
    case. '<'  do.
    at=.Position+1
    name=.read_name''
     if. (<name)e.GroupNames  do. parse_error 'duplicate group name';at  end.
    GroupNames=:GroupNames,<name
    GroupNumbers=:GroupNumbers,Groups+1
    case.  do. parse_error 'invalid group';start
    end.
   end.
   if. mode-:'group'  do. Groups=:Groups+1
  num=.Groups  end.
  child=.parse_alternation''
   if. ')'~:peek''  do. parse_error 'missing )';start  end.
  advance''
   if. mode-:'plain'  do. child  return.  end.
  n=.node mode
  value__n=:num
  children__n=:,child
  n
  case. '['  do.
  neg=.'^'=peek''
   if. neg  do. advance'' end.
   if. ']'=peek''  do. parse_error 'empty class';Position+1  end.
  set=.i.0
   while. ']'~:peek''  do.
    if. (peek'')=0{a.  do. parse_error 'missing ]';start  end.
   at=.Position
   setitem=.(peek'')='\'
    if. setitem  do. setitem=.((Position+1){Pattern)e.'dDwWsS' end.
   a=.class_item''
    if. ('-'=peek'')*.((Position+1){Pattern)~:']'  do.
    dash=.Position+1
    advance''
     if. setitem  do. parse_error 'invalid range';dash  end.
    setitem=.(peek'')='\'
     if. setitem  do. setitem=.((Position+1){Pattern)e.'dDwWsS' end.
     if. (peek'')=0{a.  do. parse_error 'missing ]';start  end.
    b=.class_item''
     if. setitem+.({.a)>{.b  do. parse_error 'invalid range';dash  end.
    a=.({.a)+i.1+({.b)-{.a
    end.
   set=.set,a
   end.
  advance''
  n=.node 'class'
  value__n=:(/:~~.set);neg
  n
  case. '\'  do.
  c=.peek''
   if. c=0{a.  do. parse_error 'trailing backslash';start  end.
  advance''
   if. c e.'dDwWsS'  do.
   n=.node 'class'
   value__n=:(escape_set c);0
   elseif. c e.'bB'  do. n=.node 'assert'
  value__n=:('WORD';'NOTWORD'){::~c='B'
   elseif. c e.'nt'  do. n=.node 'lit'
  value__n=:a.{~(10 9){~c='t'
   elseif. c e.'123456789'  do.
   digits=.,c
    while. (peek'')e.DIGITS  do. digits=.digits,peek''
  advance'' end.
   n=.node 'backref'
   value__n=:0".digits
   Backrefs=:Backrefs,<n;start;0
   elseif. c='k'  do.
    if. '<'~:peek''  do. parse_error 'invalid escape';start  end.
   advance''
   n=.node 'backref'
   value__n=:read_name''
   Backrefs=:Backrefs,<n;start;1
   elseif. c e.LETTERS,DIGITS  do. parse_error 'invalid escape';start
   else. n=.node 'lit'
  value__n=:c  end.
  n
  case. '.'  do. node 'any'
  case. '^';'$'  do. n=.node 'assert'
  value__n=:('BOL';'EOL'){::~c='$'
  n
  case.  do. n=.node 'lit'
  value__n=:c
  n
  end.
)
parse_quantified=:3 :0
  if. (peek'')e.'*+?{'  do. parse_error 'nothing to repeat';Position+1  end.
 e=.parse_element''
  if. -.(peek'')e.'*+?{'  do. e  return.  end.
 start=.Position+1
  if. (<kind__e)e.(<;._1 ' ','assert ahead not')  do. parse_error 'nothing to repeat';start  end.
 c=.peek''
 advance''
  select. c
  case. '*'  do. m=.0
  n=._
  case. '+'  do. m=.1
  n=._
  case. '?'  do. m=.0
  n=.1
  case. '{'  do.
  digits=.''
   while. (peek'')e.DIGITS  do. digits=.digits,peek''
  advance'' end.
   if. 0=#digits  do. parse_error 'invalid quantifier';start  end.
  m=.0".digits
  n=.m
   if. ','=peek''  do.
   advance''
    if. '}'=peek''  do. n=._  else.
    digits=.''
     while. (peek'')e.DIGITS  do. digits=.digits,peek''
  advance'' end.
     if. 0=#digits  do. parse_error 'invalid quantifier';start  end.
    n=.0".digits
    end.
   end.
   if. '}'~:peek''  do. parse_error 'invalid quantifier';start  end.
  advance''
   if. (m>100)+. (n~:_)*.n>100  do. parse_error 'quantifier too large';start  end.
   if. m>n  do. parse_error 'quantifier range out of order';start  end.
  end.
 mode=.'greedy'
  if. '?'=peek''  do. mode=.'lazy'
  advance''  elseif. '+'=peek''  do. mode=.'possessive'
  advance'' end.
  if. (peek'')e.'*+?{'  do. parse_error 'nested quantifier';Position+1  end.
 r=.node 'repeat'
 children__r=:,e
 lower__r=:m
 upper__r=:n
 mode__r=:mode
 r
)
parse_concat=:3 :0
 es=.0$a:
  while. -.(peek'')e.'|)',0{a.  do. es=.es,parse_quantified'' end.
  if. 1=#es  do. {.es  else. n=.node 'concat'
  children__n=:es
  n  end.
)
parse_alternation=:3 :0
 es=.,parse_concat''
  while. '|'=peek''  do. advance''
  es=.es,parse_concat'' end.
  if. 1=#es  do. {.es  else. n=.node 'alt'
  children__n=:es
  n  end.
)
emit=:3 :0
 pc=.#Code
 Code=:Code,<y
 pc
)
patch=:4 : 'Code=: (<y) x}Code'
compile=:3 :0
 e=.y
  select. kind__e
  case. 'lit'  do. emit 'CHAR';value__e
  case. 'any'  do. emit 'ANY';''
  case. 'class'  do. emit 'CLASS';value__e
  case. 'assert'  do. emit 'ASSERT';value__e
  case. 'backref'  do. emit 'BACKREF';value__e
  case. 'group'  do.
  emit 'SAVE';2*value__e
  compile {.children__e
  emit 'SAVE';1+2*value__e
  case. 'ahead';'not'  do.
  p=.emit 'LOOK';((('AHEAD';'NOT'){::~kind__e-:'not');0)
  compile {.children__e
  emit 'MATCH';''
  p patch 'LOOK';((('AHEAD';'NOT'){::~kind__e-:'not');#Code)
  case. 'concat'  do.  for_c. children__e  do. compile c  end.
  case. 'alt'  do.
  jumps=.i.0
   for_i. i.<:#children__e  do.
   p=.emit 'SPLIT';0 0
   compile i{children__e
   jumps=.jumps,emit 'JMP';0
   p patch 'SPLIT';(p+1),#Code
   end.
  compile {:children__e
   for_p. jumps  do. p patch 'JMP';#Code  end.
  case. 'repeat'  do.
  child=.{.children__e
  m=.lower__e
  n=.upper__e
  lazy=.mode__e-:'lazy'
  atomic=.mode__e-:'possessive'
   if. atomic  do. outer=.emit 'LOOK';('ATOMIC';0)  end.
   if. n=_  do.
    if. m=0  do.
    p=.emit 'SPLIT';0 0
    compile child
    emit 'JMP';p
    targets=.(p+1),#Code
     if. lazy  do. targets=.|.targets  end.
    p patch 'SPLIT';targets
    else.
     for_i. i.m-1  do. compile child  end.
    start=.#Code
    compile child
    p=.emit 'SPLIT';0 0
    targets=.start,#Code
     if. lazy  do. targets=.|.targets  end.
    p patch 'SPLIT';targets
    end.
   else.
    for_i. i.m  do. compile child  end.
   splits=.i.0
    for_i. i.n-m  do.
    splits=.splits,emit 'SPLIT';0 0
    compile child
    end.
    for_p. splits  do.
    targets=.(p+1),#Code
     if. lazy  do. targets=.|.targets  end.
    p patch 'SPLIT';targets
    end.
   end.
   if. atomic  do. emit 'MATCH';''
  outer patch 'LOOK';('ATOMIC';#Code)  end.
  end.
 0
)
properties=:3 :0
 e=.y
 lo=.0
  hi=.0
  first=.i.0
  nullable=.1
  select. kind__e
  case. 'lit'  do. lo=.hi=.1
  nullable=.0
  first=.,a.i.value__e
   if. ('i'e.Flags)*.value__e e.LETTERS  do. first=.first,a.i.swapcase value__e  end.
  case. 'any'  do. lo=.hi=.1
  nullable=.0
  first=.allchars
   if. -.'s'e.Flags  do. first=.first-.10  end.
  case. 'class'  do. lo=.hi=.1
  nullable=.0
   for_c. allchars  do.  if. value__e class_test a.{~c  do. first=.first,c  end.  end.
  case. 'backref'  do. hi=._
  first=.allchars
  case. 'group'  do. properties {.children__e  return.
  case. 'concat';'alt'  do.
  alt=.kind__e-:'alt'
   if. alt  do. lo=._
  nullable=.0  end.
   for_c. children__e  do.
   'a b f nu'=.properties c
    if. alt  do. lo=.lo<.a
  hi=.hi>.b
  first=.first,f
  nullable=.nullable+.nu
    else. lo=.lo+a
  hi=.hi+b
     if. nullable  do. first=.first,f  end.
    nullable=.nullable*.nu
    end.
   end.
  case. 'repeat'  do.
  'a b first nu'=.properties {.children__e
  lo=.lower__e*a
   if. b=0  do. hi=.0  elseif. (b=_)+.upper__e=_  do. hi=._  else. hi=.upper__e*b  end.
  nullable=.nu+.lower__e=0
   if. upper__e=0  do. first=.i.0
  nullable=.1  end.
  end.
 lo;hi;(/:~~.first);nullable
)
scan_matches=:3 :0
 matches=.0$a:
 start=.0
  while. start<:#Subject  do.
   if. y-:'backtrack'  do. cap=.bt_search start  else. cap=.pike_search start  end.
   if. 0=#cap  do.  break.  end.
  matches=.matches,<cap
   if. SingleSearch  do.  break.  end.
  start=.1{cap
   if. (0{cap)=1{cap  do. start=.start+1  end.
  end.
 matches
)
template_parts=:3 :0
 s=.y
 p=.0
  parts=.0$a:
  TemplateError=:0
  while. p<#s  do.
  c=.p{s
  p=.p+1
   if. c~:'$'  do. parts=.parts,<0;,c
   continue.  end.
   if. p=#s  do. TemplateError=:1
   break.  end.
  c=.p{s
  p=.p+1
   if. c='$'  do. parts=.parts,<0;'$'
   continue.  end.
   if. c e.DIGITS  do. k=.0".,c
   elseif. c='{'  do.
   start=.p
    while. p<#s  do.  if. '}'=p{s  do.  break.  end.
  p=.p+1  end.
    if. p=#s  do. TemplateError=:1
   break.  end.
   t=.(p-start){.start}.s
  p=.p+1
    if. (#t)*.*./t e.DIGITS  do. k=.0".t
    elseif. (<t)e.GroupNames  do. k=.(GroupNames i.<t){GroupNumbers
    else. TemplateError=:1
   break.  end.
   else. TemplateError=:1
   break.  end.
   if. k>Groups  do. TemplateError=:1
   break.  end.
  parts=.parts,<1;k
  end.
 parts
)
capture_text=:4 :0
 'a b'=.((2*x)+0 1){y
  if. (a<0)+.b<0  do. '' else. (b-a){.a}.Subject  end.
)
expand_template=:4 :0
 r=.''
  for_part. x  do.
  'ref val'=.>part
   if. ref  do. r=.r,val capture_text y  else. r=.r,val  end.
  end.
 r
)
match_lines=:3 :0
 cap=.y
 r=.0$a:
  for_k. i.Groups+1  do.
   if. k=0  do. prefix=.'match' else. prefix=.'group ',decimal k  end.
  'a b'=.((2*k)+0 1){cap
   if. (a<0)+.b<0  do. r=.r,<prefix,' -'
   else. r=.r,<prefix,' ',(decimal a),'-',(decimal b),' ',quote k capture_text cap  end.
  end.
 r
)
main=:3 :0
 Patterns=.0$a:
  PatternNames=.0$a:
  Errors=.0$a:
  for_line. read_lines 'input/patterns.txt'  do.
  line=.>line
  k=.line i.' '
  name=.k{.line
  rem=.(k+1)}.line
  k=.rem i.' '
  flags=.k{.rem
  raw=.(k+1)}.rem
  Pattern=:raw,0{a.
  Position=:0
  Groups=:0
  GroupNames=:0$a:
  GroupNumbers=:i.0
  Backrefs=:0$a:
  Error=:''
  Column=:0
  Flags=:flags
  Code=:0$a:
   try.
   root=.parse_alternation''
    if. (peek'')~:0{a.  do. parse_error 'unmatched )';Position+1  end.
    for_ref. Backrefs  do.
    'n col named'=.>ref
     if. named  do.
      if. -.(<value__n)e.GroupNames  do. parse_error 'unknown group name';col  end.
     value__n=:(GroupNames i.<value__n){GroupNumbers
     elseif. value__n>Groups  do. parse_error 'invalid group reference';col  end.
    end.
   emit 'SAVE';0
   compile root
   emit 'SAVE';1
   emit 'MATCH';''
   prop=.properties root
   catch.
   prop=.0;0;(i.0);1
   Errors=.Errors,(<name,': ',Error,' at column ',decimal Column),(< '  ',raw),<((Column+1)$' '),'^'
   end.
  compatible=.1
   for_ins. Code  do.  if. (<0{::>ins)e.'BACKREF';'LOOK'  do. compatible=.0  end.  end.
  p=.cocreate''
  code__p=:Code
  flags__p=:flags
  groups__p=:Groups
  names__p=:GroupNames
  numbers__p=:GroupNumbers
  error__p=:Error
  properties__p=:prop
  compatible__p=:compatible
  Patterns=.Patterns,p
  PatternNames=.PatternNames,<name
  end.
  if. 0=#Errors  do. Errors=.,<'no errors' end.
 'output/errors.txt' write_lines Errors
 SubjectNames=.0$a:
  Subjects=.0$a:
  for_line. read_lines 'input/subjects.txt'  do.
  line=.>line
  k=.line i.' '
  SubjectNames=.SubjectNames,<k{.line
  Subjects=.Subjects,<unquote (k+1)}.line
  end.
 Results=.0$a:
  Programs=.0$a:
  Steps=.,<'command,engine,steps'
 commands=.read_lines 'input/commands.txt'
  for_ci. i.#commands  do.
  line=.ci{::commands
  words=.<;._1 ' ',line
  command=.0{::words
  Results=.Results,<'#',(decimal ci+1),' ',line
  replace=.command-:'REPLACE'
  pi=.1+replace
  pname=.pi{::words
  p=.(PatternNames i.<pname){Patterns
   if. #error__p  do. Results=.Results,<'invalid pattern'
   continue.  end.
  Code=:code__p
  Flags=:flags__p
  Groups=:groups__p
  GroupNames=:names__p
  GroupNumbers=:numbers__p
   if. command-:'LIST'  do.
   Results=.Results,<'instructions ',decimal #Code
   'lo hi first nullable'=.properties__p
   max=.decimal hi
    if. hi=_  do. max=.'inf' end.
   names=.0$a:
    for_i. i.#GroupNames  do. names=.names,< (i{::GroupNames),':',decimal i{GroupNumbers  end.
    if. 0=#names  do. names=.,<'-' end.
   fs=.'-'
    if. #first  do. fs=.set_notation first;0  end.
   Programs=.Programs,<'=== ',pname
   Programs=.Programs,<'flags=',Flags,' groups=',(decimal Groups),' names=',(','join names),' length=',(decimal lo),'..',max,' first=',fs,' pike=',(('no';'yes'){::~compatible__p),' size=',decimal #Code
    for_i. i.#Code  do. Programs=.Programs,<(decimal i),' ',format_instruction i{::Code  end.
    continue.
   end.
  Subject=: (SubjectNames i.<((pi+1){::words)){::Subjects
  parts=.0$a:
   if. replace  do.
   spaces=.I.line=' '
   parts=.template_parts unquote (1+3{spaces)}.line
    if. TemplateError  do. Results=.Results,<'invalid template'
   continue.  end.
   end.
  FullMatch=:command-:'MATCH'
  SingleSearch=:FullMatch+.(command-:'SEARCH')+.replace*.('FIRST'-:1{::words)
  BTSteps=:0
  BTAborted=:0
  PikeSteps=:0
  bm=.0$a:
   try. bm=.scan_matches 'backtrack'  catch.  end.
  Steps=.Steps,<(decimal ci+1),',backtrack,',decimal BTSteps
   if. compatible__p  do.
   pm=.scan_matches 'pike'
   Steps=.Steps,<(decimal ci+1),',pike,',decimal PikeSteps
    if. BTAborted  do. matches=.pm
  label=.'pike (backtrack: TOO_MANY_STEPS)'
    elseif. -.bm-:pm  do. Results=.Results,<'MISMATCH'
   continue.
    else. matches=.bm
  label=.'both' end.
   elseif. BTAborted  do. Results=.Results,<'TOO_MANY_STEPS'
   continue.
   else. matches=.bm
  label=.'backtrack' end.
  Results=.Results,<'engine ',label
   select. command
   case. 'MATCH';'SEARCH'  do.
    if. 0=#matches  do. Results=.Results,<'no match' else. Results=.Results,match_lines 0{::matches  end.
   case. 'FINDALL'  do.
   Results=.Results,<'matches ',decimal #matches
    for_cap. matches  do. Results=.Results,match_lines >cap  end.
   case. 'REPLACE'  do.
   out=.''
  start=.0
    for_cap. matches  do.
    cap=.>cap
    out=.out,((0{cap)-start){.start}.Subject
    out=.out,parts expand_template cap
    start=.1{cap
    end.
   out=.out,start}.Subject
   Results=.Results,(<'replacements ',decimal #matches),<'result ',quote out
   case. 'SPLIT'  do.
   Results=.Results,<'pieces ',decimal 1+#matches
   start=.0
    for_cap. matches  do.
    cap=.>cap
    Results=.Results,<'piece ',quote ((0{cap)-start){.start}.Subject
     for_k. 1+i.Groups  do.
      if. _1 e.((2*k)+0 1){cap  do. Results=.Results,<'group ',(decimal k),' -'
      else. Results=.Results,<'group ',(decimal k),' ',quote k capture_text cap  end.
     end.
    start=.1{cap
    end.
   Results=.Results,<'piece ',quote start}.Subject
   end.
  end.
  if. 0=#Programs  do. Programs=.,<'no programs' end.
 'output/results.txt' write_lines Results
 'output/programs.txt' write_lines Programs
 'output/steps.csv' write_lines Steps
 0
)
main''
