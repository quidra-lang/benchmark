intersect=:4 : 'x-.x-.y'
rd_transfer=:4 :0
 set=.x
  n=.y
  s=.n{Instructions
  if. #dest__s  do.
  remove=.i.0
   for_i. set  do.  if. dest__s-:i{::DefinitionVars  do. remove=.remove,i  end.  end.
  set=.(set-.remove),DefinitionNumbers i.n+1
  end.
 /:~~.set
)
live_transfer=:4 :0
 s=.y
 /:~~.(x-.<dest__s),used s
)
expr_transfer=:4 :0
 set=.x
  s=.y
  if. (<kind__s)e.'bin';'load' do. set=.~.set,Expressions i.<expression s  end.
 keep=.i.0
  for_i. set  do.
  ex=.i{ExpressionIns
  killed=.0
   if. kind__s-:'store' do. killed=.(kind__ex-:'load')*.array__s-:array__ex  end.
   if. kind__s-:'call' do. killed=.kind__ex-:'load' end.
   if. #dest__s  do. killed=.killed+.(<dest__s)e.expr_uses ex  end.
   if. -.killed  do. keep=.keep,i  end.
  end.
 /:~keep
)
copy_transfer=:4 :0
 set=.x
  s=.y
  if. #dest__s  do.
  keep=.i.0
   for_i. set  do. 'a b'=.i{::Copies
   if. -.(<dest__s)e.a;b  do. keep=.keep,i  end.  end.
  set=.keep
   if. (kind__s-:'copy')*.(-.isconst a__s)*.-.dest__s-:a__s  do. set=.~.set,Copies i.<dest__s;a__s  end.
  end.
 /:~set
)
solve_flow=:3 :0
 mode=.y
  n=.#BlockIns
 universe=.i.0
  if. mode=2 do. universe=.i.#Expressions  elseif. mode=3 do. universe=.i.#Copies  end.
 ins=.n$<i.0
  outs=.n$<universe
  iterations=.0
  if. mode=1 do. ins=.n$<0$a:
  outs=.n$<0$a: end.
 changed=.1
  while. changed  do.
  changed=.0
  iterations=.iterations+1
  order=.RPO
   if. mode=1 do. order=.Postorder  end.
   for_b. order  do.
    if. mode=1 do.
    out=.0$a:
     for_s. b{::Successors  do. out=.~.out,s{::ins  end.
    state=.out
     for_i. |.b{::BlockIns  do. state=.state live_transfer i{Instructions  end.
    in=./:~state
    old=.b{::ins
    else.
    preds=.(b{::Predecessors)intersect Reachable
     if. mode=0 do.
     in=.i.0
      if. b=0 do. in=.I.DefinitionNumbers=0 end.
      for_p. preds  do. in=.~.in,p{::outs  end.
     elseif. b=0 do. in=.i.0
     else. in=.universe
   for_p. preds  do. in=.in intersect p{::outs  end.  end.
    state=.in
     for_i. b{::BlockIns  do.
      select. mode
      case. 0 do. state=.state rd_transfer i
      case. 2 do. state=.state expr_transfer i{Instructions
      case. 3 do. state=.state copy_transfer i{Instructions
      end.
     end.
    out=./:~state
  old=.b{::outs
    end.
    if. mode=1 do. new=.in  else. new=.out  end.
    if. -.old-:new  do. changed=.1 end.
   ins=:(<in)b}ins
  outs=:(<out)b}outs
   end.
  end.
 ins;outs;iterations
)
analyze=:3 :0
 build_cfg y
 DefinitionVars=:params__y
  DefinitionNumbers=:(#params__y)$0
 Expressions=:Copies=:ExpressionIns=:0$a:
  for_n. i.#Instructions  do.
  s=.n{Instructions
   if. #dest__s  do. DefinitionVars=:DefinitionVars,<dest__s
  DefinitionNumbers=:DefinitionNumbers,n+1 end.
   if. -.(n{InsBlock)e.Reachable  do.  continue.  end.
   if. (<kind__s)e.'bin';'load' do.
   ex=.expression s
    if. -.(<ex)e.Expressions  do. Expressions=:Expressions,<ex
  ExpressionIns=:ExpressionIns,s  end.
   end.
   if. (kind__s-:'copy')*.(-.isconst a__s)*.-.dest__s-:a__s  do. Copies=:~.Copies,<dest__s;a__s  end.
  end.
 'RDIn RDOut RDIters'=:solve_flow 0
 'LiveIn LiveOut LiveIters'=:solve_flow 1
 'ExprIn ExprOut ExprIters'=:solve_flow 2
 'CopyIn CopyOut CopyIters'=:solve_flow 3
 RDBefore=:ExprBefore=:CopyBefore=:(#Instructions)$<i.0
 LiveBefore=:LiveAfter=:(#Instructions)$<0$a:
  for_b. Reachable  do.
  rd=.b{::RDIn
  ex=.b{::ExprIn
  cp=.b{::CopyIn
   for_i. b{::BlockIns  do.
   RDBefore=:(<rd)i}RDBefore
  ExprBefore=:(<ex)i}ExprBefore
  CopyBefore=:(<cp)i}CopyBefore
   rd=.rd rd_transfer i
  ex=.ex expr_transfer i{Instructions
  cp=.cp copy_transfer i{Instructions
   end.
  live=.b{::LiveOut
   for_i. |.b{::BlockIns  do. LiveAfter=:(<live)i}LiveAfter
  live=.live live_transfer i{Instructions
  LiveBefore=:(<live)i}LiveBefore  end.
  end.
)
