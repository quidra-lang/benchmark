merge =: 4 : 0
 intersection =. x(17 b.)y
 if. intersection do. intersection,0 else. (x(23 b.)y),1 end.
)
fitch_column =: 4 : 0
 'adj lengths leaves negatives' =. x
 'root parent order masks' =. rooting x
 sets =. (#adj)$0
 changes =. 0
 for_node. |.order do.
  if. node e.leaves do. sets =. ((<node,y){Sets)node}sets
  elseif. node~:root do.
   children =. (I.node{adj)-.node{parent
   'value delta' =. ((0{children){sets)merge (1{children){sets
   changes =. changes+delta
   sets =. value node}sets
  end.
 end.
 children =. (I.root{adj)-.Outgroup
 'value delta' =. ((0{children){sets)merge (1{children){sets
 sets =. value root}sets
 changes =. changes+delta
 'final delta' =. value merge Outgroup{sets
 (changes+delta);sets;final
)
fitch =: 3 : 0
 scores =. i.0
 for_c. i.L do. scores =. scores,0{::y fitch_column c end.
 scores
)
insert_taxon =: 3 : 0
 'tree edge taxon' =. y
 'adj lengths leaves negatives' =. tree
 'mask a b' =. edge
 used =. I.0<+/"1 adj
 node =. 1+>./(N-1),used
 adj =. 0(<a,b)}adj
 adj =. 0(<b,a)}adj
 for_u. a,b,taxon do. adj =. 1(<u,node)}adj
 adj =. 1(<node,u)}adj end.
 adj;lengths;(/:~leaves,taxon);0
)
initial_tree =: 3 : 0
 adj =. ((2*N),2*N)$0
 for_leaf. y do. adj =. 1(<leaf,N)}adj
 adj =. 1(<N,leaf)}adj end.
 adj;(((2*N),2*N)$0.0);y;0
)
nni_candidates =: 3 : 0
 'adj lengths leaves negatives' =. y
 'root parent order masks' =. rooting y
 candidates =. 0$a:
 for_edge. branches y do.
  'mask u v' =. edge
  if. (u<N)+.v<N do. continue. end.
  kids =. (I.v{adj)-.u
  kids =. (/:kids{masks){kids
  siblings =. (I.u{adj)-.v,(u{parent),Outgroup
  sibling =. {.siblings
  for_swap. i.2 do.
   child =. swap{kids
   a =. adj
   a =. 0(<u,sibling)}a
   a =. 0(<sibling,u)}a
   a =. 0(<v,child)}a
   a =. 0(<child,v)}a
   a =. 1(<u,child)}a
   a =. 1(<child,u)}a
   a =. 1(<v,sibling)}a
   a =. 1(<sibling,v)}a
   candidates =. candidates,<mask;(swap+1);(a;lengths;leaves;0)
  end.
 end.
 candidates
)
first_state =: 3 : '{.I.0<y(17 b.)1 2 4 8'
reconstruct =: 3 : 0
 'adj lengths leaves negatives' =. y
 'root parent order masks' =. rooting y
 states =. ((#adj),L)$'A'
 changes =. ($adj)$0
 for_c. i.L do.
  'score provisional final' =. y fitch_column c
  rootstate =. first_state final
  rs =. rootstate
  if. 0=(rootstate{1 2 4 8)(17 b.)root{provisional do. rs =. first_state root{provisional end.
  os =. rootstate
  if. 0=(rootstate{1 2 4 8)(17 b.)Outgroup{provisional do. os =. first_state Outgroup{provisional end.
  assigned =. (#adj)$0
  assigned =. rs root}assigned
  assigned =. os Outgroup}assigned
  for_node. order-.root,Outgroup do.
   par =. node{parent
   value =. par{assigned
   if. 0=(value{1 2 4 8)(17 b.)node{provisional do. value =. first_state node{provisional end.
   assigned =. value node}assigned
  end.
  for_node. order do. states =. ((node{assigned){'ACGT')(<node,c)}states end.
  for_node. order-.root do.
   par =. node{parent
   if. (par{assigned)~:node{assigned do.
    changes =. (1+(<par,node){changes)(<par,node)}changes
    changes =. (1+(<node,par){changes)(<node,par)}changes
   end.
  end.
 end.
 tree =. adj;(changes%L);leaves;0
 tree;states;changes
)
