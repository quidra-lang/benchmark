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
truncated =: 4 : 0
 c =. <.(100*x)%y
 (number <.c%100),'.',_2{.'00',number 100|c
)
Algorithms =: ;:'FCFS SJF SRTF RR PRIORITY HRRN EDF LOTTERY MLFQ'
Keys =: ;:'cs q k s seed'
Allowed =: (<,0),(<,0),(<,0),(<0 1),(<0 2),(<,0),(<,0),(<0 1 4),<0 3
Low =: 0 1 1 0 1
High =: 5 20 50 500 2147483646
MetricNames =: ;:'turnaround waiting response end switches missed'
StateNames =: ;:'FUTURE READY SWITCH RUN IO DONE'
EventNames =: ;:'PREEMPT EXPIRE DEMOTE BOOST AGE'
Ids =: Bursts =: 0$a:
Arrival =: Prio =: Deadline =: i.0
sort_registry =: 3 : 0
 order =. /:s:Ids
 Ids =: order{Ids
 Arrival =: order{Arrival
 Prio =: order{Prio
 Deadline =: order{Deadline
 Bursts =: order{Bursts
)
process =: 3 : 0
 i =. Ids i.<,y
 if. i=#Ids do. fail 'unknown process ',y end.
 i
)
describe =: 3 : 0
 bs =. y{::Bursts
 text =. 0$a:
 for_j. i.#bs do. text =. text,<((2|j){'CI'),number j{bs end.
 if. (y{Deadline)<0 do. deadline =. 'none' else. deadline =. number y{Deadline end.
 words (y{::Ids);('arrival=',number y{Arrival);('priority=',number y{Prio);('deadline=',deadline);'bursts=',','join text
)
parse_params =: 4 : 0
 'algorithm preset' =. x
 seen =. 5#0
 if. preset>:0 do. seen =. 1 preset}seen end.
 Params =: 0 4 5 0 1
 for_word. y do.
  'key value' =. '='split >word
  key =. >key
  value =. 0".>value
  k =. Keys i.<key
  if. k=5 do. fail 'unknown key ',key end.
  if. algorithm>:0 do.
   if. -.k e.algorithm{::Allowed do. fail 'key ',key,' not allowed for ',algorithm{::Algorithms end.
  end.
  if. k{seen do. fail 'duplicate key ',key end.
  if. (value<k{Low)+.value>k{High do. fail 'invalid ',key end.
  seen =. 1 k}seen
  Params =: value k}Params
 end.
)
notation =: 3 : 0
 if. y<0 do. ks =. i.5 else. ks =. y{::Allowed end.
 text =. 0$a:
 for_k. ks do. text =. text,<(k{::Keys),'=',number k{Params end.
 ' 'join text
)
NB. Job columns: state,burst,left,effective,wait,level,usage,enqueued,start,finish,selections.
ready =: 3 : ';Queues'
event =: 4 : 0
 Log =: Log,<(number Time),' ',x,((0<#y)#' '),y
 index =. EventNames i.<x
 if. index<5 do. Counts =: (1+index{Counts) index}Counts end.
)
enqueue =: 3 : 0
 Job =: 1 (<y,0)}Job
 Job =: Time (<y,7)}Job
 level =. 0
 if. Algorithm=8 do. level =. (<y,5){Job end.
 Queues =: (<(level{::Queues),y) level}Queues
)
fresh =: 3 : 0
 row =. ((<y,2){Job),Time,_1,_1,0
 Records =: (<(y{::Records),row) y}Records
 enqueue y
)
start =: 3 : 0
 CPU =: 2
 RunLength =: 0
 Job =: 3 (<Current,0)}Job
 if. ((<Current,8){Job)<0 do. Job =: Time (<Current,8)}Job end.
 records =. Current{::Records
 row =. _1{records
 if. (2{row)<0 do. row =. Time 2}row end.
 records =. row ((#records)-1)}records
 Records =: (<records) Current}Records
)
absolute =: 3 : 0
 if. (y{Deadline)<0 do. 1000000000 else. (y{Arrival)+y{Deadline end.
)
preempts =: 3 : 0
 for_i. ready '' do.
  select. Algorithm
  case. 2 do. if. ((<i,2){Job)<(<Current,2){Job do. 1 return. end.
  case. 4 do. if. ((<i,3){Job)<(<Current,3){Job do. 1 return. end.
  case. 6 do. if. (absolute i)<absolute Current do. 1 return. end.
  case. 8 do. if. ((<i,5){Job)<(<Current,5){Job do. 1 return. end.
  end.
 end.
 0
)
select_job =: 3 : 0
 list =. ready ''
 chosen =. {.list
 if. Algorithm=7 do.
  Random =: 2147483647|48271*Random
  draw =. (+/10-list{Prio)|Random
  for_i. list do.
   draw =. draw-10-i{Prio
   if. draw<0 do. i return. end.
  end.
 end.
 for_i. }.list do.
  better =. 0
  select. Algorithm
  case. 1;2 do. better =. ((<i,2){Job)<(<chosen,2){Job
  case. 4 do. better =. ((<i,3){Job)<(<chosen,3){Job
  case. 5 do.
   ai =. (<i,2){Job
   bi =. (<chosen,2){Job
   aw =. Time-(<i,7){Job
   bw =. Time-(<chosen,7){Job
   better =. ((aw+ai)*bi)>(bw+bi)*ai
  case. 6 do. better =. (absolute i)<absolute chosen
  end.
  if. better do. chosen =. i end.
 end.
 chosen
)
labeltext =: 3 : 0
 if. y=_1 do. 'CS' elseif. y=_2 do. 'IDLE' else. y{::Ids end.
)
snapshot =: 3 : 0
 if. CPU=0 do. out =. <'CPU IDLE'
 else. out =. <'CPU ',(CPU{::'IDLE';'SWITCH';'RUN'),' ',Current{::Ids end.
 for_q. i.1+2*Algorithm=8 do.
  list =. q{::Queues
  if. #list do. text =. ' 'join list{Ids else. text =. 'none' end.
  if. Algorithm=8 do. label =. 'QUEUE',number q else. label =. 'QUEUE' end.
  out =. out,<label,' ',text
 end.
 for_i. i.#Ids do.
  row =. i{Job
  state =. 0{row
  text =. (i{::Ids),' ',state{::StateNames
  if. state=0 do. text =. text,' at=',number i{Arrival
  elseif. state=5 do. text =. text,' at=',number 9{row
  else.
   text =. text,' burst=',(number 1+1{row),' left=',number 2{row
   if. Algorithm=4 do. text =. text,' prio=',number 3{row end.
   if. Algorithm=8 do. text =. text,' level=',(number 5{row),' used=',number 6{row end.
  end.
  out =. out,<text
 end.
 out
)
simulate =: 4 : 0
 Algorithm =: x
 SnapshotTime =: y
 n =. #Ids
 Job =: n 11$0
 Job =: Prio (<(i.n);3)}Job
 Job =: _1 (<(i.n);8 9)}Job
 for_i. i.n do. Job =: ({.i{::Bursts) (<i,2)}Job end.
 Records =: n$<0 5$0
 Timeline =: n$<''
 Queues =: 3$<i.0
 CPU =: SwitchLeft =: RunLength =: Switches =: 0
 Current =: Previous =: _1
 Random =: 4{Params
 Labels =: QueueLengths =: i.0
 Log =: Snapshot =: 0$a:
 Counts =: 5#0
 Time =: 0
 while. 1 do.
  if. Algorithm=4 do.
   for_i. 0{::Queues do.
    wait =. 1+(<i,4){Job
    if. wait=2{Params do.
     wait =. 0
     effective =. (<i,3){Job
     if. effective do.
      Job =: (effective-1) (<i,3)}Job
      'AGE'event (i{::Ids),' ',number effective-1
     end.
    end.
    Job =: wait (<i,4)}Job
   end.
  end.
  for_i. I.(4=0{"1 Job)*.0=2{"1 Job do.
   burst =. 1+(<i,1){Job
   Job =: burst (<i,1)}Job
   Job =: (burst{i{::Bursts) (<i,2)}Job
   fresh i
   'IODONE'event i{::Ids
  end.
  for_i. I.(0=0{"1 Job)*.Time=Arrival do. fresh i [ 'ARRIVE'event i{::Ids end.
  if. (CPU=1)*.SwitchLeft=0 do.
   start ''
   'START'event Current{::Ids
  elseif. CPU=2 do.
   row =. Current{Job
   if. (0=2{row)*.(1{row)=(#Current{::Bursts)-1 do.
    Job =: 5 (<Current,0)}Job
    Job =: Time (<Current,9)}Job
    'DONE'event Current{::Ids
    CPU =: 0
   else.
    demoted =. 0
    level =. 5{row
    if. (Algorithm=8)*.level<2 do.
     if. (6{row)=level{4 8 do.
      Job =: (level+1) (<Current,5)}Job
      Job =: 0 (<Current,6)}Job
      demoted =. 1
      'DEMOTE'event (Current{::Ids),' ',number level+1
     end.
    end.
    if. 0=2{row do.
     burst =. 1+1{row
     left =. burst{Current{::Bursts
     Job =: burst (<Current,1)}Job
     Job =: left (<Current,2)}Job
     Job =: 4 (<Current,0)}Job
     CPU =: 0
     'IO'event (Current{::Ids),' ',number left
    elseif. demoted do. enqueue Current [ CPU =: 0
    elseif. (Algorithm e.3 7)*.RunLength=1{Params do.
     enqueue Current
     'EXPIRE'event Current{::Ids
     CPU =: 0
    elseif. preempts '' do.
     enqueue Current
     'PREEMPT'event Current{::Ids
     CPU =: 0
    end.
   end.
  end.
  if. *./5=0{"1 Job do.
   if. (SnapshotTime>:0)*.0=#Snapshot do. Snapshot =: snapshot '' end.
   break.
  end.
  boost =. 3{Params
  if. (Algorithm=8)*.(boost>0)*.Time>0 do.
   if. 0=boost|Time do.
    all =. ready ''
    Queues =: (<all),2$<i.0
    Job =: 0 (<(i.n);5 6)}Job
    'BOOST'event ''
   end.
  end.
  if. (CPU=0)*.0<#ready '' do.
   Current =: select_job ''
   level =. 0
   if. Algorithm=8 do. level =. (<Current,5){Job end.
   list =. level{::Queues
   Queues =: (<list#~list~:Current) level}Queues
   Job =: (Current{Prio) (<Current,3)}Job
   Job =: 0 (<Current,4)}Job
   Job =: (1+(<Current,10){Job) (<Current,10)}Job
   records =. Current{::Records
   records =. (1+(<((#records)-1),4){records) (<((#records)-1),4)}records
   Records =: (<records) Current}Records
   change =. Current~:Previous
   Switches =: Switches+change
   if. change*.0{Params do.
    CPU =: 1
    Job =: 2 (<Current,0)}Job
    SwitchLeft =: 0{Params
    'SWITCH'event Current{::Ids
   else.
    start ''
    'DISPATCH'event Current{::Ids
   end.
  end.
  if. Time=SnapshotTime do. Snapshot =: snapshot '' end.
  QueueLengths =: QueueLengths,#ready ''
  for_i. i.n do. Timeline =: (<(i{::Timeline),((<i,0){Job){'-.s#i-') i}Timeline end.
  if. CPU=2 do.
   Job =: (((<Current,2){Job)-1) (<Current,2)}Job
   Job =: (1+(<Current,6){Job) (<Current,6)}Job
   RunLength =: RunLength+1
   Previous =: Current
   Labels =: Labels,Current
   if. 0=(<Current,2){Job do.
    records =. Current{::Records
    records =. (Time+1) (<((#records)-1),3)}records
    Records =: (<records) Current}Records
   end.
  elseif. CPU=1 do. SwitchLeft =: SwitchLeft-1 [ Labels =: Labels,_1
  else. Labels =: Labels,_2 end.
  selected =. I.4=0{"1 Job
  for_i. selected do. Job =: (((<i,2){Job)-1) (<i,2)}Job end.
  Time =: Time+1
 end.
 Metrics =: 0 3$0
 met =. missed =. 0
 for_i. i.n do.
  turn =. ((<i,9){Job)-i{Arrival
  wait =. turn-+/i{::Bursts
  response =. ((<i,8){Job)-i{Arrival
  Metrics =: Metrics,turn,wait,response
  if. (i{Deadline)>:0 do.
   if. ((<i,9){Job)<:absolute i do. met =. met+1 else. missed =. missed+1 end.
  end.
 end.
 Summary =: (+/Metrics),(+/Labels>:0),(+/_1=Labels),(+/_2=Labels),Time,Switches,met,missed
 Summary
)
util =: 3 : '(100*3{y)truncated 6{y'
summary_averages =: 3 : 0
 r =. 0$a:
 for_i. i.3 do. r =. r,<(i{y)truncated #Ids end.
 r
)
table_row =: 3 : 0
 text =. 8{.(0{::y),8#' '
 for_cell. }.y do. text =. text,' ',_8{.(8#' '),>cell end.
 emit text
)
single =: 4 : 0
 'cmd algorithm' =. x
 if. cmd eq 'SNAPSHOT' do. snapshotAt =. 0".1{::y else. snapshotAt =. _1 end.
 r =. algorithm simulate snapshotAt
 header =. cmd,' ',(algorithm{::Algorithms),' ',notation algorithm
 if. cmd eq 'TIMELINE' do.
  if. Time>100 do. fail 'too long ',number Time end.
  emit header,' end=',number Time
  for_i. i.#Ids do. emit (8{.(i{::Ids),8#' '),' ',i{::Timeline end.
  return.
 end.
 if. cmd eq 'SNAPSHOT' do.
  emit header,' t=',1{::y
  for_line. Snapshot do. emit >line end.
  return.
 end.
 emit header
 select. cmd
 case. 'TRACE' do.
  for_line. Log do. emit >line end.
  say 'END';Time
 case. 'BURSTS' do.
  for_i. i.#Ids do.
   records =. i{::Records
   for_j. i.#records do.
    'len ready start end slices' =. j{records
    say (i{::Ids);('#',number j+1);('len=',number len);('ready=',number ready);('start=',number start);('end=',number end);('wait=',number end-ready+len);'slices=',number slices
   end.
  end.
 case. 'WINDOW' do.
  width =. 0".1{::y
  for_a. width*i.>.Time%width do.
   b =. Time<.a+width
   labels =. (b-a){.a}.Labels
   busy =. +/labels>:0
   sw =. +/labels=_1
   idle =. +/labels=_2
   best =. 0
   top =. 'none'
   for_i. i.#Ids do.
    count =. +/labels=i
    if. count>best do. best =. count [ top =. i{::Ids end.
   end.
   say ((number a),'-',number b);('busy=',number busy);('switch=',number sw);('idle=',number idle);('util=',(100*busy)truncated b-a);'top=',top
  end.
 case. 'STATS' do.
  for_k. i.3 do.
   values =. k{"1 Metrics
   sorted =. /:~values
   n =. #values
   if. 2|n do. twice =. 2*(<.n%2){sorted else. twice =. ((<.n%2){sorted)+((<.n%2)-1){sorted end.
   lo =. <./values
   hi =. >./values
   med =. (number <.twice%2),'.',((2|twice){'05')
   say (k{::MetricNames);('min=',number lo);('(',((values i.lo){::Ids),')');('max=',number hi);('(',((values i.hi){::Ids),')');('median=',med);'total=',number +/values
  end.
 case. 'RUN' do.
  segments =. 0$a:
  a =. 0
  while. a<Time do.
   label =. labeltext a{Labels
   b =. a+1
   while. b<Time do.
    if. -.label eq labeltext b{Labels do. break. end.
    b =. b+1
   end.
   segments =. segments,<'[',(number a),'-',(number b),' ',label,']'
   a =. b
  end.
  for_i. 8*i.>.(#segments)%8 do. emit 'GANTT ',;8{.i}.segments end.
  for_i. i.#Ids do.
   'turn wait response' =. i{Metrics
   text =. words (i{::Ids);('arrival=',number i{Arrival);('done=',number (<i,9){Job);('turnaround=',number turn);('waiting=',number wait);('response=',number response);'slices=',number (<i,10){Job
   if. (i{Deadline)>:0 do. text =. text,' deadline=',(number absolute i),' late=',number 0>.((<i,9){Job)-absolute i end.
   emit text
  end.
  av =. summary_averages r
  say 'AVERAGE';('turnaround=',0{::av);('waiting=',1{::av);'response=',2{::av
  say 'CPU';('end=',number Time);('busy=',number 3{r);('switch=',number 4{r);('idle=',number 5{r);('switches=',number Switches);'util=',util r
  say 'QUEUE';('max=',number >./QueueLengths);'avg=',(+/QueueLengths)truncated Time
  say 'EVENTS';('preempt=',number 0{Counts);('expire=',number 1{Counts);('demote=',number 2{Counts);('boost=',number 3{Counts);'age=',number 4{Counts
  say 'DEADLINE';('met=',number 8{r);'missed=',number 9{r
 end.
)
handle =: 4 : 0
 select. x
 case. 'PROC' do.
  id =. 0{::y
  if. (<id)e.Ids do. fail 'duplicate process ',id end.
  if. 10=#Ids do. fail 'too many processes' end.
  arrival =. 0".1{::y
  priority =. 0".2{::y
  if. arrival>200 do. fail 'invalid arrival ',id end.
  if. priority>9 do. fail 'invalid priority ',id end.
  text =. 3}.y
  bad =. 0=2|#text
  bs =. i.0
  for_j. i.#text do.
   token =. j{::text
   n =. 0".}.token
   if. (({.token)~:(2|j){'CI')+.(n<1)+.n>30 do. bad =. 1 end.
   bs =. bs,n
  end.
  if. bad do. fail 'invalid bursts ',id end.
  Ids =: Ids,<id
  Arrival =: Arrival,arrival
  Prio =: Prio,priority
  Deadline =: Deadline,_1
  Bursts =: Bursts,<bs
  say x;id;('cpu=',number +/bs#~0=2|i.#bs);'io=',number +/bs#~1=2|i.#bs
  sort_registry ''
  return.
 case. 'GEN' do.
  prefix =. 0{::y
  count =. 0".1{::y
  for_i. 1+i.count do.
   id =. prefix,number i
   if. (<id)e.Ids do. fail 'duplicate process ',id end.
  end.
  if. 10<(#Ids)+count do. fail 'too many processes' end.
  random =. 0".2{::y
  emit 'GEN count=',number count
  for_i. 1+i.count do.
   id =. prefix,number i
   random =. 2147483647|48271*random
   arrival =. 21|random
   random =. 2147483647|48271*random
   priority =. 10|random
   random =. 2147483647|48271*random
   m =. 1+3|random
   bs =. i.0
   for_j. i.m do.
    if. j do.
     random =. 2147483647|48271*random
     bs =. bs,1+8|random
    end.
    random =. 2147483647|48271*random
    bs =. bs,1+9|random
   end.
   Ids =: Ids,<id
   Arrival =: Arrival,arrival
   Prio =: Prio,priority
   Deadline =: Deadline,_1
   Bursts =: Bursts,<bs
   emit describe (#Ids)-1
  end.
  sort_registry ''
  return.
 case. 'SETPRIO';'DEADLINE';'DROP' do.
  i =. process 0{::y
  id =. i{::Ids
  if. x eq 'DROP' do.
   keep =. (i.#Ids)-.i
   Ids =: keep{Ids
   Arrival =: keep{Arrival
   Prio =: keep{Prio
   Deadline =: keep{Deadline
   Bursts =: keep{Bursts
   say x;id
  else.
   n =. 0".1{::y
   if. x eq 'SETPRIO' do.
    if. n>9 do. fail 'invalid priority ',id end.
    Prio =: n i}Prio
    say x;id;'priority=',number n
   else.
    if. n>1000 do. fail 'invalid deadline ',id end.
    if. n=0 do. d =. _1 [ text =. 'none' else. d =. n [ text =. number n end.
    Deadline =: d i}Deadline
    say x;id;text
   end.
  end.
  return.
 case. 'CLEAR' do.
  emit 'CLEAR count=',number #Ids
  Ids =: Bursts =: 0$a:
  Arrival =: Prio =: Deadline =: i.0
  return.
 case. 'LIST' do.
  emit 'LIST count=',number #Ids
  for_i. i.#Ids do. emit describe i end.
  return.
 end.
 algorithm =. _1
 multiple =. (<x)e.;:'DIFF COMPARE RANK'
 if. -.(<x)e.;:'COMPARE RANK' do.
  algorithm =. Algorithms i.0{y
  if. algorithm=9 do. fail 'unknown algorithm ',0{::y end.
 end.
 if. x eq 'DIFF' do.
  other =. Algorithms i.1{y
  if. other=9 do. fail 'unknown algorithm ',1{::y end.
 end.
 if. x eq 'RANK' do.
  metric =. MetricNames i.0{y
  if. metric=6 do. fail 'unknown metric ',0{::y end.
 end.
 start =. 1
 preset =. _1
 if. x eq 'COMPARE' do. start =. 0 end.
 if. (<x)e.;:'SNAPSHOT WINDOW DIFF' do. start =. 2 end.
 if. x eq 'WINDOW' do.
  w =. 0".1{::y
  if. (w<1)+.w>1000 do. fail 'invalid window' end.
 end.
 if. x eq 'SWEEP' do.
  key =. 1{::y
  preset =. Keys i.<key
  if. preset=5 do. fail 'unknown key ',key end.
  if. -.preset e.algorithm{::Allowed do. fail 'key ',key,' not allowed for ',algorithm{::Algorithms end.
  lo =. 0".2{::y
  hi =. 0".3{::y
  if. (lo>hi)+.(lo<preset{Low)+.(hi>preset{High)+.20<hi-lo do. fail 'invalid range' end.
  start =. 4
 end.
 if. multiple do. allowed =. _1 else. allowed =. algorithm end.
 (allowed,preset)parse_params start}.y
 if. 0=#Ids do. fail 'no processes' end.
 if. x eq 'SWEEP' do.
  say x;(algorithm{::Algorithms);key;lo;hi
  best =. lo
  bestvalue =. _1
  for_v. lo+i.1+hi-lo do.
   Params =: v preset}Params
   r =. algorithm simulate _1
   av =. summary_averages r
   say (notation algorithm);('turnaround=',0{::av);('waiting=',1{::av);('response=',2{::av);('util=',util r);('end=',number 6{r);'switches=',number 7{r
   if. (bestvalue<0)+.(1{r)<bestvalue do. best =. v [ bestvalue =. 1{r end.
  end.
  emit 'BEST ',key,'=',number best
 elseif. x eq 'DIFF' do.
  algorithm simulate _1
  first =. Metrics
  other simulate _1
  say x;(algorithm{::Algorithms);(other{::Algorithms);notation _1
  for_i. i.#Ids do.
   a =. i{first
   b =. i{Metrics
   say (i{::Ids);('turnaround=',(number 0{a),'/',number 0{b);('waiting=',(number 1{a),'/',number 1{b);'response=',(number 2{a),'/',number 2{b
  end.
  say 'WINS';((algorithm{::Algorithms),'=',number +/(0{"1 first)<0{"1 Metrics);((other{::Algorithms),'=',number +/(0{"1 first)>0{"1 Metrics);'ties=',number +/(0{"1 first)=0{"1 Metrics
 elseif. (<x)e.;:'COMPARE RANK' do.
  results =. 0 10$0
  for_a. i.9 do. results =. results,a simulate _1 end.
  if. x eq 'COMPARE' do.
   emit 'COMPARE ',notation _1
   table_row ;:'ALGO TURN WAIT RESP UTIL END SWITCH MISS'
   for_i. i.9 do.
    r =. i{results
    table_row (<i{::Algorithms),(summary_averages r),(<util r),number&.><"0 6 7 9{r
   end.
   text =. 'BEST'
   for_k. i.3 do.
    values =. k{"1 results
    best =. values i.<./values
    text =. text,' ',(k{::MetricNames),'=',best{::Algorithms
   end.
   emit text
  else.
   say x;(0{::y);notation _1
   if. metric<3 do. values =. metric{"1 results
   else. values =. ((metric-3){6 7 9){"1 results end.
   for_i. /:values do.
    rank =. 1++/values<i{values
    if. metric<3 do. value =. (i{values)truncated #Ids else. value =. number i{values end.
    say rank;(i{::Algorithms);value
   end.
  end.
 else. (x;algorithm)single y end.
)
main =: 3 : 0
 n =. 0".1!:1 3
 for_i. i.n do.
  fields =. ' 'split 1!:1 3
  Output =: 0$a:
  try. (0{::fields)handle }.fields
  catcht. emit 'ERROR ',Error end.
  for_line. Output do. ((>line),LF)1!:2 4 end.
 end.
 i.0
)
main ''
