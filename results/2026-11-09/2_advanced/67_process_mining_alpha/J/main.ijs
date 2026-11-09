ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'report.ijs'
load SourceDirectory,'eventlog.ijs'
load SourceDirectory,'dfg.ijs'
load SourceDirectory,'alpha_miner.ijs'
load SourceDirectory,'heuristic_miner.ijs'
load SourceDirectory,'conformance.ijs'
activity_list =: 3 : 'list y{AllNames'
net_report =: 3 : 0
 'places tids ins outs initial final' =. y
 out =. 0$a:
 for_p. i.#places do.
  before =. after =. i.0
  for_t. i.#tids do.
   if. p e.t{::outs do. before =. before,t{tids end.
   if. p e.t{::ins do. after =. after,t{tids end.
  end.
  out =. out,<emit 'PLACE';(p{::places);(activity_list before);activity_list after
 end.
 for_t. i.#tids do. out =. out,<emit 'TRANSITION';((t{tids){::AllNames);'in';(list (t{::ins){places);'out';list (t{::outs){places end.
 out,<emit 'NET places';(#places);'transitions';(#tids);'arcs';(+/#&>ins)++/#&>outs
)
heuristic_report =: 3 : 0
 f =. Follows
 tri =. triangles FullLog
 sigma =. pn 'positive_observations'
 l1 =. NA$0
 l2 =. (NA,NA)$0
 graph =. (NA,NA)$0
 out =. 0$a:
 for_a. ActivityIds do.
  n =. (<a,a){f
  if. n do.
   measure =. loop_measure n
   accepted =. (n>:sigma)*.measure>:pn 'loop1_threshold'
   l1 =. accepted a}l1
   graph =. accepted(<a,a)}graph
   out =. out,<emit 'L1';(a{::AllNames);'count';n;'measure';(frac measure);accepted{::'REJECT';'ACCEPT'
  end.
 end.
 for_a. ActivityIds do. for_b. ActivityIds#~ActivityIds>a do.
  if. (a{l1)+.b{l1 do. continue. end.
  n =. ((<a,b){tri)+(<b,a){tri
  if. n do.
   measure =. loop_measure n
   accepted =. (n>:sigma)*.measure>:pn 'loop2_threshold'
   l2 =. accepted(<a,b)}l2
   l2 =. accepted(<b,a)}l2
   out =. out,<emit 'L2';(a{::AllNames);(b{::AllNames);'count';n;'measure';(frac measure);accepted{::'REJECT';'ACCEPT'
  end.
 end. end.
 for_a. ActivityIds do. for_b. ActivityIds-.a do.
  n =. (<a,b){f
  if. n=0 do. continue. end.
  d =. f dependency a,b
  bout =. bin =. _
  for_c. ActivityIds-.a do. if. (<a,c){f do. bout =. bout>.f dependency a,c end. end.
  for_c. ActivityIds-.b do. if. (<c,b){f do. bin =. bin>.f dependency c,b end. end.
  if. (<a,b){l2 do. verdict =. 'LOOP2'
  elseif. n<sigma do. verdict =. 'REJECT_COUNT'
  elseif. d<pn 'dependency_threshold' do. verdict =. 'REJECT_MEASURE'
  elseif. ((bout-d)>pn 'relative_to_best')*.((bin-d)>pn 'relative_to_best') do. verdict =. 'REJECT_BEST'
  else. verdict =. 'ACCEPT' end.
  if. (<verdict)e.'LOOP2';'ACCEPT' do. graph =. 1(<a,b)}graph end.
  out =. out,<emit 'DEP';(a{::AllNames);(b{::AllNames);'count';n;'reverse';((<b,a){f);'measure';(frac d);verdict
 end. end.
 for_a. ActivityIds do. out =. out,<emit 'NODE';(a{::AllNames);'in';(activity_list I.a{"1 graph);'out';activity_list I.a{graph end.
 for_a. ActivityIds do.
  for_join. i.2 do.
   if. join do. ns =. (I.a{"1 graph)-.a else. ns =. (I.a{graph)-.a end.
   for_b. ns do. for_c. ns#~ns>b do.
    measure =. branch_measure f;a;b;c;join
    out =. out,<emit (join{::'SPLIT';'JOIN');(a{::AllNames);(b{::AllNames);(c{::AllNames);'measure';(frac measure);(measure>:pn 'and_threshold'){::'XOR';'AND'
   end. end.
  end.
 end.
 out,<emit 'GRAPH activities';(#ActivityIds);'edges';(+/,graph);'loops1';(+/l1);'loops2';(+/,l2)%2
)
resources_report =: 3 : 0
 nr =. #Resources
 hand =. handcases =. subcontract =. together =. (nr,nr)$0
 out =. 0$a:
 for_r. i.nr do.
  ids =. I.r=3{"1 Events
  acts =. 1{"1 ids{Events
  work =. 0$a:
  for_a. ActivityIds do. count =. +/acts=a
  if. count do. work =. work,<(a{::AllNames),'=',str count end. end.
  out =. out,<emit 'RESOURCE';(r+1);(r{::Resources);'events';(#ids);'cases';(#~.0{"1 ids{Events);'work';list work
 end.
 for_ids. Cases do.
  ids =. >ids
  rs =. 3{"1 ids{Events
  seen =. 0 2$0
  for_i. i.(#rs)-1 do.
   key =. (i{rs),(i+1){rs
   hand =. (1+(<key){hand)(<key)}hand
   seen =. seen,key
  end.
  for_key. ~.seen do. handcases =. (1+(<key){handcases)(<key)}handcases end.
  for_i. i.0>.(#rs)-2 do.
   a =. i{rs
   b =. (i+1){rs
   if. (a~:b)*.a=(i+2){rs do. subcontract =. (1+(<a,b){subcontract)(<a,b)}subcontract end.
  end.
  unique =. /:~~.rs
  for_a. unique do. for_b. unique#~unique>a do. together =. (1+(<a,b){together)(<a,b)}together end. end.
 end.
 for_kind. i.3 do.
  select. kind
  case. 0 do. matrix =. hand
  name =. 'HANDOVER'
  case. 1 do. matrix =. subcontract
  name =. 'SUBCONTRACT'
  case. 2 do. matrix =. together
  name =. 'TOGETHER'
  end.
  rows =. 0 3$0
  for_a. i.nr do. for_b. i.nr do.
   count =. (<a,b){matrix
   if. count*.a~:b do. rows =. rows,(-count),a,b end.
  end. end.
  for_row. (/:rows){rows do.
   'negative a b' =. row
   if. kind=0 do. text =. emit name;(a{::Resources);(b{::Resources);'count';(-negative);'cases';(<a,b){handcases
   elseif. kind=1 do. text =. emit name;(a{::Resources);(b{::Resources);'count';-negative
   else. text =. emit name;(a{::Resources);(b{::Resources);'cases';-negative end.
   out =. out,<text
  end.
  if. kind=0 do. out =. out,5 table <"0 hand end.
 end.
 self =. +/(<"1(i.nr),.i.nr){hand
 out,<emit 'TOTAL handovers';(+/,hand);'self';self;'other';(+/,hand)-self
)
main =: 3 : 0
 read_reference ''
 read_eventlog ''
 reference =. reference_net ''
 Follows =: follows FullLog
 Rel =: relation Follows
 variants =. ~.Traces
 groups =. 0$a:
 keys =. 0$a:
 for_trace. variants do.
  ids =. I.Traces=trace
  groups =. groups,<ids
  keys =. keys,<(-#ids);>trace
 end.
 order =. /:keys
 variants =. order{variants
 groups =. order{groups
 VariantOf =. C$0
 keepvariant =. (#variants)$0
 Filtered =. 0$a:
 keptcases =. keptevents =. 0
 for_i. i.#variants do.
  ids =. i{::groups
  VariantOf =. (i+1)ids}VariantOf
  trace =. i{::variants
  keep =. 1
  for_j. i.(#trace)-1 do. if. ((<(j{trace),(j+1){trace){Follows)<pn 'filter_min_follows' do. keep =. 0 end. end.
  keepvariant =. keep i}keepvariant
  if. keep do. Filtered =. Filtered,<trace;#ids
  keptcases =. keptcases+#ids
  keptevents =. keptevents+(#ids)*#trace end.
 end.
 tids =. i.0
 for_item. Filtered do. tids =. tids,0{::>item end.
 tids =. /:~~.tids
 wf =. follows Filtered
 loops =. tids#~0<(<"1 tids,.tids){wf
 alpharesult =. discover Filtered;tids;0
 alphanet =. 0{::alpharesult
 reducedlog =. 0$a:
 for_item. Filtered do. 'trace weight' =. >item
 reducedlog =. reducedlog,<(trace-.loops);weight end.
 plustids =. tids-.loops
 plusresult =. discover reducedlog;plustids;1
 plusbase =. 0{::plusresult
 'places pts pins pouts initial final' =. plusbase
 plusins =. plusouts =. (#tids)$<i.0
 loopplaces =. (#loops)$_1
 for_i. i.#tids do.
  t =. i{tids
  j =. pts i.t
  if. j<#pts do. plusins =. (<j{::pins)i}plusins
  plusouts =. (<j{::pouts)i}plusouts
  else.
   pre =. plustids#~0<(<plustids;t){wf
   post =. plustids#~0<(<t;plustids){wf
   for_k. i.#1{::plusresult do.
    pair =. k{::1{::plusresult
    if. (pre-:0{::pair)*.post-:1{::pair do.
     plusins =. (<,k+1)i}plusins
     plusouts =. (<,k+1)i}plusouts
     loopplaces =. (k+1)(loops i.t)}loopplaces
     break.
    end.
   end.
  end.
 end.
 plusnet =. places;tids;plusins;plusouts;initial;final
 nets =. reference;alphanet;plusnet
 netnames =. 'reference';'alpha';'alpha_plus'
 replays =. replayscores =. reach =. precisions =. 0$a:
 for_net. nets do.
  net =. >net
  replays =. replays,<replay net
  reach =. reach,<reachability net
  precisions =. precisions,<precision net
 end.
 refreplay =. 0{::replays
 fits =. 1{::refreplay
 inputtimes =. 2{"1 Events
 first =. {. /:inputtimes
 last =. {. \:inputtimes
 summary =. Errors,<emit 'LOG rows';RawRows;'adopted';(#Events);'rejected';(#Errors);'cases';C;'activities';(#ActivityIds);'resources';(#Resources);'first';(first{::Timestamps);'last';last{::Timestamps
 starts =. ends =. (NA$0)
 waits =. NA$<i.0
 edgewaits =. (NA,NA)$<i.0
 edgecases =. (NA,NA)$0
 for_ids. Cases do.
  ids =. >ids
  trace =. 1{"1 ids{Events
  a =. {.trace
  b =. {:trace
  starts =. (1+a{starts)a}starts
  ends =. (1+b{ends)b}ends
  seen =. 0 2$0
  for_i. 1+i.(#ids)-1 do.
   act =. i{trace
   prev =. (i-1){trace
   wait =. ((<(i{ids),2){Events)-(<((i-1){ids),2){Events
   waits =. (<(act{::waits),wait)act}waits
   ew =. (<prev,act){::edgewaits
   edgewaits =. (<ew,wait)(<prev,act)}edgewaits
   seen =. seen,prev,act
  end.
  for_pair. ~.seen do. edgecases =. (1+(<pair){edgecases)(<pair)}edgecases end.
 end.
 for_a. ActivityIds do.
  ids =. I.a=1{"1 Events
  casecount =. rework =. 0
  for_trace. Traces do. count =. +/a=>trace
  casecount =. casecount+count>0
  rework =. rework+count>1 end.
  wait =. '-'
  if. #a{::waits do. wait =. frac mean a{::waits end.
  summary =. summary,<emit 'ACTIVITY';(a{::AllNames);'events';(#ids);'cases';casecount;'start';(a{starts);'end';(a{ends);'rework';rework;'wait';wait;'resources';(#~.3{"1 ids{Events);'model';(a e.1{::reference){::'no';'yes'
 end.
 for_pair. ('LENGTH';Lengths);('DURATION';Durations) do.
  'name values' =. >pair
  summary =. summary,<emit name;'min';(<./values);'max';(>./values);'mean';(frac mean values);'median';frac median values
 end.
 daycounts =. <.Durations%1440
 for_d. i.1+>./daycounts do. count =. +/daycounts=d
 summary =. summary,<emit 'DAYS';d;'cases';count;'share';count percent C end.
 late =. Durations>pn 'sla_minutes'
 summary =. summary,<emit 'SLA limit';(pn 'sla_minutes');'late';(+/late);'share';(+/late)percent C
 for_day. i.7 do.
  count =. +/day=7|3+<.(2{"1 Events)%1440
  firstcount =. lastcount =. 0
  for_ids. Cases do. ids =. >ids
  firstcount =. firstcount+day=7|3+<.((<({.ids),2){Events)%1440
  lastcount =. lastcount+day=7|3+<.((<({:ids),2){Events)%1440 end.
  summary =. summary,<emit 'WEEKDAY';(day{::'Mon';'Tue';'Wed';'Thu';'Fri';'Sat';'Sun');'events';count;'starts';firstcount;'ends';lastcount
 end.
 variantlines =. 0$a:
 for_i. i.#variants do.
  ids =. i{::groups
  trace =. i{::variants
  variantlines =. variantlines,<emit 'VARIANT';(i+1);'count';(#ids);'share';((#ids)percent C);'length';(#trace);'first';(({.ids){::CaseIds);'duration';(frac mean ids{Durations);'late';(+/ids{late);'fitness';(frac ({.ids){fits);((i{keepvariant){::'DROP';'KEEP');activity_list trace
 end.
 variantlines =. variantlines,<emit 'FILTER min_follows';(pn 'filter_min_follows');'variants';(+/keepvariant);'of';(#variants);'cases';keptcases;'of';C;'events';keptevents;'of';#Events
 dfg =. 0$a:
 for_ending. i.2 do.
  values =. starts
  if. ending do. values =. ends end.
  ids =. ActivityIds#~0<ActivityIds{values
  ids =. (\:ids{values){ids
  for_a. ids do.
   text =. emit (ending{::'START';'END');(a{::AllNames);'count';a{values
   if. ending do.
    ds =. i.0
    for_i. i.C do. if. a={:i{::Traces do. ds =. ds,i{Durations end. end.
    text =. text,' duration ',frac mean ds
   end.
   dfg =. dfg,<text
  end.
 end.
 edges =. 0 3$0
 for_a. ActivityIds do. for_b. ActivityIds do. count =. (<a,b){Follows
 if. count do. edges =. edges,(-count),a,b end. end. end.
 for_row. (/:edges){edges do.
  'negative a b' =. row
  ws =. (<a,b){::edgewaits
  dfg =. dfg,<emit 'EDGE';(a{::AllNames);(b{::AllNames);'count';(-negative);'cases';((<a,b){edgecases);'mean';(frac mean ws);'min';(<./ws);'max';>./ws
 end.
 dfg =. dfg,ActivityIds footprint Rel
 alphareport =. (<emit 'LOG variants';(+/keepvariant);'cases';keptcases;'activities';activity_list tids),(<emit 'LOOPS';activity_list loops),<'MINER alpha'
 alphareport =. alphareport,(tids footprint 4{::alpharesult),(<emit 'PAIRS causal';(3{::alpharesult);'candidates';(2{::alpharesult);'maximal';#1{::alpharesult),net_report alphanet
 alphareport =. alphareport,<'MINER alpha_plus'
 tr =. 5{::plusresult
 for_a. plustids do. for_b. plustids do. count =. (<a,b){tr
 if. count do. alphareport =. alphareport,<emit 'TRIANGLE';(a{::AllNames);(b{::AllNames);'count';count end. end. end.
 alphareport =. alphareport,(plustids footprint 4{::plusresult),<emit 'PAIRS causal';(3{::plusresult);'candidates';(2{::plusresult);'maximal';#1{::plusresult
 for_i. i.#loops do.
  t =. i{loops
  pre =. plustids#~0<(<plustids;t){wf
  post =. plustids#~0<(<t;plustids){wf
  place =. '-'
  if. (i{loopplaces)>:_0 do. place =. (i{loopplaces){::places end.
  alphareport =. alphareport,<emit 'LOOP';(t{::AllNames);'before';(activity_list pre);'after';(activity_list post);'place';place
 end.
 alphareport =. alphareport,net_report plusnet
 conformancecsv =. <'case_id,variant,events,skipped,missing,remaining,consumed,produced,fitness'
 for_i. i.C do.
  row =. i{0{::refreplay
  conformancecsv =. conformancecsv,<','join (i{::CaseIds);(str i{VariantOf);(str i{Lengths);(str 0{row);(str 1{row);(str 2{row);(str 3{row);(str 4{row);frac i{fits
 end.
 conform =. <emit 'MODEL places';(#0{::reference);'transitions';(#1{::reference);'arcs';#ReferenceArcs
 for_k. i.3 do.
  'markings edges unsafe deadlocks stuck final dead sound df' =. k{::reach
  conform =. conform,<emit 'REACHABILITY';(k{::netnames);'markings';markings;'edges';edges;'unsafe';unsafe;'deadlocks';deadlocks;'stuck';stuck;'final';(final{::'no';'yes');'dead';(activity_list dead);'sound';sound{::'no';'yes'
 end.
 for_k. i.3 do.
  net =. k{::nets
  union =. /:~~.ActivityIds,1{::net
  logrel =. (<union;union){Rel
  modelrel =. (<union;union){relation 8{::k{::reach
  diff =. logrel~:modelrel
  cells =. *:#union
  d =. +/,diff
  conform =. conform,<emit 'FOOTPRINT';(k{::netnames);'activities';(#union);'cells';cells;'differing';d;'fitness';(cells-d)ratio cells
  if. k=0 do.
   for_i. i.#union do. for_j. i+i.(#union)-i do.
    if. (<i,j){diff do. conform =. conform,<emit 'DIFF';((i{union){::AllNames);((j{union){::AllNames);'log';((<i,j){logrel){::RelationSymbols;'model';((<i,j){modelrel){::RelationSymbols end.
   end. end.
  end.
 end.
 for_k. i.3 do.
  'fitted allowed escaping value escapeweights' =. k{::precisions
  name =. k{::netnames
  conform =. conform,<emit 'PRECISION';name;'prefixes';fitted;'allowed';allowed;'escaping';escaping;'precision';frac value
  tids =. 1{::k{::nets
  ids =. I.escapeweights>0
  ids =. (\:ids{escapeweights){ids
  for_i. ids do. conform =. conform,<emit 'ESCAPE';name;((i{tids){::AllNames);'weight';i{escapeweights end.
 end.
 for_k. i.3 do.
  'places tids ins outs initial final' =. k{::nets
  'rows fit missing remaining deviating waits routes' =. k{::replays
  'skipped m r c p' =. +/rows
  fitting =. +/(0=1{"1 rows)*.0=2{"1 rows
  name =. k{::netnames
  conform =. conform,<emit 'REPLAY';name;'cases';C;'fitting';fitting;'skipped';skipped;'missing';m;'remaining';r;'consumed';c;'produced';p;'fitness';frac fitness m,r,c,p
  for_i. i.#places do.
   ws =. i{::waits
   me =. mx =. '-'
   if. #ws do. me =. frac mean ws
   mx =. str >./ws end.
   conform =. conform,<emit 'PLACE';name;(i{::places);'missing';(i{missing);'remaining';(i{remaining);'deviating';(i{deviating);'tokens';(#ws);'mean';me;'max';mx
  end.
  for_i. i.#places do.
   ts =. i.0
   for_t. i.#tids do. if. i e.t{::ins do. ts =. ts,t end. end.
   if. 1<#ts do.
    entries =. 0$a:
    for_t. ts do. entries =. entries,<((t{tids){::AllNames),'=',str (<i,t){routes end.
    conform =. conform,<emit 'ROUTE';name;(i{::places);list entries
   end.
  end.
 end.
 1!:5 :: 0: <'output'
 'log_summary.txt'write summary
 'variants.txt'write variantlines
 'dfg.txt'write dfg
 'alpha_net.txt'write alphareport
 'heuristic_net.txt'write heuristic_report ''
 'conformance.csv'write conformancecsv
 'conformance.txt'write conform
 'resources.txt'write resources_report ''
 i.0 0
)
main ''
