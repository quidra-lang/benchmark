initialize_checks =: 3 : 0
 Violations =: 5$0
 RecordedLeaders =: (End+2)$_1
 CommittedTerms =: CommittedTimes =: i.0
 ApplyEntries =: ApplyResults =: 0$a:
 Truncations =: RemovedEntries =: 0
 i.0 0
)
check_leader =: 3 : 0
 term =. y{Terms
 old =. term{RecordedLeaders
 if. old<0 do. RecordedLeaders =: y term}RecordedLeaders
 elseif. old~:y do. Violations =: (1+0{Violations)0}Violations end.
 broken =. (#CommittedTerms)>last_index y
 for_k. 1+i.(#CommittedTerms)<.last_index y do.
  if. (y entry_term k)~:(k-1){CommittedTerms do. broken =. 1 end.
 end.
 if. broken do. Violations =: (1+1{Violations)1}Violations end.
 i.0 0
)
check_truncation =: 4 : 0
 Truncations =: Truncations+1
 RemovedEntries =: RemovedEntries+1+(last_index x)-y
 for_k. y+i.1+(last_index x)-y do.
  if. k<:#CommittedTerms do.
   if. (x entry_term k)=(k-1){CommittedTerms do. Violations =: (1+4{Violations)4}Violations end.
  end.
 end.
 i.0 0
)
check_log_matching =: 3 : 0
 for_a. i.N do.
  for_b. (a+1)+i.(N-a)-1 do.
   l =. (last_index a)<.last_index b
   g =. 0
   for_k. 1+i.l do. if. (a entry_term k)=b entry_term k do. g =. k end. end.
   if. -. (g{.a{::Logs)-:g{.b{::Logs do. Violations =: (1+2{Violations)2}Violations end.
  end.
 end.
 i.0 0
)
check_apply =: 3 : 0
 'index entry result' =. y
 if. index>#ApplyEntries do.
  ApplyEntries =: ApplyEntries,<entry
  ApplyResults =: ApplyResults,<result
 elseif. -.entry-:(index-1){::ApplyEntries do. Violations =: (1+3{Violations)3}Violations end.
 i.0 0
)
reference_store =: 3 : 0
 store =. (0$a:);i.0
 for_e. y{.ApplyEntries do. store =. 0{::store apply_command 1{::>e end.
 store
)
