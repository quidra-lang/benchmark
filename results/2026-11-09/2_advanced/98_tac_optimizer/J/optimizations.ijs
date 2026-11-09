initialize_rewrite=:3 :0
 Rewrites=:0$a:
  for_s. Instructions  do. Rewrites=:Rewrites,<,s  end.
 PassRecords=:0$a:
  PassCount=:0
)
finish_rewrite=:3 :0
 f=.y
  result=.0$a:
  n=.0
  for_s. code__f  do.
   if. kind__s-:'label' do. result=.result,s  else. result=.result,n{::Rewrites
  n=.n+1 end.
  end.
 code__f=:result
)
fold=:3 :0
 s=.y
  if. kind__s-:'if' do.
   if. (isconst a__s)*.isconst b__s  do.
    if. op__s operation (num a__s),num b__s  do. t=.new_instruction 'goto'
  target__t=:target__s
  ,t  else. 0$a: end.
   else. ,s  end.
  elseif. kind__s-:'bin' do.
  a=.isconst a__s
  b=.isconst b__s
  val=.''
   if. a*.b  do.
    if. ((<op__s)e.'/';'%')*.0=num b__s  do. ,s  return.  end.
   val=.dec op__s operation (num a__s),num b__s
   elseif. a~:b  do.
    if. b do. n=.num b__s
  var=.a__s  else. n=.num a__s
  var=.b__s  end.
    if. ((op__s-:'+')*.n=0)+.((op__s-:'*')*.n=1)+.(b*.(n=0)*.op__s-:'-')+.(b*.(n=1)*.op__s-:'/') do. val=.var
    elseif. (op__s-:'*')*.n=0 do. val=.'0' end.
   end.
   if. #val  do. t=.new_instruction 'copy'
  dest__t=:dest__s
  a__t=:val
  ,t  else. ,s  end.
  else. ,s  end.
)
constant_pass=:3 :0
 initialize_rewrite''
  for_n. i.#Instructions  do.
   if. -.(n{InsBlock)e.Reachable  do.  continue.  end.
  old=.n{Instructions
  s=.clone old
  rd=.n{::RDBefore
   for_field. (<;._1 ' ','a b') do.
   field=.>field
    if. (<field)e.('a';'b'){~i.2 do.
     if. field-:'a' do. v=.a__s  else. v=.b__s  end.
     if. -.(<v)e.used old  do.  continue.  end.
    defs=.i.0
     for_i. rd  do.  if. v-:i{::DefinitionVars  do. defs=.defs,i  end.  end.
     if. 0=#defs  do.  continue.  end.
    values=.i.0
  good=.1
     for_i. defs  do.
     k=.i{DefinitionNumbers
      if. k=0 do. good=.0
   break.  end.
     d=.(k-1){Instructions
      if. -.(kind__d-:'copy')*.isconst a__d  do. good=.0
   break.  end.
     values=.values,num a__d
     end.
     if. good*.1=#~.values  do.
     value=.dec {.values
      if. field-:'a' do. a__s=:value  else. b__s=:value  end.
     PassRecords=:PassRecords,<'#',(dec n+1),': ',v,' -> ',value
     end.
    end.
   end.
  result=.fold s
   if. 0=#result  do. PassRecords=:PassRecords,<'#',(dec n+1),': delete ',instruction_text s
   elseif. -.(instruction_text s)-:instruction_text {.result  do.
    if. kind__s-:'if' do. record=.'fold goto ',target__s  else. record=.'fold ',instruction_text {.result  end.
   PassRecords=:PassRecords,<'#',(dec n+1),': ',record
   end.
  Rewrites=:(<result)n}Rewrites
  end.
 PassCount=:#PassRecords
 finish_rewrite y
)
copy_pass=:3 :0
 initialize_rewrite''
  for_n. i.#Instructions  do.
   if. -.(n{InsBlock)e.Reachable  do.  continue.  end.
  old=.n{Instructions
  s=.clone old
   for_field. (<;._1 ' ','a b') do.
    if. (>field)-:'a' do. v=.a__s  else. v=.b__s  end.
    if. -.(<v)e.used old  do.  continue.  end.
    for_i. n{::CopyBefore  do. 'a b'=.i{::Copies
     if. v-:a  do.
      if. (>field)-:'a' do. a__s=:b  else. b__s=:b  end.
     PassRecords=:PassRecords,<'#',(dec n+1),': ',v,' -> ',b
      break.
     end.
    end.
   end.
  Rewrites=:(<,s)n}Rewrites
  end.
 PassCount=:#PassRecords
 finish_rewrite y
)
cse_sources=:4 :0
 expression=.x
  n=.y
  b=.n{InsBlock
 before=.(b{::BlockIns)#~(b{::BlockIns)<n
  for_i. |.before  do. s=.i{Instructions
   if. expression-:expression_text s  do. ,i  return.  end.  end.
 queue=.(b{::Predecessors)intersect Reachable
  seen=.i.0
  sources=.i.0
  while. #queue  do.
  p=.{.queue
  queue=.}.queue
   if. p e.seen  do.  continue.  end.
  seen=.seen,p
  found=.0
   for_i. |.p{::BlockIns  do. s=.i{Instructions
    if. expression-:expression_text s  do. sources=.sources,i
  found=.1
   break.  end.
   end.
   if. -.found  do. queue=.queue,((p{::Predecessors)intersect Reachable) end.
  end.
 /:~~.sources
)
expression_text=:expression
cse_pass=:3 :0
 f=.y
 initialize_rewrite''
 candidates=.i.0
  groups=.0$a:
  for_n. i.#Instructions  do.
   if. -.(n{InsBlock)e.Reachable  do.  continue.  end.
  s=.n{Instructions
  ex=.expression s
   if. (#ex)*.(Expressions i.<ex)e.n{::ExprBefore  do. candidates=.candidates,n
  groups=.~.groups,<ex  end.
  end.
  for_ex. groups  do.
  ex=.>ex
  cs=.i.0
  src=.i.0
   for_n. candidates  do. s=.n{Instructions
   if. ex-:expression s  do. cs=.cs,n
  src=.src,ex cse_sources n  end.  end.
  src=.( /:~~.src)-.candidates
  temp__f=:temp__f+1
  temp=.'_t',dec temp__f
   for_n. src  do.
   s=.clone n{Instructions
  d=.dest__s
  dest__s=:temp
   move=.new_instruction 'copy'
  dest__move=:d
  a__move=:temp
   Rewrites=:(<s,move)n}Rewrites
   end.
   for_n. cs  do.
   old=.n{Instructions
  s=.new_instruction 'copy'
  dest__s=:dest__old
  a__s=:temp
   Rewrites=:(<,s)n}Rewrites
   end.
  PassRecords=:PassRecords,<ex,': ',temp,' sources=',(','join ('#'&,)@dec&.><"0 src+1),' replaced=',','join ('#'&,)@dec&.><"0 cs+1
  PassCount=:PassCount+#cs
  end.
 finish_rewrite f
)
dce_pass=:3 :0
 initialize_rewrite''
 records=.(#Instructions)$<''
  for_b. Reachable  do.
  live=.b{::LiveOut
   for_n. |.b{::BlockIns  do.
   s=.n{Instructions
   self=.(kind__s-:'copy')*.dest__s-:a__s
   dead=.((<kind__s)e.(<;._1 ' ','copy bin load'))*.-.(<dest__s)e.live
    if. self+.dead  do. Rewrites=:(<0$a:)n}Rewrites
  records=:(<'#',(dec n+1),': delete ',instruction_text s)n}records
    else.
     if. (kind__s-:'call')*.(#dest__s)*.-.(<dest__s)e.live  do.
     records=:(<'#',(dec n+1),': unused result ',instruction_text s)n}records
     t=.clone s
  dest__t=:''
  Rewrites=:(<,t)n}Rewrites
     end.
    live=.live live_transfer s
    end.
   end.
  end.
 PassRecords=:records#~0<#&>records
 PassCount=:#PassRecords
 finish_rewrite y
)
licm_pass=:3 :0
 f=.y
 initialize_rewrite''
 sizes=.i.0
  for_l. Loops  do. sizes=.sizes,#blocks__l  end.
  for_l. ( /:sizes){Loops  do.
  ns=.I.InsBlock e.blocks__l
  marked=.i.0
  changed=.1
   while. changed  do.
   changed=.0
    for_n. ns-.marked  do.
    s=.n{Instructions
     if. -.(<kind__s)e.(<;._1 ' ','copy bin load') do.  continue.  end.
    good=.1
     if. kind__s-:'load' do.  for_j. ns  do. t=.j{Instructions
   if. (kind__t-:'call')+.((kind__t-:'store')*.array__t-:array__s) do. good=.0 end.  end.  end.
     for_v. used s  do.
     defs=.i.0
      for_di. n{::RDBefore  do.  if. (>v)-:di{::DefinitionVars  do. defs=.defs,di{DefinitionNumbers  end.  end.
     inside=.(defs-.0)-.(defs-.0)-.ns+1
      if. #inside  do.  if. (1~:#defs)+.-.(<:{.inside)e.marked  do. good=.0 end.  end.
     end.
     if. good  do. marked=.marked,n
  changed=.1 end.
    end.
   end.
  move=.i.0
   for_n. marked  do.
   s=.n{Instructions
  x=.dest__s
  defs=.i.0
    for_j. ns  do. t=.j{Instructions
   if. dest__t-:x  do. defs=.defs,j  end.  end.
    if. (1~:#defs)+.(<x)e.header__l{::LiveIn  do.  continue.  end.
   b=.n{InsBlock
  domall=.1
    for_exit. exits__l  do.  if. -.b e.exit{::Dominators  do. domall=.0 end.  end.
   dangerous=.(kind__s-:'load')+.((kind__s-:'bin')*.((<op__s)e.'/';'%')*.((-.isconst b__s)+.b__s-:'0'))
   outside_live=.0
    for_o. outside__l  do. outside_live=.outside_live+.(<x)e.o{::LiveIn  end.
    if. -.domall+.(-.dangerous)*.-.outside_live  do.  continue.  end.
   good=.1
    for_v. used s  do.  for_di. n{::RDBefore  do.
     if. (>v)-:di{::DefinitionVars  do. def=.di{DefinitionNumbers
   if. def e.ns+1 do.  if. -.(def-1)e.move  do. good=.0 end.  end.  end.
    end.  end.
    if. good  do. move=.move,n  end.
   end.
   if. 0=#move  do.  continue.  end.
  h=.header__l
  outside=.(h{::Predecessors)-.blocks__l
  existing=.0
   if. (h~:0)*.1=#outside  do. p=.{.outside
  existing=.(p{::Successors)-:,h  end.
  hoisted=.move{Instructions
   for_n. move  do. Rewrites=:(<0$a:)n}Rewrites  end.
   if. existing  do.
   pos=.{:p{::BlockIns
  s=.pos{Instructions
    if. (<kind__s)e.'goto';'if' do. rs=.hoisted,s  else. rs=.s,hoisted  end.
   Rewrites=:(<rs)pos}Rewrites
   destination=.bname p
   finish_rewrite f
   else.
   pre__f=:pre__f+1
  name=.'_p',dec pre__f
    for_b. outside  do.
    n=.{:b{::BlockIns
  s=.n{Instructions
     if. (<kind__s)e.'goto';'if' do.  if. (<target__s)e.h{::BlockLabels  do. t=.clone s
  target__t=:name
  Rewrites=:(<,t)n}Rewrites  end.  end.
    end.
   label=.new_instruction 'label'
  target__label=:name
   result=.0$a:
  n=.0
  inserted=.0
   labels=.h{::BlockLabels
  first=.{.h{::BlockIns
    for_s. code__f  do.
    here=.0
     if. kind__s-:'label' do. here=.(<target__s)e.labels  else. here=.n=first  end.
     if. here*.-.inserted  do. result=.result,label,hoisted
  inserted=.1 end.
     if. kind__s-:'label' do. result=.result,s  else. result=.result,n{::Rewrites
  n=.n+1 end.
    end.
   code__f=:result
  destination=.'new ',name
   end.
  PassRecords=:,<(bname h),': hoist ',(','join ('#'&,)@dec&.><"0 move+1),' to ',destination
  PassCount=:#move
   return.
  end.
)
unreachable_pass=:3 :0
 f=.y
 initialize_rewrite''
  for_b. (i.#BlockIns)-.Reachable  do.
  PassRecords=:PassRecords,<'remove block ',bname b
   for_n. b{::BlockIns  do. Rewrites=:(<0$a:)n}Rewrites  end.
  end.
 kept=.0$a:
  n=.0
  for_s. code__f  do.
   if. kind__s-:'label' do.  if. n<#Instructions  do.  if. (n{InsBlock)e.Reachable  do. kept=.kept,s  end.  end.
   else. kept=.kept,n{::Rewrites
  n=.n+1 end.
  end.
 code__f=:kept
 result=.0$a:
  n=.0
  for_pos. i.#kept  do.
  s=.pos{kept
   if. kind__s-:'label' do. result=.result,s
   continue.  end.
  n=.n+1
  remove=.0
   if. (<kind__s)e.'goto';'if' do.
   j=.pos+1
    while. j<#kept  do. t=.j{kept
   if. -.kind__t-:'label' do.  break.  end.
   if. target__t-:target__s  do. remove=.1 end.
  j=.j+1 end.
   end.
   if. remove  do. PassRecords=:PassRecords,<'remove jump #',dec n  else. result=.result,s  end.
  end.
 targets=.0$a:
  for_s. result  do.  if. (<kind__s)e.'goto';'if' do. targets=.targets,<target__s  end.  end.
 kept=.0$a:
  for_s. result  do.
   if. (kind__s-:'label')*.-.(<target__s)e.targets  do. PassRecords=:PassRecords,<'remove label ',target__s  else. kept=.kept,s  end.
  end.
 code__f=:kept
 PassCount=:#PassRecords
)
