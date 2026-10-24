NB. Manual Gregorian calendar, exact cents, and indexed historical night snapshots.
LF=:10{a.
EMPTY=:i.0 0
TYPES=:;:'SINGLE DOUBLE SUITE'
STATUSES=:;:'booked inhouse checkedout cancelled noshow'
WEEKDAYS=:;:'SAT SUN MON TUE WED THU FRI'
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
cents=:3:0
  parts=.'.'split y
  (100*0".0{::parts)+0".1{::parts
)
money=:3:0
  tail=.number 100|y
  (number y floor_ratio 100),'.',((2-#tail)#'0'),tail
)
padded=:4:0
  text=.number y
  ((x-#text)#'0'),text
)
leap=:3:0
  (0=4|y)*.((0~:100|y)+.0=400|y)
)
month_length=:4:0
  lengths=.31 28 31 30 31 30 31 31 30 31 30 31
  ((y-1){lengths)+((y=2)*.leap x)
)
day_number=:3:0
  year=.0".4{.y
  month=.0".2{.5}.y
  day=.0".8}.y
  if. (year<2000)+.(year>2099)+.(month<1)+.month>12 do. _1 return. end.
  if. (day<1)+.day>year month_length month do. _1 return. end.
  result=.day-1
  for_prior. 2000+i.year-2000 do. result=.result+365+leap prior end.
  for_prior. 1+i.month-1 do. result=.result+year month_length prior end.
  result
)
date_text=:3:0
  day=.y
  year=.2000
  while. day>:(365+leap year) do.
    day=.day-(365+leap year)
    year=.year+1
  end.
  month=.1
  while. day>:year month_length month do.
    day=.day-year month_length month
    month=.month+1
  end.
  (4 padded year),'-',(2 padded month),'-',2 padded day+1
)
date_weekday=:3:0
  (date_text y),' ',(7|y){::WEEKDAYS
)
type_id=:3:0
  index=.TYPES i.<,y
  if. index=3 do. _1 else. index end.
)
emit=:3:0
  (y,LF)1!:2(4)
  EMPTY
)
fail=:3:0
  emit 'ERROR ',y
)
NB. R: room-number,type,base-rate,dirty,in-house-reservation.
NB. B: created,room,wait-type,arrival,departure,status,nights,extras,deposit,
NB. paid,posting,fee,penalty-day,penalty-rate,extra-head,extra-tail.
NB. BILLS: lodging,discount,penalty,extras,tax,total. X: amount,next.
rget=:4:0
  (<x,y){R
)
bget=:4:0
  (<x,y){B
)
rset=:4:0
  R=:y(<x)}R
  EMPTY
)
bset=:4:0
  B=:y(<x)}B
  EMPTY
)
room_id=:3:0
  index=.(NR{.0{"1 R)i.y
  if. index=NR do. _1 else. index end.
)
used_id=:3:0
  index=.(NI{.IDS)i.<,y
  if. index=NI do. _1 else. index end.
)
reservation_id=:3:0
  index=.used_id y
  if. index<0 do. _1 return. end.
  if. index bget 0 do. index else. _1 end.
)
wait_position=:3:0
  for_k. i.NW do. if. y text_equal (k{WAIT){::IDS do. k return. end. end.
  _1
)
remove_wait=:3:0
  position=.y
  while. position<NW-1 do.
    WAIT=:((position+1){WAIT)position}WAIT
    position=.position+1
  end.
  NW=:NW-1
  EMPTY
)
room_order=:3:0
  indices=.i.NR
  if. y>:0 do. indices=.indices#~y=1{"1 NR{.R end.
  ( /:0{"1 indices{R){indices
)
reservation_order=:3:0
  'status field'=.y
  indices=.NC{.CREATED
  if. status>:0 do. indices=.indices#~status=5{"1 indices{B end.
  indices=.( /:indices{IDS){indices
  if. field>0 do.
    column=.3
    if. field=2 do. column=.4 end.
    indices=.( /:column{"1 indices{B){indices
  end.
  indices
)
night_rate=:4:0
  room=.x
  day=.y
  percentage=.100
  for_k. i.NS do.
    'first last percent'=.k{SEASONS
    if. (first<:day)*.day<:last do. percentage=.percent end.
  end.
  ((room rget 2)*percentage)floor_ratio 100
)
unavailable=:3:0
  'room first last except'=.y
  days=.first+i.last-first
  occupants=.room{days{"1 OCC
  blocks=.room{days{"1 BLOCKS
  unavailablemask=.blocks+.((occupants>:0)*.occupants~:except)
  index=.unavailablemask i.1
  if. index<#days do. index{days else. _1 end.
)
free_room=:3:0
  'kind first last except'=.y
  rooms=.room_order kind
  days=.first+i.last-first
  occupants=.rooms{days{"1 OCC
  blocks=.rooms{days{"1 BLOCKS
  free=.*./"1 (-.blocks)*.((occupants<0)+.occupants=except)
  index=.free i.1
  if. index<#rooms do. index{rooms else. _1 end.
)
range_error=:3:0
  'a b stay past limit'=.y
  first=.day_number a
  last=.day_number b
  if. first<0 do. 'invalid date ',a return. end.
  if. last<0 do. 'invalid date ',b return. end.
  if. past*.first<TODAY do. 'past date ',a return. end.
  if. (last<first)+.stay*.last=first do. 'invalid range ',a,' ',b return. end.
  length=.last-first
  if. -.stay do. length=.length+1 end.
  if. (limit>0)*.length>limit do. 'too long ',number length return. end.
  ''
)
lodging=:3:0
  +/(y bget 6){.y{NIGHTRATES
)
clear_nights=:4:0
  index=.x
  first=.y
  arrival=.index bget 3
  for_k. first+i.(index bget 6)-first do.
    room=.(<index,k){NIGHTROOMS
    OCC=:(_1)(<room,(arrival+k))}OCC
  end.
  EMPTY
)
price_nights=:3:0
  'index room first last'=.y
  arrival=.index bget 3
  for_day. first+i.last-first do.
    position=.day-arrival
    NIGHTROOMS=:room(<index,position)}NIGHTROOMS
    rate=.room night_rate day
    NIGHTRATES=:rate(<index,position)}NIGHTRATES
    OCC=:index(<room,day)}OCC
  end.
  EMPTY
)
deposit_text=:4:0
  deposit=.x bget 8
  if. y>:deposit do.
    label=.' due '
    amount=.y-deposit
  else.
    label=.' refund '
    amount=.deposit-y
  end.
  'deposit ',(money deposit),label,money amount
)
total_paid=:3:0
  indices=.NC{.CREATED
  mask=.(<,y)=indices{GUESTS
  +/mask#9{"1 indices{B
)
tier_name=:3:0
  if. y>:2000 do. 'GOLD' elseif. y>:500 do. 'SILVER' else. 'BRONZE' end.
)
calculate_bill=:3:0
  points=.(total_paid y{::GUESTS)floor_ratio 100
  discount=.0
  if. points>:2000 do. discount=.10 elseif. points>:500 do. discount=.5 end.
  charge=.lodging y
  reduction=.(charge*discount)floor_ratio 100
  penalty=.y bget 13
  extras=.y bget 7
  subtotal=.(charge-reduction)+penalty+extras
  tax=.subtotal floor_ratio 10
  charge,reduction,penalty,extras,tax,subtotal+tax
)
create_reservation=:3:0
  'index room prefix'=.y
  (index,0)bset 1
  (index,1)bset room
  (index,5)bset 0
  arrival=.index bget 3
  departure=.index bget 4
  nights=.departure-arrival
  (index,6)bset nights
  CREATED=:index NC}CREATED
  NC=:NC+1
  price_nights index,room,arrival,departure
  emit prefix,'BOOK ',(index{::IDS),' ',(index{::GUESTS),' room ',(number room rget 0),' ',((room rget 1){::TYPES),' ',(date_text arrival),' -> ',(date_text departure),' nights ',(number nights),' total ',money lodging index
)
process_waitlist=:3:0
  position=.0
  while. position<NW do.
    index=.position{WAIT
    arrival=.index bget 3
    departure=.index bget 4
    if. arrival<TODAY do.
      emit '  WAITLIST ',(index{::IDS),' expired'
      (index,5)bset _2
      remove_wait position
    else.
      room=.free_room (index bget 2),arrival,departure,_1
      if. room>:0 do.
        remove_wait position
        create_reservation (<index),(<room),<'  '
      else. position=.position+1 end.
    end.
  end.
  EMPTY
)
check_out=:3:0
  'index day prefix'=.y
  room=.index bget 1
  arrival=.index bget 3
  departure=.index bget 4
  if. day<departure do.
    position=.day-arrival
    (index,12)bset day
    (index,13)bset (<index,position){NIGHTRATES
    index clear_nights position
    (index,4)bset day
    (index,6)bset position
  end.
  bill=.calculate_bill index
  BILLS=:bill index}BILLS
  (index,9)bset 5{bill
  (index,5)bset 2
  (index,10)bset day
  (room,3)rset 1
  (room,4)rset _1
  emit prefix,'CHECKOUT ',(index{::IDS),' nights ',(number index bget 6),' lodging ',(money 0{bill),' discount ',(money 1{bill),' penalty ',(money 2{bill),' extras ',(money 3{bill),' tax ',(money 4{bill),' total ',(money 5{bill),' ',index deposit_text 5{bill
)
occupancy=:3:0
  'day kind'=.y
  rooms=.i.NR
  if. kind>:0 do. rooms=.rooms#~kind=1{"1 NR{.R end.
  blocks=.+/rooms{day{"1 BLOCKS
  occupants=.rooms{day{"1 OCC
  active=.occupants#~occupants>:0
  positions=.day-3{"1 active{B
  revenue=.+/(<"1 active,.positions){NIGHTRATES
  (#rooms),blocks,(#active),revenue
)
occupancy_text=:3:0
  'rooms blocks occupied revenue'=.y
  available=.rooms-blocks
  rate=.'n/a'
  if. available>0 do. rate=.(number (100*occupied)floor_ratio available),'%' end.
  'rooms ',(number rooms),' blocked ',(number blocks),' occupied ',(number occupied),' rate ',rate
)
metrics=:3:0
  'available sold revenue'=.y
  rate=.'n/a'
  adr=.'n/a'
  revpar=.'n/a'
  if. available>0 do.
    rate=.(number (100*sold)floor_ratio available),'%'
    revpar=.money revenue floor_ratio available
  end.
  if. sold>0 do. adr=.money revenue floor_ratio sold end.
  'sold ',(number sold),'/',(number available),' rate ',rate,' revenue ',(money revenue),' adr ',adr,' revpar ',revpar
)
command=:3:0
  words=.' 'split y
  action=.0{::words
  if. (<action)e.;:'ROOM RATE CLEAN BLOCK UNBLOCK' do.
    numbervalue=.0".1{::words
    room=.room_id numbervalue
    if. 'ROOM'text_equal action do.
      if. room>:0 do. fail 'duplicate room ',1{::words return. end.
      kind=.type_id 2{::words
      if. kind<0 do. fail 'invalid type ',2{::words return. end.
      rate=.cents 3{::words
      R=:(numbervalue,kind,rate,0,_1)NR}R
      NR=:NR+1
      emit 'ROOM ',(1{::words),' ',(2{::words),' ',money rate
      return.
    end.
    if. room<0 do. fail 'unknown room ',1{::words return. end.
    if. 'RATE'text_equal action do.
      before=.room rget 2
      rate=.cents 2{::words
      (room,2)rset rate
      emit 'RATE ',(1{::words),' ',(money before),' -> ',money rate
    elseif. 'CLEAN'text_equal action do.
      if. -.room rget 3 do. fail 'already clean ',1{::words return. end.
      (room,3)rset 0
      emit 'CLEAN ',1{::words
    else.
      reason=.range_error (<2{::words),(<3{::words),(<0),(<1),<31
      if. #reason do. fail reason return. end.
      first=.day_number 2{::words
      last=.day_number 3{::words
      if. 'BLOCK'text_equal action do.
        days=.first+i.1+last-first
        occupants=.room{days{"1 OCC
        at=.(occupants>:0)i.1
        if. at<#days do. fail 'room unavailable ',(1{::words),' ',date_text at{days return. end.
      end.
      desired=.'BLOCK'text_equal action
      count=.0
      for_day. first+i.1+last-first do.
        if. desired~:(<room,day){BLOCKS do.
          BLOCKS=:desired(<room,day)}BLOCKS
          count=.count+1
        end.
      end.
      if. desired do. label=.' added ' else. label=.' removed ' end.
      emit action,' ',(1{::words),' ',(2{::words),' -> ',(3{::words),label,number count
    end.
    return.
  end.
  if. (<action)e.;:'SEASON REVENUE' do.
    reason=.range_error (<1{::words),(<2{::words),(<0),(<0),<0
    if. #reason do. fail reason return. end.
    first=.day_number 1{::words
    last=.day_number 2{::words
    if. 'SEASON'text_equal action do.
      percentage=.0".3{::words
      SEASONS=:(first,last,percentage)NS}SEASONS
      NS=:NS+1
      emit 'SEASON ',(number NS),' ',(1{::words),' -> ',(2{::words),' ',(number percentage),'%'
    else.
      emit 'REVENUE ',(1{::words),' -> ',2{::words
      amounts=.7#0
      counts=.3#0
      for_k. i.NC do.
        index=.k{CREATED
        posting=.index bget 10
        if. (posting<first)+.posting>last do. continue. end.
        status=.index bget 5
        if. status=2 do.
          for_part. i.5 do. amounts=.((part{amounts)+(<index,part){BILLS)part}amounts end.
          counts=.(1+0{counts)0}counts
        elseif. status=3 do.
          amounts=.((5{amounts)+index bget 11)5}amounts
          counts=.(1+1{counts)1}counts
        elseif. status=4 do.
          amounts=.((6{amounts)+index bget 11)6}amounts
          counts=.(1+2{counts)2}counts
        end.
      end.
      names=.;:'lodging discount penalty extras tax cancellation noshow'
      for_k. i.7 do. emit '  ',(k{::names),' ',money k{amounts end.
      total=.((0{amounts)-1{amounts)++/2}.amounts
      emit '  total ',money total
      emit '  checkouts ',(number 0{counts),' cancellations ',(number 1{counts),' noshows ',number 2{counts
    end.
    return.
  end.
  if. 'TODAY'text_equal action do.
    day=.day_number 1{::words
    if. day<0 do. fail 'invalid date ',1{::words return. end.
    if. day<TODAY do. fail 'past date ',1{::words return. end.
    emit 'TODAY ',date_weekday day
    for_index. reservation_order 1 2 do.
      departure=.index bget 4
      if. departure<day do. check_out (<index),(<departure),<'  ' end.
    end.
    for_index. reservation_order 0 1 do.
      arrival=.index bget 3
      if. arrival<day do.
        fee=.(<index,0){NIGHTRATES
        (index,11)bset fee
        (index,9)bset fee
        (index,5)bset 4
        (index,10)bset arrival
        index clear_nights 0
        emit '  NOSHOW ',(index{::IDS),' ',(index{::GUESTS),' fee ',(money fee),' ',index deposit_text fee
      end.
    end.
    TODAY=:day
    return.
  end.
  if. (<action)e.;:'BOOK BOOKROOM WAITLIST' do.
    if. 0<:used_id 1{::words do. fail 'duplicate reservation ',1{::words return. end.
    room=._1
    kind=._1
    if. 'BOOKROOM'text_equal action do.
      room=.room_id 0".3{::words
      if. room<0 do. fail 'unknown room ',3{::words return. end.
      kind=.room rget 1
    else.
      kind=.type_id 3{::words
      if. kind<0 do. fail 'invalid type ',3{::words return. end.
    end.
    reason=.range_error (<4{::words),(<5{::words),(<1),(<1),<30
    if. #reason do. fail reason return. end.
    first=.day_number 4{::words
    last=.day_number 5{::words
    if. 'BOOKROOM'text_equal action do.
      at=.unavailable room,first,last,_1
      if. at>:0 do. fail 'room unavailable ',(3{::words),' ',date_text at return. end.
    else.
      room=.free_room kind,first,last,_1
      if. (room<0)*.'BOOK'text_equal action do. fail 'no availability ',(3{::words),' ',(4{::words),' ',5{::words return. end.
    end.
    index=.NI
    NI=:NI+1
    IDS=:(<,1{::words)index}IDS
    GUESTS=:(<,2{::words)index}GUESTS
    row=.0,room,kind,first,last,_1,0,0,0,0,_1,0,_1,0,_1,_1
    B=:row index}B
    if. room>:0 do. create_reservation (<index),(<room),<''
    else.
      WAIT=:index NW}WAIT
      NW=:NW+1
      emit 'WAITLIST ',(1{::words),' queued position ',number NW
    end.
    return.
  end.
  if. (<action)e.;:'AVAIL STATS OCCUPANCY SCHEDULE' do.
    kind=._1
    offset=.1
    if. 'AVAIL'text_equal action do.
      kind=.type_id 1{::words
      if. kind<0 do. fail 'invalid type ',1{::words return. end.
      offset=.2
    end.
    first=.day_number offset{::words
    last=.first
    if. (<action)e.;:'AVAIL STATS' do.
      reason=.range_error (<offset{::words),(<(offset+1){::words),(<0),(<0),<31
      if. #reason do. fail reason return. end.
      last=.day_number (offset+1){::words
    elseif. first<0 do. fail 'invalid date ',offset{::words return. end.
    if. 'AVAIL'text_equal action do.
      emit 'AVAIL ',(1{::words),' ',(2{::words),' -> ',3{::words
      for_day. first+i.1+last-first do.
        free=.i.0
        for_room. room_order kind do.
          if. 0>unavailable room,day,(day+1),_1 do. free=.free,room rget 0 end.
        end.
        text=.'  ',(date_weekday day),' free ',number #free
        for_numbervalue. free do. text=.text,' ',number numbervalue end.
        emit text
      end.
    elseif. 'STATS'text_equal action do.
      emit 'STATS ',(1{::words),' -> ',2{::words
      totals=.3#0
      for_day. first+i.1+last-first do.
        'rooms blocks occupied revenue'=.occupancy day,_1
        available=.rooms-blocks
        emit '  ',(date_weekday day),' ',metrics available,occupied,revenue
        totals=.totals+available,occupied,revenue
      end.
      emit '  total ',metrics totals
    elseif. 'OCCUPANCY'text_equal action do.
      emit 'OCCUPANCY ',(date_weekday first),' ',occupancy_text occupancy first,_1
      for_group. i.3 do.
        values=.occupancy first,group
        if. 0<0{values do. emit '  ',(group{::TYPES),' ',occupancy_text values end.
      end.
    else.
      arrivals=.i.0
      departures=.i.0
      for_index. reservation_order _1 0 do.
        status=.index bget 5
        if. (first=index bget 3)*.status~:3 do. arrivals=.arrivals,index end.
        if. (first=index bget 4)*.status<:2 do. departures=.departures,index end.
      end.
      emit 'SCHEDULE ',(date_weekday first),' arrivals ',(number #arrivals),' departures ',number #departures
      for_stage. i.2 do.
        if. stage=0 do.
          selected=.arrivals
          label=.'arrival '
        else.
          selected=.departures
          label=.'departure '
        end.
        for_index. selected do.
          emit '  ',label,(index{::IDS),' ',(index{::GUESTS),' room ',(number (index bget 1)rget 0),' ',(index bget 5){::STATUSES
        end.
      end.
    end.
    return.
  end.
  if. 'ROOMS'text_equal action do.
    emit 'ROOMS ',(date_weekday TODAY),' rooms ',number NR
    for_room. room_order _1 do.
      occupant=.room rget 4
      if. occupant>:0 do. situation=.'occupied ',occupant{::IDS
      elseif. (<room,TODAY){BLOCKS do. situation=.'blocked'
      else. situation=.'vacant' end.
      next=._1
      for_k. i.NC do.
        index=.k{CREATED
        if. (0=index bget 5)*.room=index bget 1 do.
          if. next<0 do. next=.index
          elseif. (index bget 3)<next bget 3 do. next=.index end.
        end.
      end.
      if. room rget 3 do. clean=.' dirty ' else. clean=.' clean ' end.
      text=.'  ',(number room rget 0),' ',((room rget 1){::TYPES),' base ',(money room rget 2),' tonight ',(money room night_rate TODAY),clean,situation
      if. next>:0 do. text=.text,' next ',(next{::IDS),' ',date_text next bget 3 end.
      emit text
    end.
    return.
  end.
  if. 'LIST'text_equal action do.
    status=.STATUSES i.1{words
    order=.reservation_order status,1
    emit 'LIST ',(1{::words),' ',number #order
    for_index. order do.
      emit '  ',(index{::IDS),' ',(index{::GUESTS),' room ',(number (index bget 1)rget 0),' ',(date_text index bget 3),' -> ',date_text index bget 4
    end.
    return.
  end.
  if. 'QUEUE'text_equal action do.
    emit 'QUEUE ',number NW
    for_k. i.NW do.
      index=.k{WAIT
      emit '  ',(number k+1),' ',(index{::IDS),' ',(index{::GUESTS),' ',((index bget 2){::TYPES),' ',(date_text index bget 3),' -> ',date_text index bget 4
    end.
    return.
  end.
  if. 'GUEST'text_equal action do.
    guest=.1{::words
    indices=.NC{.CREATED
    selected=.indices#~(<,guest)=indices{GUESTS
    if. 0=#selected do. fail 'unknown guest ',guest return. end.
    emit 'GUEST ',guest
    for_index. selected do.
      room=.index bget 1
      status=.index bget 5
      if. status<:1 do. amount=.'deposit ',money index bget 8 else. amount=.'paid ',money index bget 9 end.
      emit '  ',(index{::IDS),' room ',(number room rget 0),' ',((room rget 1){::TYPES),' ',(date_text index bget 3),' -> ',(date_text index bget 4),' ',(status{::STATUSES),' ',amount
    end.
    paid=.total_paid guest
    points=.paid floor_ratio 100
    emit '  total paid ',(money paid),' points ',(number points),' tier ',tier_name points
    return.
  end.
  if. 'CANCEL'text_equal action do.
    position=.wait_position 1{::words
    if. position>:0 do.
      ((position{WAIT),5)bset _2
      remove_wait position
      emit 'CANCEL ',(1{::words),' waitlist removed'
      return.
    end.
  end.
  index=.reservation_id 1{::words
  if. index<0 do. fail 'unknown reservation ',1{::words return. end.
  status=.index bget 5
  room=.index bget 1
  arrival=.index bget 3
  departure=.index bget 4
  id=.index{::IDS
  if. -.'INVOICE'text_equal action do.
    if. (<action)e.;:'MODIFY CANCEL CHECKIN' do. valid=.status=0
    elseif. 'PAY'text_equal action do. valid=.status<:1
    else. valid=.status=1 end.
    if. -.valid do. fail 'invalid status ',id,' ',status{::STATUSES return. end.
  end.
  select. action
  case. 'MODIFY' do.
    reason=.range_error (<2{::words),(<3{::words),(<1),(<1),<30
    if. #reason do. fail reason return. end.
    first=.day_number 2{::words
    last=.day_number 3{::words
    target=.room
    if. 0<:unavailable room,first,last,index do. target=.free_room (room rget 1),first,last,index end.
    if. target<0 do. fail 'no availability ',((room rget 1){::TYPES),' ',(2{::words),' ',3{::words return. end.
    index clear_nights 0
    (index,1)bset target
    (index,3)bset first
    (index,4)bset last
    (index,6)bset last-first
    price_nights index,target,first,last
    if. target=room do. label=.' kept ' else. label=.' reassigned ' end.
    emit 'MODIFY ',id,' room ',(number target rget 0),label,(2{::words),' -> ',(3{::words),' nights ',(number last-first),' total ',money lodging index
  case. 'CANCEL' do.
    days=.arrival-TODAY
    rate=.(<index,0){NIGHTRATES
    if. days>:7 do. fee=.0 elseif. days>:1 do. fee=.rate floor_ratio 2 else. fee=.rate end.
    (index,11)bset fee
    (index,9)bset fee
    (index,5)bset 3
    (index,10)bset TODAY
    index clear_nights 0
    emit 'CANCEL ',id,' days ',(number days),' fee ',(money fee),' ',index deposit_text fee
  case. 'CHECKIN' do.
    if. arrival~:TODAY do. fail 'not arrival date ',id,' ',date_text arrival return. end.
    occupant=.room rget 4
    if. occupant>:0 do. fail 'room occupied ',(number room rget 0),' ',occupant{::IDS return. end.
    if. room rget 3 do. fail 'room dirty ',number room rget 0 return. end.
    (index,5)bset 1
    (room,4)rset index
    emit 'CHECKIN ',id,' ',(index{::GUESTS),' room ',(number room rget 0),' until ',date_text departure
  case. 'MOVE' do.
    target=.room_id 0".2{::words
    if. target<0 do. fail 'unknown room ',2{::words return. end.
    if. target=room do. fail 'same room ',2{::words return. end.
    remaining=.departure-TODAY
    if. remaining<:0 do. fail 'no remaining nights ',id return. end.
    day=.unavailable target,TODAY,departure,index
    if. day>:0 do. fail 'room unavailable ',(2{::words),' ',date_text day return. end.
    occupant=.target rget 4
    if. occupant>:0 do. fail 'room occupied ',(2{::words),' ',occupant{::IDS return. end.
    if. target rget 3 do. fail 'room dirty ',2{::words return. end.
    for_day. TODAY+i.departure-TODAY do.
      position=.day-arrival
      oldroom=.(<index,position){NIGHTROOMS
      OCC=:(_1)(<oldroom,day)}OCC
      NIGHTROOMS=:target(<index,position)}NIGHTROOMS
      OCC=:index(<target,day)}OCC
    end.
    emit 'MOVE ',id,' ',(number room rget 0),' -> ',(2{::words),' nights ',number remaining
    (room,3)rset 1
    (room,4)rset _1
    (target,4)rset index
    (index,1)bset target
  case. 'EXTEND' do.
    last=.day_number 2{::words
    if. last<0 do. fail 'invalid date ',2{::words return. end.
    if. last<:departure do. fail 'invalid range ',(date_text departure),' ',2{::words return. end.
    if. (last-arrival)>30 do. fail 'too long ',number last-arrival return. end.
    day=.unavailable room,departure,last,index
    if. day>:0 do. fail 'room unavailable ',(number room rget 0),' ',date_text day return. end.
    price_nights index,room,departure,last
    (index,4)bset last
    (index,6)bset last-arrival
    emit 'EXTEND ',id,' until ',(2{::words),' nights ',(number index bget 6),' total ',money lodging index
  case. 'CHARGE';'PAY' do.
    amount=.cents 2{::words
    if. amount=0 do. fail 'invalid amount' return. end.
    if. 'PAY'text_equal action do.
      (index,8)bset amount+index bget 8
      emit 'PAY ',id,' ',(money amount),' deposit ',money index bget 8
    else.
      charge=.NX
      NX=:NX+1
      X=:(amount,_1)charge}X
      XNAMES=:(<,3{::words)charge}XNAMES
      tail=.index bget 15
      if. tail<0 do. (index,14)bset charge else. X=:charge(<tail,1)}X end.
      (index,15)bset charge
      (index,7)bset amount+index bget 7
      emit 'CHARGE ',id,' ',(3{::words),' ',(money amount),' extras ',money index bget 7
    end.
  case. 'CHECKOUT' do. check_out (<index),(<TODAY),<''
  case. 'INVOICE' do.
    emit 'INVOICE ',id,' ',(index{::GUESTS),' room ',(number room rget 0),' ',((room rget 1){::TYPES),' ',status{::STATUSES
    if. status e.3 4 do.
      if. status=3 do. label=.'cancellation' else. label=.'noshow' end.
      fee=.index bget 11
      emit '  ',label,' fee ',money fee
      emit '  total ',money fee
      emit '  ',index deposit_text fee
    else.
      for_k. i.index bget 6 do.
        nightroom=.(<index,k){NIGHTROOMS
        rate=.(<index,k){NIGHTRATES
        emit '  ',(date_weekday arrival+k),' room ',(number nightroom rget 0),' ',money rate
      end.
      if. status=2 do. bill=.index{BILLS else. bill=.calculate_bill index end.
      emit '  lodging ',money 0{bill
      emit '  discount ',money 1{bill
      penaltyday=.index bget 12
      if. penaltyday>:0 do. emit '  penalty ',(date_weekday penaltyday),' ',money 2{bill end.
      cursor=.index bget 14
      while. cursor>:0 do.
        'amount next'=.cursor{X
        emit '  extra ',(cursor{::XNAMES),' ',money amount
        cursor=.next
      end.
      emit '  tax ',money 4{bill
      emit '  total ',money 5{bill
      emit '  ',index deposit_text 5{bill
    end.
  end.
  EMPTY
)
main=:3:0
  TODAY=:day_number '2026-01-01'
  R=:50 5$0
  NR=:0
  SEASONS=:1000 3$0
  NS=:0
  B=:300 16$0
  IDS=:300$<''
  GUESTS=:300$<''
  NI=:0
  CREATED=:300#0
  NC=:0
  WAIT=:300#0
  NW=:0
  BLOCKS=:50 36525$0=1
  OCC=:50 36525$_1
  NIGHTROOMS=:300 30$_1
  NIGHTRATES=:300 30$0
  BILLS=:300 6$0
  X=:1000 2$0
  XNAMES=:1000$<''
  NX=:0
  input=.1!:1(3)
  if. LF~:{:input do. input=.input,LF end.
  lines=.<;._2 input
  count=.0".0{::lines
  for_k. 1+i.count do.
    command k{::lines
    process_waitlist''
  end.
  EMPTY
)
main''
