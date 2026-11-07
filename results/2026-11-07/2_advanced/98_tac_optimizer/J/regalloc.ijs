add_edge=:4 :0
 a=.Nodes i.<x
  b=.Nodes i.<y
  if. a~:b  do. Graph=:1 (<a,b)}Graph
  Graph=:1 (<b,a)}Graph  end.
)
allocate=:4 :0
 k=.x
  f=.y
 analyze f
 Nodes=:params__f
  for_n. i.#Instructions  do.  if. (n{InsBlock)e.Reachable  do. s=.n{Instructions
   if. #dest__s  do. Nodes=:Nodes,<dest__s  end.
  Nodes=:Nodes,used s  end.  end.
 Nodes=:/:~~.Nodes
 Graph=:((#Nodes),#Nodes)$0
 Cost=:(#Nodes)$0
  Partners=:(#Nodes)$<i.0
  pressure=.0
  for_n. i.#Instructions  do.
   if. -.(n{InsBlock)e.Reachable  do.  continue.  end.
  s=.n{Instructions
  live=.n{::LiveAfter
  def=.dest__s
  us=.used s
  pressure=.pressure>.((#live)>.#n{::LiveBefore)
   if. #def  do.
    for_v. live  do.  if. -.((>v)-:def)+.((kind__s-:'copy')*.(>v)-:a__s) do. def add_edge >v  end.  end.
   end.
  occurrences=.us
   if. #def  do. occurrences=.(<def),occurrences  end.
  weight=.10^(n{InsBlock){BlockDepth
   for_v. occurrences  do. i=.Nodes i.v
  Cost=:(weight+i{Cost)i}Cost  end.
  end.
  for_p. params__f  do.
  i=.Nodes i.p
  Cost=:(1+i{Cost)i}Cost
   for_v. ~.(0{::LiveIn),params__f  do. (>p)add_edge >v  end.
  end.
  for_s. code__f  do.
   if. (kind__s-:'copy')*.(-.isconst a__s)*.-.dest__s-:a__s  do.
   a=.Nodes i.<dest__s
  b=.Nodes i.<a__s
    if. (a<#Nodes)*.b<#Nodes  do. Partners=:(<~.(a{::Partners),b)a}Partners
  Partners=:(<~.(b{::Partners),a)b}Partners  end.
   end.
  end.
 remaining=.i.#Nodes
  stack=.i.0
  potentials=.0$a:
  while. #remaining  do.
  degrees=.+/remaining{"1 remaining{Graph
  small=.I.degrees<k
   if. #small  do.
   d=.<./small{degrees
  chosen=.{.(small#~d=small{degrees){remaining
   else.
   chosen=.{.remaining
  degree=.{.degrees
    for_i. i.#remaining  do. v=.i{remaining
  d=.i{degrees
     if. (v{Cost)*degree<(chosen{Cost)*d  do. chosen=.v
  degree=.d  end.
    end.
   potentials=.potentials,<((chosen{::Nodes),'(',(dec chosen{Cost),'/',(dec degree),')')
   end.
  stack=.stack,chosen
  remaining=.remaining-.chosen
  end.
 colors=.(#Nodes)$_1
  for_v. |.stack  do.
  neighbors=.I.v{Graph
  free=.(i.k)-.neighbors{colors
   if. 0=#free  do.  continue.  end.
  biased=.free intersect (v{::Partners){colors
   if. #biased  do. color=.<./biased  else. color=.{.free  end.
  colors=.color v}colors
  end.
 report=.,<'== ',name__f,' =='
 report=.report,<'nodes=',(dec #Nodes),' edges=',(dec <.+/,Graph%2),' registers=',dec k
  for_i. i.#Nodes  do.
  neighbors=.I.i{Graph
  report=.report,<(i{::Nodes),' degree=',(dec #neighbors),' cost=',(dec i{Cost),' neighbors=',','join neighbors{Nodes
  end.
 report=.report,(<'simplify: ',','join stack{Nodes),<'potential spills: ',','join potentials
 mapping=.Nodes
  for_i. i.#Nodes  do.
  target=.'spill'
   if. (i{colors)>:0 do. target=.'R',dec i{colors
  mapping=:(<target)i}mapping  end.
  report=.report,<(i{::Nodes),' -> ',target
  end.
 spilled=.(I.colors=_1){Nodes
 spilluses=.0
  spilldefs=.+/params__f e.spilled
  moves=.0
  newcode=.0$a:
  for_s. code__f  do.
  spilluses=.spilluses++/(used s)e.spilled
  spilldefs=.spilldefs+(<dest__s)e.spilled
  t=.clone s
   for_field. (<;._1 ' ','dest a b') do.
   field=.>field
    select. field
    case. 'dest' do. old=.dest__t
    case. 'a' do. old=.a__t
    case. 'b' do. old=.b__t
    end.
   i=.Nodes i.<old
    if. i<#Nodes  do.
     select. field
     case. 'dest' do. dest__t=:i{::mapping
     case. 'a' do. a__t=:i{::mapping
     case. 'b' do. b__t=:i{::mapping
     end.
    end.
   end.
   if. (kind__t-:'copy')*.dest__t-:a__t  do. moves=.moves+1 else. newcode=.newcode,t  end.
  end.
 allocated=.cocreate''
 name__allocated=:name__f
  code__allocated=:newcode
 params__allocated=:params__f
  for_i. i.#params__f  do. j=.Nodes i.i{params__f
  params__allocated=:(j{mapping)i}params__allocated  end.
 report=.report,<'summary: pressure=',(dec pressure),' used=',(dec #~.colors-. _1),' spilled=',(dec #spilled),' moves=',(dec moves),' spill_uses=',(dec spilluses),' spill_defs=',dec spilldefs
 report=.report,function_lines allocated
 allocated;report
)
