visit=:3 :0
  if. y e.Reachable  do.  return.  end.
 Reachable=:Reachable,y
  for_s. y{::Successors  do. visit s  end.
 Postorder=:Postorder,y
)
build_cfg=:3 :0
 Function=:y
 Instructions=:0$a:
  LabelNames=:0$a:
  LabelIns=:i.0
  Pending=:0$a:
  Leaders=:i.0
 previous=.'return'
  for_s. code__Function  do.
   if. kind__s-:'label' do. LabelNames=:LabelNames,<target__s
  LabelIns=:LabelIns,#Instructions
  Pending=:Pending,<target__s
   else.
    if. (0=#Instructions)+.(#Pending)+.(<previous)e.(<;._1 ' ','goto if return') do. Leaders=:Leaders,#Instructions  end.
   Instructions=:Instructions,s
  previous=.kind__s
  Pending=:0$a:
   end.
  end.
 n=.#Leaders
 BlockIns=:BlockLabels=:Successors=:Predecessors=:0$a:
 InsBlock=:(#Instructions)$0
  for_b. i.n  do.
  start=.b{Leaders
   if. b+1=n  do. finish=.#Instructions  else. finish=.(b+1){Leaders  end.
  ns=.start+i.finish-start
  BlockIns=:BlockIns,<ns
  BlockLabels=:BlockLabels,<(LabelIns=start)#LabelNames
  InsBlock=:b ns}InsBlock
  Successors=:Successors,<i.0
  Predecessors=:Predecessors,<i.0
  end.
  for_b. i.n  do.
  s=.({:b{::BlockIns){Instructions
  succ=.i.0
   if. -.(<kind__s)e.'goto';'return' do.  if. b+1<n  do. succ=.,b+1 end.  end.
   if. (<kind__s)e.'goto';'if' do. dest=.(LabelNames i.<target__s){LabelIns
  succ=.~.succ,dest{InsBlock  end.
  Successors=:(<succ)b}Successors
   for_t. succ  do. Predecessors=:(<(t{::Predecessors),b)t}Predecessors  end.
  end.
 Reachable=:Postorder=:i.0
 visit 0
 Reachable=:/:Reachable
 RPO=:|.Postorder
 Dominators=:n$<Reachable
 Dominators=:(<,0)0}Dominators
 changed=.1
  while. changed  do.
  changed=.0
   for_b. }.RPO  do.
   preds=.(b{::Predecessors)intersect Reachable
   d=.Reachable
    for_p. preds  do. d=.d intersect p{::Dominators  end.
   d=./:~ ~.d,b
    if. -.d-:b{::Dominators  do. changed=.1
  Dominators=:(<d)b}Dominators  end.
   end.
  end.
 Idom=:n$_1
  for_b. }.Reachable  do.
  ds=.(b{::Dominators)-.b
  sizes=.i.0
   for_d. ds  do. sizes=.sizes,#d{::Dominators  end.
  Idom=:( ({.\:sizes){ds)b}Idom
  end.
 Loops=:0$a:
  BlockDepth=:n$0
  for_h. Reachable  do.
  latches=.i.0
   for_t. Reachable  do.  if. (h e.t{::Successors)*.h e.t{::Dominators  do. latches=.latches,t  end.  end.
   if. 0=#latches  do.  continue.  end.
  blocks=.,h
  queue=.latches
   while. #queue  do.
   b=.{.queue
  queue=.}.queue
    if. b e.blocks  do.  continue.  end.
   blocks=.blocks,b
   queue=.queue,((b{::Predecessors)intersect Reachable)
   end.
  loop=.cocreate''
  header__loop=:h
  latches__loop=:latches
  blocks__loop=:/:blocks
  exits__loop=:i.0
  outside__loop=:i.0
   for_b. blocks  do.
   out=.(b{::Successors)-.blocks
   outside__loop=:~.outside__loop,out
   s=.({:b{::BlockIns){Instructions
    if. (#out)+.kind__s-:'return' do. exits__loop=:exits__loop,b  end.
   end.
  exits__loop=:/:exits__loop
  outside__loop=:/:outside__loop
  BlockDepth=:(1+blocks{BlockDepth)blocks}BlockDepth
  Loops=:Loops,loop
  end.
  for_l. Loops  do. depth__l=:header__l{BlockDepth  end.
)
bname=:3 : '''B'',dec y+1'
blist=:3 : ''',''join bname&.><"0 /:~y'
