ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'cluster.ijs'
load SourceDirectory,'minstd.ijs'
load SourceDirectory,'raft_node.ijs'
load SourceDirectory,'network.ijs'
load SourceDirectory,'checker.ijs'
str =: 3 : 0
 if. 2=3!:0 y do. y return. end.
 n =. <.|y
 text =. ''
 while. n>0 do.
  text =. ((10|n){'0123456789'),text
  n =. <.n%10
 end.
 if. 0=#text do. text =. '0' end.
 if. y<0 do. '-',text else. text end.
)
join =: 4 : 0
 s =. ''
 for_i. i.#y do. if. i do. s =. s,x end.
 s =. s,str i{::y end.
 s
)
emit =: 3 : ''' ''join y'
node =: 3 : 0
 if. y<0 do. '-' else. 'n',str y+1 end.
)
request =: 3 : '''r'',str y+1'
nodes =: 3 : 0
 if. #y do. ','join node&.>/:~~.y else. '-' end.
)
roles =: 'FOLLOWER';'CANDIDATE';'LEADER'
trace =: 3 : 0
 Trace =: Trace,<emit Now;y
 i.0 0
)
write =: 4 : 0
 (;(,&LF)&.>y)1!:2 <'output/',x
 i.0 0
)
end_leadership =: 4 : 0
 term =. x{Terms
 rec =. term{::LeaderRecords
 rec =. (<Now)3}rec
 rec =. (<y)4}rec
 rec =. (<x{Commit)6}rec
 LeaderRecords =: (<rec)term}LeaderRecords
 TransferTarget =: _1 x}TransferTarget
 i.0 0
)
start_election =: 4 : 0
 Terms =: (1+x{Terms)x}Terms
 Role =: 1 x}Role
 Voted =: x x}Voted
 Votes =: (<,x)x}Votes
 KnownLeader =: _1 x}KnownLeader
 set_timer x
 (x,0)stat_add 1
 rec =. Now;x;(x{Terms);y;(,x);_1
 LatestElection =: (#ElectionRecords)x}LatestElection
 ElectionRecords =: ElectionRecords,<rec
 trace emit 'ELECTION';(node x);'term';(x{Terms);'last';((str last_index x),'/',str last_term x);'deadline';x{Deadline
 for_j. (i.N)-.x do. send_message x;j;'RV';(last_index x),last_term x end.
 i.0 0
)
send_append =: 4 : 0
 prev =. _1+(<x,y){Next
 entries =. (prev+i.Batch<.(last_index x)-prev){x{::Logs
 send_message x;y;'AE';prev;(x entry_term prev);entries;x{Commit
)
send_timeout =: 4 : 0
 trace emit 'TIMEOUTNOW';(node x);(node y);'term';(x{Terms);'index';last_index x
 TransferSent =: 1 x}TransferSent
 send_message x;y;'TN';i.0
)
become_leader =: 3 : 0
 i =. y
 Role =: 2 i}Role
 KnownLeader =: i i}KnownLeader
 Next =: (N$1+last_index i)i}Next
 Matched =: (N$0)i}Matched
 i append_entry (i{Terms);'NOOP';0
 (i,1)stat_add 1
 ei =. i{LatestElection
 rec =. ei{::ElectionRecords
 rec =. (<Now)5}rec
 ElectionRecords =: (<rec)ei}ElectionRecords
 check_leader i
 term =. i{Terms
 while. term>:#LeaderRecords do. LeaderRecords =: LeaderRecords,<i.0 end.
 LeaderRecords =: (<i;Now;(i{::Votes);_1;'ACTIVE';1;(i{Commit))term}LeaderRecords
 trace emit 'LEADER';(node i);'term';term;'votes';(nodes i{::Votes);'noop';last_index i
 for_j. (i.N)-.i do. i send_append j end.
 HeartbeatDue =: (Now+H)i}HeartbeatDue
 QuorumDue =: (Now+Q)i}QuorumDue
 Heard =: (<i.0)i}Heard
 i.0 0
)
advance_commit =: 4 : 0
 i =. x
 upto =. y
 old =. i{Commit
 for_k. (old+1)+i.upto-old do.
  if. k>#CommittedTerms do.
   CommittedTerms =: CommittedTerms,i entry_term k
   CommittedTimes =: CommittedTimes,Now
  end.
 end.
 Commit =: upto i}Commit
 first =. 1+i{Applied
 for_k. first+i.1+upto-first do.
  entry =. (k-1){::i{::Logs
  'store result' =. (i{::Stores)apply_command 1{::entry
  Stores =: (<store)i}Stores
  (i,8)stat_add 1
  check_apply k;entry;result
 end.
 Applied =: upto i}Applied
 trace emit 'APPLY';(node i);(str first),'-',str upto
 i.0 0
)
commit_check =: 3 : 0
 i =. y
 for_k. |.(1+i{Commit)+i.(last_index i)-i{Commit do.
  if. (i entry_term k)~:i{Terms do. break. end.
  count =. 1++/((i.N)-.i){k<:i{Matched
  if. (2*count)>N do.
   trace emit 'COMMIT';(node i);((str 1+i{Commit),'-',str k);'term';i{Terms
   i advance_commit k
   break.
  end.
 end.
 i.0 0
)
process_message =: 3 : 0
 'arrival sequence src dest type term payload' =. y
 i =. dest
 if. term>i{Terms do.
  oldrole =. i{Role
  trace emit 'TERM';(node i);((str i{Terms),'->',str term);type;(node src);oldrole{::roles
  if. oldrole=2 do. i end_leadership 'STEPDOWN' end.
  Terms =: term i}Terms
  Voted =: _1 i}Voted
  KnownLeader =: _1 i}KnownLeader
  Role =: 0 i}Role
  if. oldrole=2 do. set_timer i end.
 end.
 select. type
 case. 'RV' do.
  'li lt' =. payload
  reason =. ''
  if. term<i{Terms do. reason =. 'term'
  elseif. -.(i{Voted)e._1,src do. reason =. 'voted'
  elseif. (lt<last_term i)+.((lt=last_term i)*.li<last_index i) do. reason =. 'log' end.
  granted =. 0=#reason
  if. granted do.
   Voted =: src i}Voted
   (i,2)stat_add 1
   set_timer i
   trace emit 'VOTE';(node i);(node src);'term';(i{Terms);'deadline';i{Deadline
  else. trace emit 'DENY';(node i);(node src);'term';(i{Terms);reason end.
  send_message i;src;'RVR';granted
 case. 'RVR' do.
  if. ((i{Role)=1)*.(term=i{Terms)*.payload do.
   vv =. /:~~.(i{::Votes),src
   Votes =: (<vv)i}Votes
   ei =. i{LatestElection
   rec =. ei{::ElectionRecords
   rec =. (<vv)4}rec
   ElectionRecords =: (<rec)ei}ElectionRecords
   if. (2*#vv)>N do. become_leader i end.
  end.
 case. 'AE' do.
  'prev prevterm entries leadercommit' =. payload
  if. term<i{Terms do. send_message i;src;'AER';0 0
  return. end.
  if. (i{Role)=1 do. Role =: 0 i}Role
  trace emit 'YIELD';(node i);'term';(i{Terms);node src end.
  KnownLeader =: src i}KnownLeader
  set_timer i
  fail =. prev>last_index i
  if. -.fail do. fail =. prevterm~:i entry_term prev end.
  if. fail do.
   (i,5)stat_add 1
   hint =. prev-1
   if. prev>last_index i do. hint =. last_index i end.
   send_message i;src;'AER';0,hint
  else.
   (i,4)stat_add 1
   for_j. i.#entries do.
    k =. prev+j+1
    entry =. j{::entries
    if. k<:last_index i do.
     if. (i entry_term k)~:0{::entry do.
      removed =. (last_index i)-k+1
      i check_truncation k
      (i,7)stat_add removed
      Logs =: (<(k-1){.i{::Logs)i}Logs
      trace emit 'TRUNCATE';(node i);'from';k;'removed';removed
     end.
    end.
    if. k>last_index i do. i append_entry entry
    (i,6)stat_add 1 end.
   end.
   m =. prev+#entries
   upto =. leadercommit<.m
   if. upto>i{Commit do. i advance_commit upto end.
   send_message i;src;'AER';1,m
  end.
 case. 'AER' do.
  if. ((i{Role)=2)*.term=i{Terms do.
   heard =. /:~~.(i{::Heard),src
   Heard =: (<heard)i}Heard
   'success m' =. payload
   if. success do.
    Matched =: (m>.(<i,src){Matched)(<i,src)}Matched
    Next =: ((m+1)>.(<i,src){Next)(<i,src)}Next
    commit_check i
    if. (src=i{TransferTarget)*.(-.i{TransferSent)*.((<i,src){Matched)=last_index i do. i send_timeout src
    elseif. ((<i,src){Next)<:last_index i do. i send_append src end.
   else.
    next =. (1+(<i,src){Matched)>.((_1+(<i,src){Next)<.m+1)
    Next =: next(<i,src)}Next
    trace emit 'BACKTRACK';(node i);(node src);'next';next
    i send_append src
   end.
  end.
 case. 'TN' do.
  if. (term=i{Terms)*.(i{Role)=0 do. i start_election 'transfer'
  else. trace emit 'IGNORE';(node i);'TN';(node src);'term';term end.
 end.
 i.0 0
)
transfer =: 3 : 0
 'a b' =. y
 if. (-.a{Up)+.((a{Role)~:2)+.((a{TransferTarget)>:_0)+.a=b do.
  trace emit 'TRANSFER';(node a);(node b);'ignored'
 else.
  trace emit 'TRANSFER';(node a);(node b);'start match';(str (<a,b){Matched),'/',str last_index a
  TransferTarget =: b a}TransferTarget
  TransferSent =: 0 a}TransferSent
  TransferDue =: (Now+Emin)a}TransferDue
  if. ((<a,b){Matched)=last_index a do. a send_timeout b else. a send_append b end.
 end.
 i.0 0
)
control =: 3 : 0
 'time kind args' =. y
 select. kind
 case. 'CRASH' do.
  i =. _1+num 0{::args
  trace emit 'CRASH';(node i);((i{Role){::roles);'term';i{Terms
  if. (i{Role)=2 do. i end_leadership 'CRASH' end.
  Up =: 0 i}Up
  reset_node i
 case. 'RESTART' do.
  i =. _1+num 0{::args
  Up =: 1 i}Up
  set_timer i
  trace emit 'RESTART';(node i);'term';(i{Terms);'length';(last_index i);'deadline';i{Deadline
 case. 'PARTITION' do.
  names =. 0$a:
  for_g. i.#args do.
   ns =. _1+num&><;._1 ',',g{::args
   Groups =: g ns}Groups
   names =. names,<nodes ns
  end.
  trace emit 'PARTITION';' 'join names
 case. 'HEAL' do. Groups =: N$0
 trace 'HEAL'
 case. 'TRANSFER' do. transfer _1+num&>args
 end.
 i.0 0
)
client_attempt =: 3 : 0
 q =. y
 'time initial command next dest attempts redirects status index term' =. q{::Requests
 attempts =. attempts+1
 i =. dest
 hops =. 0
 accepted =. 0
 while. 1 do.
  reason =. ''
  if. -.i{Up do. reason =. 'down'
  elseif. (i{Role)=2 do.
   if. (i{TransferTarget)>:_0 do. reason =. 'transfer'
   else.
    i append_entry (i{Terms);command;q+1
    index =. last_index i
    term =. i{Terms
    rec =. term{::LeaderRecords
    rec =. (<1+5{::rec)5}rec
    LeaderRecords =: (<rec)term}LeaderRecords
    trace emit 'ACCEPT';(request q);(node i);'index';index;'term';term
    status =. 1
    accepted =. 1
    break.
   end.
  elseif. ((i{KnownLeader)<0)+.hops=N-1 do. reason =. 'noleader'
  else.
   j =. i{KnownLeader
   trace emit 'REDIRECT';(request q);(node i);node j
   redirects =. redirects+1
   hops =. hops+1
   i =. j
   continue.
  end.
  break.
 end.
 if. -.accepted do.
  if. attempts<Attempts do.
   dest =. N|i+1
   next =. Now+Retry
   trace emit 'REJECT';(request q);(node i);reason;'retry';(node dest);'at';next
  else. status =. 2
  trace emit 'REJECT';(request q);(node i);reason;'giveup' end.
 end.
 Requests =: (<time;initial;command;next;dest;attempts;redirects;status;index;term)q}Requests
 i.0 0
)
timers =: 3 : 0
 i =. y
 if. (i{Role)=2 do.
  if. Now=i{QuorumDue do.
   heard =. i{::Heard
   if. (2*(1+#heard))<:N do.
    trace emit 'STEPDOWN';(node i);'term';(i{Terms);'heard';nodes heard
    i end_leadership 'QUORUM'
    Role =: 0 i}Role
    KnownLeader =: _1 i}KnownLeader
    set_timer i
    return.
   end.
   Heard =: (<i.0)i}Heard
   QuorumDue =: (Now+Q)i}QuorumDue
  end.
  if. ((i{TransferTarget)>:_0)*.Now=i{TransferDue do.
   trace emit 'TRANSFER';(node i);(node i{TransferTarget);'abort'
   TransferTarget =: _1 i}TransferTarget
  end.
  if. Now=i{HeartbeatDue do.
   for_j. (i.N)-.i do. i send_append j end.
   HeartbeatDue =: (Now+H)i}HeartbeatDue
  end.
 elseif. Now=i{Deadline do. i start_election 'timeout' end.
 i.0 0
)
state_lines =: 3 : 0
 'keys vals' =. y
 out =. 0$a:
 for_i. /:keys do. out =. out,<emit (i{::keys);i{vals end.
 out
)
network_line =: 4 : 0
 'sent delivered inflight partition rule loss down' =. y
 emit x;'sent';sent;'delivered';delivered;'inflight';inflight;'partition';partition;'rule';rule;'loss';loss;'down';down
)
final_reports =: 3 : 0
 kt =. >./Terms
 committed =. #CommittedTerms
 leaders =. +/0<#&>LeaderRecords
 leaderships =. +/1{"1 Stats
 leaderlines =. 0$a:
 for_rec. ElectionRecords do.
  'time i term trigger votes won' =. >rec
  outcome =. 'LOST'
  if. won>:0 do. outcome =. emit 'WON';won end.
  leaderlines =. leaderlines,<emit 'ELECTION';time;(node i);'term';term;'trigger';trigger;'votes';(#votes);outcome
 end.
 for_term. 1+i.kt do.
  candidates =. i.0
  start =. _
  for_rec. ElectionRecords do.
   'time i tr trigger votes won' =. >rec
   if. tr=term do. candidates =. candidates,i
   start =. start<.time end.
  end.
  hasleader =. 0
  if. term<#LeaderRecords do. hasleader =. 0<#term{::LeaderRecords end.
  if. hasleader do.
   'i elected votes ended reason appended ci' =. term{::LeaderRecords
   endtext =. '-'
   if. ended<0 do. ci =. i{Commit else. endtext =. str ended end.
   leaderlines =. leaderlines,<emit 'TERM';term;'LEADER';(node i);'elected';elected;'votes';(nodes votes);'ended';endtext;reason;'appended';appended;'commit';ci;'candidates';(nodes candidates);'started';start;'wait';elected-start
  else. leaderlines =. leaderlines,<emit 'TERM';term;'NONE candidates';nodes candidates end.
 end.
 for_i. i.N do. leaderlines =. leaderlines,<emit 'NODE';(node i);'elections';((<i,0){Stats);'leader_terms';((<i,1){Stats);'leader_ticks';((<i,3){Stats);'votes_granted';(<i,2){Stats end.
 leaderlines =. leaderlines,Timeline
 gaps =. 0 2$0
 i =. 0
 while. i<#LeaderPresent do.
  if. i{LeaderPresent do. i =. i+1
  continue. end.
  j =. i+1
  while. j<#LeaderPresent do. if. j{LeaderPresent do. break. end.
  j =. j+1 end.
  gaps =. gaps,i,j-1
  i =. j
 end.
 longest =. 0
 for_gap. gaps do.
  'a b' =. gap
  longest =. longest>.1+b-a
  leaderlines =. leaderlines,<emit 'GAP';((str a),'-',str b);'length';1+b-a
 end.
 leaderlines =. leaderlines,<emit 'SUMMARY terms';kt;'leaders';leaders;'elections';(#ElectionRecords);'leader_ticks';(+/LeaderPresent);'multi_ticks';MultiTicks;'ticks';(End+1);'gaps';(#gaps);'longest';longest
 loglines =. statelines =. 0$a:
 for_i. i.N do.
  status =. 'DOWN'
  if. i{Up do. status =. (i{Role){::roles end.
  loglines =. loglines,<emit 'NODE';(node i);status;'term';(i{Terms);'voted';(node i{Voted);'commit';(i{Commit);'applied';(i{Applied);'length';last_index i
  for_k. i.last_index i do.
   'term command rq' =. k{::i{::Logs
   text =. emit (k+1);term;command
   if. rq do. text =. text,' ',request rq-1 end.
   loglines =. loglines,<text
  end.
  store =. i{::Stores
  replay =. (state_lines store)-:state_lines reference_store i{Applied
  statelines =. statelines,<emit 'NODE';(node i);((i{Up){::'DOWN';'UP');'applied';(i{Applied);'keys';(#0{::store);'replay';replay{::'mismatch';'match'
  statelines =. statelines,state_lines store
 end.
 prefix =. <./#&>Logs
 for_k. i.prefix do.
  e =. k{::0{::Logs
  same =. 1
  for_i. 1+i.N-1 do. if. -.e-:k{::i{::Logs do. same =. 0
  break. end. end.
  if. -.same do. prefix =. k
  break. end.
 end.
 loglines =. loglines,<emit 'AGREE prefix';prefix;'committed';committed
 for_i. i.N do.
  common =. 0
  for_k. 1+i.committed<.last_index i do.
   if. (i entry_term k)~:(k-1){CommittedTerms do. break. end.
   common =. k
  end.
  loglines =. loglines,<emit 'DIFF';(node i);'common';common;'behind';(committed-common);'extra';((last_index i)-common);'ae_ok';((<i,4){Stats);'ae_fail';((<i,5){Stats);'appended';((<i,6){Stats);'truncated';((<i,7){Stats);'applies';(<i,8){Stats
 end.
 statuses =. i.0
 latencies =. i.0
 allkeys =. 0$a:
 requestkeys =. 0$a:
 for_q. i.#Requests do.
  'time initial command next dest attempts redirects status index term' =. q{::Requests
  key =. 1{::words command
  requestkeys =. requestkeys,<key
  allkeys =. ~.allkeys,<key
  code =. 4
  if. status=2 do. code =. 3
  field =. 'FAILED'
  elseif. status=0 do. field =. emit 'WAITING next';next
  else.
   if. index<:committed do. good =. term=(index-1){CommittedTerms else. good =. 0 end.
   if. good do.
    code =. 0
    latency =. ((index-1){CommittedTimes)-time
    latencies =. latencies,latency
    field =. emit 'COMMITTED index';index;'term';term;'latency';latency;'result';(index-1){::ApplyResults
   else.
    retained =. 0
    for_i. i.N do.
     if. index<:last_index i do. retained =. retained+.term=i entry_term index end.
    end.
    code =. retained{2 1
    field =. emit (retained{::'LOST';'UNCOMMITTED');'index';index;'term';term
   end.
  end.
  statuses =. statuses,code
  statelines =. statelines,<emit 'REQUEST';(request q);'at';time;(node initial);command;'attempts';attempts;'redirects';redirects;field
 end.
 'keys vals' =. reference_store committed
 for_key. /:~allkeys do.
  mask =. requestkeys=key
  index =. keys i.key
  final =. 'missing'
  if. index<#keys do. final =. str index{vals end.
  statelines =. statelines,<emit 'KEY';(>key);'requests';(+/mask);'committed';(+/mask*.statuses=0);'final';final
 end.
 statelines =. statelines,<emit 'REQUESTS total';(#Requests);'committed';(+/statuses=0);'uncommitted';(+/statuses=1);'lost';(+/statuses=2);'failed';(+/statuses=3);'waiting';+/statuses=4
 minlat =. maxlat =. 0
 if. #latencies do. minlat =. <./latencies
 maxlat =. >./latencies end.
 statelines =. statelines,<emit 'LATENCY count';(#latencies);'total';(+/latencies);'min';minlat;'max';maxlat
 safety =. 0$a:
 properties =. 'ELECTION_SAFETY';'LEADER_COMPLETENESS';'LOG_MATCHING';'STATE_MACHINE_SAFETY';'COMMITTED_KEPT'
 details =. (emit 'terms';kt;'leaders';(+/RecordedLeaders>:0);'elected';leaderships);(emit 'checks';leaderships;'committed';committed);(emit 'checks';(End+1);'pairs';((End+1)*N*(N-1))%2);(emit 'applies';(+/8{"1 Stats);'indices';#ApplyEntries);emit 'truncations';Truncations;'removed';RemovedEntries
 for_i. i.5 do. safety =. safety,<emit (i{::properties);((i{Violations)=0){::'FAIL';'OK';'violations';(i{Violations);i{::details end.
 for_msg. Queue do.
  'arrival seq a b type term payload' =. >msg
  (a;b;type)message_count 2
 end.
 safety =. safety,<'MESSAGES'network_line +/TypeStats
 for_i. i.5 do. safety =. safety,<('TYPE ',i{::MessageTypes)network_line i{TypeStats end.
 for_a. i.N do.
  for_b. (i.N)-.a do.
   counts =. (<a,b){LinkStats
   safety =. safety,<emit 'LINK';((node a),'->',node b);'delay';((<a,b){Delay);'loss';((<a,b){Loss);'sent';(0{counts);'delivered';(1{counts);'dropped';+/3}.counts
  end.
 end.
 safety =. safety,(<emit 'DRAWS';Draws),<emit 'RESULT';(+./Violations>0){::'SAFE';'UNSAFE'
 'trace.txt'write Trace
 'leaders.txt'write leaderlines
 'logs.txt'write loglines
 'state.txt'write statelines
 'safety.txt'write safety
 i.0 0
)
main =: 3 : 0
 read_cluster ''
 initialize_nodes ''
 read_network ''
 initialize_checks ''
 Trace =: Timeline =: ElectionRecords =: LeaderRecords =: 0$a:
 LeaderPresent =: i.0
 MultiTicks =: Draws =: 0
 Now =: 0
 for_i. i.N do. set_timer i
 trace emit 'START';(node i);'deadline';i{Deadline end.
 for_t. i.End+1 do.
  Now =: t
  for_c. Controls do. if. t=0{::>c do. control >c end. end.
  for_q. i.#Requests do.
   rec =. q{::Requests
   if. ((7{::rec)=0)*.t=3{::rec do. client_attempt q end.
  end.
  for_m. due_messages '' do.
   msg =. >m
   a =. 2{::msg
   b =. 3{::msg
   key =. a;b;4{::msg
   if. -.b{Up do. key message_count 6
   elseif. (a{Groups)~:b{Groups do. key message_count 3
   else. key message_count 1
   process_message msg end.
  end.
  for_i. I.Up do. timers i end.
  check_log_matching ''
  leaders =. I.Up*.Role=2
  for_i. leaders do. (i,3)stat_add 1 end.
  LeaderPresent =: LeaderPresent,0<#leaders
  MultiTicks =: MultiTicks+1<#leaders
  if. 0=Sample|Now do.
   fields =. 0$a:
   for_i. i.N do.
    ch =. 'D'
    if. i{Up do. ch =. (i{Role){'FCL' end.
    fields =. fields,<ch,str i{Terms
   end.
   Timeline =: Timeline,<emit 'TIMELINE';Now;' 'join fields
  end.
 end.
 1!:5 :: 0: <'output'
 final_reports ''
 i.0 0
)
main ''
