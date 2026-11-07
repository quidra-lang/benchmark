words =: 3 : '<;._1 '' '',y'
lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
num =: 3 : '0".''_''(I.y=''-'')}y'
read_cluster =: 3 : 0
 for_l. lines 'cluster.txt' do.
  f =. words >l
  vals =. num&>}.f
  select. 0{::f
  case. 'NODES' do. N =: {.vals
  case. 'ELECTION' do. 'Emin Emax' =: vals
  case. 'HEARTBEAT' do. H =: {.vals
  case. 'BATCH' do. Batch =: {.vals
  case. 'QUORUM' do. Q =: {.vals
  case. 'SEED' do. RNG =: {.vals
  case. 'END' do. End =: {.vals
  case. 'RETRY' do. Retry =: {.vals
  case. 'ATTEMPTS' do. Attempts =: {.vals
  case. 'SAMPLE' do. Sample =: {.vals
  end.
 end.
 Controls =: Requests =: 0$a:
 for_l. lines 'script.txt' do.
  f =. words >l
  time =. num 0{::f
  kind =. 1{::f
  if. kind-:'REQUEST' do.
   dest =. _1+num 2{::f
   command =. ' 'join 3}.f
   Requests =: Requests,<time;dest;command;time;dest;0;0;0;0;0
  else. Controls =: Controls,<time;kind;2}.f end.
 end.
 i.0 0
)
