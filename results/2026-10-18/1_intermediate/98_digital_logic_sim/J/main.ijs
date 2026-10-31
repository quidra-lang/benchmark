LF=:10{a.
say=:3 : '1!:2&2 y,LF'
num=:3 : ',''0'' 8!:2 y'
words=:3 : '(<;._1 '' '',y)-.<'''''
join=:4 : 0
 if. 0=#y do. '' return. end.
 (#x)}.;(<x),&.>y
)
fail=:3 : 0
 Reason=:y
 throw.
)
nameok=:4 : 0
 if. (0=#y)+.16<#y do. 0 return. end.
 (({.y)e.x)*.*./y e.x,'0123456789_'
)
number=:3 : 0
 if. (0=#y)+.9<#y do. fail 'bad number ',y end.
 if. (-.*./y e.'0123456789')+.((1<#y)*.'0'={.y) do. fail 'bad number ',y end.
 0".y
)
positive=:3 : 0
 n=.number y
 if. n=0 do. fail 'bad number ',y end.
 n
)
validvalue=:3 : 0
 if. -. (<y)e.'0';'1';'X' do. fail 'bad value ',y end.
 '01X'i.{.y
)
Types=:words 'AND OR NAND NOR XOR XNOR NOT BUF MUX2 DFF'
Names=:Modules=:0$a:
lookup=:3 : 0
 i=.Names i.<y
 if. i=#Names do. fail 'unknown module ',y end.
 i{::Modules
)
define=:3 : 0
 'header body start'=.y
 ErrorLine=:start
 w=.words header
 if. 5>#w do. fail 'bad module header' end.
 if. (-.'IN'-:2{::w)+.(1~:+/(3}.w)=<'OUT') do. fail 'bad module header' end.
 if. 'OUT'-:>{:w do. fail 'bad module header' end.
 m=.1{::w
 if. -. 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'nameok m do. fail 'bad module name ',m end.
 if. (<m)e.Names do. fail 'duplicate module ',m end.
 p=.3+(3}.w)i.<'OUT'
 ins=.3}.p{.w
 outs=.(>:p)}.w
 ports=.0$a:
 for_s. ins,outs do.
  if. -. 'abcdefghijklmnopqrstuvwxyz'nameok >s do. fail 'bad name ',>s end.
  if. s e.ports do. fail 'duplicate port ',>s end.
  ports=.ports,s
 end.
 driven=.ins
 used=.items=.reads=.0$a:
 readlines=.i.0
 gc=.0
 for_b. i.#body do.
  ErrorLine=:start+1+b
  a=.words b{::body
  typ=.Types i.{.a
  if. typ<10 do.
   if. 5>#a do. fail 'bad gate syntax' end.
   if. (-.'->'-:(_3){::a)+.1~:+/a=<'->' do. fail 'bad gate syntax' end.
   gn=.1{::a
   if. -. 'abcdefghijklmnopqrstuvwxyz'nameok gn do. fail 'bad name ',gn end.
   pins=.2}._3}.a
   c=.#pins
   ok=.c e.2+i.7
   if. typ e.6 7 do. ok=.c=1 elseif. typ=8 do. ok=.c=3 elseif. typ=9 do. ok=.c=2 end.
   if. -.ok do. fail 'bad input count ',(num c),' for ',typ{::Types end.
   out=.(_2){::a
   for_s. pins,<out do.
    if. -. 'abcdefghijklmnopqrstuvwxyz'nameok >s do. fail 'bad name ',>s end.
   end.
   delayword=._1{::a
   try. delay=.number delayword catcht. fail 'bad delay ',delayword end.
   if. delay>1000 do. fail 'bad delay ',delayword end.
   if. (<gn)e.used do. fail 'duplicate name ',gn end.
   if. (<out)e.driven do. fail 'multiple drivers for ',out end.
   driven=.driven,<out
   used=.used,<gn
   reads=.reads,pins
   readlines=.readlines,(#pins)#ErrorLine
   items=.items,<typ;gn;pins;out;delay
   gc=.>:gc
  elseif. 'INST'-:0{::a do.
   if. 3>#a do. fail 'bad instance syntax' end.
   gn=.1{::a
   if. -. 'abcdefghijklmnopqrstuvwxyz'nameok gn do. fail 'bad name ',gn end.
   child=.lookup 2{::a
   'ci co cb'=.child
   cp=.cs=.0$a:
   for_connection. 3}.a do.
    s=.>connection
    at=.s i.'='
    if. (1~:+/s='=')+.(at=0)+.at=<:#s do. fail 'bad connection ',s end.
    port=.at{.s
    signal=.(>:at)}.s
    if. -.(<port)e.ci,co do. fail 'unknown port ',port end.
    if. (<port)e.cp do. fail 'duplicate connection ',port end.
    if. -. 'abcdefghijklmnopqrstuvwxyz'nameok signal do. fail 'bad name ',signal end.
    cp=.cp,<port
    cs=.cs,<signal
   end.
   for_port. ci do. if. -.port e.cp do. fail 'unconnected input ',>port end. end.
   if. (<gn)e.used do. fail 'duplicate name ',gn end.
   for_j. i.#cp do.
    if. (j{cp)e.co do.
     s=.j{::cs
     if. (<s)e.driven do. fail 'multiple drivers for ',s end.
     driven=.driven,<s
    else.
     reads=.reads,j{cs
     readlines=.readlines,ErrorLine
    end.
   end.
   used=.used,<gn
   items=.items,<_1;gn;(2{::a);cp;<cs
  else. fail 'unknown statement ',0{::a end.
 end.
 reads=.reads,outs
 readlines=.readlines,(#outs)#start
 for_j. i.#reads do.
  if. -.(j{reads)e.driven do.
   ErrorLine=:j{readlines
   fail 'undriven signal ',j{::reads
  end.
 end.
 Names=:Names,<m
 Modules=:Modules,<ins;outs;<items
 say 'defined ',m,' inputs ',(num #ins),' outputs ',(num #outs),' gates ',(num gc),' instances ',num (#items)-gc
)
actual=:4 : 0
 'prefix keys vals'=.x
 i=.keys i.<y
 if. i<#keys do. i{::vals else. prefix,y end.
)
flatten=:3 : 0
 'm prefix keys vals'=.y
 'ins outs body'=.lookup m
 result=.0$a:
 for_item. body do.
  'typ gn a b c'=.>item
  if. typ=_1 do.
   mapped=.0$a:
   for_s. c do. mapped=.mapped,<(prefix;keys;<vals)actual >s end.
   result=.result,flatten a;(prefix,gn,'.');b;<mapped
  else.
   pins=.0$a:
   for_s. a do. pins=.pins,<(prefix;keys;<vals)actual >s end.
   result=.result,<(prefix,gn);typ;pins;((prefix;keys;<vals)actual b);c
  end.
 end.
 result
)
circuit=:3 : 0
 'ins outs body'=.lookup y
 raw=.flatten y;'';(0$a:);<0$a:
 signals=.ins
 for_g. raw do. signals=.signals,<3{::>g end.
 gates=.0$a:
 readers=.(#signals)#<i.0
 for_i. i.#raw do.
  'gn typ pins out delay'=.i{::raw
  indexes=.signals i.pins
  gates=.gates,<gn;typ;indexes;(signals i.<out);delay
  for_s. ~.indexes do. readers=.(<(s{::readers),i)s}readers end.
 end.
 known=.(#signals)$0
 known=.1(i.#ins)}known
 todo=.i.0
 for_i. i.#gates do.
  g=.i{::gates
  if. 9=1{::g do. known=.1(3{::g)}known else. todo=.todo,i end.
 end.
 order=.i.0
 while. #todo do.
  ready=.i.0
  for_i. todo do.
   g=.i{::gates
   if. *./(2{::g){known do.
    ready=.ready,i
    known=.1(3{::g)}known
   end.
  end.
  if. 0=#ready do. break. end.
  order=.order,ready
  todo=.todo-.ready
 end.
 y;ins;outs;signals;gates;order;readers;(0<#todo)
)
value=:4 : 0
 select. x
 case. 0;2 do. r=.2
  if. 0 e.y do. r=.0 elseif. *./y=1 do. r=.1 end.
 case. 1;3 do. r=.2
  if. 1 e.y do. r=.1 elseif. *./y=0 do. r=.0 end.
 case. 4;5 do. r=.2
  if. -.2 e.y do. r=.2|+/y end.
 case. 6;7 do. r=.{.y
 case. 8 do.
  's a b'=.y
  r=.2
  if. s=0 do. r=.a elseif. s=1 do. r=.b elseif. a=b do. r=.a end.
 end.
 if. x e.2 3 5 6 do. r=.r{1 0 2 end.
 r
)
combinational=:3 : 0
 c=.circuit y
 gs=.4{::c
 for_g. gs do. if. 9=1{::>g do. fail y,' is not combinational' end. end.
 if. 7{::c do. fail y,' has a combinational loop' end.
 if. 8<#1{::c do. fail 'too many inputs ',num #1{::c end.
 c
)
evaluate=:4 : 0
 'row fault fv'=.y
 'mn ins outs signals gates order readers loop'=.x
 vals=.(#signals)$2
 vals=.(((#ins)#2)#:row)(i.#ins)}vals
 if. (fault>:0)*.fault<#ins do. vals=.fv fault}vals end.
 for_i. order do.
  'gn typ pins out delay'=.i{::gates
  v=.typ value pins{vals
  if. out=fault do. v=.fv end.
  vals=.v out}vals
 end.
 (signals i.outs){vals
)
bitstring=:4 : '''01''{~(x#2)#:y'
arrivals=:4 : 0
 'mn ins outs signals gates order readers loop'=.y
 latest=.earliest=.previous=.(#signals)$_1
 if. x do.
  for_g. gates do.
   'gn typ pins out delay'=.>g
   if. typ=9 do. latest=.delay out}latest [ earliest=.delay out}earliest end.
  end.
 else.
  latest=.0(i.#ins)}latest
  earliest=.latest
 end.
 for_i. order do.
  'gn typ pins out delay'=.i{::gates
  usable=.pins#~0<:pins{latest
  if. #usable do.
   best=.usable{~(usable{latest)i.>./usable{latest
   latest=.(delay+best{latest)out}latest
   earliest=.(delay+<./usable{earliest)out}earliest
   previous=.best out}previous
  end.
 end.
 latest;earliest;previous
)
trace=:4 : 0
 'signals previous'=.x
 path=.,y
 while. 0<:y{previous do.
  y=.y{previous
  path=.y,path
 end.
 ' -> 'join path{signals
)
hierarchy=:4 : 0
 'ins outs body'=.lookup y
 for_g. body do.
  'typ gn a b c'=.>g
  if. typ=_1 do.
   say ((2*x)#' '),gn,' ',a
   (>:x)hierarchy a
  end.
 end.
)
Built=:0
reset=:3 : 0
 Values=.(#Signals)$2
 Time=:Processed=:Halted=:Serial=:0
 Queue=:0 4$0
 Records=:(#Signals)#<0 2$0
)
schedule=:3 : 0
 'time signal val'=.y
 Queue=:Queue,time,Serial,signal,val
 Serial=:>:Serial
 Queue=:(/:2{."1 Queue){Queue
)
requireSignal=:3 : 0
 i=.Signals i.<y
 if. i=#Signals do. fail 'unknown signal ',y end.
 i
)
requireInput=:3 : 0
 i=.Inputs i.<y
 if. i=#Inputs do. fail 'not an input ',y end.
 i
)
timearg=:3 : 0
 t=.number y
 if. t<Time do. fail 'time ',(num t),' is in the past' end.
 t
)
describe=:3 : 0
 r=.0$a:
 for_i. y do. r=.r,<(i{::Signals),'=',(i{Values){'01X' end.
 ' 'join r
)
run=:3 : 0
 events=.glitches=.0
 while. #Queue do.
  tau=.(<0,0){Queue
  if. tau>:y do. break. end.
  original=.Values
  changed=.(#Signals)$0
  count=.0
  while. #Queue do.
   if. tau~:(<0,0){Queue do. break. end.
   if. count=1000 do.
    say 'halted: oscillation at time ',num tau
    Queue=:0 4$0
    Time=:tau
    Halted=:1
    return.
   end.
   't serial s v'=.0{Queue
   Queue=:}.Queue
   count=.>:count
   events=.>:events
   Processed=:>:Processed
   old=.s{Values
   if. old=v do. continue. end.
   Values=:v s}Values
   changed=.1 s}changed
   for_i. s{::Readers do.
    'gn typ pins out delay'=.i{::Gates
    if. typ=9 do.
     if. (s={.pins)*.(old=0)*.v=1 do. schedule (tau+delay),out,(1{pins){Values end.
    else. schedule (tau+delay),out,typ value pins{Values end.
   end.
  end.
  different=.Values~:original
  glitches=.glitches++/changed*.-.different
  for_s. I.different do. Records=.(<(s{::Records),tau,s{Values)s}Records end.
  for_s. Watch do.
   if. s{different do. say (num tau),' ',(s{::Signals),' ',(s{Values){'01X' end.
  end.
 end.
 Time=:y
 say 'run ',(num y),' events ',(num events),' glitches ',(num glitches),' pending ',num #Queue
)
Commands=:words 'BUILD RESET SET APPLY PULSE CLOCK RUN WATCH UNWATCH SHOW CHECK PROBE WAVE HISTORY ACTIVITY STATUS MODULES NETLIST HIERARCHY STATS TRUTHTABLE EQUIV FAULTS CRITICAL PERIOD'
Arity=:1 0 3 2 3 4 1 1 1 0 2 1 2 1 1 0 0 1 1 1 1 2 1 1 1
command=:3 : 0
 w=.words y
 name=.0{::w
 cmd=.Commands i.<name
 if. cmd=#Commands do. fail 'unknown command ',name end.
 a=.}.w
 valid=.(cmd{Arity)=#a
 if. cmd e.7 8 9 do. valid=.(cmd{Arity)<:#a end.
 if. -.valid do. fail 'wrong argument count' end.
 if. (cmd e.1+i.15)*.-.Built do. fail 'no circuit' end.
 if. cmd e.2 3 4 5 6 do. if. Halted do. fail 'simulation halted' end. end.
 select. cmd
 case. 0 do.
  c=.circuit 0{::a
  'Circuit Inputs Outputs Signals Gates Order Readers Loop'=:c
  Built=:1
  Watch=:i.0
  reset 0
  say 'built ',Circuit,' signals ',(num #Signals),' gates ',num #Gates
 case. 1 do. reset 0 [ say 'reset'
 case. 2 do.
  t=.timearg 0{::a
  s=.requireInput 1{::a
  v=.validvalue 2{::a
  schedule t,s,v
  say 'set ',(s{::Signals),' ',(v{'01X'),' at ',num t
 case. 3 do.
  t=.timearg 0{::a
  bits=.1{::a
  if. ((#bits)~:#Inputs)+.-.*./bits e.'01X' do. fail 'bad vector ',bits end.
  for_s. i.#Inputs do. schedule t,s,'01X'i.s{bits end.
  say 'apply ',bits,' at ',num t
 case. 4;5 do.
  s=.requireInput 0{::a
  t=.timearg 1{::a
  half=.positive 2{::a
  if. cmd=4 do.
   schedule t,s,1
   schedule (t+half),s,0
   say 'pulse ',(s{::Signals),' ',(num t),' ',num t+half
  else.
   count=.positive 3{::a
   for_i. i.count do. schedule (t+i*half),s,2|i end.
   say 'clock ',(s{::Signals),' events ',(num count),' last ',num t+(count-1)*half
  end.
 case. 6 do.
  t=.number 0{::a
  if. t<:Time do. fail 'time ',(num t),' is not after ',num Time end.
  run t
 case. 7;8 do.
  ids=.i.0
  for_s. a do.
   i=.requireSignal >s
   if. cmd=7 do.
    if. i e.Watch,ids do. fail 'already watched ',>s end.
   else.
    if. (-.i e.Watch)+.i e.ids do. fail 'not watched ',>s end.
   end.
   ids=.ids,i
  end.
  if. cmd=7 do. Watch=:Watch,ids else. Watch=:Watch-.ids end.
  text=.'nothing'
  if. #Watch do. text=.' 'join Watch{Signals end.
  say 'watching ',text
 case. 9 do.
  ids=.i.0
  for_s. a do. ids=.ids,requireSignal >s end.
  if. #a do. say describe ids else.
   left=.describe i.#Inputs
   if. #left do. left=.left,' ' end.
   say left,'| ',describe Signals i.Outputs
  end.
 case. 10 do.
  s=.requireSignal 0{::a
  v=.validvalue 1{::a
  text=.'ok'
  if. v~:s{Values do. text=.'failed (',((s{Values){'01X'),')' end.
  say 'check ',(s{::Signals),'=',(v{'01X'),' ',text
 case. 11 do.
  s=.requireSignal 0{::a
  text=.(describe ,s),' driven by '
  if. s<#Inputs do. text=.text,'input' else.
   'gn typ pins out delay'=.(s-#Inputs){::Gates
   text=.text,gn,' ',(typ{::Types),' ',(describe pins),' delay ',num delay
  end.
  say text
  rs=.s{::Readers
  text=.'fanout ',num #rs
  for_i. rs do. text=.text,' ',0{::i{::Gates end.
  say text
 case. 12 do.
  start=.number 0{::a
  finish=.number 1{::a
  if. -. (start<finish)*.finish<:Time do. fail 'bad range ',(num start),' ',num finish end.
  if. 0=#Watch do. fail 'nothing watched' end.
  for_s. Watch do.
   record=.s{::Records
   wave=.''
   for_t. start+i.finish-start do.
    pos=.I.t>:0{"1 record
    v=.2
    if. #pos do. v=.(<({:pos),1){record end.
    wave=.wave,v{'01X'
   end.
   say (s{::Signals),' ',wave
  end.
 case. 13 do.
  s=.requireSignal 0{::a
  record=.s{::Records
  text=.'history ',(s{::Signals),' changes ',num #record
  for_pair. record do. text=.text,' ',(num {.pair),':',({:pair){'01X' end.
  say text
 case. 14 do.
  k=.positive 0{::a
  ids=./:Signals
  counts=.#&>Records
  ids=.(\:ids{counts){ids
  for_s. (k<.#ids){.ids do. say (s{::Signals),' ',num s{counts end.
 case. 15 do.
  say 'circuit ',Circuit,' time ',(num Time),' pending ',(num #Queue),' events ',(num Processed),' halted ',Halted{::'no';'yes'
  say 'values 0:',(num +/Values=0),' 1:',(num +/Values=1),' X:',num +/Values=2
 case. 16 do.
  say 'modules ',num #Names
  for_m. Names do.
   c=.circuit >m
   say (>m),' inputs ',(num #1{::c),' outputs ',(num #2{::c),' gates ',num #4{::c
  end.
 case. 17;18;19;20;21;22;23;24 do.
  m=.0{::a
  if. cmd=21 do.
   lookup m
   lookup 1{::a
  end.
  if. cmd e.20 21 22 do. c=.combinational m else. c=.circuit m end.
  'mn ins outs signals gates order readers loop'=.c
  n=.#ins
  total=.#signals
  select. cmd
  case. 17 do.
   say 'netlist ',m,' gates ',(num #gates),' signals ',num total
   for_g. gates do.
    'gn typ pins out delay'=.>g
    say gn,' ',(typ{::Types),' ',(' 'join pins{signals),' -> ',(out{::signals),' ',num delay
   end.
  case. 18 do.
   say m
   1 hierarchy m
  case. 19 do.
   depth=.'-'
   if. -.loop do.
    levels=.total$0
    for_i. order do.
     'gn typ pins out delay'=.i{::gates
     levels=.(>:>./pins{levels)out}levels
    end.
    depth=.num >./levels
   end.
   say 'stats ',m,' gates ',(num #gates),' signals ',(num total),' depth ',depth
   counts=.10$0
   for_g. gates do.
    t=.1{::>g
    counts=.(>:t{counts)t}counts
   end.
   text=.'types'
   for_t. I.counts>0 do. text=.text,' ',(t{::Types),' ',num t{counts end.
   say text
   fanout=.#&>readers
   best=.fanout i.>./fanout
   say 'max fanout ',(best{::signals),' ',num best{fanout
  case. 20 do.
   say ' 'join ins,(<'|'),outs
   for_r. i.2^n do.
    vals=.c evaluate r,_1,0
    say ' 'join (<"0 n bitstring r),(<'|'),<"0 vals{'01X'
   end.
  case. 21 do.
   other=.combinational 1{::a
   if. ((#ins)~:#1{::other)+.(#outs)~:#2{::other do. fail 'port mismatch' end.
   text=.'equivalent'
   for_r. i.2^n do.
    v=.c evaluate r,_1,0
    z=.other evaluate r,_1,0
    if. -.v-:z do.
     text=.'not equivalent at ',(n bitstring r),': ',(v{'01X'),' vs ',z{'01X'
     break.
    end.
   end.
   say text
  case. 22 do.
   normal=.0$a:
   for_r. i.2^n do. normal=.normal,<c evaluate r,_1,0 end.
   missing=.0$a:
   tests=.i.0
   for_s. i.total do.
    for_v. i.2 do.
     found=._1
     for_r. i.2^n do.
      if. -.(r{::normal)-:c evaluate r,s,v do. found=.r break. end.
     end.
     if. found<0 do. missing=.missing,<(s{::signals),'/',num v else. tests=.tests,found end.
    end.
   end.
   say 'faults ',(num 2*total),' detected ',num (2*total)-#missing
   for_f. missing do. say 'undetected ',>f end.
   text=.'tests'
   for_r. /:~~.tests do. text=.text,' ',n bitstring r end.
   say text
  case. 23;24 do.
   ff=.i.0
   for_i. i.#gates do. if. 9=1{::i{::gates do. ff=.ff,i end. end.
   if. (cmd=24)*.0=#ff do. fail m,' has no flip-flops' end.
   if. loop do. fail m,' has a combinational loop' end.
   'latest earliest previous'=.(cmd=24)arrivals c
   candidates=.i.0
   if. cmd=23 do.
    for_s. signals i.outs do.
     if. 0<:s{latest do.
      say (s{::signals),' min ',(num s{earliest),' max ',num s{latest
      candidates=.candidates,s
     else. say (s{::signals),' unreachable' end.
    end.
    prefix=.'critical'
   else.
    for_i. ff do.
     s=.1{2{::i{::gates
     if. 0<:s{latest do. candidates=.candidates,s end.
    end.
    prefix=.'flip-flops ',(num #ff),' period'
   end.
   if. 0=#candidates do. say prefix,' none' else.
    best=.candidates{~(candidates{latest)i.>./candidates{latest
    say prefix,' ',(num best{latest),': ',(signals;previous)trace best
   end.
  end.
 end.
)
main=:3 : 0
 lines=.<;._2 (1!:1&3''),LF
 i=.0
 while. i<#lines do.
  line=.i{::lines
  if. 'END'-:line do. break. end.
  if. 0=#line do. i=.>:i continue. end.
  ErrorLine=:>:i
  if. 'MODULE'-:0{::words line do.
   finish=.>:i
   while. -.'ENDMODULE'-:finish{::lines do. finish=.>:finish end.
   try. define line;((>:i)}.finish{.lines);>:i catcht. say 'error: line ',(num ErrorLine),': ',Reason end.
   i=.>:finish
  else.
   try. command line catcht. say 'error: line ',(num ErrorLine),': ',Reason end.
   i=.>:i
  end.
 end.
)
main''
