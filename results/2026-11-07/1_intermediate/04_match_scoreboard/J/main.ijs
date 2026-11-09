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
pair =: 3 : 0
  (number 0{y),'-',number 1{y
)
stat =: 4 : 0
  24+(16*x)+y
)
DLABEL =: 0$<''
DVALUE =: i.0
DDOUBLE =: i.0
initialize_darts =: 3 : 0
  for_group. i.3 do.
    for_n. 20-i.20 do.
      DLABEL =: DLABEL,< (group{'STD'),number n
      DVALUE =: DVALUE,n*group{1 3 2
      DDOUBLE =: DDOUBLE,group=2
    end.
  end.
  DLABEL =: DLABEL,'25';'BULL';'MISS'
  DVALUE =: DVALUE,25 50 0
  DDOUBLE =: DDOUBLE,0 1 0
  i.0 0
)
initialize_darts''
finishing_dart =: 3 : 0
  if. y=50 do. 61 return. end.
  if. (y>:2)*.(y<:40)*.0=2|y do. 60-y floor_ratio 2
  else. _1
  end.
)
checkout =: 4 : 0
  last =. finishing_dart x
  if. (last>:0)*.y>:1 do. ,last return. end.
  if. y>:2 do.
    for_first. i.62 do.
      last =. finishing_dart x-first{DVALUE
      if. last>:0 do. first,last return. end.
    end.
  end.
  if. y>:3 do.
    for_first. i.62 do.
      for_second. i.62 do.
        last =. finishing_dart (x-first{DVALUE)-second{DVALUE
        if. last>:0 do. first,second,last return. end.
      end.
    end.
  end.
  i.0
)
dart_names =: 3 : 0
  ' ' join y{DLABEL
)
V =: i.0
D =: i.0
CFG =: i.0
INIT =: i.0
SPORT =: 0
HEAD =: i.0
GAMES =: 0$<i.0
put =: 4 : 0
  if. y~:x{V do.
    D =: D,x,x{V
    V =: y x}V
  end.
  i.0 0
)
add =: 4 : 0
  x put y+x{V
)
tennis_mode =: 3 : 0
  target =. 1+(0{CFG) floor_ratio 2
  final =. ((4{V)=target-1)*.(5{V)=target-1
  if. final*.3=2{CFG do. 2 return. end.
  if. ((2{V)=6)*.(3{V)=6 do.
    if. -.final*.2=2{CFG do. 1 return. end.
  end.
  0
)
server =: 3 : 0
  if. SPORT=0 do.
    if. 0~:tennis_mode'' do. 2|(6{V)+2|(1+(0{V)+1{V) floor_ratio 2
    else. 6{V
    end.
  elseif. SPORT=1 do.
    rallies =. (0{V)+1{V
    changes =. rallies
    if. rallies<20 do. changes =. rallies floor_ratio 2 end.
    2|(3{CFG)+(9{V)+changes
  else. 6{V
  end.
)
finished_set =: 3 : 0
  base =. 68+4*9{V
  for_k. i.4 do. (base+k) put k{y end.
  9 add 1
)
normal_game_won =: 3 : 0
  ((y{V)>:4)*.((1=1{CFG)+.((y{V)-(1-y){V)>:2)
)
rally =: 3 : 0
  side =. y
  serving =. server''
  mode =. 0
  if. SPORT=0 do. mode =. tennis_mode'' end.
  if. (SPORT=0)*.mode=0 do.
    receiving =. 1-serving
    hypothetical =. 1+receiving{V
    opportunity =. (hypothetical>:4)*.((1=1{CFG)+.(hypothetical-serving{V)>:2)
    if. opportunity do.
      (receiving stat 7) add 1
      if. side=receiving do. (side stat 8) add 1 end.
    end.
  end.
  (side stat 0) add 1
  (serving stat 1) add 1
  if. serving=side do. (side stat 2) add 1 end.
  run =. 1
  if. side=10{V do. run =. 1+11{V end.
  10 put side
  11 put run
  (side stat 3) put run>.(side stat 3){V
  side add 1
  ended =. 0
  if. SPORT=0 do.
    if. mode=0 do.
      if. -.normal_game_won side do. return. end.
      (serving stat 5) add 1
      if. side=serving do. (side stat 4) add 1
      else. (side stat 6) add 1
      end.
      (2+side) add 1
      0 put 0
      1 put 0
      ended =. ((2+side){V)>:6
      ended =. ended*.(((2+side){V)-(3-side){V)>:2
      if. ended do. finished_set (2{V),(3{V),_1 0 end.
    else.
      final =. ((4{V)=(0{CFG) floor_ratio 2)*.(5{V)=(0{CFG) floor_ratio 2
      target =. 7
      if. (mode=2)+.final*.1=2{CFG do. target =. 10 end.
      if. ((side{V)<target)+.((side{V)-(1-side){V)<2 do. return. end.
      if. mode=2 do. finished_set (0{V),(1{V),_1 2
      else.
        (2+side) add 1
        finished_set (2{V),(3{V),((1-side){V),1
      end.
      ended =. 1
    end.
    12 add 1
    6 put 1-6{V
  elseif. SPORT=1 do.
    ended =. ((side{V)>:11)*.((side{V)-(1-side){V)>:2
  elseif. SPORT=2 do.
    6 put side
    ended =. ((side{V)>:30)+.((side{V)>:21)*.((side{V)-(1-side){V)>:2
  else.
    if. side~:6{V do.
      6 put side
      base =. 56+6*side
      first =. base{V
      for_k. i.5 do. (base+k) put (base+k+1){V end.
      (base+5) put first
    end.
    target =. 25
    if. 4=9{V do. target =. 15 end.
    ended =. ((side{V)>:target)*.((side{V)-(1-side){V)>:2
  end.
  if. -.ended do. return. end.
  if. SPORT~:0 do. finished_set (0{V),(1{V),_1 0 end.
  (4+side) add 1
  if. SPORT e.0 1 do. target =. 1+(0{CFG) floor_ratio 2
  elseif. SPORT=2 do. target =. 2
  else. target =. 3
  end.
  if. target=(4+side){V do.
    7 put 1
    8 put side
    return.
  end.
  for_k. i.4 do. k put 0 end.
  if. SPORT=3 do.
    6 put 2|(3{CFG)+9{V
    for_team. i.2 do.
      (team stat 9) put 0
      (team stat 10) put 0
      for_k. i.6 do. (56+(6*team)+k) put (<team,k){INIT end.
    end.
  end.
)
roll =: 3 : 0
  frame =. 17{V
  ball =. 18{V
  mark =. y
  if. (1=20{V)*.y=10 do. mark =. 10
  elseif. y=19{V do. mark =. 11
  end.
  (104+(3*frame)+ball) put y
  (137+(3*frame)+ball) put mark
  21 add 1
  standing =. (19{V)-y
  if. frame<9 do. frame_done =. ((ball=0)*.y=10)+.ball=1
  else.
    first =. 131{V
    frame_done =. (ball=2)+.(ball=1)*.(first~:10)*.(first+y)<10
  end.
  if. frame_done do.
    base =. 104+3*frame
    if. ((base{V)~:10)*.(ball>:1)*.((base{V)+(base+1){V)<10 do. 22 add 1 end.
    if. frame=9 do. 7 put 1
    else.
      17 put frame+1
      18 put 0
      19 put 10
      20 put 1
    end.
  else.
    18 put ball+1
    reset =. (frame=9)*.standing=0
    if. reset do.
      19 put 10
      20 put 1
    else.
      19 put standing
      20 put 0
    end.
  end.
)
bowling_scores =: 3 : 0
  rolls =. i.0
  starts =. i.0
  for_frame. i.10 do.
    starts =. starts,#rolls
    for_ball. i.3 do.
      pins =. (104+(3*frame)+ball){y
      if. pins>:0 do. rolls =. rolls,pins end.
    end.
  end.
  result =. 10$_1
  cumulative =. 0
  for_frame. i.10 do.
    base =. 104+3*frame
    first =. base{y
    second =. (base+1){y
    if. first<0 do. break. end.
    score =. _1
    if. frame=9 do.
      if. 7{y do. score =. first+(0>.second)+0>.(base+2){y end.
    elseif. first=10 do.
      if. (2+frame{starts)<#rolls do. score =. 10+ +/((1+frame{starts)+i.2){rolls end.
    elseif. second>:0 do.
      if. (first+second)<10 do. score =. first+second
      elseif. (2+frame{starts)<#rolls do. score =. 10+(2+frame{starts){rolls
      end.
    end.
    if. score>:0 do.
      cumulative =. cumulative+score
      result =. cumulative frame}result
    end.
  end.
  result
)
complete_turn =: 3 : 0
  scored =. 16{V
  (y stat 3) put scored>.(y stat 3){V
  if. scored>:100 do. (y stat 4) add 1 end.
  if. scored=180 do. (y stat 5) add 1 end.
)
next_turn =: 3 : 0
  6 put 1-6{V
  14 put 0
  16 put 0
  15 put (6{V){V
)
throw_dart =: 3 : 0
  side =. 6{V
  before =. side{V
  scored =. y{DVALUE
  remaining =. before-scored
  (side stat 0) add 1
  if. (before=50)+.(before<:40)*.0=2|before do. (side stat 6) add 1 end.
  if. (remaining<0)+.(remaining=1)+.(remaining=0)*.-.y{DDOUBLE do.
    (side stat 2) add 1
    (side stat 1) add -16{V
    side put 15{V
    next_turn''
    return.
  end.
  side put remaining
  (side stat 1) add scored
  (134+14{V) put y
  14 add 1
  16 add scored
  if. remaining=0 do.
    (side stat 7) add 1
    complete_turn side
    (2+side) add 1
    if. (5{CFG)=(2+side){V do.
      finished_set (2{V),(3{V),_1 0
      (4+side) add 1
      if. (0{CFG)=(4+side){V do.
        7 put 1
        8 put side
        return.
      end.
      2 put 0
      3 put 0
    end.
    13 add 1
    0 put 4{CFG
    1 put 4{CFG
    6 put 2|(3{CFG)+13{V
    14 put 0
    15 put 4{CFG
    16 put 0
  elseif. 3=14{V do.
    complete_turn side
    next_turn''
  end.
)
set_text =: 4 : 0
  'index reverse' =. y
  base =. 68+4*index
  result =. pair (base+reverse,1-reverse){x
  if. 2=(base+3){x do. '[',result,']' return. end.
  if. 1=(base+3){x do. result =. result,'(',(number (base+2){x),')' end.
  result
)
situation =: 3 : 0
  saved =. V
  saved_delta =. D
  before_server =. server''
  rally y
  result =. ''
  if. 7{V do. result =. 'match point'
  elseif. (9{V)>9{saved do.
    if. SPORT e.1 2 do. result =. 'game point' else. result =. 'set point' end.
  elseif. (SPORT=0)*.(12{V)>12{saved do.
    if. y=before_server do. result =. 'game point' else. result =. 'break point' end.
  end.
  V =: saved
  D =: saved_delta
  result
)
score_text =: 3 : 0
  'id sport names cfg initial values history' =. y
  result =. id,': '
  if. SPORT=4 do.
    result =. result,0{::names
    scores =. bowling_scores V
    for_frame. i.10 do.
      if. 0>(104+3*frame){V do. break. end.
      marks =. ''
      for_ball. i.3 do.
        mark =. (137+(3*frame)+ball){V
        if. mark>:0 do.
          if. mark=10 do. marks =. marks,'X'
          elseif. mark=11 do. marks =. marks,'/'
          elseif. mark=0 do. marks =. marks,'-'
          else. marks =. marks,number mark
          end.
        end.
      end.
      result =. result,' ',marks
      if. 0<:frame{scores do. result =. result,'(',(number frame{scores),')' end.
    end.
    result return.
  end.
  serving =. server''
  displays =. names
  if. 0=7{V do. displays =. (<(serving{::names),'*') serving}displays end.
  result =. result,(0{::displays),' vs ',1{::displays
  if. SPORT=5 do.
    result =. result,' sets ',(pair 4 5{V),' legs ',(pair 2 3{V),' score ',pair 0 1{V
    if. 0=7{V do.
      if. 0<14{V do. result =. result,' turn ',dart_names (14{V){.134}.V end.
      finish =. (serving{V) checkout 3-14{V
      if. #finish do. result =. result,' checkout ',dart_names finish end.
    end.
    result return.
  end.
  for_k. i.9{V do. result =. result,' ',V set_text k,0 end.
  if. 0=7{V do.
    if. SPORT=0 do.
      mode =. tennis_mode''
      if. mode=2 do. result =. result,' [',(pair 0 1{V),']'
      else.
        points =. pair 0 1{V
        if. mode=0 do.
          if. (0=1{CFG)*.(0{V)>:3 do.
            if. (1{V)>:3 do.
              if. (0{V)=1{V do. points =. '40-40'
              elseif. (0{V)>1{V do. points =. 'AD-40'
              else. points =. '40-AD'
              end.
            else. points =. '-' join (0 1{V){'0';'15';'30';'40'
            end.
          else. points =. '-' join (0 1{V){'0';'15';'30';'40'
          end.
        end.
        result =. result,' ',(pair 2 3{V),' ',points
      end.
    else.
      result =. result,' ',pair 0 1{V
      if. SPORT=3 do. result =. result,' server ',number (56+6*serving){V end.
    end.
    for_side. i.2 do.
      status =. situation side
      if. #status do. result =. result,' (',status,' ',(side{::names),')' end.
    end.
  end.
  result
)
stats_text =: 3 : 0
  'id sport names cfg initial values history' =. y
  output =. 0$<''
  if. SPORT=4 do.
    strikes =. +/10=137}.V
    spares =. +/11=137}.V
    saved =. V
    saved_delta =. D
    while. 0=7{V do. roll 19{V end.
    possible =. 9{bowling_scores V
    V =: saved
    D =: saved_delta
    <id,' ',(0{::names),': strikes ',(number strikes),' spares ',(number spares),' open ',(number 22{V),' max ',number possible return.
  end.
  for_side. i.2 do.
    base =. side stat 0
    result =. id,' ',(side{::names),': '
    if. SPORT=5 do.
      average =. 0
      if. 0<base{V do. average =. (300*(base+1){V) floor_ratio base{V end.
      cents =. number 100|average
      if. 10>100|average do. cents =. '0',cents end.
      result =. result,'darts ',(number base{V),' average ',(number average floor_ratio 100),'.',cents,' busts ',(number (base+2){V),' high ',(number (base+3){V),' tons ',(number (base+4){V),' 180s ',(number (base+5){V),' doubles ',(number (base+7){V),'/',number (base+6){V
    else.
      result =. result,'points ',(number base{V),' serve ',(number (base+2){V),'/',(number (base+1){V),' run ',number (base+3){V
      if. SPORT=0 do.
        result =. result,' holds ',(number (base+4){V),'/',(number (base+5){V),' breaks ',(number (base+6){V),' break points ',(number (base+8){V),'/',number (base+7){V
      elseif. SPORT=3 do.
        lineup =. (56+(6*side)+i.6){V
        result =. result,' subs ',(number (base+9){V),' timeouts ',(number (base+10){V),' lineup ',',' join number&.><"0 lineup
      end.
    end.
    output =. output,<result
  end.
  output
)
event =: 4 : 0
  if. 7{V do. 'ERROR match over' return. end.
  D =: i.0
  if. x text_equal 'POINT' do.
    rally 'B' text_equal 0{::y
  elseif. x text_equal 'ROLL' do.
    pins =. 0".0{::y
    if. pins>19{V do. 'ERROR too many pins' return. end.
    roll pins
  elseif. x text_equal 'THROW' do.
    dart =. DLABEL i.0{y
    if. dart=#DLABEL do. 'ERROR invalid dart' return. end.
    throw_dart dart
  else.
    side =. 'B' text_equal 0{::y
    if. x text_equal 'TIMEOUT' do.
      if. 2<:(side stat 10){V do. 'ERROR no timeouts left' return. end.
      (side stat 10) add 1
    else.
      outgoing =. 0".1{::y
      incoming =. 0".2{::y
      lineup =. (56+(6*side)+i.6){V
      position =. lineup i.outgoing
      if. position=6 do. 'ERROR player not on court' return. end.
      if. incoming e.lineup do. 'ERROR player already on court' return. end.
      if. 6<:(side stat 9){V do. 'ERROR no substitutions left' return. end.
      (56+(6*side)+position) put incoming
      (side stat 9) add 1
    end.
  end.
  HEAD =: (<D),<HEAD
  ''
)
store_match =: 3 : 0
  game =. y{::GAMES
  game =. (<V) 5}game
  game =. (<HEAD) 6}game
  GAMES =: (<game) y}GAMES
)
execute =: 3 : 0
  fields =. ' ' split y
  command =. 0{::fields
  if. command text_equal 'CHECKOUT' do.
    score =. 0".1{::fields
    finish =. score checkout 3
    answer =. 'none'
    if. #finish do. answer =. dart_names finish end.
    <'checkout ',(number score),': ',answer return.
  end.
  if. command text_equal 'STANDINGS' do.
    names =. 0$<''
    wins =. i.0
    losses =. i.0
    for_game. GAMES do.
      game =. >game
      values =. 5{::game
      if. (4=1{::game)+.0=7{values do. continue. end.
      for_side. i.2 do.
        name =. side{::2{::game
        k =. names i.<name
        if. k=#names do.
          names =. names,<name
          wins =. wins,0
          losses =. losses,0
        end.
        if. side=8{values do. wins =. (1+k{wins) k}wins
        else. losses =. (1+k{losses) k}losses
        end.
      end.
    end.
    ordered =. /:names
    keys =. (-wins),.losses
    ordered =. ordered {~ /:ordered{keys
    items =. 0$<''
    for_k. ordered do. items =. items,<(k{::names),' ',pair (k{wins),k{losses end.
    if. 0=#items do. <'standings: none' else. <'standings: ',', ' join items end. return.
  end.
  match_id =. _1
  for_k. i.#GAMES do.
    if. (1{::fields) text_equal 0{::k{::GAMES do. match_id =. k end.
  end.
  if. command text_equal 'MATCH' do.
    if. match_id>:0 do. <'ERROR duplicate match' return. end.
    sport =. (;:'TENNIS TABLETENNIS BADMINTON VOLLEYBALL BOWLING DARTS') i.2{fields
    if. sport=4 do. names =. ,3{fields
    else. names =. 3 4{fields
    end.
    cfg =. 3 0 0 0 501 1
    if. sport=1 do. cfg =. (5) 0}cfg
    elseif. sport=5 do. cfg =. (1) 0}cfg
    end.
    initial =. 2 6$0
    option_start =. 5
    if. sport=4 do. option_start =. 4
    elseif. sport=3 do.
      option_start =. 7
      for_side. i.2 do.
        lineup =. 0".&>',' split (5+side){::fields
        initial =. lineup side}initial
      end.
    end.
    used =. 0$<''
    for_k. option_start+i.(#fields)-option_start do.
      option =. '=' split k{::fields
      if. 2~:#option do. <'ERROR invalid option' return. end.
      'key value' =. option
      if. (<key)e.used do. <'ERROR invalid option' return. end.
      used =. used,<key
      if. (key text_equal 'FIRST')*.(sport~:4)*.(<value)e.' ' split 'A B' do.
        cfg =. ('B' text_equal value) 3}cfg
      elseif. (key text_equal 'SETS')*.(sport=0)*.(<value)e.' ' split '3 5' do. cfg =. (0".value) 0}cfg
      elseif. (key text_equal 'GAMES')*.(sport=1)*.(<value)e.' ' split '5 7' do. cfg =. (0".value) 0}cfg
      elseif. (key text_equal 'DEUCE')*.(sport=0)*.(<value)e.'AD';'NOAD' do. cfg =. ('NOAD' text_equal value) 1}cfg
      elseif. (key text_equal 'FINAL')*.(sport=0)*.(<value)e.;:'TB7 TB10 ADV SUPER' do. cfg =. ((;:'TB7 TB10 ADV SUPER') i.<value) 2}cfg
      elseif. (key text_equal 'START')*.(sport=5)*.(<value)e.;:'301 501 701' do. cfg =. (0".value) 4}cfg
      elseif. ((<key)e.'SETS';'LEGS')*.(sport=5)*.(<value)e.;:'1 2 3 4 5' do.
        slot =. 0
        if. key text_equal 'LEGS' do. slot =. 5 end.
        cfg =. (0".value) slot}cfg
      else. <'ERROR invalid option' return.
      end.
    end.
    values =. 167$0
    values =. (3{cfg) 6}values
    values =. (_1) 8 10}values
    values =. (10) 19}values
    values =. (1) 20}values
    values =. _1 (104+i.30)}values
    values =. _1 (137+i.30)}values
    if. sport=3 do. values =. (,initial) (56+i.12)}values
    elseif. sport=5 do. values =. (4{cfg) 0 1 15}values
    end.
    game =. (1{fields),(<sport),(<names),(<cfg),(<initial),(<values),<i.0
    GAMES =: GAMES,<game
    0$<'' return.
  end.
  if. match_id<0 do. <'ERROR unknown match' return. end.
  game =. match_id{::GAMES
  SPORT =: 1{::game
  CFG =: 3{::game
  INIT =: 4{::game
  V =: 5{::game
  HEAD =: 6{::game
  D =: i.0
  if. command text_equal 'UNDO' do.
    if. 0=#HEAD do. <'ERROR nothing to undo' return. end.
    delta =. 0{::HEAD
    for_p. |.2*i.(#delta) floor_ratio 2 do.
      V =: ((p+1){delta) (p{delta)}V
    end.
    HEAD =: 1{::HEAD
    store_match match_id
    0$<'' return.
  end.
  if. command text_equal 'SCORE' do. <score_text game return. end.
  if. command text_equal 'STATS' do. stats_text game return. end.
  if. command text_equal 'RESULT' do.
    if. 0=7{V do. <'ERROR match not finished' return. end.
    names =. 2{::game
    id =. 0{::game
    if. SPORT=4 do. <id,': ',(0{::names),' ',number 9{bowling_scores V return. end.
    winner =. 8{V
    result =. id,': ',(winner{::names),' def. ',(1-winner){::names
    for_k. i.9{V do. result =. result,' ',V set_text k,winner end.
    <result return.
  end.
  if. ((command text_equal 'POINT')*.SPORT>3)+.((command text_equal 'ROLL')*.SPORT~:4)+.((command text_equal 'THROW')*.SPORT~:5)+.(((<command)e.'SUB';'TIMEOUT')*.SPORT~:3) do.
    <'ERROR wrong event' return.
  end.
  problem =. ''
  if. command text_equal 'POINT' do.
    for_c. 2{::fields do.
      problem =. command event <,c
      if. #problem do. break. end.
    end.
  elseif. (<command)e.'ROLL';'THROW' do.
    for_k. 2+i.(#fields)-2 do.
      problem =. command event ,k{fields
      if. #problem do. break. end.
    end.
  else. problem =. command event 2}.fields
  end.
  store_match match_id
  if. #problem do. <problem else. 0$<'' end.
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
