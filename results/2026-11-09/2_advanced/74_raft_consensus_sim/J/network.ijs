MessageTypes =: 'RV';'RVR';'AE';'AER';'TN'
match_node =: 4 : '(x-:''*'')+.y=_1+num x'
read_network =: 3 : 0
 input =. lines 'network.txt'
 Delay =: (N,N)$num 1{::words 0{::input
 Loss =: (N,N)$0
 DropRules =: 0$a:
 for_l. }.input do.
  f =. words >l
  if. 'DROP'-:0{::f do. DropRules =: DropRules,<}.f
  continue. end.
  for_a. i.N do.
   for_b. (i.N)-.a do.
    if. ((1{::f)match_node a)*.(2{::f)match_node b do.
     v =. num 3{::f
     if. 'DELAY'-:0{::f do. Delay =: v(<a,b)}Delay else. Loss =: v(<a,b)}Loss end.
    end.
   end.
  end.
 end.
 Groups =: N$0
 PassCount =: (N,N)$0
 TypeStats =: 5 7$0
 LinkStats =: (N,N,7)$0
 Queue =: 0$a:
 Sequence =: 0
 i.0 0
)
message_count =: 4 : 0
 'a b type' =. x
 c =. MessageTypes i.<type
 TypeStats =: (1+(<c,y){TypeStats)(<c,y)}TypeStats
 LinkStats =: (1+(<a,b,y){LinkStats)(<a,b,y)}LinkStats
 i.0 0
)
send_message =: 3 : 0
 'a b type payload' =. y
 key =. a;b;type
 key message_count 0
 reason =. _1
 if. (a{Groups)~:b{Groups do. reason =. 3
 else.
  for_rule. DropRules do.
   'sa sb st t1 t2' =. >rule
   if. ((sa match_node a)*.(sb match_node b)*.((st-:'ALL')+.st-:type)*.(Now>:num t1)*.Now<:num t2) do. reason =. 4
   break. end.
  end.
  if. reason<0 do.
   count =. 1+(<a,b){PassCount
   PassCount =: count(<a,b)}PassCount
   period =. (<a,b){Loss
   if. period>0 do. if. 0=period|count do. reason =. 5 end. end.
  end.
 end.
 if. reason>:0 do. key message_count reason
 else.
  Queue =: Queue,< (Now+(<a,b){Delay);Sequence;a;b;type;(a{Terms);payload
  Sequence =: Sequence+1
 end.
 i.0 0
)
due_messages =: 3 : 0
 due =. 0$a:
 pending =. 0$a:
 keys =. 0 2$0
 for_m. Queue do.
  msg =. >m
  if. Now=0{::msg do. due =. due,<msg
  keys =. keys,(2{::msg),1{::msg
  else. pending =. pending,<msg end.
 end.
 Queue =: pending
 (/:keys){due
)
