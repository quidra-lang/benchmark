ScriptPath=: >{:4!:3''
SourceDirectory=: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'terms.ijs'
load SourceDirectory,'unify.ijs'
load SourceDirectory,'reader.ijs'
load SourceDirectory,'database.ijs'
load SourceDirectory,'predicates.ijs'
atom_text=:3 :0
 s=.y
  if. -.Quoted  do. s  return.  end.
 plain=.(<s)e.'[]';'!';';'
  if. #s  do. plain=.plain+.(({.s)e.'abcdefghijklmnopqrstuvwxyz')*.*./s e.alnum
  plain=.plain+.(-.s-:'.')*.*./s e.symbols
  end.
  if. plain  do. s  return.  end.
 r=.''''
  for_c. s  do.
   select. c
   case. '\' do. r=.r,'\\'
   case. '''' do. r=.r,'\'''
   case. LF do. r=.r,'\n'
   case. 9{a. do. r=.r,'\t'
   case.  do. r=.r,c
   end.
  end.
 r,''''
)
write_term=:4 :0
 'limit operand'=.x
 t=.deref y
  if. kind__t=0  do.
  i=.NameVars i.t
   if. i=#NameVars  do. NameCounter=:NameCounter+1
  NameVars=:NameVars,t
  Names=:Names,<'_G',decimal NameCounter  end.
  i{::Names  return.
  end.
  if. kind__t=1  do. decimal value__t  return.  end.
 name=.value__t
  if. kind__t=2  do.
  s=.atom_text name
   if. operand*.((<name)e.InfixNames,PrefixNames) do. s=.'(',s,')' end.
  s  return.
  end.
  if. (name-:'.')*.2=#args__t  do.
  'es tail'=.unlist t
  parts=.0$a:
   for_e. es  do. parts=.parts,<(999;0)write_term e  end.
  s=.'[',','join parts
   if. -.(kind__tail=2)*.value__tail-:'[]' do. s=.s,'|',(999;0)write_term tail  end.
  s,']' return.
  end.
 i=.InfixNames i.<name
  if. (2=#args__t)*.i<#InfixNames  do.
  p=.i{InfixPriority
  typ=.i{::InfixType
  l=.((p-typ~:'yfx');1)write_term 0{args__t
  r=.((p-typ~:'xfy');1)write_term 1{args__t
   if. name-:',' do. s=.l,',',r
   elseif. ({.name)e.letters  do. s=.l,' ',name,' ',r
   else.
    if. #l  do.  if. ({:l)e.symbols  do. l=.l,' ' end.  end.
    if. #r  do.  if. ({.r)e.symbols  do. r=.' ',r  end.  end.
   s=.l,name,r
   end.
   if. p>limit  do. s=.'(',s,')' end.
  s  return.
  end.
 i=.PrefixNames i.<name
  if. (1=#args__t)*.i<#PrefixNames  do.
  p=.i{PrefixPriority
  r=.(p;1)write_term 0{args__t
   if. #r  do.  if. ({.r)e.symbols,digits,'(' do. r=.' ',r  end.  end.
  s=.name,r
   if. p>limit  do. s=.'(',s,')' end.
  s  return.
  end.
 parts=.0$a:
  for_e. args__t  do. parts=.parts,<(999;0)write_term e  end.
 (atom_text name),'(',(','join parts),')'
)
written=:3 :0
 NameVars=:Names=:0$a:
  NameCounter=:0
  Quoted=:1
 (1200;0)write_term y
)
pi_text=:3 : 'written indicator_term y'
report=:3 :0
 'file line kind message'=.y
 Reports=:Reports,<file,':',(decimal line),': ',kind,': ',message
 fi=.('prelude.pl';'program.pl')i.<file
  if. kind-:'warning' do. WarnCounts=:(1+fi{WarnCounts)fi}WarnCounts  else. ErrorCounts=:(1+fi{ErrorCounts)fi}ErrorCounts  end.
)
consult_file=:3 :0
 file=.y
  fi=.('prelude.pl';'program.pl')i.<file
 source=.1!:1 <'input/',file
 lines=.<;._2 source
 Tokens=:1 lex source
  ReaderPosition=:0
  last=.''
  warned=.0$a:
  while. 1 do.
  first=.next_token''
   if. kind__first-:'eof' do.  break.  end.
  line=.line__first
   try.
   term=.read_clause''
   catch.
   t=.ReaderError
   ReaderPosition=:Tokens i.t
   Reports=:Reports,<file,':',(decimal line__t),':',(decimal column__t),': syntax error: ',ReaderMessage
    if. -.kind__t-:'eof' do. Reports=:Reports,(<'    ',(line__t-1){::lines),<((column__t+3)$' '),'^' end.
   ErrorCounts=:(1+fi{ErrorCounts)fi}ErrorCounts
    while. ReaderPosition<#Tokens  do.
    t=.ReaderPosition{Tokens
  ReaderPosition=:ReaderPosition+1
     if. (<kind__t)e.'end';'eof' do.  break.  end.
    end.
    continue.
   end.
  head=.term
  body=.a:
   if. (kind__term=3)*.(value__term-:':-')*.2=#args__term  do. head=.0{args__term
  body=.1{args__term  end.
  error=.a:
   if. kind__head=0 do. error=.atom 'instantiation_error'
   elseif. kind__head=1 do. error=.'callable'type_error head
   else.
   pk=.key head
    if. (<pk)e.ControlKeys,BuiltinKeys  do. error=.'permission_error'compound (atom 'modify'),(atom 'static_procedure'),indicator_term indicator head
    elseif. -.body-:a: do. ConversionFailed=:0
  converted=.goal_convert body
     if. ConversionFailed  do. error=.'callable'type_error body  else. body=.converted  end.
    end.
   end.
   if. -.error-:a: do. report file;line;'error';written error
   continue.  end.
  p=.find_predicate pk
   if. p-:a: do.
   p=.cocreate''
   key__p=:pk
  indicator__p=:indicator head
  clauses__p=:0$a:
   DatabaseKeys=:DatabaseKeys,<pk
  Database=:Database,p
   end.
   if. file-:'program.pl' do.
    if. #clauses__p  do. c=.{.clauses__p
     if. file__c-:'prelude.pl' do. report file;line;'warning';'redefining prelude procedure ',pi_text indicator__p
  clauses__p=:0$a: end.
    end.
   end.
  samefile=.0
   for_c. clauses__p  do.  if. file__c-:file  do. samefile=.1 end.  end.
   if. samefile*.(-.last-:pk)*.-.(<pk)e.warned  do. report file;line;'warning';'clauses of ',(pi_text indicator__p),' are not together'
  warned=.warned,<pk  end.
  c=.cocreate''
  head__c=:head
  body__c=:body
  file__c=:file
  line__c=:line
  clauses__p=:clauses__p,c
  last=.pk
  ClauseCounts=:(1+fi{ClauseCounts)fi}ClauseCounts
  singles=.0$a:
  repeated=.0$a:
   for_i. i.#VarNames  do.
   n=.i{::VarNames
  count=.i{VarCounts
    if. ('_'~:{.n)*.count=1 do. singles=.singles,<n  end.
    if. ('_'={.n)*.(#n)>1 do.  if. count>1 do. repeated=.repeated,<n  end.  end.
   end.
   if. #singles  do. report file;line;'warning';'singleton variables: ',', 'join singles  end.
   if. #repeated  do. report file;line;'warning';'variables starting with _ occur more than once: ',', 'join repeated  end.
  end.
)
undefined_check=:3 :0
 warned=.0$a:
  for_p. Database  do.  for_c. clauses__p  do.
   if. body__c-:a: do.  continue.  end.
  pending=.,body__c
   while. #pending  do.
   g=.{.pending
  pending=.}.pending
    if. kind__g<2 do.  continue.  end.
   pk=.key g
    if. (<pk)e.',/2';';/2';'->/2' do. pending=.args__g,pending
    elseif. (<pk)e.'\+/1';'call/1' do. pending=.(0{args__g),pending
    elseif. pk-:'findall/3' do. pending=.(1{args__g),pending
    elseif. pk-:'catch/3' do. pending=.(0 2{args__g),pending
    elseif. -.(<pk)e.ControlKeys,BuiltinKeys,DatabaseKeys,warned  do.
    report file__c;line__c;'warning';'undefined procedure ',(pi_text indicator g),' called from ',pi_text indicator__p
    warned=.warned,<pk
    end.
   end.
  end.  end.
)
listing=:3 :0
 result=.0$a:
  for_p. Database  do.
   if. #result  do. result=.result,<'' end.
   for_c. clauses__p  do.
   vs=.variables head__c
    if. -.body__c-:a: do. vs=.vs,variables body__c  end.
   NameVars=:~.vs
  Names=:0$a:
  Quoted=:1
  NameCounter=:0
  n=.0
    for_v. NameVars  do.
     if. 1=+/vs=v  do. Names=:Names,<'_'
     else.
     name=.,(26|n){'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
      if. n>:26 do. name=.name,decimal <.n%26 end.
     Names=:Names,<name
  n=.n+1
     end.
    end.
   h=.(1200;0)write_term head__c
    if. body__c-:a: do. result=.result,<h,'.'
    else.
    result=.result,<h,' :-'
    body=.body__c
  goals=.0$a:
     while. (kind__body=3)*.(value__body-:',')*.2=#args__body  do. goals=.goals,0{args__body
  body=.1{args__body  end.
    goals=.goals,body
     for_i. i.#goals  do.
     suffix=.'.'
      if. i< <:#goals  do. suffix=.',' end.
     result=.result,<'    ',((999;0)write_term i{goals),suffix
     end.
    end.
   end.
  end.
 result
)
profile_index=:3 :0
 i=.ProfileKeys i.<y
  if. i=#ProfileKeys  do. ProfileKeys=:ProfileKeys,<y
  ProfileCalls=:ProfileCalls,0
  ProfileTries=:ProfileTries,0 end.
 i
)
inference=:3 :0
  if. Inferences=20000 do. LimitExceeded=:1
  13!:8]3 end.
 Inferences=:Inferences+1
 i=.profile_index y
 ProfileCalls=:(1+i{ProfileCalls)i}ProfileCalls
)
choice=:4 :0
 f=.cocreate''
 kind__f=:x
  trail__f=:#Trail
  resume__f=:y
 ChoiceStack=:ChoiceStack,f
 Choicepoints=:Choicepoints+1
 f
)
cut=:3 : 'ChoiceStack=:y{.ChoiceStack'
entry=:3 : '<y'
marker=:4 :0
 t=.4 term x
 marker_data__t=:y
 t
)
try_clause=:3 :0
 'goal clause barrier context continuation'=.y
 idx=.profile_index key goal
 ProfileTries=:(1+idx{ProfileTries)idx}ProfileTries
 es=.copy_clause clause
  if. -.goal unify {.es  do. 0 return.  end.
 Goals=:continuation
  if. 1<#es  do. Goals=.(entry (1{es);barrier;context),Goals  end.
 1
)
answer=:3 :0
 NameVars=:Names=:0$a:
  NameCounter=:0
  Quoted=:1
 values=.0$a:
  for_v. QueryVars  do. values=.values,deref v  end.
  for_i. i.#values  do. v=.i{values
   if. kind__v=0 do.  if. -.v e.NameVars  do. NameVars=:NameVars,v
  Names=:Names,i{QueryNames  end.  end.
  end.
 items=.0$a:
  for_i. i.#values  do.
  v=.i{values
  name=.i{::QueryNames
   if. kind__v=0 do.
   previous=.I.(i{.values)=v
    if. #previous  do. items=.items,<(({:previous){::QueryNames),' = ',name  end.
   else. items=.items,<name,' = ',(699;1)write_term v  end.
  end.
  if. 0=#items  do. 'true' else. ', 'join items  end.
)
raise_ball=:3 :0
 ball=.copy_term Ball
 f=.CurrentContext
  while. -.f-:a: do.
  idx=.ChoiceStack i.f
  ChoiceStack=:idx{.ChoiceStack
  undo trail__f
  mark=.#Trail
   if. (copy_term ball)unify catcher__f  do.
   h=.#ChoiceStack
   Goals=.(entry ('call'compound ,recovery__f);h;parent__f),resume__f
   1 return.
   end.
  undo mark
  f=.parent__f
  end.
 AnswerLines=:AnswerLines,<'uncaught exception: ',written ball
 Finished=:1
 0
)
backtrack=:3 :0
  while. 1 do.
  Backtracks=:Backtracks+1
   while. #ChoiceStack  do.
   f=.{:ChoiceStack
   undo trail__f
    if. kind__f-:'CATCH' do. ChoiceStack=:}:ChoiceStack  else.  break.  end.
   end.
   if. 0=#ChoiceStack  do. AnswerLines=:AnswerLines,<'false.'
  Finished=:1
  0 return.  end.
  f=.{:ChoiceStack
   select. kind__f
   case. 'ALT' do. ChoiceStack=:}:ChoiceStack
  Goals=:resume__f
  1 return.
   case. 'CLAUSES' do.
   n=.next__f
  cs=.clauses__f
    if. n= <:#cs  do. ChoiceStack=:}:ChoiceStack  else. next__f=:n+1 end.
    if. try_clause goal__f;(n{cs);barrier__f;context__f;resume__f  do. 1 return.  end.
   case. 'BETWEEN' do.
   CurrentContext=:context__f
  CurrentPI=:'between';3
   inference 'between/3'
   n=.next__f
    if. n=upper__f  do. ChoiceStack=:}:ChoiceStack  else. next__f=:n+1 end.
    if. variable__f unify integer n  do. Goals=:resume__f
  1 return.  end.
   case. 'LENGTH' do.
   CurrentContext=:context__f
  CurrentPI=:'length';2
   inference 'length/2'
   n=.next__f
  next__f=:n+1
   xs=.0$a:
    for_i. i.n-prefix__f  do. xs=.xs,fresh'' end.
    if. tail__f unify proper_list xs  do.  if. number__f unify integer n  do. Goals=:resume__f
  1 return.  end.  end.
   case. 'FINDALL' do.
   ChoiceStack=:}:ChoiceStack
    if. result__f unify proper_list collected__f  do. Goals=:resume__f
  1 return.  end.
   end.
  end.
)
execute_goal=:3 :0
 'goal barrier context'=.y
 continuation=.Goals
 CurrentContext=:context
 goal=.deref goal
  if. kind__goal=4 do.
  data=.marker_data__goal
   select. value__goal
   case. 'ITE' do. cut data
   case. 'NAF' do. cut data
  Failed=:1
   case. 'EXIT' do.  if. #ChoiceStack  do.  if. data-:{:ChoiceStack  do. ChoiceStack=:}:ChoiceStack  end.  end.
   case. 'COLLECT' do. f=.data
  collected__f=:collected__f,copy_term template__f
  Failed=:1
   end.
   return.
  end.
 pk=.key goal
  es=.args__goal
  if. #es  do. a=.deref 0{es  end.
  if. 1<#es  do. b=.deref 1{es  end.
  if. 2<#es  do. c=.deref 2{es  end.
  select. pk
  case. ',/2' do. Goals=.(entry a;barrier;context),(entry b;barrier;context),continuation
  case. '!/0' do. cut barrier
  case. ';/2' do.
  h=.#ChoiceStack
  f=.'ALT'choice (entry b;barrier;context),continuation
   if. (kind__a=3)*.(value__a-:'->')*.2=#args__a  do.
   Goals=.(entry (0{args__a);(h+1);context),(entry ('ITE'marker h);barrier;context),(entry (1{args__a);barrier;context),continuation
   else. Goals=.(entry a;barrier;context),continuation  end.
  case. '->/2' do.
  h=.#ChoiceStack
  Goals=.(entry a;h;context),(entry ('ITE'marker h);barrier;context),(entry b;barrier;context),continuation
  case. '\+/1' do.
  h=.#ChoiceStack
  f=.'ALT'choice continuation
  Goals=.(entry ('call'compound ,a);barrier;context),(entry ('NAF'marker h);barrier;context),continuation
  case. 'catch/3' do.
  f=.'CATCH'choice continuation
  catcher__f=:b
  recovery__f=:c
  parent__f=:context
  Goals=.(entry ('call'compound ,a);barrier;f),(entry ('EXIT'marker f);barrier;context),continuation
  case.  do.
  CurrentPI=:indicator goal
   if. (value__goal-:'call')*.(#es)e.1+i.8 do.
    if. kind__a=0 do. builtin_error atom 'instantiation_error' end.
    if. kind__a=1 do. builtin_error 'callable'type_error a  end.
   g=.a
    if. 1<#es  do. g=.value__a compound args__a,}.es  end.
   ConversionFailed=:0
   converted=.goal_convert g
    if. ConversionFailed  do. builtin_error 'callable'type_error g  end.
   Goals=.(entry converted;(#ChoiceStack);context),continuation
    return.
   end.
  inference pk
   select. pk
   case. 'throw/1' do.  if. kind__a=0 do. builtin_error atom 'instantiation_error' else. Ball=:a
  13!:8]3 end.
   case. 'findall/3' do.
   f=.'FINDALL'choice continuation
   template__f=:a
  result__f=:c
  collected__f=:0$a:
   Goals=.(entry ('call'compound ,b);barrier;context),entry ('COLLECT'marker f);barrier;context
   case. 'between/3' do.
   lo=.check_integer a
  hi=.check_integer b
    if. -.kind__c e.0 1 do. builtin_error 'integer'type_error c  end.
    if. kind__c=1 do. Failed=: -. (value__c>:lo)*.value__c<:hi
    elseif. lo>hi  do. Failed=:1
    else.
     if. lo<hi  do. f=.'BETWEEN'choice continuation
  upper__f=:hi
  variable__f=:c
  next__f=:lo+1
  context__f=:context  end.
    Failed=: -.c unify integer lo
    end.
   case. 'length/2' do.
    if. -.kind__b e.0 1 do. builtin_error 'integer'type_error b  end.
    if. kind__b=1 do.  if. value__b<0 do. builtin_error 'not_less_than_zero'domain_error b  end.  end.
   'xs tail'=.unlist a
  k=.#xs
    if. (kind__tail=2)*.value__tail-:'[]' do. Failed=: -.b unify integer k
    elseif. kind__tail~:0 do. builtin_error 'list'type_error a
    elseif. kind__b=1 do.
     if. value__b<k  do. Failed=:1 else.
     xs=.0$a:
      for_i. i.value__b-k  do. xs=.xs,fresh'' end.
     Failed=: -.tail unify proper_list xs
     end.
    else.
    f=.'LENGTH'choice continuation
    tail__f=:tail
  number__f=:b
  prefix__f=:k
  next__f=:k+1
  context__f=:context
    Failed=: -.tail unify atom '[]'
     if. -.Failed  do. Failed=: -.b unify integer k  end.
    end.
   case.  do.
    if. (<pk)e.BuiltinKeys  do. Failed=: -.deterministic goal
    else.
    p=.find_predicate pk
     if. p-:a: do. builtin_error 'existence_error'compound (atom 'procedure'),indicator_term CurrentPI  end.
    cs=.goal candidates p
     if. 0=#cs  do. Failed=:1 else.
     h=.#ChoiceStack
      if. 1<#cs  do.
      f=.'CLAUSES'choice continuation
      goal__f=:goal
  clauses__f=:cs
  next__f=:1
  barrier__f=:h
  context__f=:context
      end.
     Failed=: -.try_clause goal;({.cs);h;context;continuation
     end.
    end.
   end.
  end.
)
run_query=:3 :0
 'query limit'=.y
 Goals=.,entry ('call'compound ,query);0;a:
 ChoiceStack=:0$a:
  Trail=:0$a:
 Inferences=:Choicepoints=:Backtracks=:Solutions=:0
 Finished=:LimitExceeded=:0
 AnswerLines=:0$a:
  QueryOutput=:''
  while. -.Finished  do.
   try.
    if. 0=#Goals  do.
    Solutions=:Solutions+1
    suffix=.' ;'
     if. (Solutions=limit)+.0=#ChoiceStack  do. suffix=.'.'
  Finished=:1 end.
    AnswerLines=:AnswerLines,<(answer''),suffix
     if. -.Finished  do. backtrack'' end.
    else.
    e=.{.Goals
  Goals=:}.Goals
  Failed=:0
    execute_goal >e
     if. Failed  do. backtrack'' end.
    end.
   catch.
    if. LimitExceeded  do. AnswerLines=:AnswerLines,<'inference limit exceeded'
  Finished=:1
    else. raise_ball'' end.
   end.
  end.
 0
)
main=:3 :0
 Database=:DatabaseKeys=:Reports=:0$a:
 ClauseCounts=:ErrorCounts=:WarnCounts=:0 0
 ProfileKeys=:0$a:
  ProfileCalls=:ProfileTries=:i.0
 consult_file 'prelude.pl'
 consult_file 'program.pl'
 undefined_check''
  for_i. i.2 do. Reports=:Reports,<((i{::'prelude.pl';'program.pl')),': clauses=',(decimal i{ClauseCounts),' errors=',(decimal i{ErrorCounts),' warnings=',decimal i{WarnCounts  end.
 count=.0
  for_p. Database  do. count=.count+#clauses__p  end.
 Reports=:Reports,<'database: predicates=',(decimal #Database),' clauses=',decimal count
 'output/consult.txt'write_lines Reports
 'output/listing.txt'write_lines listing''
 Answers=.0$a:
  Stats=.0$a:
  Writes=.''
  totals=.4$0
 lines=.readlines 'input/queries.txt'
  for_qi. i.#lines  do.
  line=.qi{::lines
  Answers=.Answers,<line
  Writes=.Writes,'== query ',(decimal qi+1),' ==',LF
  qpos=.1+line i.'?'
  limit=._
   if. qpos>1 do. limit=.0".(qpos-1){.line  end.
  offset=.qpos+2
  Tokens=:(offset+1) lex offset}.line
  ReaderPosition=:0
   try.
   q=.read_clause''
   t=.next_token''
    if. -.kind__t-:'eof' do. syntax_error t  end.
   catch.
   t=.ReaderError
   Answers=.Answers,<'syntax error at column ',(decimal column__t),': ',ReaderMessage
   Stats=.Stats,<'query ',(decimal qi+1),': syntax error'
    continue.
   end.
  QueryNames=:0$a:
  QueryVars=:0$a:
   for_i. i.#VarNames  do. n=.i{::VarNames
   if. '_'~:{.n  do. QueryNames=:QueryNames,<n
  QueryVars=:QueryVars,i{VarTerms  end.  end.
  run_query q;limit
  Answers=.Answers,AnswerLines
  Writes=.Writes,QueryOutput
   if. #QueryOutput  do.  if. LF~:{:QueryOutput  do. Writes=.Writes,LF  end.  end.
  Stats=.Stats,<'query ',(decimal qi+1),': solutions=',(decimal Solutions),' inferences=',(decimal Inferences),' choicepoints=',(decimal Choicepoints),' backtracks=',decimal Backtracks
  totals=.totals+Solutions,Inferences,Choicepoints,Backtracks
  undo 0
  end.
 's i c b'=.totals
 Stats=.Stats,(<'total: solutions=',(decimal s),' inferences=',(decimal i),' choicepoints=',(decimal c),' backtracks=',decimal b),<'== profile =='
 names=.0$a:
  for_k. ProfileKeys  do.
  raw=.>k
  slash=.raw i:'/'
  names=.names,<pi_text (slash{.raw);0".(slash+1)}.raw
  end.
 order=./:names
 order=.(\:order{ProfileCalls){order
  for_j. order  do.
  raw=.j{::ProfileKeys
  line=.(j{::names),' calls=',decimal j{ProfileCalls
   if. (<raw)e.DatabaseKeys  do. line=.line,' tries=',decimal j{ProfileTries  end.
  Stats=.Stats,<line
  end.
 'output/answers.txt'write_lines Answers
 Writes 1!:2 <'output/write_output.txt'
 'output/stats.txt'write_lines Stats
 0
)
main''
