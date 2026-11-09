LF=:10{a.
EMPTY=:i.0 0
NONE=:1000000000000
split=:4:0
  <;._1 x,y
)
join=:4:0
  if. 0=#y do. '' return. end.
  (#x)}.;(<x),&.>y
)
text_equal=:4:0
  (,x)-:,y
)
number=:3:0
  ,'0' 8!:2 y
)
integer_value=:3:0
  if. '-'={.y do. -0".}.y else. 0".y end.
)
floor_ratio=:4:0
  <.(x:x)%x:y
)
half_up=:4:0
  ((2*x)+y)floor_ratio 2*y
)
half_away=:4:0
  result=.((2*|x)+y)floor_ratio 2*y
  if. x<0 do. -result else. result end.
)
decimal_text=:4:0
  absolute=.|y
  prefix=.''
  if. y<0 do. prefix=.x end.
  prefix,(number absolute floor_ratio 10),'.',number 10|absolute
)
index_text=:3:0
  if. y=NONE do. 'none' else. '+'decimal_text y end.
)
handicap_text=:3:0
  if. y=NONE do. 'none' return. end.
  if. y<0 do. '+',number -y else. number y end.
)
hundredths=:3:0
  tail=.number 100|y
  (number y floor_ratio 100),'.',((2-#tail)#'0'),tail
)
integer_list=:3:0
  ' 'join number&.>y
)
sum_range=:4:0
  'first last'=.x
  +/(first+i.last-first){y
)
ranked=:3:0
  if. 0=#y do. i.0 return. end.
  width=.#1{::0{::y
  keys=.(0,width)$0
  ids=.0$a:
  targets=.i.0
  for_item. y do.
    rec=.>item
    targets=.targets,0{::rec
    keys=.keys,1{::rec
    ids=.ids,<2{::rec
  end.
  initial=./:ids
  if. width=0 do. initial{targets return. end.
  ((/:initial{keys){initial){targets
)
cget=:4:0
  y{::x{::C
)
tget=:4:0
  y{::x{::T
)
pget=:4:0
  y{::x{::P
)
rget=:4:0
  y{::x{::R
)
eget=:4:0
  y{::x{::E
)
pset=:4:0
  rec=.({.x){::P
  rec=.(<y)({:x)}rec
  P=:(<rec)({.x)}P
  EMPTY
)
emit=:3:0
  (y,LF)1!:2(4)
  EMPTY
)
fail=:3:0
  emit 'ERROR ',y
)
course_id=:3:0
  for_k. i.#C do. if. y text_equal k cget 0 do. k return. end. end.
  _1
)
tee_id=:4:0
  for_k. i.#T do.
    if. x=k tget 0 do. if. y text_equal k tget 1 do. k return. end. end.
  end.
  _1
)
player_id=:3:0
  for_k. i.#P do. if. y text_equal k pget 0 do. k return. end. end.
  _1
)
event_id=:3:0
  for_k. i.#E do. if. y text_equal k eget 0 do. k return. end. end.
  _1
)
course_handicap=:3:0
  'course tee index'=.y
  numerator=.(index*tee tget 3)+113*((tee tget 2)-10*course cget 3)
  numerator half_up 1130
)
allocation=:4:0
  si=.x cget 2
  absolute=.|y
  quotient=.absolute floor_ratio 18
  remainder=.18|absolute
  if. y>:0 do. quotient+(si<:remainder) else. -(quotient+(si>:19-remainder)) end.
)
low_record=:4:0
  dates=.x pget 4
  indexes=.x pget 5
  value=.NONE
  date=.0
  for_k. i.#dates do.
    candidate=.k{indexes
    candidate_day=.k{dates
    if. ((y-365)<:candidate_day)*.candidate_day<y do.
      if. (candidate<value)+.((candidate=value)*.candidate_day<date) do.
        value=.candidate
        date=.candidate_day
      end.
    end.
  end.
  value,date
)
count_rule=:3:0
  if. y=3 do. 1 _20 return. end.
  if. y=4 do. 1 _10 return. end.
  if. y=5 do. 1 0 return. end.
  if. y=6 do. 2 _10 return. end.
  if. y<:8 do. 2 0 return. end.
  if. y<:11 do. 3 0 return. end.
  if. y<:14 do. 4 0 return. end.
  if. y<:16 do. 5 0 return. end.
  if. y<:18 do. 6 0 return. end.
  if. y=19 do. 7 0 else. 8 0 end.
)
adjusted_differentials=:3:0
  ids=.y pget 3
  ids=.(0>.(#ids)-20)}.ids
  differentials=.7{::&>ids{R
  reductions=.8{::&>ids{R
  differentials-|.+/\|.reductions
)
counting_order=:3:0
  keys=.y,.-i.#y
  /:keys
)
update_index=:4:0
  person=.x
  day=.y
  adjusted=.adjusted_differentials person
  count=.#adjusted
  if. count<3 do.
    (person,6)pset 0 0 0,NONE,0 0 0
    return.
  end.
  'k adjustment'=.count_rule count
  order=.counting_order adjusted
  total=.+/(k{.order){adjusted
  average=.total half_away k
  candidate=.average+adjustment
  low=.{.person low_record day
  soft=.0
  hard=.0
  if. low~:NONE do.
    if. (candidate-low)>30 do.
      candidate=.low+30+((candidate-low)-30)floor_ratio 2
      soft=.1
    end.
    if. (candidate-low)>50 do.
      candidate=.low+50
      hard=.1
    end.
  end.
  capped=.candidate>540
  candidate=.540<.candidate
  (person,2)pset candidate
  (person,6)pset k,average,adjustment,low,hard,soft,capped
)
countback_keys=:4:0
  keys=.(+/y),(9 18 sum_range y),(12 18 sum_range y),(15 18 sum_range y),17{y
  if. x do. -keys else. keys end.
)
evaluate=:3:0
  event=.y
  'id format course tee day allowance people'=.event{::E
  rounds=.i.0
  ph=.i.0
  nets=.0 18$0
  points=.0 18$0
  records=.0 18$0
  complete=.i.0
  for_person. people do.
    selected=._1
    for_index. person pget 3 do.
      if. (course=index rget 0)*.(tee=index rget 1)*.day=index rget 2 do. selected=.index break. end.
    end.
    if. selected<0 do. (<'missing round'),(<i.0),(<i.0),(<nets),(<points),(<records),<complete return. end.
    if. NONE=selected rget 4 do. (<'no index'),(<i.0),(<i.0),(<nets),(<points),(<records),<complete return. end.
    rounds=.rounds,selected
    ph=.ph,((selected rget 4)*allowance)half_up 100
  end.
  lowest=.<./ph
  relative=.(<format)e.;:'MATCH NASSAU FOURBALL'
  for_k. i.#people do.
    index=.k{rounds
    handicap=.k{ph
    if. relative do. handicap=.handicap-lowest end.
    strokes=.course allocation handicap
    scores=.index rget 3
    net=.18#NONE
    point=.18#0
    record=.18#_1
    full=.1
    for_hole. i.18 do.
      score=.hole{scores
      par=.hole{course cget 1
      if. score>0 do.
        value=.score-hole{strokes
        net=.value hole}net
        point=.(0>.par+2-value)hole}point
        outcome=._1
        if. value<par do. outcome=.1 elseif. value=par do. outcome=.0 end.
        record=.outcome hole}record
      else. full=.0 end.
    end.
    nets=.nets,net
    points=.points,point
    records=.records,record
    complete=.complete,full
  end.
  (<''),(<rounds),(<ph),(<nets),(<points),(<records),<complete
)
individual_ranking=:4:0
  'event gross'=.x
  result=.y
  format=.event eget 1
  people=.event eget 6
  rounds=.1{::result
  nets=.3{::result
  points=.4{::result
  records=.5{::result
  complete=.6{::result
  entries=.0$a:
  for_k. i.#people do.
    if. ('STROKE'text_equal format)*.-.k{complete do. continue. end.
    if. gross do. values=.(k{rounds)rget 3
    elseif. 'STROKE'text_equal format do. values=.k{nets
    elseif. 'STABLEFORD'text_equal format do. values=.k{points
    else. values=.k{records end.
    keys=.(-.'STROKE'text_equal format)countback_keys values
    entries=.entries,<(<k),(<keys),<(k{people)pget 0
  end.
  ranked entries
)
match_status=:3:0
  if. y=0 do. 'AS' elseif. y>0 do. (number y),' UP' else. (number -y),' DN' end.
)
play_match=:4:0
  'first last one two'=.x
  outcomes=.y
  lead=.0
  statuses=.0$a:
  remaining=.last-first
  for_hole. first+i.1+last-first do.
    lead=.lead+hole{outcomes
    remaining=.last-hole
    statuses=.statuses,<match_status lead
    if. (|lead)>remaining do. break. end.
  end.
  text=.'AS'
  if. lead~:0 do.
    side=.one
    if. lead<0 do. side=.two end.
    if. remaining>0 do. suffix=.'&',number remaining else. suffix=.' UP' end.
    text=.side,' ',(number |lead),suffix
  end.
  (<statuses),<text
)
event_results=:4:0
  event=.x
  result=.y
  'id format course tee day allowance people'=.event{::E
  'reason rounds ph nets points records complete'=.result
  count=.#people
  emit 'results ',id,': ',format,' ',(course cget 0),' ',(tee tget 1),' day ',(number day),' allowance ',number allowance
  if. (<format)e.;:'STROKE STABLEFORD PAR' do.
    order=.(event,0)individual_ranking result
    for_k. i.#order do.
      position=.k{order
      text=.(number k+1),' ',(position{people)pget 0
      if. 'STROKE'text_equal format do.
        text=.text,' net ',(number +/position{nets),' gross ',number +/(position{rounds)rget 3
      elseif. 'STABLEFORD'text_equal format do. text=.text,' points ',number +/position{points
      else. text=.text,' ',match_status +/position{records end.
      emit text,' hcp ',handicap_text position{ph
    end.
    if. 'STROKE'text_equal format do.
      entries=.0$a:
      for_k. i.count do.
        if. -.k{complete do. entries=.entries,<(<k),(<i.0),<(k{people)pget 0 end.
      end.
      for_position. ranked entries do. emit 'NR ',((position{people)pget 0),' hcp ',handicap_text position{ph end.
      if. #order do.
        winner=.{.(event,1)individual_ranking result
        emit 'gross ',((winner{people)pget 0),' ',number +/(winner{rounds)rget 3
      end.
    end.
  elseif. (<format)e.;:'MATCH NASSAU FOURBALL' do.
    lowest=.<./ph
    text=.'strokes'
    for_k. i.count do. text=.text,' ',((k{people)pget 0),' ',number (k{ph)-lowest end.
    emit text
    width=.1
    if. 'FOURBALL'text_equal format do. width=.2 end.
    sides=.0$a:
    side_scores=.0 18$0
    for_side. i.2 do.
      names=.0$a:
      scores=.18#NONE
      for_k. (side*width)+i.width do.
        names=.names,<(k{people)pget 0
        scores=.scores<.k{nets
      end.
      sides=.sides,<'+'join names
      side_scores=.side_scores,scores
    end.
    outcomes=.(0{side_scores)<1{side_scores
    outcomes=.outcomes-((0{side_scores)>1{side_scores)
    if. 'NASSAU'text_equal format do.
      for_segment. i.3 do.
        first=.0
        last=.17
        label=.'total'
        if. segment=0 do.
          last=.8
          label=.'front'
        end.
        if. segment=1 do.
          first=.9
          label=.'back'
        end.
        match=.((<first),(<last),sides)play_match outcomes
        emit label,' ',1{::match
      end.
    else.
      match=.((<0),(<17),sides)play_match outcomes
      emit 'status ',(', 'join 0{::match)
      emit 'result ',1{::match
    end.
  elseif. 'BETTERBALL'text_equal format do.
    entries=.0$a:
    team_points=.0 18$0
    for_team. i.count floor_ratio 2 do.
      values=.((2*team){points)>.((1+2*team){points)
      team_points=.team_points,values
      keys=.1 countback_keys values
      entries=.entries,<(<team),(<keys),<((2*team){people)pget 0
    end.
    order=.ranked entries
    for_k. i.#order do.
      team=.k{order
      emit (number k+1),' ',(((2*team){people)pget 0),'+',(((1+2*team){people)pget 0),' points ',(number +/team{team_points),' hcp ',(handicap_text (2*team){ph),' ',handicap_text (1+2*team){ph
    end.
  else.
    carry=.0
    totals=.count#0
    finalties=.i.0
    for_hole. i.18 do.
      carry=.carry+1
      best=.NONE
      ties=.i.0
      for_k. i.count do.
        value=.(<k,hole){nets
        if. value<best do.
          best=.value
          ties=.,k
        elseif. (value=best)*.value~:NONE do. ties=.ties,k end.
      end.
      if. 1=#ties do.
        winner=.{.ties
        totals=.((winner{totals)+100*carry)winner}totals
        emit 'hole ',(number hole+1),' ',((winner{people)pget 0),' ',number carry
        carry=.0
      end.
      finalties=.ties
    end.
    if. carry>0 do.
      if. 0=#finalties do. finalties=.i.count end.
      entries=.0$a:
      for_position. finalties do. entries=.entries,<(<position),(<i.0),<(position{people)pget 0 end.
      text=.'carry ',number carry
      share=.(carry*100)floor_ratio #finalties
      for_position. ranked entries do.
        totals=.((position{totals)+share)position}totals
        text=.text,' ',(position{people)pget 0
      end.
      emit text
    end.
    entries=.0$a:
    for_k. i.count do. entries=.entries,<(<k),(<,-k{totals),<(k{people)pget 0 end.
    for_position. ranked entries do. emit ((position{people)pget 0),' ',hundredths position{totals end.
  end.
  EMPTY
)
card_totals=:3:0
  'course index strokes label first last'=.y
  pars=.course cget 1
  scores=.index rget 3
  adjusted=.index rget 5
  score=.0
  net=.0
  points=.0
  complete=.1
  for_hole. first+i.last-first do.
    value=.hole{scores
    if. value>0 do.
      score=.score+value
      netvalue=.value-hole{strokes
      net=.net+netvalue
      points=.points+0>.(hole{pars)+2-netvalue
    else. complete=.0 end.
  end.
  scoretext=.'-'
  nettext=.'-'
  if. complete do.
    scoretext=.number score
    nettext=.number net
  end.
  emit label,' ',(number (first,last)sum_range pars),' ',scoretext,' ',(number (first,last)sum_range adjusted),' ',(number (first,last)sum_range strokes),' ',nettext,' ',number points
)
player_statistics=:3:0
  person=.y
  categories=.7#0
  sums=.3#0
  counts=.3#0
  completecount=.0
  completetotal=.0
  best=.NONE
  for_index. person pget 3 do.
    course=.index rget 0
    pars=.course cget 1
    scores=.index rget 3
    full=.1
    total=.0
    for_hole. i.18 do.
      score=.hole{scores
      if. score<:0 do.
        full=.0
        if. score=0 do. categories=.(1+6{categories)6}categories end.
      else.
        difference=.score-hole{pars
        if. difference<:_2 do. category=.0
        elseif. difference=_1 do. category=.1
        elseif. difference=0 do. category=.2
        elseif. difference=1 do. category=.3
        elseif. difference=2 do. category=.4
        else. category=.5 end.
        categories=.(1+category{categories)category}categories
        par=.(hole{pars)-3
        sums=.(score+par{sums)par}sums
        counts=.(1+par{counts)par}counts
        total=.total+score
      end.
    end.
    if. full do.
      completecount=.completecount+1
      completetotal=.completetotal+total
      best=.best<.total
    end.
  end.
  besttext=.'-'
  average=.'-'
  if. completecount>0 do.
    besttext=.number best
    average=.hundredths (100*completetotal)floor_ratio completecount
  end.
  text=.'stats ',(person pget 0),': rounds ',(number #person pget 3),' best ',besttext,' average ',average
  names=.;:'eagles birdies pars bogeys doubles others pickups'
  for_k. i.7 do. text=.text,' ',(k{::names),' ',number k{categories end.
  for_k. i.3 do.
    average=.'-'
    if. 0<k{counts do. average=.hundredths (100*k{sums)floor_ratio k{counts end.
    text=.text,' par',(number k+3),' ',average
  end.
  emit text
)
hole_statistics=:3:0
  course=.y
  pars=.course cget 1
  si=.course cget 2
  considered=.0
  sums=.18#0
  counts=.18#0
  for_person. i.#P do.
    for_index. person pget 3 do.
      if. course=index rget 0 do.
        considered=.considered+1
        scores=.index rget 3
        for_hole. i.18 do.
          score=.hole{scores
          if. score>0 do.
            sums=.(score+hole{sums)hole}sums
            counts=.(1+hole{counts)hole}counts
          end.
        end.
      end.
    end.
  end.
  played=.counts>0
  holes=.I.played
  relative=.18$0x
  values=.((x:holes{sums)%x:holes{counts)-holes{pars
  relative=.values holes}relative
  order=./:(-.played),.-relative
  ranks=.(1+i.18)order}18#0
  emit 'holestats ',(course cget 0),': rounds ',number considered
  for_hole. i.18 do.
    average=.'-'
    if. 0<hole{counts do. average=.hundredths (100*hole{sums)floor_ratio hole{counts end.
    emit (number hole+1),' par ',(number hole{pars),' si ',(number hole{si),' scores ',(number hole{counts),' avg ',average,' rank ',number hole{ranks
  end.
)
merit=:3:0
  count=.#P
  points=.count#0
  wins=.count#0
  appearances=.count#0
  counted=.0
  awards=.10 8 6 5 4 3 2 1
  for_event. i.#E do.
    if. -.(<event eget 1)e.;:'STROKE STABLEFORD PAR' do. continue. end.
    result=.evaluate event
    if. #0{::result do. continue. end.
    counted=.counted+1
    people=.event eget 6
    for_person. people do. appearances=.(1+person{appearances)person}appearances end.
    order=.(event,0)individual_ranking result
    for_k. i.#order do.
      person=.(k{order){people
      points=.((k{awards)+person{points)person}points
      if. k=0 do. wins=.(1+person{wins)person}wins end.
    end.
  end.
  entries=.0$a:
  for_k. i.count do.
    if. 0<k{appearances do.
      keys=.(-k{points),-k{wins
      entries=.entries,<(<k),(<keys),<k pget 0
    end.
  end.
  emit 'merit: events ',number counted
  order=.ranked entries
  for_k. i.#order do.
    person=.k{order
    emit (number k+1),' ',(person pget 0),' ',(number person{points),' wins ',(number person{wins),' played ',number person{appearances
  end.
)
command=:3:0
  words=.' 'split y
  action=.0{::words
  if. 'COURSE'text_equal action do.
    if. 0<:course_id 1{::words do. fail 'duplicate course' return. end.
    pars=.integer_value&>18{.2}.words
    si=.integer_value&>18{.20}.words
    if. (-.*./pars e.3 4 5)+.-.((/:~si)-:1+i.18) do. fail 'invalid course' return. end.
    rec=.(<1{::words),(<pars),(<si),<+/pars
    C=:C,<rec
    return.
  end.
  if. (<action)e.;:'TEE HCPTABLE HOLESTATS' do.
    course=.course_id 1{::words
    if. course<0 do. fail 'unknown course' return. end.
    if. 'HOLESTATS'text_equal action do. hole_statistics course return. end.
    tee=.course tee_id 2{::words
    if. 'TEE'text_equal action do.
      if. tee>:0 do. fail 'duplicate tee' return. end.
      rating=.integer_value 3{::words
      slope=.integer_value 4{::words
      if. (rating<500)+.(rating>900)+.(slope<55)+.slope>155 do. fail 'invalid tee' return. end.
      rec=.(<course),(<2{::words),(<rating),<slope
      T=:T,<rec
    else.
      if. tee<0 do. fail 'unknown tee' return. end.
      first=.integer_value 3{::words
      last=.integer_value 4{::words
      if. (first<_100)+.(first>last)+.last>540 do. fail 'invalid index' return. end.
      emit 'hcptable ',(1{::words),' ',(2{::words),': ',(index_text first),' to ',index_text last
      start=.first
      handicap=.course_handicap course,tee,first
      for_value. (first+1)+i.1+last-first do.
        if. value<:last do. next=.course_handicap course,tee,value else. next=.handicap+1 end.
        if. next~:handicap do.
          emit (index_text start),' to ',(index_text value-1),': ',handicap_text handicap
          start=.value
          handicap=.next
        end.
      end.
    end.
    return.
  end.
  if. 'PLAYER'text_equal action do.
    if. 0<:player_id 1{::words do. fail 'duplicate player' return. end.
    index=.NONE
    if. 4=#words do. index=.integer_value 3{::words end.
    if. (index~:NONE)*.((index<_100)+.index>540) do. fail 'invalid index' return. end.
    last=.0 0 0,NONE,0 0 0
    rec=.(<1{::words),(<2{::words),(<index),(<i.0),(<i.0),(<i.0),<last
    P=:P,<rec
    return.
  end.
  if. 'EVENT'text_equal action do.
    if. 0<:event_id 1{::words do. fail 'duplicate event' return. end.
    course=.course_id 3{::words
    if. course<0 do. fail 'unknown course' return. end.
    tee=.course tee_id 4{::words
    if. tee<0 do. fail 'unknown tee' return. end.
    allowance=.integer_value 6{::words
    if. (allowance<1)+.allowance>100 do. fail 'invalid allowance' return. end.
    people=.i.0
    duplicate=.0
    for_k. 7+i.(#words)-7 do.
      person=.player_id k{::words
      if. person<0 do. fail 'unknown player' return. end.
      if. person e.people do. duplicate=.1 end.
      people=.people,person
    end.
    count=.#people
    format=.2{::words
    if. (<format)e.;:'MATCH NASSAU' do. valid=.count=2
    elseif. 'FOURBALL'text_equal format do. valid=.count=4
    elseif. 'BETTERBALL'text_equal format do. valid=.count e.4 6 8
    else. valid=.(count>:2)*.count<:8 end.
    if. duplicate+.-.valid do. fail 'invalid players' return. end.
    rec=.(<1{::words),(<format),(<course),(<tee),(<integer_value 5{::words),(<allowance),<people
    E=:E,<rec
    return.
  end.
  if. 'RESULTS'text_equal action do.
    event=.event_id 1{::words
    if. event<0 do. fail 'unknown event' return. end.
    result=.evaluate event
    reason=.0{::result
    if. #reason do. fail reason else. event event_results result end.
    return.
  end.
  if. 'MERIT'text_equal action do. merit'' return. end.
  if. 'PLAYERS'text_equal action do.
    entries=.0$a:
    for_k. i.#P do. entries=.entries,<(<k),(<,k pget 2),<k pget 0 end.
    emit 'players ',number #P
    for_person. ranked entries do.
      emit (person pget 0),' ',(person pget 1),' ',(index_text person pget 2),' rounds ',number #person pget 3
    end.
    return.
  end.
  person=.player_id 1{::words
  if. person<0 do. fail 'unknown player' return. end.
  id=.person pget 0
  ids=.person pget 3
  count=.#ids
  if. (<action)e.;:'ROUND COURSEHCP' do.
    course=.course_id 2{::words
    if. course<0 do. fail 'unknown course' return. end.
    tee=.course tee_id 3{::words
    if. tee<0 do. fail 'unknown tee' return. end.
    index=.person pget 2
    if. 'COURSEHCP'text_equal action do.
      if. index=NONE do. fail 'no index' return. end.
      handicap=.course_handicap course,tee,index
      emit 'coursehcp ',id,' ',(2{::words),' ',(3{::words),': ',(handicap_text handicap),' strokes ',integer_list course allocation handicap
      return.
    end.
    day=.integer_value 4{::words
    if. count>0 do. if. day<({:ids)rget 2 do. fail 'invalid day' return. end. end.
    scores=.i.0
    for_hole. i.18 do.
      text=.(hole+5){::words
      if. 'X'text_equal text do. score=.0
      elseif. '-'text_equal text do. score=._1
      else. score=.integer_value text end.
      scores=.scores,score
    end.
    if. (+/scores=_1)>:5 do. fail 'too few holes' return. end.
    handicap=.NONE
    strokes=.18#0
    if. index~:NONE do.
      handicap=.course_handicap course,tee,index
      strokes=.course allocation handicap
    end.
    adjusted=.18#0
    pars=.course cget 1
    for_hole. i.18 do.
      par=.hole{pars
      limit=.par+5
      if. index~:NONE do. limit=.par+2+hole{strokes end.
      score=.hole{scores
      if. score>0 do. value=.score<.limit
      elseif. score=0 do. value=.limit
      else. value=.par+hole{strokes end.
      adjusted=.value hole}adjusted
    end.
    ags=.+/adjusted
    differential=.(113*((10*ags)-tee tget 2))half_away tee tget 3
    exceptional=.0
    if. index~:NONE do.
      if. (index-differential)>:100 do. exceptional=.20
      elseif. (index-differential)>:70 do. exceptional=.10 end.
    end.
    priorrecords=.#person pget 4
    rec=.(<course),(<tee),(<day),(<scores),(<handicap),(<adjusted),(<ags),(<differential),(<exceptional),(<index),(<priorrecords),<person pget 6
    roundindex=.NR
    R=:(<rec)roundindex}R
    NR=:NR+1
    (person,3)pset ids,roundindex
    person update_index day
    updated=.person pget 2
    if. updated~:NONE do.
      (person,4)pset (person pget 4),day
      (person,5)pset (person pget 5),updated
    end.
    text=.'round ',id,' ',(number count+1),': ags ',(number ags),' diff ','-'decimal_text differential
    if. exceptional>0 do. text=.text,' exceptional ','-'decimal_text -exceptional end.
    emit text,' index ',index_text updated
    return.
  end.
  select. action
  case. 'REMOVE' do.
    if. count=0 do. fail 'no rounds' return. end.
    roundindex=.{:ids
    oldindex=.roundindex rget 9
    oldrecords=.roundindex rget 10
    oldlast=.roundindex rget 11
    (person,3)pset }:ids
    (person,2)pset oldindex
    (person,4)pset oldrecords{.person pget 4
    (person,5)pset oldrecords{.person pget 5
    (person,6)pset oldlast
    emit 'removed ',id,' ',(number count),': index ',index_text oldindex
  case. 'INDEX' do.
    text=.'index ',id,': ',(index_text person pget 2),' rounds ',number count
    'k average adjustment low hard soft capped'=.person pget 6
    if. k>0 do.
      text=.text,' lowest ',(number k),' average ',('-'decimal_text average),' adjustment ','-'decimal_text adjustment
      if. low~:NONE do. text=.text,' low ',index_text low end.
      if. hard do. text=.text,' hard cap' elseif. soft do. text=.text,' soft cap' end.
      if. capped do. text=.text,' maximum' end.
    end.
    emit text
  case. 'LOWINDEX' do.
    day=.integer_value 2{::words
    'low date'=.person low_record day
    text=.'lowindex ',id,' ',(number day),': ',index_text low
    if. low~:NONE do. text=.text,' day ',number date end.
    emit text
  case. 'HISTORY' do.
    emit 'history ',id,': rounds ',number count
    adjusted=.adjusted_differentials person
    order=.counting_order adjusted
    used=.0
    if. (#adjusted)>:3 do. used=.{.count_rule #adjusted end.
    first=.0>.count-20
    for_k. i.#adjusted do.
      roundindex=.(first+k){ids
      'course tee day scores handicap values ags differential exceptional'=.9{.roundindex{::R
      text=.(number first+k+1),' day ',(number day),' ',(course cget 0),' ',(tee tget 1),' ags ',(number ags),' diff ','-'decimal_text differential
      value=.k{adjusted
      if. value~:differential do. text=.text,' adjusted ','-'decimal_text value end.
      if. k e.used{.order do. text=.text,' *' end.
      emit text
    end.
  case. 'STATS' do. player_statistics person
  case. 'CARD' do.
    copyno=.integer_value 2{::words
    if. copyno>count do. fail 'unknown round' return. end.
    roundindex=.(copyno-1){ids
    'course tee day scores handicap adjusted ags differential'=.8{.roundindex{::R
    pars=.course cget 1
    si=.course cget 2
    strokes=.18#0
    if. handicap~:NONE do. strokes=.course allocation handicap end.
    emit 'card ',id,' ',(number copyno),': ',(course cget 0),' ',(tee tget 1),' day ',(number day),' handicap ',handicap_text handicap
    for_hole. i.18 do.
      score=.hole{scores
      net=.'-'
      points=.0
      if. score>0 do.
        raw=.number score
        netvalue=.score-hole{strokes
        net=.number netvalue
        points=.0>.(hole{pars)+2-netvalue
      elseif. score=0 do. raw=.'X'
      else. raw=.'-' end.
      emit (number hole+1),' ',(number hole{pars),' ',(number hole{si),' ',raw,' ',(number hole{adjusted),' ',(number hole{strokes),' ',net,' ',number points
      if. hole=8 do. card_totals (<course),(<roundindex),(<strokes),(<'OUT'),(<0),<9 end.
      if. hole=17 do.
        card_totals (<course),(<roundindex),(<strokes),(<'IN'),(<9),<18
        card_totals (<course),(<roundindex),(<strokes),(<'TOTAL'),(<0),<18
      end.
    end.
    emit 'ags ',(number ags),' diff ','-'decimal_text differential
  end.
  EMPTY
)
main=:3:0
  C=:0$a:
  T=:0$a:
  P=:0$a:
  R=:1000$<i.0
  NR=:0
  E=:0$a:
  input=.1!:1(3)
  if. LF~:{:input do. input=.input,LF end.
  lines=.<;._2 input
  count=.integer_value 0{::lines
  for_k. i.count do. command (k+1){::lines end.
  EMPTY
)
main''
