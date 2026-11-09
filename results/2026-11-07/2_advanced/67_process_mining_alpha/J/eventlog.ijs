words =: 3 : '<;._1 '' '',y'
lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
num =: 3 : '0".''_''(I.y=''-'')}y'
parse_time =: 3 : 0
 m =. num 2{.5}.y
 d =. num 2{.8}.y
 h =. num 2{.11}.y
 minute =. num 2{.14}.y
 md =. 31 28 31 30 31 30 31 31 30 31 30 31
 if. (m<1)+.(m>12)+.(d<1)+.(h<0)+.(h>23)+.(minute<0)+.minute>59 do. _1 return. end.
 if. d>(m-1){md do. _1 return. end.
 minute+60*(h+24*((d-1)++/(m-1){.md))
)
median =: 3 : 0
 a =. /:~y
 n =. #a
 if. 2|n do. x:(<.n%2){a else. (x:+/((<.n%2)+_1 0){a)%2 end.
)
read_eventlog =: 3 : 0
 ParamNames =: ParamValues =: 0$a:
 for_l. lines 'params.txt' do.
  f =. words >l
  value =. 1{::f
  if. '/'e.value do. pair =. num&><;._1 '/',value
  value =. (x:{.pair)%x:{:pair
  else. value =. num value end.
  ParamNames =: ParamNames,{.f
  ParamValues =: ParamValues,<value
 end.
 Errors =: RawEvents =: 0$a:
 seen =. 0$a:
 input =. }.lines 'eventlog.csv'
 RawRows =: #input
 for_i. i.#input do.
  'cid act stamp resource' =. <;._1 ',',i{::input
  t =. parse_time stamp
  key =. cid;act;stamp
  if. t<0 do. Errors =: Errors,<emit 'ERROR line';((str i+2),':');'bad timestamp';stamp
  elseif. (<key)e.seen do. Errors =: Errors,<emit 'ERROR line';((str i+2),':');'duplicate event';cid;act;stamp
  else.
   seen =. seen,<key
   RawEvents =: RawEvents,<cid;act;stamp;resource;t;i+2
  end.
 end.
 CaseIds =: /:~~.0{&>RawEvents
 ActivityNames =: /:~~.1{&>RawEvents
 Resources =: /:~~.3{&>RawEvents
 AllNames =: /:~~.ActivityNames,ReferenceTransitionNames
 NA =: #AllNames
 ActivityIds =: AllNames i.ActivityNames
 Events =: 0 5$0
 Timestamps =: 0$a:
 for_e. RawEvents do.
  'cid act stamp resource time ln' =. >e
  Events =: Events,(CaseIds i.<cid),(AllNames i.<act),time,(Resources i.<resource),ln
  Timestamps =: Timestamps,<stamp
 end.
 Cases =: Traces =: 0$a:
 Durations =: Lengths =: i.0
 for_c. i.#CaseIds do.
  ids =. I.c=0{"1 Events
  ids =. (/:2 4{"1 ids{Events){ids
  Cases =: Cases,<ids
  trace =. 1{"1 ids{Events
  Traces =: Traces,<trace
  Durations =: Durations,((<({:ids),2){Events)-(<({.ids),2){Events
  Lengths =: Lengths,#ids
 end.
 C =: #Cases
 FullLog =: 0$a:
 for_trace. Traces do. FullLog =: FullLog,< (>trace);1 end.
 i.0 0
)
pn =: 3 : '(ParamNames i.<y){::ParamValues'
