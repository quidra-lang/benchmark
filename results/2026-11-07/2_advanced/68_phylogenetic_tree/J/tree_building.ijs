members =: 3 : 'I.1=2|<.y%2^i.N'
bitcount =: 3 : '#members y'
subset =: 4 : 'x=x(17 b.)y'
rooting =: 3 : 0
 'adj lengths leaves negatives' =. y
 root =. {.I.Outgroup{adj
 parent =. (#adj)$_1
 parent =. root root}parent
 order =. ,root
 i =. 0
 while. i<#order do.
  node =. i{order
  for_child. I.node{adj do.
   if. child=node{parent do. continue. end.
   parent =. node child}parent
   order =. order,child
  end.
  i =. i+1
 end.
 masks =. (#adj)$0
 for_node. |.order do.
  if. node e.leaves do. mask =. 2^node
  else.
   children =. (I.node{adj)-.node{parent
   mask =. +/children{masks
  end.
  masks =. mask node}masks
 end.
 ingroupmask =. +/2^leaves-.Outgroup
 masks =. ingroupmask root}masks
 root;parent;order;masks
)
branches =: 3 : 0
 'adj lengths leaves negatives' =. y
 'root parent order masks' =. rooting y
 out =. 0 3$0
 for_child. order-.root do.
  mask =. child{masks
  if. child=Outgroup do. mask =. root{masks end.
  out =. out,mask,(child{parent),child
 end.
 (/:0{"1 out){out
)
splits =: 3 : 0
 rows =. branches y
 rows =. rows#~(1{"1 rows)>:N
 rows =. rows#~(2{"1 rows)>:N
 /:~0{"1 rows
)
neighbor_joining =: 4 : 0
 leaves =. y
 cap =. 2*N
 d =. (cap,cap)$0.0
 d =. x(<(i.N);i.N)}d
 adj =. (cap,cap)$0
 lengths =. (cap,cap)$0.0
 active =. leaves
 next =. N
 while. 3<#active do.
  r =. #active
  totals =. cap$0.0
  for_i. active do.
   total =. 0.0
   for_j. active-.i do. total =. total+(<i,j){d end.
   totals =. total i}totals
  end.
  best =. _
  for_ai. i.r do.
   for_bi. (ai+1)+i.(r-ai)-1 do.
    i =. ai{active
    j =. bi{active
    q =. (((r-2)*((<i,j){d))-i{totals)-j{totals
    if. q<best do. best =. q
    chosen =. i,j end.
   end.
  end.
  'i j' =. chosen
  li =. (((<i,j){d)%2)+((i{totals)-j{totals)%(2*(r-2))
  lj =. ((<i,j){d)-li
  adj =. 1(<i,next)}adj
  adj =. 1(<next,i)}adj
  adj =. 1(<j,next)}adj
  adj =. 1(<next,j)}adj
  lengths =. li(<i,next)}lengths
  lengths =. li(<next,i)}lengths
  lengths =. lj(<j,next)}lengths
  lengths =. lj(<next,j)}lengths
  remaining =. active-.i,j
  for_k. remaining do.
   value =. (((<i,k){d)+((<j,k){d)-(<i,j){d)%2
   d =. value(<next,k)}d
   d =. value(<k,next)}d
  end.
  active =. remaining,next
  next =. next+1
 end.
 'a b c' =. active
 values =. ((((<a,b){d)+((<a,c){d)-(<b,c){d)%2),((((<a,b){d)+((<b,c){d)-(<a,c){d)%2),((((<a,c){d)+((<b,c){d)-(<a,b){d)%2)
 for_i. i.3 do.
  node =. i{active
  adj =. 1(<node,next)}adj
  adj =. 1(<next,node)}adj
  lengths =. (i{values)(<node,next)}lengths
  lengths =. (i{values)(<next,node)}lengths
 end.
 negatives =. <.(+/,adj*.lengths<0)%2
 lengths =. 0>.lengths
 adj;lengths;leaves;negatives
)
path_distances =: 4 : 0
 'adj lengths leaves negatives' =. x
 source =. y
 distances =. (#adj)$_1.0
 distances =. 0 source}distances
 counts =. (#adj)$_1
 counts =. 0 source}counts
 queue =. ,source
 i =. 0
 while. i<#queue do.
  u =. i{queue
  for_v. I.u{adj do.
   if. (v{counts)>:_0 do. continue. end.
   distances =. ((u{distances)+(<u,v){lengths)v}distances
   counts =. (1+u{counts)v}counts
   queue =. queue,v
  end.
  i =. i+1
 end.
 distances;counts
)
patristic =: 3 : 0
 matrix =. (N,N)$0.0
 for_i. 2{::y do.
  distances =. 0{::y path_distances i
  matrix =. (N{.distances)i}matrix
 end.
 matrix
)
consensus_tree =: 3 : 0
 'leaves clades' =. y
 cap =. 2*N
 root =. N
 adj =. (cap,cap)$0
 len =. (cap,cap)$0.0
 all =. +/2^leaves-.Outgroup
 for_i. i.#clades do.
  mask =. i{clades
  candidates =. I.(clades~:mask)*.(mask&subset)"0 clades
  parent =. root
  if. #candidates do.
   sizes =. bitcount"0 candidates{clades
   parent =. N+1+(sizes i.<./sizes){candidates
  end.
  child =. N+1+i
  adj =. 1(<parent,child)}adj
  adj =. 1(<child,parent)}adj
 end.
 for_leaf. leaves do.
  parent =. root
  if. leaf~:Outgroup do.
   candidates =. I.(2^leaf)&subset"0 clades
   if. #candidates do.
    counts =. bitcount"0 candidates{clades
    parent =. N+1+(counts i.<./counts){candidates
   end.
  end.
  adj =. 1(<parent,leaf)}adj
  adj =. 1(<leaf,parent)}adj
 end.
 adj;len;leaves;0
)
