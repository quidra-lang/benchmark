reset_node =: 3 : 0
 Role =: 0 y}Role
 Commit =: 0 y}Commit
 Applied =: 0 y}Applied
 KnownLeader =: _1 y}KnownLeader
 Votes =: (<i.0)y}Votes
 Deadline =: _1 y}Deadline
 Next =: (N$0)y}Next
 Matched =: (N$0)y}Matched
 HeartbeatDue =: _1 y}HeartbeatDue
 QuorumDue =: _1 y}QuorumDue
 Heard =: (<i.0)y}Heard
 TransferTarget =: _1 y}TransferTarget
 TransferSent =: 0 y}TransferSent
 TransferDue =: _1 y}TransferDue
 Stores =: (<((0$a:);i.0))y}Stores
 i.0 0
)
initialize_nodes =: 3 : 0
 Terms =: N$0
 Voted =: N$_1
 Logs =: N$<0$a:
 Up =: N$1
 Role =: Commit =: Applied =: TransferSent =: N$0
 KnownLeader =: Deadline =: HeartbeatDue =: QuorumDue =: TransferTarget =: TransferDue =: LatestElection =: N$_1
 Votes =: Heard =: N$<i.0
 Stores =: N$<((0$a:);i.0)
 Next =: Matched =: (N,N)$0
 Stats =: (N,9)$0
 i.0 0
)
last_index =: 3 : '#y{::Logs'
entry_term =: 4 : 0
 if. y=0 do. 0 else. 0{::(y-1){::x{::Logs end.
)
last_term =: 3 : 'y entry_term last_index y'
append_entry =: 4 : 0
 Logs =: (<(x{::Logs),<y)x}Logs
 i.0 0
)
apply_command =: 4 : 0
 'keys vals' =. x
 f =. words y
 op =. 0{::f
 if. op-:'NOOP' do. x;'' return. end.
 key =. 1{::f
 i =. keys i.<key
 exists =. i<#keys
 select. op
 case. 'SET' do.
  value =. num 2{::f
  if. exists do. vals =. value i}vals else. keys =. keys,<key
  vals =. vals,value end.
  result =. 'ok'
 case. 'ADD' do.
  value =. num 2{::f
  if. exists do. value =. value+i{vals
  vals =. value i}vals else. keys =. keys,<key
  vals =. vals,value end.
  result =. str value
 case. 'DEL' do.
  result =. exists{::'missing';'deleted'
  if. exists do. ids =. (i.#keys)-.i
  keys =. ids{keys
  vals =. ids{vals end.
 case. 'GET' do.
  result =. 'missing'
  if. exists do. result =. str i{vals end.
 end.
 (keys;vals);result
)
stat_add =: 4 : 0
 'node column' =. x
 Stats =: (y+(<node,column){Stats)(<node,column)}Stats
 i.0 0
)
