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
number=:4 : 0
 'lo hi'=.x
 if. 0=#y do. _1 return. end.
 if. (-.*./y e.'0123456789')+.((1<#y)*.'0'={.y) do. _1 return. end.
 v=.0".y
 if. (v<lo)+.v>hi do. _1 else. v end.
)
Kinds=:'IOTSZJL'
States=:'0R2L'
Ops=:words 'L R LL RR SD DD CW CCW HD LOCK HOLD'
ClearNames=:words 'SINGLE DOUBLE TRIPLE TETRIS TSPIN_MINI TSPIN_MINI_SINGLE TSPIN_MINI_DOUBLE TSPIN TSPIN_SINGLE TSPIN_DOUBLE TSPIN_TRIPLE'
Shapes=:0$a:
initShapes=:3 : 0
 originals=.(4 2$0 1 1 1 2 1 3 1);(4 2$0 0 1 0 0 1 1 1);(4 2$1 0 0 1 1 1 2 1);(4 2$1 0 2 0 0 1 1 1);(4 2$0 0 1 0 1 1 2 1);(4 2$0 0 0 1 1 1 2 1);4 2$2 0 0 1 1 1 2 1
 for_k. i.7 do.
  n=.k{4 2 3 3 3 3 3
  shape=.k{::originals
  for_s. i.4 do.
   Shapes=:Shapes,<shape
   shape=.((n-1)-1{"1 shape),.0{"1 shape
  end.
 end.
)
initShapes''
KickTransitions=:0 1;1 0;1 2;2 1;2 3;3 2;3 0;0 3
Kicks=: (5 2$0 0 _1 0 _1 1 0 _2 _1 _2);(5 2$0 0 1 0 1 _1 0 2 1 2);(5 2$0 0 1 0 1 _1 0 2 1 2);(5 2$0 0 _1 0 _1 1 0 _2 _1 _2);(5 2$0 0 1 0 1 1 0 _2 1 _2);(5 2$0 0 _1 0 _1 _1 0 2 _1 2);(5 2$0 0 _1 0 _1 _1 0 2 _1 2);5 2$0 0 1 0 1 1 0 _2 1 _2
IKicks=:(5 2$0 0 _2 0 1 0 _2 _1 1 2);(5 2$0 0 2 0 _1 0 2 1 _1 _2);(5 2$0 0 _1 0 2 0 _1 2 2 _1);(5 2$0 0 1 0 _2 0 1 _2 _2 1);(5 2$0 0 2 0 _1 0 2 1 _1 _2);(5 2$0 0 _2 0 1 0 _2 _1 1 2);(5 2$0 0 1 0 _2 0 1 _2 _2 1);5 2$0 0 _1 0 2 0 _1 2 2 _1
spawnpos=:3 : '0,(4+y=1),22'
cells=:4 : 0
 's cx cy'=.y
 shape=.((4*x)+s){::Shapes
 (cx+0{"1 shape),.cy-1{"1 shape
)
canplace=:4 : 0
 cs=.x cells y
 if. (+./(0{"1 cs)<1)+.(+./(0{"1 cs)>10)+.(+./(1{"1 cs)<1)+.+./(1{"1 cs)>22 do. 0 return. end.
 -. +./(<"1 |."1 cs-1){Board
)
lowest=:4 : '<./1{"1 x cells y'
move=:4 : 0
 k=.x
 'p op'=.y
 's cx cy'=.p
 test=.0
 if. op e.0 1 4 do.
  q=.p+op{::0 _1 0;0 1 0;0 0 0;0 0 0;0 0 _1
  ok=.k canplace q
  if. -.ok do. q=.p end.
 elseif. op e.2 3 5 do.
  basic=.op{0 0 0 1 0 4
  q=.p
  ok=.0
  while. 1 do.
   'r trial success'=.k move q;basic
   if. -.success do. break. end.
   q=.r
   ok=.1
  end.
 else.
  b=.4|s+(op=6){3 1
  offsets=.1 2$0
  if. k~:1 do.
   i=.KickTransitions i.<s,b
   if. k=0 do. offsets=.i{::IKicks else. offsets=.i{::Kicks end.
  end.
  q=.p
  ok=.0
  for_i. i.#offsets do.
   r=.b,(cx+0{i{offsets),cy+1{i{offsets
   if. k canplace r do. q=.r [ test=.>:i [ ok=.1 break. end.
  end.
 end.
 q;test;ok
)
landing=:4 : 0
 0{::x move y;5
)
placed=:4 : 0
 cs=.x cells y
 board=.1(<"1 |."1 cs-1)}Board
 complete=.*./"1 board
 n=.+/complete
 board=.((-.complete)#board),(n,10)$0
 board;n
)
analysis=:3 : 0
 heights=.10$0
 holes=.0
 for_c. i.10 do.
  column=.c{"1 y
  filled=.I.column
  if. #filled do.
   h=.>:>{:filled
   heights=.h c}heights
   holes=.holes++/-.h{.column
  end.
 end.
 bump=.+/|(}.heights)-}:heights
 value=.(-51*+/heights)-(36*holes)+18*bump
 heights;holes;bump;value
)
reachable=:4 : 0
 k=.x
 positions=.,<y
 paths=.,<i.0
 cursor=.0
 while. cursor<#positions do.
  p=.cursor{::positions
  sequence=.cursor{::paths
  for_op. i.8 do.
   'q test ok'=.k move p;op
   if. ok do.
    if. -.(<q)e.positions do.
     positions=.positions,<q
     paths=.paths,<sequence,op
    end.
   end.
  end.
  cursor=.>:cursor
 end.
 positions;<paths
)
shortest=:4 : 0
 k=.x
 start=.spawnpos k
 if. -.k canplace start do. 0$a: return. end.
 positions=.,<start
 paths=.,<i.0
 cursor=.0
 while. cursor<#positions do.
  p=.cursor{::positions
  sequence=.cursor{::paths
  if. y-:k landing p do. <sequence return. end.
  for_op. i.8 do.
   'q test ok'=.k move p;op
   if. ok do.
    if. -.(<q)e.positions do.
     positions=.positions,<q
     paths=.paths,<sequence,op
    end.
   end.
  end.
  cursor=.>:cursor
 end.
 0$a:
)
occupied=:3 : 0
 'c r'=.y
 if. (c<1)+.(c>10)+.(r<1)+.r>22 do. 1 else. (<(r-1),c-1){Board end.
)
spin=:4 : 0
 's cx cy'=.x
 corners=.(cx,cy);((cx+2),cy);((cx+2),cy-2);cx,cy-2
 busy=.occupied&>corners
 if. 3>+/busy do. 0 return. end.
 if. (y=5)+.*./(4|s,s+1){busy do. 2 else. 1 end.
)
clearindex=:4 : 0
 if. x=0 do. y-1 elseif. x=1 do. y+4 else. y+7 end.
)
sequenceText=:3 : 0
 if. 0=#y do. 'none' else. ' 'join y{Ops end.
)
positionText=:3 : 0
 's cx cy'=.y
 (s{States),' ',(num cx),' ',num cy
)
ratio=:4 : 0
 if. y=0 do. '0.00' return. end.
 q=.<.(100*x)%y
 fraction=._2{.'00',num 100|q
 (num <.q%100),'.',fraction
)
statadd=:4 : 'Stats=:(y+x{Stats)x}Stats'
snapshot=:3 : 0
 Board;Random;Queue;Hold;HoldUsed;Kind;Position;Motion;Test;Keys;Drop;Fall;Ground;Resets;Lowest;StartLevel;Level;Score;Lines;Pieces;Streak;Chain;Pending;Stats;Ended
)
restore=:3 : 0
 'Board Random Queue Hold HoldUsed Kind Position Motion Test Keys Drop Fall Ground Resets Lowest StartLevel Level Score Lines Pieces Streak Chain Pending Stats Ended'=:y
)
summary=:3 : 0
 say 'summary game ',(num Game),' score ',(num Score),' level ',(num Level),' lines ',(num Lines),' pieces ',num Pieces
 text=.'clears'
 labels=.words 'single double triple tetris'
 for_i. i.4 do. text=.text,' ',(i{::labels),' ',num (17+i){Stats end.
 say text,' perfect ',num 4{Stats
 text=.'tspins'
 labels=.words 'mini mini_single mini_double zero single double triple'
 for_i. i.7 do. text=.text,' ',(i{::labels),' ',num (21+i){Stats end.
 say text
 text=.'pieces'
 for_i. i.7 do. text=.text,' ',(i{Kinds),' ',num (10+i){Stats end.
 say text
 say 'best combo ',(num 8{Stats),' chain ',(num 9{Stats),' holds ',(num 1{Stats),' drops ',(num 0{Stats),' faults ',num 3{Stats
 say 'garbage sent ',(num 5{Stats),' cancelled ',(num 6{Stats),' received ',num 7{Stats
 say 'rates app ',((5{Stats)ratio Pieces),' apl ',((5{Stats)ratio Lines),' kpp ',(2{Stats)ratio Pieces
)
endgame=:3 : 0
 say 'game over ',y,' out'
 summary 0
 Ended=:1
 Reason=:''
 throw.
)
random=:3 : 0
 Random=:2147483647|48271*Random
 Random
)
addbag=:3 : 0
 bag=.i.7
 for_i. 6 5 4 3 2 1 do.
  j=.(>:i)|random 0
  pair=.(j,i){bag
  bag=.pair(i,j)}bag
 end.
 Queue=:Queue,bag
)
takepiece=:3 : 0
 k=.{.Queue
 Queue=:}.Queue
 if. 5>#Queue do. addbag 0 end.
 k
)
spawn=:3 : 0
 Kind=:y
 Position=:spawnpos y
 Motion=:Test=:Keys=:Drop=:Fall=:Ground=:Resets=:0
 Lowest=:Kind lowest Position
 if. -.Kind canplace Position do. endgame 'block' end.
)
update=:4 : 0
 Position=:y
 'Motion Test'=:x
 low=.Kind lowest y
 if. low<Lowest do. Lowest=:low [ Resets=:0 end.
)
droppoints=:3 : 0
 Score=:Score+y
 Drop=:Drop+y
 0 statadd y
)
garbage=:3 : 0
 'n hole'=.y
 if. +./,(22-n)}.Board do. endgame 'top' end.
 row=.0(hole-1)}10$1
 Board=:((n,10)$row),(22-n){.Board
)
lock=:3 : 0
 k=.Kind
 p=.Position
 seq=.k shortest p
 tspin=.0
 if. (k=2)*.Motion=2 do. tspin=.p spin Test end.
 cs=.k cells p
 'board n'=.k placed p
 Board=:board
 History=:History,<PieceStart
 Pieces=:>:Pieces
 (10+k)statadd 1
 2 statadd Keys
 index=.tspin clearindex n
 base=.sent=.0
 if. index>:0 do.
  base=.index{100 300 500 800 100 200 400 400 800 1200 1600
  sent=.index{0 1 2 4 0 0 1 0 2 4 6
 end.
 points=.base*Level
 back=.0
 if. n do.
  Streak=:>:Streak
  if. (n=4)+.tspin>0 do.
   Chain=:>:Chain
   back=.Chain>:2
  else. Chain=:0 end.
 else. Streak=:0 end.
 if. back do. points=.<.(points*3)%2 [ sent=.>:sent end.
 combo=.Streak-1
 comboPoints=.50*(0>.combo)*Level
 if. combo>:0 do. sent=.sent+(10<.combo){0 1 1 2 2 3 3 4 4 4 5 end.
 perfect=.(n>0)*.-.+./,Board
 perfectPoints=.0
 if. perfect do.
  perfectPoints=.Level*(n-1){800 1200 1800 2000
  if. (n=4)*.back do. perfectPoints=.3200*Level end.
  sent=.sent+10
  4 statadd 1
 end.
 gain=.points+comboPoints+perfectPoints
 Score=:Score+gain
 Lines=:Lines+n
 5 statadd sent
 Stats=:((8{Stats)>.combo)8}Stats
 Stats=:((9{Stats)>.Chain)9}Stats
 best=.'-'
 if. #seq do. best=.num #0{::seq end.
 say 'lock ',(num Pieces),' ',(k{Kinds),' ',(positionText p),' keys ',(num Keys),' ',best,' drop ',(num Drop),' lines ',(num n),' sent ',(num sent),' +',(num gain),' total ',num Score
 if. #seq do.
  sequence=.0{::seq
  if. Keys>#sequence do.
   3 statadd 1
   say 'finesse ',sequenceText sequence
  end.
 end.
 if. index>:0 do.
  (17+index)statadd 1
  text=.'clear ',(index{::ClearNames),' ',num points
  if. back do. text=.text,' b2b' end.
  if. combo>:1 do. text=.text,' combo ',(num combo),' ',num comboPoints end.
  if. perfect do. text=.text,' perfect ',num perfectPoints end.
  say text
 end.
 nextLevel=.StartLevel+<.Lines%10
 if. nextLevel>Level do. Level=:nextLevel [ say 'level ',num nextLevel end.
 if. *./(1{"1 cs)>20 do. endgame 'lock' end.
 cancelled=.sent<.+/Pending
 if. cancelled>0 do.
  left=.cancelled
  while. left>0 do.
   amount=.left<.{.Pending
   Pending=:(({.Pending)-amount)0}Pending
   if. 0={.Pending do. Pending=:}.Pending end.
   left=.left-amount
  end.
  6 statadd cancelled
  say 'cancel ',(num cancelled),' pending ',num +/Pending
 end.
 if. n=0 do.
  risen=.0
  while. (0<#Pending)*.risen<8 do.
   amount=.({.Pending)<.8-risen
   hole=.1+10|random 0
   garbage amount,hole
   7 statadd amount
   risen=.risen+amount
   Pending=:(({.Pending)-amount)0}Pending
   if. 0={.Pending do. Pending=:}.Pending end.
   say 'rise ',(num amount),' hole ',(num hole),' pending ',num +/Pending
  end.
 end.
 HoldUsed=:0
 spawn takepiece 0
 PieceStart=:snapshot 0
)
operation=:3 : 0
 op=.y
 if. op<8 do.
  Keys=:>:Keys
  'q test ok'=.Kind move Position;op
  if. -.ok do. say 'fail ',op{::Ops return. end.
  if. op e.4 5 do.
   droppoints (2{Position)-2{q
   1 0 update q
   Fall=:Ground=:0
  else.
   motion=.1
   if. op e.6 7 do. motion=.2 end.
   (motion,test)update q
   if. (Ground>0)*.Resets<15 do. Ground=:0 [ Resets=:>:Resets end.
  end.
 elseif. op=8 do.
  q=.Kind landing Position
  rows=.(2{Position)-2{q
  droppoints 2*rows
  if. rows>0 do. 1 0 update q end.
  lock 0
 elseif. op=9 do.
  if. Kind canplace Position+0 0 _1 do. say 'fail LOCK' else. lock 0 end.
 else.
  if. HoldUsed do. say 'fail HOLD' return. end.
  HoldUsed=:1
  1 statadd 1
  k=.Hold
  Hold=:Kind
  if. k<0 do. k=.takepiece 0 end.
  spawn k
 end.
)
candidates=:3 : 0
 'k p prefix'=.y
 result=.seen=.0$a:
 rotations=.(i.0);(,6);6 6;,7
 for_rot. rotations do.
  r=.>rot
  q=.p
  ok=.1
  for_op. r do.
   'q test ok'=.k move q;op
   if. -.ok do. break. end.
  end.
  if. -.ok do. continue. end.
  positions=.,<q
  paths=.,<i.0
  for_op. 0 1 do.
   at=.q
   seq=.i.0
   while. 1 do.
    'at test ok'=.k move at;op
    if. -.ok do. break. end.
    seq=.seq,op
    positions=.positions,<at
    paths=.paths,<seq
   end.
  end.
  for_i. i.#positions do.
   t=.k landing i{::positions
   cs=.k cells t
   canonical=./:~cs
   if. (<canonical)e.seen do. continue. end.
   seen=.seen,<canonical
   'board n'=.k placed t
   value=.(3{::analysis board)+76*n
   seq=.prefix,r,(i{::paths),8
   result=.result,<value;k;seq
  end.
 end.
 result
)
ranked=:3 : 0
 result=.candidates Kind;Position;i.0
 if. -.HoldUsed do.
  k=.Hold
  if. k<0 do. k=.{.Queue end.
  p=.spawnpos k
  if. k canplace p do. result=.result,candidates k;p;,10 end.
 end.
 values=.i.0
 for_c. result do. values=.values,0{::>c end.
 (\:values){result
)
spins=:3 : 0
 if. Kind~:2 do. say 'spins 0' return. end.
 'positions paths'=.2 reachable Position
 found=.0$a:
 types=.i.0
 for_p. positions do.
  for_op. 6 7 do.
   'q test ok'=.2 move (>p);op
   if. -.ok do. continue. end.
   if. 2 canplace q+0 0 _1 do. continue. end.
   typ=.q spin test
   if. typ=0 do. continue. end.
   i=.found i.<q
   if. i=#found do. found=.found,<q [ types=.types,typ
   else. types=.(typ>.i{types)i}types end.
  end.
 end.
 keys=.0 3$0
 for_p. found do. keys=.keys,|.>p end.
 for_i. /:keys do.
  p=.i{::found
  n=.1{::2 placed p
  index=.(i{types)clearindex n
  say 'spin ',(positionText p),' ',index{::ClearNames
 end.
 say 'spins ',num #found
)
Game=:0
Ended=:1
Commands=:words 'NEW PRINT NEXT PREVIEW STATUS ANALYZE ROW GARBAGE ATTACK TICK UNDO SAVE LOAD SPINS HINT AUTO'
Arity=:2 0 0 1 0 0 2 2 1 1 0 1 1 0 1 1
command=:3 : 0
 w=.words y
 cmd=.Commands i.{.w
 a=.}.w
 if. cmd=#Commands do.
  for_token. w do. if. -.token e.Ops do. fail 'ERROR unknown ',>token end. end.
  if. Game=0 do. fail 'ERROR no game' end.
  if. Ended do. fail 'ERROR game over' end.
  for_token. w do. operation Ops i.token end.
  return.
 end.
 if. (cmd{Arity)~:#a do. fail 'ERROR bad arguments' end.
 n=.h=._1
 select. cmd
 case. 0 do.
  n=.1 2147483646 number 0{::a
  h=.1 15 number 1{::a
  if. (n<0)+.h<0 do. fail 'ERROR bad arguments' end.
 case. 3;6;7;8;9;14;15 do.
  hi=.cmd{0 0 0 14 0 0 22 10 20 1000 0 0 0 0 10 50
  n=.(1,hi)number 0{::a
  if. n<0 do. fail 'ERROR bad arguments' end.
  if. cmd=6 do.
   pattern=.1{::a
   if. (10~:#pattern)+.(-.*./pattern e.'#.')+.-.'.'e.pattern do. fail 'ERROR bad arguments' end.
  elseif. cmd=7 do.
   h=.1 10 number 1{::a
   if. h<0 do. fail 'ERROR bad arguments' end.
  end.
 case. 11;12 do.
  name=.0{::a
  if. (0=#name)+.(8<#name)+.-.*./name e.'abcdefghijklmnopqrstuvwxyz' do. fail 'ERROR bad arguments' end.
 end.
 if. cmd~:0 do.
  if. Game=0 do. fail 'ERROR no game' end.
  if. Ended*.-.cmd e.1 2 3 4 5 12 do. fail 'ERROR game over' end.
 end.
 select. cmd
 case. 0 do.
  if. (Game>0)*.-.Ended do.
   say 'game stopped'
   summary 0
  end.
  Game=:>:Game
  say 'game ',(num Game),' seed ',(num n),' level ',num h
  Board=:22 10$0
  Random=:n
  StartLevel=:Level=:h
  Score=:Lines=:Pieces=:Streak=:Chain=:HoldUsed=:0
  Hold=:_1
  Queue=:Pending=:i.0
  Stats=:28$0
  History=:SaveNames=:Saves=:0$a:
  Ended=:0
  addbag 0
  spawn takepiece 0
  PieceStart=:snapshot 0
 case. 1 do.
  display=.'.#'{~Board
  if. -.Ended do.
   ghost=.Kind cells Kind landing Position
   active=.Kind cells Position
   for_cs. ghost do.
    at=.<|.cs-1
    if. '.'=at{display do. display=.'+'at}display end.
   end.
   for_cs. active do.
    at=.<|.cs-1
    if. '#'~:at{display do. display=.'@'at}display end.
   end.
  end.
  for_r. |.i.22 do. say (_2{.' ',num >:r),' ',r{display end.
 case. 2 do.
  held=.'-'
  if. Hold>:0 do. held=.,Hold{Kinds end.
  say 'hold ',held,' next ',(5{.Queue){Kinds
 case. 3 do.
  oldQueue=.Queue
  oldRandom=.Random
  while. n>#Queue do. addbag 0 end.
  text=.(n{.Queue){Kinds
  Queue=:oldQueue
  Random=:oldRandom
  say 'preview ',text
 case. 4 do.
  say 'score ',(num Score),' level ',(num Level),' lines ',(num Lines),' pieces ',num Pieces
  piece=.'-'
  if. -.Ended do. piece=.(Kind{Kinds),' ',positionText Position end.
  say 'piece ',piece,' streak ',(num Streak),' chain ',(num Chain),' pending ',num +/Pending
 case. 5 do.
  'heights holes bump value'=.analysis Board
  say 'heights ',' 'join num&.><"0 heights
  say 'holes ',(num holes),' bumpiness ',(num bump),' value ',num value
 case. 6 do.
  for_cs. Kind cells Position do.
   'c r'=.cs
   if. (r=n)*.'#'=(c-1){pattern do. fail 'ERROR overlap' end.
  end.
  Board=:('#'=pattern)(n-1)}Board
  say 'OK'
 case. 7 do.
  garbage n,h
  found=.0
  for_j. i.>:n do.
   p=.Position+0 0,j
   if. Kind canplace p do. Position=:p [ found=.1 break. end.
  end.
  if. -.found do. endgame 'top' end.
  say 'OK'
 case. 8 do.
  Pending=:Pending,n
  say 'pending ',num +/Pending
 case. 9 do.
  for_tick. i.n do.
   if. Kind canplace Position+0 0 _1 do.
    Ground=:0
    Fall=:>:Fall
    interval=.(12<.Level-1){60 48 37 28 21 16 11 8 6 4 3 2 1
    if. Fall>:interval do. 1 0 update Position+0 0 _1 [ Fall=:0 end.
   else.
    Ground=:>:Ground
    if. Ground>:30 do. lock 0 end.
   end.
  end.
 case. 10 do.
  if. 0=#History do. fail 'ERROR nothing to undo' end.
  saved=.{:History
  History=:}:History
  restore >saved
  PieceStart=:>saved
  say 'undo ',(num Pieces),' ',Kind{Kinds
 case. 11 do.
  saved=.(snapshot 0);History;<PieceStart
  index=.SaveNames i.<name
  if. index=#SaveNames do. SaveNames=:SaveNames,<name [ Saves=:Saves,<saved
  else. Saves=:(<saved)index}Saves end.
  say 'OK'
 case. 12 do.
  index=.SaveNames i.<name
  if. index=#SaveNames do. fail 'ERROR unknown save' end.
  'saved history start'=.index{::Saves
  restore saved
  History=:history
  PieceStart=:start
  say 'load ',(num Pieces),' ',Kind{Kinds
 case. 13 do. spins 0
 case. 14 do.
  choices=.ranked 0
  for_i. i.n<.#choices do.
   'value k seq'=.i{::choices
   say 'hint ',(num >:i),' ',(k{Kinds),' ',(sequenceText seq),' value ',num value
  end.
 case. 15 do.
  for_i. i.n do.
   'value k seq'=.0{::ranked 0
   say 'auto ',(k{Kinds),' ',sequenceText seq
   for_op. seq do. operation op end.
  end.
 end.
)
main=:3 : 0
 lines=.<;._2 (1!:1&3''),LF
 n=.0".0{::lines
 for_line. n{.}.lines do.
  try. command >line catcht. if. #Reason do. say Reason end. end.
 end.
 if. (Game>0)*.-.Ended do.
  say 'game stopped'
  summary 0
 end.
)
main''
