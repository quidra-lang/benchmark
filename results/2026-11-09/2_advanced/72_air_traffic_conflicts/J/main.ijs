ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'report.ijs'
load SourceDirectory,'flight_plans.ijs'
load SourceDirectory,'trajectory.ijs'
load SourceDirectory,'conflict.ijs'
load SourceDirectory,'resolution.ijs'
contains =: 4 : 0
 'x1 y1 x2 y2 lower upper capacity' =. x
 'px py pz' =. y
 (px>:x1%10)*.(px<x2%10)*.(py>:y1%10)*.(py<y2%10)*.(pz>:100*lower)*.pz<100*upper
)
classification =: 4 : 0
 'a b start end pieces closest' =. y
 'ia ib lo hi tc dist vert' =. closest
 sa =. ia{a{::x
 sb =. ib{b{::x
 pa =. sa position tc
 pb =. sb position tc
 ta =. track sa
 tb =. track sb
 angle =. |ta-tb
 if. angle>180 do. angle =. 360-angle end.
 dot =. ((8{sa)*8{sb)+(9{sa)*9{sb
 cross =. ((8{sa)*9{sb)-(9{sa)*8{sb
 geometry =. 'crossing'
 if. (dot*dot)>cross*cross do. geometry =. (dot<0){::'trailing';'head_on' end.
 severity =. 'LOW'
 if. (10*dist)<4*Dh do. severity =. 'HIGH' elseif. (10*dist)<7*Dh do. severity =. 'MEDIUM' end.
 sector =. _1
 for_s. i.#Sectors do. if. (s{Sectors)contains (pa+pb)%2 do. sector =. s
 break. end. end.
 pa;pb;ta;tb;angle;geometry;severity;sector;sa;sb
)
sector_interval =: 4 : 0
 segment =. x
 sector =. y
 lo =. 3{segment
 hi =. 4{segment
 lower =. (0 1{sector)%10
 upper =. (2 3{sector)%10
 lower =. lower,100*4{sector
 upper =. upper,100*5{sector
 for_i. i.3 do.
  p =. (5+i){segment
  v =. (8+i){segment
  a =. i{lower
  b =. i{upper
  if. v=0 do. if. (p<a)+.p>:b do. i.0 return. end.
  else.
   r1 =. (a-p)%v
   r2 =. (b-p)%v
   lo =. lo>.(3{segment)+r1<.r2
   hi =. hi<.(3{segment)+r1>.r2
  end.
 end.
 if. (hi-lo)>1e_6 do. lo,hi else. i.0 end.
)
transits =: 3 : 0
 all =. 0 6$0.0
 for_a. i.NF do.
  out =. 0 6$0.0
  for_s. i.#Sectors do.
   intervals =. 0 2$0.0
   for_seg. a{::y do.
    v =. seg sector_interval s{Sectors
    if. 0=#v do. continue. end.
    merge =. 0
    if. #intervals do. merge =. (({.v)-(<((#intervals)-1),1){intervals)<:1e_6 end.
    if. merge do. intervals =. ({:v)(<((#intervals)-1),1)}intervals else. intervals =. intervals,v end.
   end.
   for_interval. intervals do. out =. out,a,s,interval,_1 _1 end.
  end.
  out =. (/:2 1{"1 out){out
  for_i. i.(#out)-1 do.
   if. (|((<(i+1),2){out)-(<i,3){out)<:1e_6 do.
    out =. ((<(i+1),1){out)(<i,5)}out
    out =. ((<i,1){out)(<(i+1),4)}out
   end.
  end.
  all =. all,out
 end.
 all
)
occupancy =: 3 : 0
 out =. ((#Sectors),#SampleTimes)$0
 for_j. i.#SampleTimes do.
  t =. j{SampleTimes
  for_a. i.NF do.
   path =. a{::y
   si =. path segment_at t
   if. si<0 do. continue. end.
   pos =. (si{path)position t
   for_s. i.#Sectors do. if. (s{Sectors)contains pos do. out =. (1+(<s,j){out)(<s,j)}out end. end.
  end.
 end.
 out
)
conflict_report =: 3 : 0
 'plan paths conflicts' =. y
 out =. <'CONFLICTS plan=| count=|'render plan;#conflicts
 geometries =. severities =. 0$a:
 distances =. durations =. i.0
 for_i. i.#conflicts do.
  c =. i{::conflicts
  'a b start end pieces closest' =. c
  'ia ib lo hi tc dist vert' =. closest
  'pa pb ta tb angle geometry severity sector sa sb' =. paths classification c
  geometries =. geometries,<geometry
  severities =. severities,<severity
  distances =. distances,dist
  durations =. durations,end-start
  outcome =. 'indirect'
  pair =. a,b
  if. +./pair-:"1 FinalPairs do. outcome =. 'remaining'
  elseif. (<pair)e.Resolved do. outcome =. 'resolved' end.
  out =. out,<'CONFLICT | | start=| end=| duration=| outcome=|'render (i+1);(pair_name pair);(fixed start);(fixed end);(fixed end-start);outcome
  out =. out,<'  CPA t=| dist=| vert=| levels=|/| tracks=|/| angle=|'render (fixed tc);(fixed dist);(1 fmt vert);(2 fmt (2{pa)%100);(2 fmt (2{pb)%100);(1 fmt ta);(1 fmt tb);1 fmt angle
  out =. out,<'  TYPE geometry=| phases=|/| segments=|/| sector=| severity=|'render geometry;((2{sa){::Phases);((2{sb){::Phases);(ia+1);(ib+1);(sector_name sector);severity
  for_piece. pieces do. out =. out,<'  PIECE |/| | |'render ((0{piece)+1);((1{piece)+1);(fixed 2{piece);fixed 3{piece end.
 end.
 md =. '-'
 if. #distances do. md =. fixed <./distances end.
 out =. out,<'SUMMARY count=| total=| min_dist=| head_on=| crossing=| trailing=| high=| medium=| low=|'render (#conflicts);(fixed sum durations);md;(+/(<'head_on')=geometries);(+/(<'crossing')=geometries);(+/(<'trailing')=geometries);(+/(<'HIGH')=severities);(+/(<'MEDIUM')=severities);+/(<'LOW')=severities
 involved =. i.0
 for_a. i.NF do.
  partners =. i.0
  starts =. i.0
  for_c. conflicts do.
   c =. >c
   if. a e.(0{::c),1{::c do. partners =. partners,((0{::c),1{::c)-.a
   starts =. starts,2{::c end.
  end.
  if. #starts do.
   involved =. involved,a
   out =. out,<'FLIGHT | conflicts=| first=| partners=|'render (a{::Callsigns);(#starts);(fixed <./starts);','join (/:~~.partners){Callsigns
  end.
 end.
 out =. out,<'TIMELINE from=| to=| step=60'render Ta;Tb
 for_a. involved do.
  timeline =. ''
  for_t. SampleTimes do.
   ch =. '.'
   if. ((a{::paths)segment_at t)>:_0 do.
    ch =. '-'
    for_c. conflicts do.
     'i j start end pieces closest' =. >c
     if. (a e.i,j)*.(t>:start)*.t<end do. ch =. 'X'
     break. end.
    end.
   end.
   timeline =. timeline,ch
  end.
  out =. out,<emit (a{::Callsigns);timeline
 end.
 out
)
alert_report =: 3 : 0
 'plan paths conflicts' =. y
 alerts =. 0 7$0.0
 for_a. i.NF do.
  for_b. (a+1)+i.(NF-a)-1 do.
   pairalerts =. 0 7$0.0
   for_t. SampleTimes do.
    pa =. a{::paths
    pb =. b{::paths
    ia =. pa segment_at t
    ib =. pb segment_at t
    if. (ia<0)+.ib<0 do. continue. end.
    sa =. ia{pa
    sb =. ib{pb
    v =. loss_interval ((sa position t)-sb position t);((8 9 10{sa)-8 9 10{sb);0;pn 'alert'
    if. 0=#v do. continue. end.
    merge =. 0
    if. #pairalerts do. merge =. t=60+(<((#pairalerts)-1),3){pairalerts end.
    if. merge do.
     last =. {:pairalerts
     last =. t 3}last
     last =. (1+4{last)4}last
     last =. ((6{last)<.3{v)6}last
     pairalerts =. last ((#pairalerts)-1)}pairalerts
    else. pairalerts =. pairalerts,a,b,t,t,1,(t+0{v),3{v end.
   end.
   alerts =. alerts,pairalerts
  end.
 end.
 alerts =. (/:2 0 1{"1 alerts){alerts
 out =. <'ALERTS plan=| horizon=| count=|'render plan;(pn 'alert');#alerts
 detected =. (#conflicts)$0
 leads =. i.0
 for_i. i.#alerts do.
  'a b first last samples predicted minimum' =. i{alerts
  matches =. i.0
  for_j. i.#conflicts do.
   c =. j{::conflicts
   if. (a=0{::c)*.(b=1{::c)*.((2{::c)<last+pn 'alert')*.(3{::c)>first do. matches =. matches,j end.
  end.
  result =. 'status=false lead=-'
  if. #matches do.
   detected =. 1 matches}detected
   lead =. (2{::({.matches){::conflicts)-first
   leads =. leads,lead
   result =. 'status=true lead=',fixed lead
  end.
  out =. out,<'ALERT | | first=| last=| samples=| predicted=| min_dist=| |'render (i+1);(pair_name a,b);first;last;samples;(fixed predicted);(fixed minimum);result
 end.
 for_i. I.-.detected do.
  c =. i{::conflicts
  out =. out,<'MISSED | start=| end=|'render (pair_name (0{::c),1{::c);(fixed 2{::c);fixed 3{::c
 end.
 mean =. '-'
 if. #leads do. mean =. fixed (sum leads)%#leads end.
 out,<'SUMMARY alerts=| true=| false=| missed=| mean_lead=|'render (#alerts);(#leads);((#alerts)-#leads);(+/-.detected);mean
)
screen =: 3 : 0
 'x y z' =. y
 col =. <.(((10*x)-Rx0)*Rw)%(Rx1-Rx0)
 row =. <.(((10*y)-Ry0)*Rh)%(Ry1-Ry0)
 if. (col<0)+.(col>:Rw)+.(row<0)+.row>:Rh do. _1 _1 else. col,(Rh-1)-row end.
)
radar =: 3 : 0
 'plan paths conflicts t' =. y
 cells =. (Rh,Rw)$'.'
 counts =. (Rh,Rw)$0
 letters =. (Rh,Rw)$'.'
 info =. 0$a:
 active =. 0$a:
 for_c. conflicts do. c =. >c
 if. (t>:2{::c)*.t<3{::c do. active =. active,<c end. end.
 inflight =. i.0
 for_a. i.NF do.
  path =. a{::paths
  i =. path segment_at t
  if. i<0 do. continue. end.
  inflight =. inflight,a
  seg =. i{path
  pos =. seg position t
  'col row' =. screen pos
  where =. 'outside'
  if. col>:0 do.
   where =. (str col),',',str row
   counts =. (1+(<row,col){counts)(<row,col)}counts
   ch =. {.a{::Callsigns
   for_c. active do. if. a e.(0{::>c),1{::>c do. ch =. a.{~32+a.i.ch
   break. end. end.
   letters =. ch(<row,col)}letters
  end.
  info =. info,<'| x=| y=| fl=| track=| phase=| cell=|'render (a{::Callsigns);(fixed 0{pos);(fixed 1{pos);(2 fmt (2{pos)%100);(1 fmt track seg);((2{seg){::Phases);where
 end.
 for_row. i.Rh do.
  for_col. i.Rw do.
   n =. (<row,col){counts
   if. n=1 do. ch =. (<row,col){letters elseif. n>1 do. ch =. n{'0123456789' else. ch =. '.' end.
   cells =. ch(<row,col)}cells
  end.
 end.
 for_a. inflight do.
  path =. a{::paths
  future =. t+pn 'leader'
  si =. path segment_at future
  if. si<0 do. continue. end.
  'col row' =. screen (si{path)position future
  if. col>:0 do. if. '.'=(<row,col){cells do. cells =. '*'(<row,col)}cells end. end.
 end.
 out =. (<'RADAR plan=| t=| aircraft=| conflicts=|'render plan;t;(#inflight);#active),chart cells
 out =. out,info
 for_c. active do.
  'a b start end pieces closest' =. >c
  ap =. a{::paths
  bp =. b{::paths
  pa =. ((ap segment_at t){ap)position t
  pb =. ((bp segment_at t){bp)position t
  diff =. pa-pb
  out =. out,<'CONFLICT | dist=| vert=|'render (pair_name a,b);(fixed %:sum *:2{.diff);1 fmt |2{diff
 end.
 out
)
main =: 3 : 0
 read_plans ''
 InitialPlans =: Plans
 InitialPaths =: 0$a:
 Lengths =: i.0
 for_p. Plans do. 'path len' =. trajectory >p
 InitialPaths =: InitialPaths,<path
 Lengths =: Lengths,len end.
 paths =. InitialPaths
 initialconflicts =. all_conflicts paths
 Resolved =: unresolvedpairs =. unresolved =. 0$a:
 ManoeuvreHistory =: NF$<0$a:
 resolutions =. 0$a:
 rounds =. trials =. infeasible =. blocked =. 0
 acceptedtypes =. 3$0
 while. 1 do.
  conflicts =. all_conflicts paths
  target =. i.0
  for_c. conflicts do.
   c =. >c
   if. -.(<(0{::c),1{::c)e.unresolvedpairs do. target =. c
   break. end.
  end.
  if. 0=#target do. break. end.
  'a b start end pieces closest' =. target
  rounds =. rounds+1
  resolutions =. resolutions,<'ROUND | | start=| end=| dist=|'render rounds;(pair_name a,b);(fixed start);(fixed end);fixed 5{closest
  order =. b,a
  if. (a{::Plans)priority b{::Plans do. order =. a,b end.
  accepted =. 0
  for_f. order do.
   partner =. {. (a,b)-.f
   for_man. manoeuvres '' do.
    man =. >man
    trials =. trials+1
    'feasible proposal' =. man apply_manoeuvre f{::Plans
    prefix =. emit '  TRY';(f{::Callsigns);man
    if. -.feasible do. resolutions =. resolutions,<prefix,' infeasible'
    infeasible =. infeasible+1
    continue. end.
    'path len' =. trajectory proposal
    proposedpaths =. (<path)f}paths
    blockers =. 0$a:
    for_c. all_conflicts proposedpaths do.
     c =. >c
     pair =. (0{::c),1{::c
     if. (f e.pair)*.-.(<pair)e.unresolvedpairs do.
      other =. {.pair-.f
      if. (other=partner)+.(2{::c)<start+pn 'lookahead' do. blockers =. blockers,<c end.
     end.
    end.
    if. #blockers do.
     blocker =. 0{::blockers
     resolutions =. resolutions,<prefix,' blocked ',(pair_name (0{::blocker),1{::blocker),' start=',fixed 2{::blocker
     blocked =. blocked+1
     continue.
    end.
    Plans =: (<proposal)f}Plans
    paths =. proposedpaths
    history =. (f{::ManoeuvreHistory),<man
    ManoeuvreHistory =: (<history)f}ManoeuvreHistory
    kind =. 2
    if. 'level_'-:6{.man do. kind =. 0 elseif. man-:'speed_down' do. kind =. 1 end.
    acceptedtypes =. (1+kind{acceptedtypes)kind}acceptedtypes
    resolutions =. resolutions,(<prefix,' accepted'),<'  RESULT resolved ',(f{::Callsigns),' ',man
    accepted =. 1
    break.
   end.
   if. accepted do. break. end.
  end.
  if. accepted do. Resolved =: ~.Resolved,<(a,b)
  else. unresolvedpairs =. unresolvedpairs,<a,b
  unresolved =. unresolved,<target
  resolutions =. resolutions,<'  RESULT unresolved' end.
 end.
 FinalPaths =: paths
 finalconflicts =. all_conflicts paths
 FinalPairs =: 0 2$0
 for_c. finalconflicts do. c =. >c
 FinalPairs =: FinalPairs,(0{::c),1{::c end.
 extras =. i.0
 for_a. i.NF do.
  p =. a{::Plans
  op =. a{::InitialPlans
  initialarrival =. arrival a{::InitialPaths
  finalarrival =. arrival a{::paths
  extra =. finalarrival-initialarrival
  extras =. extras,extra
  ni =. nf =. 0
  for_c. initialconflicts do. ni =. ni+a e.(0{::>c),1{::>c end.
  for_c. finalconflicts do. nf =. nf+a e.(0{::>c),1{::>c end.
  hist =. '-'
  if. #a{::ManoeuvreHistory do. hist =. ','join a{::ManoeuvreHistory end.
  offset =. str 7{::p
  if. (7{::p)>0 do. offset =. '+',offset end.
  resolutions =. resolutions,<'FLIGHT | departure=| delay=| level=| speed=|->| arrival=|->| extra=| length=| conflicts=|->| manoeuvres=|'render (a{::Callsigns);((2{::p)+6{::p);(6{::p);offset;(8{::op);(8{::p);(fixed initialarrival);(fixed finalarrival);(fixed extra);(fixed a{Lengths);ni;nf;hist
 end.
 for_c. unresolved do. c =. >c
 resolutions =. resolutions,<'UNRESOLVED | start=| dist=|'render (pair_name (0{::c),1{::c);(fixed 2{::c);fixed 5{5{::c end.
 delays =. +/6{::&>Plans
 resolutions =. resolutions,<'TOTAL rounds=| resolved=| unresolved=| level=| speed=| delay=| total_delay=| total_extra=| trials=| infeasible=| blocked=|'render rounds;(rounds-#unresolved);(#unresolved);(0{acceptedtypes);(1{acceptedtypes);(2{acceptedtypes);delays;(fixed sum extras);trials;infeasible;blocked
 trajectorycsv =. <'callsign,segment,leg,phase,t_start,t_end,x_start,y_start,fl_start,x_end,y_end,fl_end'
 for_a. i.NF do.
  for_s. a{::paths do.
   trajectorycsv =. trajectorycsv,<','join (a{::Callsigns);(str 0{s);(str 1{s);((2{s){::Phases);(fixed 3{s);(fixed 4{s);(fixed 5{s);(fixed 6{s);(str <.(7{s)%100);(fixed 11{s);(fixed 12{s);str <.(13{s)%100
  end.
 end.
 trinitial =. transits InitialPaths
 trfinal =. transits paths
 oi =. occupancy InitialPaths
 of =. occupancy paths
 transitscsv =. <'callsign,sector,entry,exit,duration,from,to'
 for_tr. trfinal do.
  'a s en ex previous next' =. tr
  transitscsv =. transitscsv,<','join (a{::Callsigns);(s{::SectorNames);(fixed en);(fixed ex);(fixed ex-en);(sector_name previous);sector_name next
 end.
 loadcsv =. <'sector,period,start,end,entries_initial,entries_final,peak_initial,peak_final,mean_final,capacity,status'
 sectorreport =. 0$a:
 nperiods =. <.(#SampleTimes)%5
 for_s. i.#Sectors do.
  'x1 y1 x2 y2 lower upper capacity' =. s{Sectors
  sectorreport =. sectorreport,<'SECTOR | x=|..| y=|..| fl=|..| capacity=|'render (s{::SectorNames);x1;x2;y1;y2;lower;upper;capacity
  ti =. trinitial#~s=1{"1 trinitial
  tf =. trfinal#~s=1{"1 trfinal
  vi =. s{oi
  vf =. s{of
  pi =. >./"1 (nperiods,5)$vi
  pf =. >./"1 (nperiods,5)$vf
  for_period. i.nperiods do.
   start =. Ta+300*period
   end =. start+300
   eni =. +/((2{"1 ti)>:start)*.(2{"1 ti)<end
   enf =. +/((2{"1 tf)>:start)*.(2{"1 tf)<end
   status =. 'OK'
   if. (period{pf)>capacity do. status =. 'OVER' elseif. (period{pi)>capacity do. status =. 'RELIEVED' end.
   loadcsv =. loadcsv,<','join (s{::SectorNames);(str period+1);(str start);(str end);(str eni);(str enf);(str period{pi);(str period{pf);(1 fmt (+/(period*5+i.5){vf)%5);(str capacity);status
  end.
  for_k. i.2 do.
   if. k=0 do. ts =. ti
   occupancyvalues =. vi
   peaks =. pi
   cs =. initialconflicts
   ps =. InitialPaths
   else. ts =. tf
   occupancyvalues =. vf
   peaks =. pf
   cs =. finalconflicts
   ps =. paths end.
   dwell =. sum (3{"1 ts)-2{"1 ts
   mean =. '-'
   if. #ts do. mean =. fixed dwell%#ts end.
   cc =. 0
   for_c. cs do. cc =. cc+s=7{::ps classification >c end.
   sectorreport =. sectorreport,<'| entries=| time=| mean=| peak=| over=| conflicts=|'render (k{::'INITIAL';'FINAL');(#ts);(fixed dwell);mean;(>./occupancyvalues);(+/peaks>capacity);cc
  end.
  height =. (capacity+1)>.>./vf
  cells =. (height,#SampleTimes)$'.'
  for_r. i.height do.
   value =. height-r
   line =. (#SampleTimes)#'.'
   if. value=capacity do. line =. (#SampleTimes)#'-' end.
   line =. '#'(I.vf>:value)}line
   cells =. line r}cells
  end.
  sectorreport =. sectorreport,chart cells
 end.
 sectorreport =. sectorreport,<'LEVELS'
 levels =. i.0
 for_ps. InitialPaths;paths do.
  for_path. >ps do.
   for_seg. >path do. if. (2{seg)=0 do. levels =. levels,<.(7{seg)%100 end. end.
  end.
 end.
 for_level. \:~~.levels do.
  counts =. times =. i.0
  for_ps. InitialPaths;paths do.
   flights =. 0
   total =. 0.0
   for_path. >ps do.
    found =. 0
    for_seg. >path do.
     if. ((2{seg)=0)*.level=(7{seg)%100 do. found =. 1
     total =. total+(4{seg)-3{seg end.
    end.
    flights =. flights+found
   end.
   counts =. counts,flights
   times =. times,total
  end.
  sectorreport =. sectorreport,<'LEVEL | flights=|->| time=|->|'render level;(0{counts);(1{counts);(fixed 0{times);fixed 1{times
 end.
 handoffs =. ((#Sectors),#Sectors)$0
 for_tr. trfinal do. if. (5{tr)>:_0 do. key =. (1{tr),5{tr
 handoffs =. (1+(<key){handoffs)(<key)}handoffs end. end.
 sectorreport =. sectorreport,<'HANDOFFS plan=final count=',str +/,handoffs
 for_a. i.#Sectors do. for_b. i.#Sectors do. count =. (<a,b){handoffs
 if. count do. sectorreport =. sectorreport,<emit 'HANDOFF';(a{::SectorNames);(b{::SectorNames);count end. end. end.
 radarreport =. 0$a:
 for_t. pv 'snapshots' do.
  radarreport =. radarreport,radar 'initial';InitialPaths;initialconflicts;t
  radarreport =. radarreport,radar 'final';paths;finalconflicts;t
 end.
 for_k. i.2 do.
  if. k=0 do. ps =. InitialPaths else. ps =. paths end.
  density =. (Rh,Rw)$0
  for_t. SampleTimes do.
   for_path. ps do.
    path =. >path
    si =. path segment_at t
    if. si<0 do. continue. end.
    'col row' =. screen (si{path)position t
    if. col>:0 do. density =. (1+(<row,col){density)(<row,col)}density end.
   end.
  end.
  chars =. (10<.density){'.123456789#'
  radarreport =. radarreport,(<'DENSITY plan=| from=| to=| step=60 max=|'render (k{::'initial';'final');Ta;Tb;>./,density),chart chars
 end.
 strips =. 0$a:
 for_a. i.NF do.
  plan =. a{::Plans
  wp =. 5{::plan
  hist =. '-'
  if. #a{::ManoeuvreHistory do. hist =. ','join a{::ManoeuvreHistory end.
  strips =. strips,<'STRIP | type=| waypoints=| length=| manoeuvres=|'render (a{::Callsigns);((1{::plan){::TypeNames);(#wp);(fixed a{Lengths);hist
  for_k. i.#wp do.
   times =. levels =. i.0
   for_ps. InitialPaths;paths do.
    path =. a{::>ps
    if. k=0 do. seg =. 0{path
    time =. 3{seg
    fl =. (7{seg)%100
    else. seg =. {:path#~k=1{"1 path
    time =. 4{seg
    fl =. (13{seg)%100 end.
    times =. times,time
    levels =. levels,<.fl
   end.
   coord =. (str (<k,0){wp),':',str (<k,1){wp
   strips =. strips,<'WPT | at=| eta=|->| fl=|->|'render k;coord;(fixed 0{times);(fixed 1{times);(0{levels);1{levels
  end.
  seq =. 0$a:
  for_tr. trfinal#~a=0{"1 trfinal do. seq =. seq,<(sector_name 1{tr),'@',fixed 2{tr end.
  text =. '-'
  if. #seq do. text =. ','join seq end.
  strips =. strips,<'SECTORS ',text
 end.
 1!:5 :: 0: <'output'
 'trajectories.csv'write trajectorycsv
 'conflicts.txt'write (conflict_report 'initial';InitialPaths;initialconflicts),conflict_report 'final';paths;finalconflicts
 'resolutions.txt'write resolutions
 'sector_transits.csv'write transitscsv
 'sector_load.csv'write loadcsv
 'sector_report.txt'write sectorreport
 'alerts.txt'write (alert_report 'initial';InitialPaths;initialconflicts),alert_report 'final';paths;finalconflicts
 'radar.txt'write radarreport
 'strips.txt'write strips
 i.0 0
)
main ''
