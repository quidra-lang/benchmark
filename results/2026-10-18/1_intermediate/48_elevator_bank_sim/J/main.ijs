LF =: 10{a.
number =: 3 : ',''0'' 8!:2 y'
eq =: 4 : '(,x)-:,y'
split =: 4 : '<;._1 x,y'
join =: 4 : 0
 r =. ''
 for_i. i.#y do.
  if. i do. r =. r,x end.
  r =. r,i{::y
 end.
 r
)
words =: 3 : 0
 r =. 0$a:
 for_v. y do.
  v =. >v
  if. 2~:3!:0 v do. v =. number v end.
  r =. r,<,v
 end.
 ' ' join r
)
emit =: 3 : 'Output =: Output,<y'
say =: 3 : 'emit words y'
fail =: 3 : 0
 Error =: y
 throw.
)
numlist =: 3 : 0
 if. #y do. ',' join number&.><"0 y else. '-' end.
)
glabel =: 3 : '''G'',number y'
glist =: 3 : 0
 if. #y do. ',' join glabel&.> <"0 y+1 else. '-' end.
)
avg =: 4 : 0
 if. y=0 do. '-' return. end.
 c =. <.(100*x)%y
 (number <.c%100),'.',_2{.'00',number 100|c
)
Policies =: ;:'COST NEAREST ROUND ETA'
Keys =: ;:'FLOORS CARS CAPACITY DOOR START POLICY ZONES PARK PATIENCE BYPASS PERIOD LIMIT COMPARE'
Commands =: ;:'CALL CANCEL OUT IN HOLD FIRE RESET WHERE STATUS'
Counts =: 3 1 1 1 2 1 0 1 0
bounds =: 4 : 0
 'lo hi' =. x
 n =. 0".y
 if. (n<lo)+.n>hi do. fail 'bad value for ',Key end.
 n
)
config =: 3 : 0
 entries =. (#Keys)$<0$a:
 seen =. (#Keys)#0
 for_line. y do.
  line =. >line
  key =. 0{::line
  k =. Keys i.<key
  if. k=#Keys do. fail 'unknown key ',key end.
  if. k{seen do. fail 'duplicate key ',key end.
  seen =. 1 k}seen
  entries =. (<}.line) k}entries
 end.
 for_k. i.5 do. if. -.k{seen do. fail 'missing key ',k{::Keys end. end.
 F =: E =: C =: D =: 0
 Park =: Patience =: Period =: _1
 Bypass =: 100
 Limit =: 1000
 Policy =: 0
 Compare =: i.0
 Starts =: Homes =: i.0
 Zones =: 0 2$0
 for_k. I.seen do.
  Key =: k{::Keys
  a =. k{::entries
  n =. 1
  if. k e.4 6 do. n =. E end.
  if. k=7 do. n =. E+1 end.
  if. k=12 do. bad =. (1>#a)+.4<#a else. bad =. n~:#a end.
  if. bad do. fail 'wrong number of values for ',Key end.
  select. k
  case. 0 do. F =: 2 50 bounds 0{::a
  case. 1 do. E =: 1 8 bounds 0{::a
  case. 2 do. C =: 1 20 bounds 0{::a
  case. 3 do. D =: 1 9 bounds 0{::a
  case. 4 do.
   for_v. a do. Starts =: Starts,(1,F)bounds >v end.
  case. 5 do.
   Policy =: Policies i.0{a
   if. Policy=4 do. fail 'bad value for POLICY' end.
  case. 6 do.
   for_v. a do.
    'lo hi' =. 0".>':' split >v
    if. (lo<1)+.(lo>:hi)+.hi>F do. fail 'bad value for ZONES' end.
    Zones =: Zones,lo,hi
   end.
  case. 7 do.
   Park =: 0 100 bounds 0{::a
   for_v. }.a do. Homes =: Homes,(1,F)bounds >v end.
  case. 8 do. Patience =: 1 1000 bounds 0{::a
  case. 9 do. Bypass =: 50 100 bounds 0{::a
  case. 10 do. Period =: 1 1000 bounds 0{::a
  case. 11 do. Limit =: 1 5000 bounds 0{::a
  case. 12 do.
   Compare =: Policies i.a
   if. (4 e.Compare)+.(#~.Compare)~:#Compare do. fail 'bad value for COMPARE' end.
  end.
 end.
 if. 0=#Zones do. Zones =: E 2$1,F end.
 for_i. i.E do.
  'lo hi' =. i{Zones
  if. ((i{Starts)<lo)+.(i{Starts)>hi) do. fail 'car ',(number i+1),' starts outside its zone' end.
  if. Park>:0 do.
   if. ((i{Homes)<lo)+.(i{Homes)>hi) do. fail 'car ',(number i+1),' home outside its zone' end.
  end.
 end.
)
serves =: 4 : 0
 'a b' =. y
 'lo hi' =. x{Zones
 (lo<:a)*.(a<:hi)*.(lo<:b)*.b<:hi
)
validate =: 3 : 0
 Events =: 0 5$0
 last =. ng =. fire =. 0
 out =. E#0
 for_entry. y do.
  'line fields' =. >entry
  t =. 0".0{::fields
  cmd =. 1{::fields
  c =. Commands i.<cmd
  args =. 2}.fields
  error =. ''
  if. c=9 do. error =. 'unknown command ',cmd
  elseif. (#args)~:c{Counts do. error =. 'wrong number of arguments for ',cmd
  elseif. t<last do. error =. 'time goes backwards'
  else.
   v =. 0".>args
   'a b n' =. 3{.v
   select. c
   case. 0 do.
    if. (a<1)+.(a>F)+.(b<1)+.b>F do. error =. 'bad floor'
    elseif. a=b do. error =. 'same floor'
    elseif. (n<1)+.n>99 do. error =. 'bad count'
    else.
     served =. 0
     for_i. i.E do. served =. served+.i serves a,b end.
     if. -.served do. error =. 'no car serves ',(number a),'->',number b
     elseif. fire do. error =. 'fire service active' end.
    end.
   case. 1;7 do. if. (a<1)+.a>ng do. error =. 'unknown group' end.
   case. 2;3;4 do.
    if. (a<1)+.a>E do. error =. 'bad car'
    elseif. (c=2)*.(a-1){out do. error =. 'car ',(number a),' already out'
    elseif. (c=3)*.-.(a-1){out do. error =. 'car ',(number a),' already in'
    elseif. (c=4)*.((b<1)+.b>9) do. error =. 'bad ticks' end.
   case. 5 do.
    if. (a<1)+.a>F do. error =. 'bad floor'
    elseif. fire do. error =. 'fire already active' end.
   case. 6 do. if. -.fire do. error =. 'fire not active' end.
   end.
  end.
  if. #error do. emit 'line ',(number line),': ',error continue. end.
  Events =: Events,t,c,3{.v
  last =. t
  select. c
  case. 0 do. ng =. ng+1
  case. 2 do. out =. 1 (a-1)}out
  case. 3 do. out =. 0 (a-1)}out
  case. 5 do. fire =. 1
  case. 6 do. fire =. 0
  end.
 end.
)
NB. Group columns: from,to,count,time,waiting,car,boarded,delivered,lost,lastboard,lastalight,wait,travel,maxwait.
NB. Car columns: floor,direction,door,inservice,idlesince,distance,stops,boarded,busy,energy.
log =: 3 : 0
 if. Logging do. emit (number Time),' ',y end.
)
loadcar =: 3 : '+/1{"1 y{::Passengers'
targets =: 3 : 0
 ps =. y{::Passengers
 gs =. y{::Calls
 ~.((0{"1 ps){1{"1 G),gs{0{"1 G
)
remove =: 3 : 0
 car =. (<y,5){G
 if. car<0 do. Pending =: Pending#~Pending~:y
 else. Calls =: (<(car{::Calls)#~(car{::Calls)~:y) car}Calls end.
 G =: _1 (<y,5)}G
)
cost =: 4 : 0
 f =. (<x,0){Cars
 d =. (<x,1){Cars
 landing =. (<y,0){G
 u =. *((<y,1){G)-landing
 if. (SimPolicy=1)+.d=0 do. |f-landing return. end.
 s =. targets x
 if. (u=d)*.((landing-f)*d)>:0 do.
  distance =. |f-landing
  via =. +/(((s-f)*d)>0)*.((landing-s)*d)>0
 else.
  if. d>0 do. m =. >./f,s else. m =. <./f,s end.
  distance =. (|f-m)+|m-landing
  via =. +/((s-f)*d)>0
 end.
 if. SimPolicy=3 do. distance =. distance+(D*via)+(<x,2){Cars end.
 distance
)
assign =: 4 : 0
 candidates =. i.0
 for_i. i.E do.
  if. (i~:x)*.(<i,3){Cars do.
   if. i serves 0 1{y{G do. candidates =. candidates,i end.
  end.
 end.
 if. 0=#candidates do. 0 return. end.
 chosen =. {.candidates
 if. SimPolicy=2 do.
  later =. candidates#~candidates>Round
  if. #later do. chosen =. {.later end.
 else.
  for_i. candidates do. if. (i cost y)<chosen cost y do. chosen =. i end. end.
 end.
 value =. chosen cost y
 remove y
 G =: chosen (<y,5)}G
 Calls =: (<(chosen{::Calls),y) chosen}Calls
 text =. 'E',(number chosen+1),' ASSIGN G',number y+1
 if. SimPolicy=2 do. Round =: chosen else. text =. text,' cost=',number value end.
 log text
 1
)
pending =: 3 : 0
 Pending =: Pending,y
 G =: _1 (<y,5)}G
 log 'PENDING G',number y+1
)
walk =: 4 : 0
 n =. (<y,4){G
 remove y
 log x,' G',(number y+1),' x',number n
 Abandoned =: Abandoned+n
 G =: (((<y,8){G)+n) (<y,8)}G
 G =: 0 (<y,4)}G
)
choose =: 3 : 0
 f =. (<y,0){Cars
 d =. (<y,1){Cars
 s =. targets y
 calls =. y{::Calls
 calls =. calls#~f=calls{0{"1 G
 if. (100*loadcar y)>:C*Bypass do. calls =. i.0 end.
 dirs =. *(calls{1{"1 G)-calls{0{"1 G
 if. (d~:0)*.((+./((s-f)*d)>0)+.d e.dirs) do. d return. end.
 if. #calls do. {.dirs return. end.
 if. (d~:0)*.+./((s-f)*d)<0 do. -d return. end.
 if. (d=0)*.0<#y{::Calls do. *(({.y{::Calls){0{"1 G)-f return. end.
 0
)
move =: 4 : 0
 energy =. 1
 if. x>0 do. energy =. 3+loadcar y end.
 Cars =: (energy+(<y,9){Cars) (<y,9)}Cars
 Cars =: (x+(<y,0){Cars) (<y,0)}Cars
 Cars =: (1+(<y,5){Cars) (<y,5)}Cars
)
event =: 3 : 0
 't cmd a b n' =. y
 select. cmd
 case. 0 do.
  gi =. #G
  G =: G,a,b,n,Time,n,_1,0,0,0,_1,_1,0,0,0
  Used =: Used,1 E$0
  log 'CALL G',(number gi+1),' ',(number a),'->',(number b),' x',number n
  if. -._1 assign gi do. pending gi end.
 case. 1 do.
  gi =. a-1
  if. (<gi,4){G do. 'CANCEL' walk gi else. log 'CANCEL G',(number a),' ignored' end.
 case. 2 do.
  i =. a-1
  Cars =: 0 (<i,3)}Cars
  log 'E',(number a),' OUT'
  calls =. i{::Calls
  Calls =: (<i.0) i}Calls
  for_g. calls do.
   G =: _1 (<g,5)}G
   if. -._1 assign g do. pending g end.
  end.
 case. 3 do.
  i =. a-1
  Cars =: 1 (<i,3)}Cars
  Cars =: Time (<i,4)}Cars
  log 'E',(number a),' IN'
  calls =. Pending
  Pending =: i.0
  for_g. calls do. if. -._1 assign g do. Pending =: Pending,g end. end.
 case. 4 do.
  i =. a-1
  door =. (<i,2){Cars
  if. door do.
   door =. door+b
   Cars =: door (<i,2)}Cars
   log 'E',(number a),' HOLD ',number door
  else. log 'E',(number a),' HOLD ignored' end.
 case. 5 do.
  Fire =: 1
  Evacuation =: a
  log 'FIRE ',number a
  for_g. I.0<4{"1 G do. 'ABANDON' walk g end.
 case. 6 do.
  Fire =: 0
  log 'RESET'
  Cars =: Time (<(i.E);4)}Cars
 case. 7 do.
  g =. a-1
  row =. g{G
  riding =. 0$a:
  for_i. i.E do.
   ps =. i{::Passengers
   count =. +/(1{"1 ps)#~g=0{"1 ps
   if. count do. riding =. riding,<'E',(number i+1),'x',number count end.
  end.
  if. #riding do. ridingtext =. ','join riding else. ridingtext =. '-' end.
  car =. '-'
  if. 4{row do.
   if. (5{row)<0 do. car =. 'pending' else. car =. 'E',number 1+5{row end.
  end.
  log 'WHERE G',(number a),' waiting=',(number 4{row),' car=',car,' riding=',ridingtext,' delivered=',(number 7{row),' lost=',number 8{row
 case. 8 do.
  for_i. i.E do.
   row =. i{Cars
   stops =. /:~~.(0{"1 i{::Passengers){1{"1 G
   dir =. ((1{row)+1){::'down';'idle';'up'
   service =. (3{row){::'out';'in'
   log 'STATUS E',(number i+1),' floor=',(number 0{row),' dir=',dir,' door=',(number 2{row),' load=',(number loadcar i),' stops=',(numlist stops),' calls=',(glist i{::Calls),' service=',service
  end.
  log 'STATUS pending=',glist Pending
 end.
)
action =: 3 : 0
 i =. y
 moved =. 0
 door =. (<i,2){Cars
 if. door do. door =. door-1 [ Cars =: (door-1) (<i,2)}Cars end.
 if. door=0 do.
  f =. (<i,0){Cars
  d =. (<i,1){Cars
  if. Fire do.
   n =. *Evacuation-f
   stop =. (n=0)*.0<#i{::Passengers
  else.
   n =. choose i
   dest =. (0{"1 i{::Passengers){1{"1 G
   stop =. f e.dest
   if. (100*loadcar i)<C*Bypass do.
    for_g. i{::Calls do.
     if. (f=(<g,0){G)*.n=*((<g,1){G)-(<g,0){G do. stop =. 1 end.
    end.
   end.
  end.
  if. stop do.
   log 'E',(number i+1),' OPEN ',number f
   Cars =: D (<i,2)}Cars
   Cars =: (1+(<i,6){Cars) (<i,6)}Cars
   Cars =: (2+(<i,9){Cars) (<i,9)}Cars
   keep =. 0 3$0
   for_p. i{::Passengers do.
    'g count boardtime' =. p
    dest =. (<g,1){G
    if. (dest=f)+.Fire do.
     if. dest=f do.
      log 'E',(number i+1),' ALIGHT G',(number g+1),' x',number count
      wait =. boardtime-(<g,3){G
      travel =. Time-(<g,3){G
      G =: (count+(<g,7){G) (<g,7)}G
      G =: Time (<g,10)}G
      G =: ((count*wait)+(<g,11){G) (<g,11)}G
      G =: ((count*travel)+(<g,12){G) (<g,12)}G
      G =: (wait>.(<g,13){G) (<g,13)}G
     else.
      log 'E',(number i+1),' EVACUATE G',(number g+1),' x',number count
      G =: (count+(<g,8){G) (<g,8)}G
      Evacuated =: Evacuated+count
     end.
    else. keep =. keep,p end.
   end.
   Passengers =: (<keep) i}Passengers
   if. -.Fire do.
    n =. choose i
    if. n do. Cars =: n (<i,1)}Cars end.
    calls =. i{::Calls
    for_g. calls do.
     if. (f~:(<g,0){G)+.n~:*((<g,1){G)-(<g,0){G do. continue. end.
     count =. (C-loadcar i)<.(<g,4){G
     if. count do.
      Passengers =: (<(i{::Passengers),g,count,Time) i}Passengers
      G =: (((<g,4){G)-count) (<g,4)}G
      G =: (count+(<g,6){G) (<g,6)}G
      G =: Time (<g,9)}G
      Used =: 1 (<g,i)}Used
      Cars =: (count+(<i,7){Cars) (<i,7)}Cars
      log 'E',(number i+1),' BOARD G',(number g+1),' x',number count
     end.
     if. 0=(<g,4){G do. remove g
     else.
      log 'E',(number i+1),' LEFT G',(number g+1),' x',number (<g,4){G
      i assign g
     end.
    end.
   end.
  elseif. n do.
   Cars =: n (<i,1)}Cars
   n move i
   moved =. 1
  else.
   if. d do.
    log 'E',(number i+1),' IDLE ',number f
    Cars =: 0 (<i,1)}Cars
    Cars =: Time (<i,4)}Cars
   end.
   if. (-.Fire)*.(<i,3){Cars do.
    if. Park>:0 do.
     home =. i{Homes
     if. (f~:home)*.(Time-(<i,4){Cars)>:Park do.
      (*home-f)move i
      moved =. 1
      if. home=(<i,0){Cars do. log 'E',(number i+1),' PARK ',number home end.
     end.
    end.
   end.
  end.
 end.
 if. moved+.0<(<i,2){Cars do. Cars =: (1+(<i,8){Cars) (<i,8)}Cars end.
)
simulate =: 4 : 0
 SimPolicy =: x
 Logging =: y
 G =: 0 14$0
 Used =: 0 E$0
 Cars =: E 10$0
 Cars =: Starts (<(i.E);0)}Cars
 Cars =: 1 (<(i.E);3)}Cars
 Passengers =: E$<0 3$0
 Calls =: E$<i.0
 Pending =: i.0
 Fire =: Evacuation =: Abandoned =: Evacuated =: 0
 Round =: _1
 cursor =. 0
 aborted =. 0
 for_t. i.Limit+1 do.
  Time =: t
  if. Patience>:0 do.
   for_g. I.0<4{"1 G do.
    if. Time=Patience+(<g,3){G do. 'ABANDON' walk g end.
   end.
  end.
  while. cursor<#Events do.
   if. Time~:0{cursor{Events do. break. end.
   event cursor{Events
   cursor =. cursor+1
  end.
  for_i. i.E do. action i end.
  done =. cursor=#Events
  for_i. i.E do.
   row =. i{Cars
   done =. done*.(0=2{row)*.(0=#i{::Passengers)*.0=#i{::Calls
   if. Fire do. done =. done*.Evacuation=0{row
   elseif. (3{row)*.Park>:0 do. done =. done*.(i{Homes)=0{row end.
  end.
  if. done do. log 'END' break. end.
  if. Time=Limit do. log 'ABORT' [ aborted =. 1 end.
 end.
 delivered =. +/7{"1 G
 wait =. +/11{"1 G
 travel =. +/12{"1 G
 maxwait =. 0>.(>./13{"1 G)
 delivered,Abandoned,Evacuated,wait,travel,maxwait,Time,aborted
)
aggregate =: 4 : 0
 gs =. y{G
 say x;('groups=',number #gs);('passengers=',number +/2{"1 gs);('delivered=',number +/7{"1 gs);'avg_wait=',(+/11{"1 gs)avg +/7{"1 gs
)
statistics =: 3 : 0
 for_g. i.#G do.
  row =. g{G
  'a b n t w car boarded delivered lost lb la wait travel mw' =. row
  wt =. tr =. '-'
  if. boarded=n do. wt =. number lb-t end.
  if. delivered=n do. tr =. number la-t end.
  emit 'G',(number g+1),' t=',(number t),' ',(number a),'->',(number b),' n=',(number n),' delivered=',(number delivered),' lost=',(number lost),' wait=',wt,' travel=',tr,' cars=',numlist 1+I.g{Used
 end.
 for_i. i.E do.
  row =. i{Cars
  u =. <.(1000*8{row)%1+Time
  say ('E',number i+1);('distance=',number 5{row);('stops=',number 6{row);('boarded=',number 7{row);('busy=',number 8{row);('util=',(number <.u%10),'.',(number 10|u),'%');'energy=',number 9{row
 end.
 for_f. /:~~.0{"1 G do. ('F',(number f),':')aggregate I.f=0{"1 G end.
 if. Period>:0 do.
  periods =. <.(3{"1 G)%Period
  for_k. /:~~.periods do. ('P',(number k),' ',(number k*Period),'-',(number (k*Period)+Period-1),':')aggregate I.k=periods end.
 end.
 'delivered abandoned evacuated wait travel mw end aborted' =. y
 if. delivered do. maximum =. number mw else. maximum =. '-' end.
 say 'summary:';('groups=',number #G);('passengers=',number +/2{"1 G);('delivered=',number delivered);('abandoned=',number abandoned);('evacuated=',number evacuated);('avg_wait=',wait avg delivered);('avg_travel=',travel avg delivered);('max_wait=',maximum);'end=',number end
)
main =: 3 : 0
 Output =: 0$a:
 q =. 0".1!:1 3
 lineno =. 1
 scenarioNames =. 0$a:
 results =. 0 10$0
 for_s. i.q do.
  line =. ' 'split 1!:1 3
  lineno =. lineno+1
  name =. 1{::line
  scenarioNames =. scenarioNames,<name
  settings =. raw =. 0$a:
  while. 1 do.
   text =. 1!:1 3
   lineno =. lineno+1
   if. text eq 'END' do. break. end.
   fields =. ' 'split text
   if. ({.text)e.'0123456789' do. raw =. raw,<lineno;fields else. settings =. settings,<fields end.
  end.
  emit '== ',name,' =='
  try. config settings
  catcht.
   emit 'error: ',Error
   results =. results,0,0,8#0
   continue.
  end.
  park =. patience =. period =. 'off'
  if. Park>:0 do. park =. number Park end.
  if. Patience>:0 do. patience =. number Patience end.
  if. Period>:0 do. period =. number Period end.
  comparison =. '-'
  if. #Compare do. comparison =. ','join Compare{Policies end.
  say 'config:';('floors=',number F);('cars=',number E);('capacity=',number C);('door=',number D);('policy=',Policy{::Policies);('park=',park);('patience=',patience);('bypass=',number Bypass);('period=',period);('limit=',number Limit);'compare=',comparison
  for_i. i.E do.
   home =. '-'
   if. Park>:0 do. home =. number i{Homes end.
   'lo hi' =. i{Zones
   say ('E',(number i+1),':');('start=',number i{Starts);('zone=',(number lo),'-',number hi);'home=',home
  end.
  validate raw
  result =. Policy simulate 1
  statistics result
  results =. results,1,Policy,result
  for_p. Compare do.
   r =. p simulate 0
   'delivered abandoned evacuated wait travel mw end aborted' =. r
   maximum =. '-'
   if. delivered do. maximum =. number mw end.
   say ('compare ',(p{::Policies),':');('delivered=',number delivered);('avg_wait=',wait avg delivered);('avg_travel=',travel avg delivered);('max_wait=',maximum);('end=',number end);'status=',aborted{::'end';'abort'
  end.
 end.
 emit '== ranking =='
 ranked =. i.0
 for_i. i.q do.
  row =. i{results
  if. (0{row)*.(0=9{row)*.0<2{row do.
   at =. #ranked
   for_j. i.#ranked do.
    old =. (j{ranked){results
    d =. ((5{row)*2{old)-(5{old)*2{row
    e =. ((6{row)*2{old)-(6{old)*2{row
    if. (d<0)+.(d=0)*.e<0 do. at =. j break. end.
   end.
   ranked =. (at{.ranked),i,at}.ranked
  end.
 end.
 for_j. i.#ranked do.
  i =. j{ranked
  row =. i{results
  say ((number j+1),'.');(i{::scenarioNames);('policy=',(1{row){::Policies);('avg_wait=',(5{row)avg 2{row);('avg_travel=',(6{row)avg 2{row);'max_wait=',number 7{row
 end.
 for_i. (i.q)-.ranked do.
  row =. i{results
  if. 0=0{row do. status =. 'invalid'
  elseif. 9{row do. status =. 'aborted' else. status =. 'empty' end.
  say '-';(i{::scenarioNames);status
 end.
 emit '== policies =='
 for_p. i.4 do.
  selected =. ranked#~p=ranked{1{"1 results
  if. #selected do.
   rs =. selected{results
   delivered =. +/2{"1 rs
   say ((p{::Policies),':');('runs=',number #selected);('avg_wait=',(+/5{"1 rs)avg delivered);'avg_travel=',(+/6{"1 rs)avg delivered
  end.
 end.
 for_line. Output do. ((>line),LF)1!:2 4 end.
 i.0
)
main ''
