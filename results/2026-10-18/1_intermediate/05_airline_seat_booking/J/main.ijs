NB. Indexed native boxed records retain passenger and booking acceptance order.
split =: 4 : 0
  <;._1 x,y
)
join =: 4 : 0
  if. 0=#y do. '' return. end.
  (#x)}.;(<x),&.>y
)
text_equal =: 4 : 0
  (,x)-:,y
)
number =: 3 : 0
  ,'0' 8!:2 y
)
floor_ratio =: 4 : 0
  <.(x:x)%x:y
)
cabin_name =: 3 : 0
  y{'FJY'
)
AIRCRAFT =: 0$<i.0
FLIGHTS =: 0$<i.0
BOOKINGS =: 0$<i.0
PEOPLE =: 0$<i.0
TIERNAMES =: 0$<''
TIERS =: i.0
PENDING =: (<' '),(<0),(<0),(<0$<i.0),<0$<i.0
NB. Seat: label,row,cabin,block,offset,kind,exit,blocked.
NB. Cabin: cabin,first,last,blocks. Aircraft: model,base,limit,cabins,seats.
NB. Flight: name,aircraft,limits,blocked,occupied,closed,volunteers.
NB. Booking: pnr,flight,checked,people.
NB. Passenger: name,type,pref,booking,cabin,seat,partner,alive.
pget =: 4 : 0
  y{::x{::PEOPLE
)
fget =: 4 : 0
  y{::x{::FLIGHTS
)
bget =: 4 : 0
  y{::x{::BOOKINGS
)
pwrite =: 4 : 0
  'person slot' =. x
  record =. person{::PEOPLE
  record =. (<y) slot}record
  PEOPLE =: (<record) person}PEOPLE
)
fwrite =: 4 : 0
  'flight slot' =. x
  record =. flight{::FLIGHTS
  record =. (<y) slot}record
  FLIGHTS =: (<record) flight}FLIGHTS
)
bwrite =: 4 : 0
  'booking slot' =. x
  record =. booking{::BOOKINGS
  record =. (<y) slot}record
  BOOKINGS =: (<record) booking}BOOKINGS
)
flight_id =: 3 : 0
  for_k. i.#FLIGHTS do.
    if. y text_equal k fget 0 do. k return. end.
  end.
  _1
)
remaining_count =: 3 : 0
  result =. 0
  for_person. y bget 3 do. result =. result+person pget 7 end.
  result
)
booking_id =: 4 : 0
  for_k. i.#BOOKINGS do.
    if. y text_equal k bget 0 do.
      if. x+.0<remaining_count k do. k return. end.
    end.
  end.
  _1
)
person_id =: 4 : 0
  for_person. x bget 3 do.
    if. person pget 7 do.
      if. y text_equal person pget 0 do. person return. end.
    end.
  end.
  _1
)
people_of =: 3 : 0
  result =. i.0
  for_k. i.#PEOPLE do.
    if. k pget 7 do.
      if. y=(k pget 3) bget 1 do. result =. result,k end.
    end.
  end.
  result
)
tier_of =: 3 : 0
  k =. TIERNAMES i.<,y
  if. k=#TIERNAMES do. 3 else. k{TIERS end.
)
cabin_id =: 4 : 0
  cabins =. 3{::x
  for_k. i.#cabins do.
    if. y=0{::k{::cabins do. k return. end.
  end.
  _1
)
seat_id =: 4 : 0
  seats =. 4{::x
  for_k. i.#seats do.
    if. y text_equal 0{::k{::seats do. k return. end.
  end.
  _1
)
with_infant =: 3 : 0
  (0=y pget 1)*.(y pget 6)>:0
)
booked_count =: 4 : 0
  result =. 0
  for_person. people_of x do.
    if. (2~:person pget 1)*.y=person pget 4 do. result =. result+1 end.
  end.
  result
)
permitted =: 3 : 0
  'flight person seat cabin ignored' =. y
  trip =. flight{::FLIGHTS
  plane =. (1{::trip){::AIRCRAFT
  seats =. 4{::plane
  target =. seat{::seats
  if. ((2{::target)~:cabin)+.seat{3{::trip do. 0 return. end.
  occupant =. seat{4{::trip
  if. (occupant>:0)*.-.occupant e.ignored do. 0 return. end.
  if. 6{::target do.
    if. (1=person pget 1)+.with_infant person do. 0 return. end.
  end.
  if. with_infant person do.
    for_k. i.#seats do.
      other =. k{::seats
      occupant =. k{4{::trip
      if. ((1{::other)=1{::target)*.(3{::other)=3{::target do.
        if. (occupant>:0)*.-.occupant e.ignored do.
          if. with_infant occupant do. 0 return. end.
        end.
      end.
    end.
  end.
  1
)
fits =: 3 : 0
  'flight persons seats' =. y
  plane =. (flight fget 1){::AIRCRAFT
  layout =. 4{::plane
  for_k. i.#persons do.
    person =. k{persons
    seat =. k{seats
    if. seat<0 do. 0 return. end.
    if. -.permitted (<flight),(<person),(<seat),(<person pget 4),<persons do. 0 return. end.
    for_j. i.k do.
      if. (j{seats)=seat do. 0 return. end.
      if. (with_infant person)*.with_infant j{persons do.
        a =. seat{::layout
        b =. (j{seats){::layout
        if. ((1{::a)=1{::b)*.(3{::a)=3{::b do. 0 return. end.
      end.
    end.
  end.
  1
)
choose =: 3 : 0
  'flight person cabin' =. y
  plane =. (flight fget 1){::AIRCRAFT
  seats =. 4{::plane
  first =. _1
  for_k. i.#seats do.
    if. permitted (<flight),(<person),(<k),(<cabin),<,person do.
      if. first<0 do. first =. k end.
      preference =. person pget 2
      if. #preference do.
        if. preference text_equal 5{::k{::seats do. k return. end.
      end.
    end.
  end.
  first
)
place =: 4 : 0
  flight =. (x pget 3) bget 1
  old =. x pget 5
  occupied =. flight fget 4
  if. old>:0 do. occupied =. (_1) old}occupied end.
  (x,5) pwrite y
  if. y>:0 do. occupied =. x y}occupied end.
  (flight,4) fwrite occupied
)
seat_text =: 3 : 0
  if. 2=y pget 1 do. 'LAP' return. end.
  seat =. y pget 5
  if. seat<0 do. 'UNASSIGNED' return. end.
  flight =. (y pget 3) bget 1
  plane =. (flight fget 1){::AIRCRAFT
  0{::seat{::4{::plane
)
reassign =: 3 : 0
  output =. 0$<''
  for_person. people_of y do.
    if. (2~:person pget 1)*.(person pget 5)<0 do.
      seat =. choose (<y),(<person),<person pget 4
      if. seat>:0 do.
        person place seat
        output =. output,<'REASSIGNED ',((person pget 3) bget 0),' ',(person pget 0),' ',seat_text person
      end.
    end.
  end.
  output
)
remove_person =: 3 : 0
  if. -.y pget 7 do. return. end.
  partner =. y pget 6
  flight =. (y pget 3) bget 1
  if. partner>:0 do.
    if. 0=y pget 1 do. remove_person partner
    elseif. 2=y pget 1 do. (partner,6) pwrite _1
    end.
  end.
  y place _1
  (y,7) pwrite 0
  (y,6) pwrite _1
  volunteers =. flight fget 6
  (flight,6) fwrite volunteers#~volunteers~:y
)
row_seats =: 4 : 0
  'row block' =. y
  seats =. 4{::x
  result =. i.0
  for_k. i.#seats do.
    seat =. k{::seats
    if. row=1{::seat do.
      if. (block<0)+.block=3{::seat do. result =. result,k end.
    end.
  end.
  result
)
assign_group =: 3 : 0
  'flight cabin persons' =. y
  count =. #persons
  if. count=1 do.
    person =. 0{persons
    person place choose (<flight),(<person),<cabin
    'SINGLE' return.
  end.
  plane =. (flight fget 1){::AIRCRAFT
  section =. (plane cabin_id cabin){::3{::plane
  first_row =. 1{::section
  last_row =. 2{::section
  for_stage. i.3 do.
    heights =. ,1
    if. stage=2 do. heights =. 2+i.count-1 end.
    for_height. heights do.
      width =. count
      if. stage=2 do. width =. (count+height-1) floor_ratio height end.
      for_row. first_row+i.1+last_row-first_row do.
        blocks =. i.#3{::section
        if. stage=1 do. blocks =. ,_1 end.
        for_block. blocks do.
          seats =. plane row_seats row,block
          for_start. i.0>.1+(#seats)-width do.
            candidate =. i.0
            if. stage<2 do. candidate =. count{.start}.seats
            else.
              for_k. i.count do.
                next_row =. row+k floor_ratio width
                next_seats =. plane row_seats next_row,block
                if. (next_row>last_row)+.(#next_seats)<start+width do. candidate =. i.0 break. end.
                candidate =. candidate,(start+width|k){next_seats
              end.
            end.
            if. (#candidate)=count do.
              if. fits (<flight),(<persons),<candidate do.
                for_k. i.count do. (k{persons) place k{candidate end.
                stage{::'BLOCK';'ROW';'STACK' return.
              end.
            end.
          end.
        end.
      end.
    end.
  end.
  for_person. persons do. person place choose (<flight),(<person),<cabin end.
  'SPLIT'
)
closed_error =: 3 : 0
  'ERROR flight ',(y fget 0),' is closed'
)
passenger_error =: 4 : 0
  booking =. 0 booking_id x
  if. booking<0 do. 'ERROR unknown PNR ',x return. end.
  flight =. booking bget 1
  if. flight fget 5 do. closed_error flight return. end.
  if. 0>booking person_id y do. 'ERROR no passenger ',y,' in ',x return. end.
  ''
)
load_factor =: 4 : 0
  q =. (x*1000) floor_ratio y
  (number q floor_ratio 10),'.',(number 10|q),'%'
)
execute =: 3 : 0
  fields =. ' ' split y
  command =. 0{::fields
  if. command text_equal 'AIRCRAFT' do.
    PENDING =: (1{fields),(<0".2{::fields),(<0".3{::fields),(<0$<i.0),<0$<i.0
    0$<'' return.
  end.
  if. command text_equal 'CABIN' do.
    cabin =. 'FJY' i.{.1{::fields
    first =. 0".2{::fields
    last =. 0".3{::fields
    blocks =. 4}.fields
    section =. (<cabin),(<first),(<last),<blocks
    cabins =. (3{::PENDING),<section
    seats =. 4{::PENDING
    for_row. first+i.1+last-first do.
      for_block. i.#blocks do.
        letters =. block{::blocks
        for_offset. i.#letters do.
          window =. ((block=0)*.offset=0)+.((block=(#blocks)-1)*.offset=(#letters)-1)
          kind =. 'M'
          if. window do. kind =. 'W'
          elseif. (offset=0)+.offset=(#letters)-1 do. kind =. 'A'
          end.
          label =. (number row),offset{letters
          seat =. (<label),(<row),(<cabin),(<block),(<offset),(<kind),(<0),<0
          seats =. seats,<seat
        end.
      end.
    end.
    PENDING =: (<cabins) 3}PENDING
    PENDING =: (<seats) 4}PENDING
    0$<'' return.
  end.
  if. (<command)e.'EXIT';'BLOCKED' do.
    seats =. 4{::PENDING
    for_k. 1+i.(#fields)-1 do.
      for_j. i.#seats do.
        seat =. j{::seats
        selected =. 0
        if. command text_equal 'EXIT' do. selected =. (1{::seat)=0".k{::fields
        else. selected =. (0{::seat) text_equal k{::fields
        end.
        if. selected do.
          slot =. 6
          if. command text_equal 'BLOCKED' do. slot =. 7 end.
          seat =. (<1) slot}seat
          seats =. (<seat) j}seats
        end.
      end.
    end.
    PENDING =: (<seats) 4}PENDING
    0$<'' return.
  end.
  if. command text_equal 'END' do.
    result =. 'AIRCRAFT ',0{::PENDING
    for_section. 3{::PENDING do.
      cabin =. 0{::>section
      count =. 0
      for_seat. 4{::PENDING do.
        seat =. >seat
        if. (cabin=2{::seat)*.-.7{::seat do. count =. count+1 end.
      end.
      result =. result,' ',(cabin_name cabin),' ',number count
    end.
    AIRCRAFT =: AIRCRAFT,<PENDING
    <result return.
  end.
  if. command text_equal 'STATUS' do.
    tier =. (;:'PLATINUM GOLD SILVER NONE') i.2{fields
    k =. TIERNAMES i.1{fields
    if. k=#TIERNAMES do.
      TIERNAMES =: TIERNAMES,1{fields
      TIERS =: TIERS,tier
    else. TIERS =: tier k}TIERS
    end.
    <'STATUS ',(1{::fields),' ',2{::fields return.
  end.
  if. command text_equal 'FLIGHT' do.
    if. 0<:flight_id 1{::fields do. <'ERROR duplicate flight ',1{::fields return. end.
    model =. _1
    for_k. i.#AIRCRAFT do.
      if. (2{::fields) text_equal 0{::k{::AIRCRAFT do. model =. k end.
    end.
    if. model<0 do. <'ERROR unknown aircraft ',2{::fields return. end.
    plane =. model{::AIRCRAFT
    seats =. 4{::plane
    overbook =. 0".3{::fields
    limits =. 3$0
    blocked =. i.0
    for_seat. seats do. blocked =. blocked,7{::>seat end.
    result =. 'FLIGHT ',(1{::fields),' ',2{::fields
    for_section. 3{::plane do.
      cabin =. 0{::>section
      count =. 0
      for_seat. seats do.
        seat =. >seat
        if. (cabin=2{::seat)*.-.7{::seat do. count =. count+1 end.
      end.
      limit =. (count*(100+overbook)) floor_ratio 100
      limits =. limit cabin}limits
      result =. result,' ',(cabin_name cabin),' ',(number count),'/',number limit
    end.
    trip =. (1{fields),(<model),(<limits),(<blocked),(<(#seats)$_1),(<0),<i.0
    FLIGHTS =: FLIGHTS,<trip
    <result return.
  end.
  if. command text_equal 'BOOK' do.
    pnr =. 1{::fields
    if. 0<:1 booking_id pnr do. <'ERROR duplicate PNR ',pnr return. end.
    flight =. flight_id 2{::fields
    if. flight<0 do. <'ERROR unknown flight ',2{::fields return. end.
    if. flight fget 5 do. <closed_error flight return. end.
    cabin =. 'FJY' i.{.3{::fields
    plane =. (flight fget 1){::AIRCRAFT
    if. 0>plane cabin_id cabin do. <'ERROR no cabin ',(3{::fields),' on ',2{::fields return. end.
    names =. 0$<''
    types =. i.0
    preferences =. 0$<''
    for_k. 4+i.(#fields)-4 do.
      part =. ':' split k{::fields
      name =. 0{::part
      if. (<name)e.names do. <'ERROR duplicate name ',name,' in ',pnr return. end.
      names =. names,<name
      types =. types,(;:'ADULT CHILD INFANT') i.1{part
      preference =. ''
      if. 3=#part do. preference =. 2{::part end.
      preferences =. preferences,<preference
    end.
    for_name. names do.
      name =. >name
      for_person. people_of flight do.
        if. name text_equal person pget 0 do. <'ERROR ',name,' already on ',2{::fields return. end.
      end.
    end.
    adults =. +/types=0
    infants =. +/types=2
    if. adults=0 do. <'ERROR no adult in ',pnr return. end.
    if. infants>adults do. <'ERROR too many infants in ',pnr return. end.
    needed =. (#names)-infants
    if. ((flight booked_count cabin)+needed)>cabin{flight fget 2 do. <'ERROR limit exceeded for ',(2{::fields),' ',3{::fields return. end.
    booking =. #BOOKINGS
    persons =. i.0
    seated_people =. i.0
    adult_ids =. i.0
    infant_ids =. i.0
    for_k. i.#names do.
      person =. #PEOPLE
      record =. (k{names),(<k{types),(k{preferences),(<booking),(<cabin),(<_1),(<_1),<1
      PEOPLE =: PEOPLE,<record
      persons =. persons,person
      if. 2=k{types do. infant_ids =. infant_ids,person
      else.
        seated_people =. seated_people,person
        if. 0=k{types do. adult_ids =. adult_ids,person end.
      end.
    end.
    record =. (<pnr),(<flight),(<0),<persons
    BOOKINGS =: BOOKINGS,<record
    for_k. i.infants do.
      ((k{adult_ids),6) pwrite k{infant_ids
      ((k{infant_ids),6) pwrite k{adult_ids
    end.
    method =. assign_group (<flight),(<cabin),<seated_people
    result =. 'BOOKED ',pnr,' ',(2{::fields),' ',(3{::fields),' ',method
    for_person. persons do. result =. result,' ',(person pget 0),':',seat_text person end.
    <result return.
  end.
  if. command text_equal 'FIND' do.
    output =. 0$<''
    name =. 1{::fields
    for_flight. i.#FLIGHTS do.
      for_person. people_of flight do.
        if. name text_equal person pget 0 do.
          status =. 'OPEN'
          if. flight fget 5 do. status =. 'CLOSED' end.
          output =. output,<(flight fget 0),' ',((person pget 3) bget 0),' ',(cabin_name person pget 4),' ',(seat_text person),' ',status
        end.
      end.
    end.
    tier =. (tier_of name){::;:'PLATINUM GOLD SILVER NONE'
    (<'FIND ',name,' ',tier,' ',number #output),output return.
  end.
  if. (<command)e.'SEAT';'SWAP';'CANCEL';'CHECKIN';'VOLUNTEER';'INFO' do.
    booking =. 0 booking_id 1{::fields
    if. booking<0 do. <'ERROR unknown PNR ',1{::fields return. end.
    flight =. booking bget 1
    if. -.command text_equal 'INFO' do.
      if. flight fget 5 do. <closed_error flight return. end.
    end.
    if. command text_equal 'INFO' do.
      status =. 'NOT-CHECKED'
      if. booking bget 2 do. status =. 'CHECKED' end.
      output =. ,<'INFO ',(1{::fields),' ',(flight fget 0),' ',(number remaining_count booking),' ',status
      for_person. booking bget 3 do.
        if. person pget 7 do. output =. output,<(person pget 0),' ',((person pget 1){::;:'ADULT CHILD INFANT'),' ',(cabin_name person pget 4),' ',seat_text person end.
      end.
      output return.
    end.
    if. command text_equal 'CHECKIN' do.
      if. booking bget 2 do. <'ERROR ',(1{::fields),' already checked in' return. end.
      (booking,2) bwrite 1
      <'CHECKIN ',(1{::fields),' ',number remaining_count booking return.
    end.
    person =. _1
    if. (#fields)>2 do. person =. booking person_id 2{::fields end.
    require_name =. -.command text_equal 'CANCEL'
    if. command text_equal 'CANCEL' do. require_name =. 3=#fields end.
    if. require_name*.person<0 do. <'ERROR no passenger ',(2{::fields),' in ',1{::fields return. end.
    if. command text_equal 'CANCEL' do.
      targets =. i.0
      adults =. 0
      remaining =. 0
      for_member. booking bget 3 do.
        if. -.member pget 7 do. continue. end.
        target =. ((#fields)=2)+.member=person
        if. person>:0 do.
          if. with_infant person do. target =. target+.member=person pget 6 end.
        end.
        if. target do. targets =. targets,member
        else.
          remaining =. remaining+1
          adults =. adults+0=member pget 1
        end.
      end.
      if. (remaining>0)*.adults=0 do. <'ERROR ',(1{::fields),' would have no adult' return. end.
      result =. 'CANCELLED ',1{::fields
      for_target. targets do.
        result =. result,' ',target pget 0
        remove_person target
      end.
      (<result),reassign flight return.
    end.
    if. command text_equal 'SWAP' do.
      problem =. (3{::fields) passenger_error 4{::fields
      if. #problem do. <problem return. end.
      other_booking =. 0 booking_id 3{::fields
      other =. other_booking person_id 4{::fields
      if. person=other do. <'ERROR cannot swap ',(2{::fields),' with itself' return. end.
      for_target. person,other do.
        if. 2=target pget 1 do. <'ERROR infant ',(target pget 0),' has no seat' return. end.
      end.
      if. flight~:other_booking bget 1 do. <'ERROR ',(1{::fields),' and ',(3{::fields),' are on different flights' return. end.
      if. (person pget 4)~:other pget 4 do. <'ERROR ',(2{::fields),' and ',(4{::fields),' are in different cabins' return. end.
      for_target. person,other do.
        if. 0>target pget 5 do. <'ERROR ',(target pget 0),' has no seat' return. end.
      end.
      first_seat =. person pget 5
      second_seat =. other pget 5
      if. -.fits (<flight),(<person,other),<second_seat,first_seat do. <'ERROR swap of ',(2{::fields),' and ',(4{::fields),' breaks seating rules' return. end.
      person place _1
      other place _1
      person place second_seat
      other place first_seat
      result =. 'SWAPPED ',(1{::fields),' ',(2{::fields),' ',(seat_text person),' ',(3{::fields),' ',(4{::fields),' ',seat_text other
      (<result),reassign flight return.
    end.
    if. command text_equal 'VOLUNTEER' do.
      if. (0~:person pget 1)+.with_infant person do. <'ERROR ',(2{::fields),' cannot volunteer' return. end.
      if. 0>person pget 5 do. <'ERROR ',(2{::fields),' has no seat' return. end.
      if. person e.flight fget 6 do. <'ERROR ',(2{::fields),' already volunteered' return. end.
      (flight,6) fwrite (flight fget 6),person
      <'VOLUNTEER ',(1{::fields),' ',(2{::fields),' ',seat_text person return.
    end.
    if. 2=person pget 1 do. <'ERROR infant ',(2{::fields),' has no seat' return. end.
    plane =. (flight fget 1){::AIRCRAFT
    seat =. plane seat_id 3{::fields
    cabin =. person pget 4
    invalid =. seat<0
    if. -.invalid do. invalid =. cabin~:2{::seat{::4{::plane end.
    if. invalid do. <'ERROR no seat ',(3{::fields),' in cabin ',cabin_name cabin return. end.
    target =. seat{::4{::plane
    if. seat{flight fget 3 do. <'ERROR seat ',(3{::fields),' is blocked' return. end.
    if. 0<:seat{flight fget 4 do. <'ERROR seat ',(3{::fields),' is occupied' return. end.
    if. (6{::target)*.((1=person pget 1)+.with_infant person) do. <'ERROR exit row ',(number 1{::target),' not allowed for ',2{::fields return. end.
    if. -.permitted (<flight),(<person),(<seat),(<cabin),<,person do. <'ERROR infant limit reached at ',3{::fields return. end.
    old =. seat_text person
    person place seat
    (<'MOVED ',(1{::fields),' ',(2{::fields),' ',old,' -> ',3{::fields),reassign flight return.
  end.
  flight =. flight_id 1{::fields
  if. flight<0 do. <'ERROR unknown flight ',1{::fields return. end.
  plane =. (flight fget 1){::AIRCRAFT
  if. (<command)e.'UPGRADE';'CLOSE';'BLOCK';'UNBLOCK' do.
    if. flight fget 5 do. <closed_error flight return. end.
  end.
  if. (<command)e.'BLOCK';'UNBLOCK' do.
    seat =. plane seat_id 2{::fields
    if. seat<0 do. <'ERROR no seat ',(2{::fields),' on ',1{::fields return. end.
    blocking =. command text_equal 'BLOCK'
    blocked =. flight fget 3
    if. blocking=seat{blocked do.
      if. blocking do. suffix =. ' is blocked' else. suffix =. ' is not blocked' end.
      <'ERROR seat ',(2{::fields),suffix return.
    end.
    blocked =. blocking seat}blocked
    (flight,3) fwrite blocked
    output =. ,<command,' ',(1{::fields),' ',2{::fields
    person =. seat{flight fget 4
    if. blocking*.person>:0 do.
      person place _1
      person place choose (<flight),(<person),<person pget 4
      output =. output,<'DISPLACED ',((person pget 3) bget 0),' ',(person pget 0),' ',(2{::fields),' -> ',seat_text person
    end.
    output,reassign flight return.
  end.
  if. command text_equal 'UPGRADE' do.
    output =. 0$<''
    count =. 0
    cabins =. 3{::plane
    for_pair_id. 1+i.(#cabins)-1 do.
      higher =. 0{::(pair_id-1){::cabins
      lower =. 0{::pair_id{::cabins
      targets =. i.0
      for_tier. i.3 do.
        for_person. people_of flight do.
          if. ((person pget 4)=lower)*.(0=person pget 1)*.(-.with_infant person)*.tier=tier_of person pget 0 do. targets =. targets,person end.
        end.
      end.
      for_person. targets do.
        if. (flight booked_count higher)>:higher{flight fget 2 do. break. end.
        seat =. choose (<flight),(<person),<higher
        if. seat<0 do. break. end.
        old =. seat_text person
        (person,4) pwrite higher
        person place seat
        count =. count+1
        output =. output,<'UPGRADED ',((person pget 3) bget 0),' ',(person pget 0),' ',(cabin_name lower),' ',old,' -> ',(cabin_name higher),' ',seat_text person
      end.
    end.
    output =. output,reassign flight
    output,<'UPGRADE ',(1{::fields),' ',number count return.
  end.
  if. command text_equal 'CLOSE' do.
    output =. 0$<''
    for_booking. i.#BOOKINGS do.
      if. (flight=booking bget 1)*.(-.booking bget 2)*.0<remaining_count booking do.
        output =. output,<'NOSHOW ',(booking bget 0),' ',number remaining_count booking
        for_person. booking bget 3 do. remove_person person end.
      end.
    end.
    output =. output,reassign flight
    count =. 0
    total =. 0
    for_section. 3{::plane do.
      cabin =. 0{::>section
      volunteers =. i.0
      for_person. flight fget 6 do.
        if. (person pget 7)*.((person pget 5)>:0)*.cabin=person pget 4 do. volunteers =. volunteers,person end.
      end.
      for_person. volunteers do.
        seat =. person pget 5
        useful =. 0
        for_waiting. people_of flight do.
          if. (2~:waiting pget 1)*.((waiting pget 5)<0)*.cabin=waiting pget 4 do.
            if. permitted (<flight),(<waiting),(<seat),(<cabin),<,person do. useful =. 1 break. end.
          end.
        end.
        if. useful do.
          compensation =. cabin{500 300 150
          output =. output,<'DENIED VOLUNTARY ',((person pget 3) bget 0),' ',(person pget 0),' ',(cabin_name cabin),' ',number compensation
          remove_person person
          count =. count+1
          total =. total+compensation
          output =. output,reassign flight
        end.
      end.
    end.
    for_person. people_of flight do.
      if. (person pget 7)*.(2~:person pget 1)*.(person pget 5)<0 do.
        cabin =. person pget 4
        compensation =. cabin{1000 600 300
        if. 1=person pget 1 do. compensation =. compensation floor_ratio 2 end.
        output =. output,<'DENIED INVOLUNTARY ',((person pget 3) bget 0),' ',(person pget 0),' ',(cabin_name cabin),' ',number compensation
        remove_person person
        count =. count+1
        total =. total+compensation
      end.
    end.
    (flight,5) fwrite 1
    output,<'CLOSED ',(1{::fields),' denied ',(number count),' compensation ',number total return.
  end.
  seats =. 4{::plane
  if. command text_equal 'MAP' do.
    output =. ,<'MAP ',1{::fields
    for_section. 3{::plane do.
      section =. >section
      output =. output,<'CABIN ',cabin_name 0{::section
      output =. output,<'   ',' ' join 3{::section
      for_row. (1{::section)+i.1+(2{::section)-1{::section do.
        blocks =. 0$<''
        for_block. i.#3{::section do.
          text =. ''
          for_seat. plane row_seats row,block do.
            if. seat{flight fget 3 do. text =. text,'#'
            elseif. 0<:seat{flight fget 4 do. text =. text,'X'
            elseif. 6{::seat{::seats do. text =. text,'E'
            else. text =. text,'.'
            end.
          end.
          blocks =. blocks,<text
        end.
        prefix =. ''
        if. row<10 do. prefix =. ' ' end.
        output =. output,<prefix,(number row),' ',' ' join blocks
      end.
    end.
    output return.
  end.
  if. command text_equal 'AVAIL' do.
    cabin =. 'FJY' i.{.2{::fields
    if. 0>plane cabin_id cabin do. <'ERROR no cabin ',(2{::fields),' on ',1{::fields return. end.
    counts =. 5$0
    for_k. i.#seats do.
      seat =. k{::seats
      if. (cabin=2{::seat)*.(-.k{flight fget 3)*.(k{flight fget 4)<0 do.
        counts =. (1+0{counts) 0}counts
        p =. 1+'WMA' i.{.5{::seat
        counts =. (1+p{counts) p}counts
        if. 6{::seat do. counts =. (1+4{counts) 4}counts end.
      end.
    end.
    <'AVAIL ',(1{::fields),' ',(2{::fields),' free ',(number 0{counts),' W ',(number 1{counts),' M ',(number 2{counts),' A ',(number 3{counts),' EXIT ',number 4{counts return.
  end.
  if. command text_equal 'LOADFACTOR' do.
    output =. ,<'LOADFACTOR ',1{::fields
    total_seats =. 0
    total_seated =. 0
    for_section. 3{::plane do.
      cabin =. 0{::>section
      count =. 0
      seated =. 0
      for_k. i.#seats do.
        if. cabin=2{::k{::seats do.
          count =. count+-.k{flight fget 3
          seated =. seated+0<:k{flight fget 4
        end.
      end.
      output =. output,<(cabin_name cabin),' ',(number seated),'/',(number count),' ',(seated load_factor count),' booked ',(number flight booked_count cabin),'/',number cabin{flight fget 2
      total_seats =. total_seats+count
      total_seated =. total_seated+seated
    end.
    output,<'ALL ',(number total_seated),'/',(number total_seats),' ',total_seated load_factor total_seats return.
  end.
  if. command text_equal 'BALANCE' do.
    weight =. 0
    moment =. 0
    for_person. people_of flight do.
      seat =. person pget 5
      if. seat>:0 do.
        amount =. 80
        if. 1=person pget 1 do. amount =. 40
        elseif. with_infant person do. amount =. 90
        end.
        weight =. weight+amount
        moment =. moment+amount*((1{::seat{::seats)-1{::plane)
      end.
    end.
    limit =. 2{::plane
    verdict =. 'OK'
    if. moment < -limit do. verdict =. 'NOSE-HEAVY'
    elseif. moment>limit do. verdict =. 'TAIL-HEAVY'
    end.
    <'BALANCE ',(1{::fields),' weight ',(number weight),' moment ',(number moment),' limit ',(number limit),' ',verdict return.
  end.
  seated_people =. i.0
  waiting_people =. i.0
  infant_count =. 0
  for_seat. i.#seats do.
    person =. seat{flight fget 4
    if. person>:0 do. seated_people =. seated_people,person end.
  end.
  for_person. people_of flight do.
    if. 2=person pget 1 do. infant_count =. infant_count+1
    elseif. (person pget 5)<0 do. waiting_people =. waiting_people,person
    end.
  end.
  if. command text_equal 'MANIFEST' do.
    output =. ,<'MANIFEST ',(1{::fields),' seated ',(number #seated_people),' unassigned ',(number #waiting_people),' infants ',number infant_count
    for_person. seated_people,waiting_people do.
      booking =. person pget 3
      label =. seat_text person
      if. (person pget 5)<0 do. label =. '---' end.
      result =. label,' ',(cabin_name person pget 4),' ',(booking bget 0),' ',(person pget 0),' ',(person pget 1){::'ADULT';'CHILD'
      if. with_infant person do. result =. result,' +',(person pget 6) pget 0 end.
      tier =. tier_of person pget 0
      if. tier<3 do. result =. result,' ',tier{::;:'PLATINUM GOLD SILVER' end.
      if. booking bget 2 do. result =. result,' CHECKED' end.
      if. person e.flight fget 6 do. result =. result,' VOL' end.
      output =. output,<result
    end.
    output return.
  end.
  NB. BOARDING: whole integer keys retain PRE and cabin precedence.
  keys =. 0 5$0
  groups =. 0$<''
  order =. i.0
  y_first =. 1{::(plane cabin_id 2){::3{::plane
  for_k. i.#seated_people do.
    person =. k{seated_people
    seat_id_value =. person pget 5
    seat =. seat_id_value{::seats
    row =. 1{::seat
    preboard =. 0
    for_member. (person pget 3) bget 3 do.
      if. (member pget 7)*.2=member pget 1 do. preboard =. 1 end.
    end.
    group =. 3
    if. preboard do. group =. 0
    elseif. (person pget 4)<2 do. group =. 1
    elseif. 2>tier_of person pget 0 do. group =. 2
    end.
    zone =. 1+(row-y_first) floor_ratio 5
    kind =. 'WMA' i.{.5{::seat
    label =. group{::'PRE';'CABIN';'TIER';'ZONE'
    if. group=3 do.
      key =. group,(-zone),kind,(-row),seat_id_value
      label =. label,number zone
    else. key =. group,0 0,row,seat_id_value
    end.
    keys =. keys,key
    groups =. groups,<label
  end.
  order =. /:keys
  output =. ,<'BOARDING ',(1{::fields),' ',number #seated_people
  for_k. i.#order do.
    item =. k{order
    person =. item{seated_people
    output =. output,<(number k+1),' ',(item{::groups),' ',(seat_text person),' ',((person pget 3) bget 0),' ',person pget 0
  end.
  output
)
main =: 3 : 0
  input =. 1!:1 (3)
  if. LF~:{:input do. input=.input,LF end.
  lines =. <;._2 input
  count =. 0".0{::lines
  for_k. 1+i.count do.
    output =. execute k{::lines
    for_line. output do. ((>line),LF) 1!:2 (4) end.
  end.
  i.0 0
)
main''
