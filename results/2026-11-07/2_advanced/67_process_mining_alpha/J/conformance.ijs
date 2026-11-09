read_reference =: 3 : 0
 ReferencePlaces =: ReferenceTransitionNames =: 0$a:
 ReferenceArcs =: 0$a:
 for_l. lines 'model.txt' do.
  f =. words >l
  select. 0{::f
  case. 'PLACE' do. ReferencePlaces =: ReferencePlaces,1{f
  case. 'TRANSITION' do. ReferenceTransitionNames =: ReferenceTransitionNames,1{f
  case. 'ARC' do. ReferenceArcs =: ReferenceArcs,<1 2{f
  case. 'INITIAL' do. ReferenceInitial =: ReferencePlaces i.1{f
  case. 'FINAL' do. ReferenceFinal =: ReferencePlaces i.1{f
  end.
 end.
 i.0 0
)
reference_net =: 3 : 0
 trans =. /:~AllNames i.ReferenceTransitionNames
 ins =. outs =. 0$a:
 for_t. trans do.
  name =. t{::AllNames
  input =. output =. i.0
  for_arc. ReferenceArcs do.
   'a b' =. >arc
   if. b-:name do. input =. input,ReferencePlaces i.<a end.
   if. a-:name do. output =. output,ReferencePlaces i.<b end.
  end.
  ins =. ins,</:~input
  outs =. outs,</:~output
 end.
 ReferencePlaces;trans;ins;outs;ReferenceInitial;ReferenceFinal
)
enabled =: 4 : 0
 'places tids ins outs initial final' =. x
 answer =. i.0
 for_t. i.#tids do. if. *./0<(t{::ins){y do. answer =. answer,t end. end.
 answer
)
fire =: 3 : 0
 'net marking transition' =. y
 input =. transition{::2{::net
 output =. transition{::3{::net
 marking =. ((input{marking)-1)input}marking
 ((output{marking)+1)output}marking
)
fitness =: 3 : 0
 'missing remaining consumed produced' =. y
 1-((x:missing)%2*consumed)-((x:remaining)%2*produced)
)
reachability =: 3 : 0
 'places tids ins outs initial final' =. y
 marking =. (#places)$0
 marking =. 1 initial}marking
 target =. 1 final}(#places)$0
 markings =. ,:marking
 edges =. 0 3$0
 unsafe =. deadlocks =. 0
 live =. (#tids)$0
 df =. (NA,NA)$0
 head =. 0
 while. head<#markings do.
  marking =. head{markings
  active =. y enabled marking
  live =. 1 active}live
  if. (0=#active)*.-.marking-:target do. deadlocks =. deadlocks+1 end.
  for_t. active do.
   next =. fire y;marking;t
   if. +./next>1 do. unsafe =. unsafe+1
   continue. end.
   hits =. I.next-:"1 markings
   if. #hits do. j =. {.hits else. j =. #markings
   markings =. markings,next end.
   edges =. edges,head,t,j
   for_u. y enabled next do. df =. 1(<(t{tids),u{tids)}df end.
  end.
  head =. head+1
 end.
 reached =. I.target-:"1 markings
 good =. reached
 while. 1 do.
  before =. #good
  good =. ~.good,0{"1 edges#~(2{"1 edges)e.good
  if. before=#good do. break. end.
 end.
 dead =. (-.live)#tids
 stuck =. (#markings)-#good
 sound =. (unsafe=0)*.(stuck=0)*.0=#dead
 (#markings);(#edges);unsafe;deadlocks;stuck;(0<#reached);dead;sound;df
)
replay =: 3 : 0
 'places tids ins outs initial final' =. y
 np =. #places
 rows =. 0 5$0
 fit =. i.0x
 totalsmissing =. totalsremaining =. deviating =. np$0
 waits =. np$<i.0
 routes =. (np,#tids)$0
 for_ids. Cases do.
  ids =. >ids
  tokens =. np$<i.0
  tokens =. (<,(<({.ids),2){Events)initial}tokens
  missing =. np$0
  consumed =. 0
  produced =. 1
  skipped =. 0
  for_ei. ids do.
   'cid act time res line' =. ei{Events
   t =. tids i.act
   if. t=#tids do. skipped =. skipped+1
   continue. end.
   for_p. t{::ins do.
    consumed =. consumed+1
    held =. p{::tokens
    if. #held do.
     tokens =. (<}.held)p}tokens
     waits =. (<(p{::waits),time-{.held)p}waits
     routes =. (1+(<p,t){routes)(<p,t)}routes
    else. missing =. (1+p{missing)p}missing end.
   end.
   for_p. t{::outs do. tokens =. (<(p{::tokens),time)p}tokens
   produced =. produced+1 end.
  end.
  consumed =. consumed+1
  held =. final{::tokens
  if. #held do. tokens =. (<}.held)final}tokens
  else. missing =. (1+final{missing)final}missing end.
  remaining =. #&>tokens
  m =. +/missing
  r =. +/remaining
  rows =. rows,skipped,m,r,consumed,produced
  fit =. fit,fitness m,r,consumed,produced
  totalsmissing =. totalsmissing+missing
  totalsremaining =. totalsremaining+remaining
  deviating =. deviating+(missing>0)+.remaining>0
 end.
 rows;fit;totalsmissing;totalsremaining;deviating;waits;routes
)
precision =: 3 : 0
 'places tids ins outs initial final' =. y
 prefixes =. 0$a:
 for_trace. Traces do.
  trace =. >trace
  for_n. i.1+#trace do. prefixes =. prefixes,<n{.trace end.
 end.
 prefixes =. ~.prefixes
 allowed =. escaping =. fitted =. 0
 escapeweights =. (#tids)$0
 for_prefix. prefixes do.
  prefix =. >prefix
  weight =. 0
  followers =. i.0
  for_trace. Traces do.
   trace =. >trace
   if. prefix-:(#prefix){.trace do.
    weight =. weight+1
    if. (#trace)>#prefix do. followers =. followers,(#prefix){trace end.
   end.
  end.
  marking =. 1 initial}(#places)$0
  ok =. 1
  for_act. prefix do.
   t =. tids i.act
   if. (t=#tids)+.-.t e.y enabled marking do. ok =. 0
   break. end.
   marking =. fire y;marking;t
  end.
  if. -.ok do. continue. end.
  fitted =. fitted+1
  active =. y enabled marking
  escapes =. active#~-. (active{tids)e.followers
  allowed =. allowed+weight*#active
  escaping =. escaping+weight*#escapes
  escapeweights =. ((escapes{escapeweights)+weight)escapes}escapeweights
 end.
 value =. 1x
 if. allowed do. value =. 1-(x:escaping)%allowed end.
 fitted;allowed;escaping;value;escapeweights
)
