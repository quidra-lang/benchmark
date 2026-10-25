LF=:10{a.
EMPTY=:i.0 0
TYPES=:;:'MOTORCYCLE CAR ECAR VAN BUS'
KINDS=:;:'MOTO COMPACT LARGE EV'
PREFERENCES=:(<0 1 2),(<1 2),(<3 1 2),<,2
split=:4:0
  <;._1 x,y
)
text_equal=:4:0
  (,x)-:,y
)
number=:3:0
  ,'0' 8!:2 y
)
floor_ratio=:4:0
  <.(x:x)%x:y
)
two_digits=:3:0
  text=.number y
  ((2-#text)#'0'),text
)
clock_text=:3:0
  (number 1+y floor_ratio 1440),'-',(two_digits (1440|y)floor_ratio 60),':',two_digits 60|y
)
duration=:3:0
  (number y floor_ratio 60),':',two_digits 60|y
)
tenth=:3:0
  (number y floor_ratio 10),'.',number 10|y
)
type_id=:3:0
  index=.TYPES i.<,y
  if. index=5 do. _1 else. index end.
)
preference=:3:0
  if. y=4 do. ,2 else. y{::PREFERENCES end.
)
preference_rank=:4:0
  kinds=.preference x
  index=.kinds i.y
  if. index=#kinds do. _1 else. index end.
)
sget=:4:0
  (<x,y){S
)
vget=:4:0
  (<x,y){V
)
sset=:4:0
  S=:y(<x)}S
  EMPTY
)
vset=:4:0
  V=:y(<x)}V
  EMPTY
)
emit=:3:0
  (y,LF)1!:2(4)
  EMPTY
)
fail=:3:0
  emit 'ERROR ',y
)
spot_text=:3:0
  'L',(number y sget 0),'-',number y sget 1
)
location=:3:0
  target=.y vget 1
  result=.spot_text target
  if. 4=y vget 0 do. result=.result,'..',number 2+target sget 1 end.
  result
)
parked_id=:3:0
  for_k. i.NV do.
    if. k vget 9 do. if. y text_equal k{::PLATES do. k return. end. end.
  end.
  _1
)
waiting_id=:3:0
  for_k. i.#W do. if. y text_equal 0{::k{::W do. k return. end. end.
  _1
)
pass_id=:3:0
  for_k. i.#PASSPLATES do. if. y text_equal k{::PASSPLATES do. k return. end. end.
  _1
)
valid_pass=:4:0
  index=.pass_id x
  if. index<0 do. 0 return. end.
  (1+y floor_ratio 1440)<:index{LASTDAYS
)
spot_id=:3:0
  for_k. i.NS do. if. y text_equal spot_text k do. k return. end. end.
  _1
)
free_spot=:3:0
  (0=y sget 3)*.(y sget 4)<0
)
assign_spot=:3:0
  if. y=4 do.
    for_k. i.0>.NS-2 do.
      fits=.1
      for_offset. i.3 do.
        index=.k+offset
        if. ((index sget 0)~:k sget 0)+.((index sget 1)~:offset+k sget 1)+.(2~:index sget 2)+.-.free_spot index do. fits=.0 end.
      end.
      if. fits do. k return. end.
    end.
  else.
    for_kind. preference y do.
      for_k. i.NS do. if. (kind=k sget 2)*.free_spot k do. k return. end. end.
    end.
  end.
  _1
)
location_order=:3:0
  result=.i.0
  for_k. i.NS do.
    index=.k sget 4
    if. index>:0 do. if. k=index vget 1 do. result=.result,index end. end.
  end.
  result
)
occupy=:4:0
  (x,1)vset y
  width=.1
  if. 4=x vget 0 do. width=.3 end.
  for_offset. i.width do. ((y+offset),4)sset x end.
  EMPTY
)
vacate=:3:0
  target=.y vget 1
  width=.1
  if. 4=y vget 0 do. width=.3 end.
  for_offset. i.width do. ((target+offset),4)sset _1 end.
  EMPTY
)
admit=:3:0
  'plate kind target'=.y
  index=.NV
  NV=:NV+1
  PLATES=:(<plate)index}PLATES
  row=.kind,target,NOW,0,0,0,_1,0,0,1,_1,0,0
  V=:row index}V
  index occupy target
  STATS=:(1+(<kind,0){STATS)(<kind,0)}STATS
  date=.1+NOW floor_ratio 1440
  DAILY=:(1+(<date,kind,0){DAILY)(<date,kind,0)}DAILY
  PARKED=:PARKED+1
  if. PARKED>PEAK do.
    PEAK=:PARKED
    PEAKAT=:NOW
  end.
  index
)
refusal=:4:0
  kind=.x
  date=.1+y floor_ratio 1440
  STATS=:(1+(<kind,2){STATS)(<kind,2)}STATS
  DAILY=:(1+(<date,kind,2){DAILY)(<date,kind,2)}DAILY
  EMPTY
)
give_up=:3:0
  remaining=.0$a:
  for_item. W do.
    'plate kind joined'=.>item
    if. (NOW-joined)>:30 do.
      emit 'GIVEUP ',plate,' ',(kind{::TYPES),' ',clock_text joined+30
      kind refusal joined+30
    else.
      remaining=.remaining,item
    end.
  end.
  W=:remaining
  EMPTY
)
process_queue=:3:0
  remaining=.0$a:
  for_item. W do.
    'plate kind joined'=.>item
    target=.assign_spot kind
    if. target<0 do. remaining=.remaining,item
    else.
      index=.admit (<plate),(<kind),<target
      emit 'ADMIT ',plate,' ',(kind{::TYPES),' ',(location index),' waited ',duration NOW-joined
    end.
  end.
  W=:remaining
  EMPTY
)
interval_fee=:3:0
  'index start finish freetime'=.y
  stay=.finish-start
  plate=.index{::PLATES
  if. (plate valid_pass finish)+.stay<:freetime do. 0 0 return. end.
  kind=.index vget 0
  parking=.0
  offset=.0
  while. offset<stay do.
    minutes=.1440<.stay-offset
    if. offset=0 do. minutes=.minutes-freetime end.
    blocks=.(minutes+29)floor_ratio 30
    parking=.parking+(kind{CAPS)<.blocks*kind{RATES
    offset=.offset+1440
  end.
  parking,((finish floor_ratio 1440)-start floor_ratio 1440)*0{FEES
)
exit_fees=:4:0
  index=.y
  'kind target entered energy cost validation paidat paidparking paidnight'=.9{.index{V
  amounts=.6#0
  if. paidat<0 do.
    partial=.interval_fee index,entered,NOW,15+validation
    amounts=.partial 0 1}amounts
    lostfee=.0
    if. x do. lostfee=.1{FEES end.
    amounts=.lostfee 2}amounts
    due=.(+/partial)+lostfee+cost
  else.
    extra=.interval_fee index,paidat,NOW,15
    amounts=.(paidparking+0{extra)0}amounts
    amounts=.(paidnight+1{extra)1}amounts
    due=.+/extra
  end.
  amounts=.cost 3}amounts
  amounts=.(+/4{.amounts)4}amounts
  due 5}amounts
)
fee_line=:4:0
  'index amounts'=.y
  emit x,' ',(index{::PLATES),' ',(location index),' stay ',(duration NOW-index vget 2),' parking ',(number 0{amounts),' night ',(number 1{amounts),' lost ',(number 2{amounts),' charge ',(number 3{amounts),' total ',(number 4{amounts),' due ',number 5{amounts
)
annotation=:3:0
  result=.''
  if. (y{::PLATES)valid_pass NOW do. result=.result,' PASS' end.
  if. 0<y vget 5 do. result=.result,' VAL ',number y vget 5 end.
  if. 0<y vget 3 do. result=.result,' KWH ',number y vget 3 end.
  if. 0<:y vget 6 do. result=.result,' PAID' end.
  result
)
move_vehicle=:4:0
  previous=.location x
  vacate x
  x occupy y
  emit 'MOVE ',(x{::PLATES),' ',previous,' -> ',location x
)
occupancy_line=:4:0
  'used available closedcount'=.y
  result=.x
  for_k. i.4 do. result=.result,' ',(k{::KINDS),' ',(number k{used),'/',number k{available end.
  result,' closed ',number closedcount
)
daily_fields=:3:0
  ' entries ',(number 0{y),' exits ',(number 1{y),' refused ',(number 2{y),' revenue ',number 3{y
)
stats_fields=:3:0
  average=.0
  if. 0<1{y do. average=.(10*3{y)floor_ratio 1{y end.
  ' entries ',(number 0{y),' exits ',(number 1{y),' refused ',(number 2{y),' avg_stay ',tenth average
)
revenue_fields=:3:0
  ' exits ',(number 0{y),' parking ',(number 1{y),' night ',(number 2{y),' lost ',(number 3{y),' charge ',(number 4{y),' total ',number 5{y
)
command=:3:0
  words=.' 'split y
  clock=.':'split 1{::words
  NOW=:(1440*<:0".0{::words)+(60*0".0{::clock)+0".1{::clock
  give_up''
  action=.2{::words
  select. action
  case. 'LEVEL' do.
    LEVELS=:LEVELS+1
    total=.0
    result=.''
    for_kind. i.4 do.
      count=.0".(kind+3){::words
      result=.result,' ',(kind{::KINDS),' ',number count
      for_k. i.count do.
        total=.total+1
        S=:(LEVELS,total,kind,0,_1)NS}S
        NS=:NS+1
      end.
    end.
    emit 'LEVEL ',(number LEVELS),' spots ',(number total),result
    process_queue''
    return.
  case. 'CLOSE';'OPEN' do.
    text=.3{::words
    target=.spot_id text
    if. target<0 do. fail 'unknown spot ',text return. end.
    if. 'CLOSE'text_equal action do.
      if. target sget 3 do. fail 'spot ',text,' is already closed' return. end.
      occupant=.target sget 4
      if. occupant>:0 do. fail 'spot ',text,' is occupied by ',occupant{::PLATES return. end.
      (target,3)sset 1
    else.
      if. -.target sget 3 do. fail 'spot ',text,' is not closed' return. end.
      (target,3)sset 0
    end.
    emit action,' ',text,' ',(target sget 2){::KINDS
    if. 'OPEN'text_equal action do. process_queue'' end.
    return.
  case. 'RATE' do.
    kind=.type_id 3{::words
    rate=.0".4{::words
    cap=.0".5{::words
    if. kind<0 do. fail 'unknown type ',3{::words return. end.
    if. cap<rate do. fail 'cap below rate for ',3{::words return. end.
    RATES=:rate kind}RATES
    CAPS=:cap kind}CAPS
    emit 'RATE ',(kind{::TYPES),' ',(number rate),' ',number cap
    return.
  case. 'FEE' do.
    item=.(;:'NIGHT LOST KWH')i.<3{::words
    if. item=3 do. fail 'unknown fee ',3{::words return. end.
    amount=.0".4{::words
    FEES=:amount item}FEES
    emit 'FEE ',(3{::words),' ',number amount
    return.
  case. 'ENTER' do.
    plate=.3{::words
    kind=.type_id 4{::words
    index=.parked_id plate
    queued=.waiting_id plate
    if. kind<0 do. fail 'unknown type ',4{::words return. end.
    if. index>:0 do. fail plate,' is already parked at ',location index return. end.
    if. queued>:0 do. fail plate,' is already waiting' return. end.
    target=.assign_spot kind
    if. target>:0 do.
      index=.admit (<plate),(<kind),<target
      emit 'ENTER ',plate,' ',(kind{::TYPES),' ',location index
    elseif. (#W)<3 do.
      rec=.(<plate),(<kind),<NOW
      W=:W,<rec
      emit 'WAIT ',plate,' ',(kind{::TYPES),' ',number #W
    else.
      kind refusal NOW
      emit 'FULL ',plate,' ',kind{::TYPES
    end.
    return.
  case. 'LEAVE' do.
    plate=.3{::words
    queued=.waiting_id plate
    if. queued<0 do. fail plate,' is not waiting' return. end.
    kind=.1{::queued{::W
    emit 'LEAVE ',plate,' ',kind{::TYPES
    W=:W#~(i.#W)~:queued
    return.
  case. 'PASS';'UNPASS' do.
    plate=.3{::words
    index=.pass_id plate
    valid=.plate valid_pass NOW
    if. 'UNPASS'text_equal action do.
      if. -.valid do. fail plate,' has no pass' return. end.
      LASTDAYS=:0 index}LASTDAYS
      emit 'UNPASS ',plate
    else.
      days=.0".4{::words
      base=.NOW floor_ratio 1440
      if. valid do. base=.index{LASTDAYS end.
      deadline=.base+days
      if. index<0 do.
        PASSPLATES=:PASSPLATES,<plate
        LASTDAYS=:LASTDAYS,deadline
      else.
        LASTDAYS=:deadline index}LASTDAYS
      end.
      emit 'PASS ',plate,' until ',number deadline
    end.
    return.
  end.
  if. (<action)e.;:'EXIT PAY QUOTE CHARGE VALIDATE MOVE' do.
    plate=.3{::words
    index=.parked_id plate
    if. index<0 do. fail plate,' is not parked' return. end.
    kind=.index vget 0
    target=.index vget 1
    paidat=.index vget 6
    if. 'MOVE'text_equal action do.
      destination=.4{::words
      next=.spot_id destination
      if. kind=4 do. fail 'bus ',plate,' cannot be moved' return. end.
      if. next<0 do. fail 'unknown spot ',destination return. end.
      if. next=target do. fail plate,' is already at ',destination return. end.
      if. next sget 3 do. fail 'spot ',destination,' is closed' return. end.
      occupant=.next sget 4
      if. occupant>:0 do. fail 'spot ',destination,' is occupied by ',occupant{::PLATES return. end.
      if. 0>kind preference_rank next sget 2 do. fail (kind{::TYPES),' cannot use ',((next sget 2){::KINDS),' spot ',destination return. end.
      index move_vehicle next
      process_queue''
      return.
    end.
    if. 'CHARGE'text_equal action do.
      energy=.0".4{::words
      if. kind~:2 do. fail plate,' is not an electric car' return. end.
      if. 3~:target sget 2 do. fail plate,' is not at a charger' return. end.
      if. paidat>:0 do. fail plate,' has already paid' return. end.
      if. (energy+index vget 3)>100 do. fail 'charge limit exceeded for ',plate return. end.
      cost=.energy*2{FEES
      (index,3)vset energy+index vget 3
      (index,4)vset cost+index vget 4
      emit 'CHARGE ',plate,' kwh ',(number energy),' cost ',(number cost),' stay_kwh ',(number index vget 3),' stay_cost ',number index vget 4
      return.
    end.
    if. 'VALIDATE'text_equal action do.
      minutes=.0".4{::words
      if. paidat>:0 do. fail plate,' has already paid' return. end.
      if. (minutes+index vget 5)>180 do. fail 'validation limit exceeded for ',plate return. end.
      (index,5)vset minutes+index vget 5
      emit 'VALIDATE ',plate,' ',(number minutes),' total ',number index vget 5
      return.
    end.
    lost=.(('EXIT'text_equal action)*.5=#words)
    if. (paidat>:0)*.(('PAY'text_equal action)+.lost) do. fail plate,' has already paid' return. end.
    amounts=.lost exit_fees index
    if. 'PAY'text_equal action do.
      (index,6)vset NOW
      (index,7)vset 0{amounts
      (index,8)vset 1{amounts
      emit 'PAY ',plate,' parking ',(number 0{amounts),' night ',(number 1{amounts),' charge ',(number 3{amounts),' total ',number 4{amounts
    else.
      action fee_line (<index),<amounts
      if. 'EXIT'text_equal action do.
        EXITLOCATIONS=:(<location index)index}EXITLOCATIONS
        (index,10)vset NOW
        (index,11)vset 4{amounts
        (index,12)vset lost
        (index,9)vset 0
        EXITS=:index NE}EXITS
        NE=:NE+1
        vacate index
        PARKED=:PARKED-1
        STATS=:(1+(<kind,1){STATS)(<kind,1)}STATS
        STATS=:((NOW-index vget 2)+(<kind,3){STATS)(<kind,3)}STATS
        date=.1+NOW floor_ratio 1440
        DAILY=:(1+(<date,kind,1){DAILY)(<date,kind,1)}DAILY
        DAILY=:((4{amounts)+(<date,kind,3){DAILY)(<date,kind,3)}DAILY
        REVENUE=:(1+(<kind,0){REVENUE)(<kind,0)}REVENUE
        for_k. i.5 do. REVENUE=:((k{amounts)+(<kind,(k+1)){REVENUE)(<kind,(k+1))}REVENUE end.
        process_queue''
      end.
    end.
    return.
  end.
  select. action
  case. 'REBALANCE' do.
    moved=.0
    snapshot=.location_order''
    for_index. snapshot do.
      kind=.index vget 0
      target=.index vget 1
      if. kind~:4 do.
        rank=.kind preference_rank target sget 2
        if. rank>0 do.
          next=.assign_spot kind
          if. next>:0 do.
            if. (kind preference_rank next sget 2)<rank do.
              index move_vehicle next
              moved=.moved+1
            end.
          end.
        end.
      end.
    end.
    emit 'REBALANCE ',number moved
    process_queue''
  case. 'WHERE' do.
    plate=.3{::words
    index=.parked_id plate
    queued=.waiting_id plate
    last=._1
    for_k. i.NE do. visit=.k{EXITS
      if. plate text_equal visit{::PLATES do. last=.visit end.
    end.
    if. index>:0 do.
      emit 'WHERE ',plate,' ',(location index),' ',((index vget 0){::TYPES),' ',(clock_text index vget 2),' stay ',(duration NOW-index vget 2),annotation index
    elseif. queued>:0 do. emit 'WHERE ',plate,' waiting ',number queued+1
    elseif. last>:0 do. emit 'WHERE ',plate,' gone ',clock_text last vget 10
    else. fail 'unknown plate ',plate end.
  case. 'LIST';'OVERSTAY' do.
    level=.0
    hours=.0
    if. 'LIST'text_equal action do.
      if. 4=#words do. level=.0".3{::words end.
      if. level>LEVELS do. fail 'unknown level ',number level return. end.
    else. hours=.0".3{::words end.
    found=.i.0
    for_index. location_order'' do.
      target=.index vget 1
      if. ((level=0)+.level=target sget 0)*.(NOW-index vget 2)>:60*hours do. found=.found,index end.
    end.
    if. 'OVERSTAY'text_equal action do.
      times=.2{"1 found{V
      found=.( /:times){found
      emit 'OVERSTAY ',(number hours),' ',number #found
    else. emit 'LIST ',number #found end.
    for_index. found do.
      text=.(location index),' ',(index{::PLATES),' ',((index vget 0){::TYPES),' ',clock_text index vget 2
      if. 'OVERSTAY'text_equal action do. text=.text,' stay ',duration NOW-index vget 2 else. text=.text,annotation index end.
      emit text
    end.
  case. 'MAP' do.
    emit 'MAP ',number LEVELS
    for_level. 1+i.LEVELS do.
      symbols=.''
      count=.0
      for_k. i.NS do.
        if. level=k sget 0 do.
          if. (count>0)*.0=10|count do. symbols=.symbols,' ' end.
          kind=.k sget 2
          if. k sget 3 do. symbol=.'#'
          elseif. 0<:k sget 4 do. symbol=.kind{'MCLE'
          else. symbol=.kind{'mcle' end.
          symbols=.symbols,symbol
          count=.count+1
        end.
      end.
      emit 'L',(number level),' ',symbols
    end.
  case. 'OCCUPANCY' do.
    emit 'OCCUPANCY vehicles ',(number PARKED),' waiting ',number #W
    allused=.4#0
    allavailable=.4#0
    allclosed=.0
    for_level. 1+i.LEVELS do.
      used=.4#0
      available=.4#0
      closedcount=.0
      for_k. i.NS do.
        if. level=k sget 0 do.
          kind=.k sget 2
          if. k sget 3 do. closedcount=.closedcount+1
          else.
            available=.(1+kind{available)kind}available
            if. 0<:k sget 4 do. used=.(1+kind{used)kind}used end.
          end.
        end.
      end.
      emit ('L',number level)occupancy_line (<used),(<available),<closedcount
      allused=.allused+used
      allavailable=.allavailable+available
      allclosed=.allclosed+closedcount
    end.
    usage=.0
    if. 0<+/allavailable do. usage=.(1000*+/allused)floor_ratio +/allavailable end.
    emit ('TOTAL'occupancy_line (<allused),(<allavailable),<allclosed),' rate ',(tenth usage),'%'
  case. 'SIGN' do.
    spaces=.5#0
    for_kind. i.4 do.
      count=.0
      for_k. i.NS do.
        if. (free_spot k)*.0<:kind preference_rank k sget 2 do. count=.count+1 end.
      end.
      spaces=.count kind}spaces
    end.
    run=.0
    previouslevel=.0
    count=.0
    for_k. i.NS do.
      level=.k sget 0
      kind=.k sget 2
      free=.free_spot k
      if. (level~:previouslevel)+.(kind~:2)+.-.free do.
        count=.count+run floor_ratio 3
        run=.0
      end.
      if. (kind=2)*.free do. run=.run+1 end.
      previouslevel=.level
    end.
    spaces=.(count+run floor_ratio 3)4}spaces
    text=.'SIGN'
    for_k. i.5 do.
      value=.'FULL'
      if. 0<k{spaces do. value=.number k{spaces end.
      text=.text,' ',(k{::TYPES),' ',value
    end.
    emit text
  case. 'RATES' do.
    emit 'RATES'
    for_k. i.5 do. emit (k{::TYPES),' ',(number k{RATES),' ',number k{CAPS end.
    emit 'NIGHT ',(number 0{FEES),' LOST ',(number 1{FEES),' KWH ',number 2{FEES
  case. 'PASSES' do.
    plates=./:~PASSPLATES#~LASTDAYS>:1+NOW floor_ratio 1440
    emit 'PASSES ',number #plates
    for_item. plates do.
      plate=.>item
      text=.plate,' until ',number (pass_id plate){LASTDAYS
      if. 0<:parked_id plate do. text=.text,' IN' end.
      emit text
    end.
  case. 'HISTORY' do.
    plate=.3{::words
    visits=.NE{.EXITS
    found=.visits#~(<,plate)=visits{PLATES
    total=.+/11{"1 found{V
    if. 0=#found do. fail 'no history for ',plate return. end.
    emit 'HISTORY ',plate,' visits ',(number #found),' paid ',number total
    for_index. found do.
      text=.(clock_text index vget 2),' ',(clock_text index vget 10),' ',(index{::EXITLOCATIONS),' ',((index vget 0){::TYPES),' ',number index vget 11
      if. index vget 12 do. text=.text,' LOST' end.
      emit text
    end.
  case. 'REVENUE' do.
    emit 'REVENUE'
    for_k. i.5 do. emit (k{::TYPES),revenue_fields k{REVENUE end.
    emit 'TOTAL',revenue_fields +/REVENUE
  case. 'DAILY' do.
    date=.0".3{::words
    values=.5 4$0
    if. date<:60 do. values=.date{DAILY end.
    emit 'DAILY ',(number date),daily_fields +/values
    for_k. i.5 do. emit (k{::TYPES),daily_fields k{values end.
  case. 'STATS' do.
    at=.'-'
    if. PEAKAT>:0 do. at=.clock_text PEAKAT end.
    emit 'STATS parked ',(number PARKED),' peak ',(number PEAK),' at ',at
    for_k. i.5 do. emit (k{::TYPES),stats_fields k{STATS end.
    emit 'ALL',stats_fields +/STATS
  end.
  EMPTY
)
main=:3:0
  NOW=:0
  LEVELS=:0
  S=:1080 5$0
  NS=:0
  V=:1000 13$0
  PLATES=:1000$<''
  EXITLOCATIONS=:1000$<''
  NV=:0
  EXITS=:1000#0
  NE=:0
  W=:0$a:
  PASSPLATES=:0$a:
  LASTDAYS=:i.0
  RATES=:100 200 200 300 600
  CAPS=:800 1600 1600 2400 4800
  FEES=:300 2000 30
  STATS=:5 4$0
  REVENUE=:5 6$0
  DAILY=:61 5 4$0
  PARKED=:0
  PEAK=:0
  PEAKAT=:_1
  input=.1!:1(3)
  if. LF~:{:input do. input=.input,LF end.
  lines=.<;._2 input
  count=.0".0{::lines
  for_k. i.count do. command (k+1){::lines end.
  EMPTY
)
main''
